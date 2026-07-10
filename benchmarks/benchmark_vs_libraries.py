r"""
benchmark_vs_libraries.py - Apples-to-apples binding-overhead comparison of
Nano-FFI vs. ctypes vs. cffi, all calling the SAME trivial native functions.

Unlike benchmarks/benchmark.py (which times Nano-FFI against a ctypes msvcrt.abs
proxy — a DIFFERENT function on each side, so the comparison is unfair), this
script binds ctypes and cffi to a purpose-built shared library, `benchlib`,
whose add/strlen/fill have the same semantics as Nano-FFI's built-ins. All three
bindings therefore do the same trivial native work, and the measured delta is
purely the per-call BINDING overhead — which is exactly what we want to compare.

WHAT IS MEASURED
    - Nano-FFI : nano_ffi.call("add"/"strlen"/"fill", ...)
    - ctypes   : lib.nf_bench_add / nf_bench_strlen / nf_bench_fill
    - cffi     : the same three symbols via an ffi.dlopen handle
Native bodies are trivial (a +% b, strlen, memset), so native cost is ~equal
across all three and the difference is the marshalling/dispatch cost of each
binding layer.

PREREQUISITES
    1. Build the Python extension (nano_ffi.pyd/.so):
           Windows : powershell -File scripts\build_local.ps1
           Linux   : zig build -Doptimize=ReleaseFast \
                         -Dpython-include=$(python -c "import sysconfig;print(sysconfig.get_path('include'))")
           macOS   : same as Linux
    2. Build the benchmark shared library (produces nano_ffi_benchlib.{dll,so,dylib}):
           Windows : & "$env:LOCALAPPDATA\zig-0.15.2\zig.exe" build benchlib -Doptimize=ReleaseFast
                     (or add the same `zig build benchlib` line to scripts\build_local.ps1)
           Linux   : zig build benchlib -Doptimize=ReleaseFast
           macOS   : zig build benchlib -Doptimize=ReleaseFast
    3. cffi is optional. Without it, the cffi column is skipped with a note.
       Install with:  pip install cffi

USAGE
    python benchmarks/benchmark_vs_libraries.py

NOTE ON NUMBERS
    All figures printed by this script are measured live on the machine that runs
    it. They are NOT hardcoded. ns/call is machine-, OS- and build-dependent;
    treat the ratios (speedup) as more portable than the absolute nanoseconds.
"""

import ctypes
import statistics
import sys
import time
from pathlib import Path

# --- Locate the built artifacts ---------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "zig-out" / "lib"))

import nano_ffi  # noqa: E402

ITERATIONS = 100_000
REPEATS = 7
WARMUP = 1000


def _benchlib_path() -> Path:
    """Return the path to nano_ffi_benchlib for this platform, or raise.

    Zig installs a dynamic library's loadable image into zig-out/bin on Windows
    (the .lib import stub goes to zig-out/lib) and into zig-out/lib on Linux and
    macOS, so we search both. The base name also differs: Windows produces
    nano_ffi_benchlib.dll, Unix produces libnano_ffi_benchlib.{so,dylib}.
    """
    if sys.platform == "win32":
        names = ["nano_ffi_benchlib.dll"]
    elif sys.platform == "darwin":
        names = ["libnano_ffi_benchlib.dylib", "nano_ffi_benchlib.dylib"]
    else:
        names = ["libnano_ffi_benchlib.so", "nano_ffi_benchlib.so"]

    search = [ROOT / "zig-out" / "bin", ROOT / "zig-out" / "lib", ROOT]
    for d in search:
        for n in names:
            p = d / n
            if p.exists():
                return p
    tried = "\n  ".join(str(d / n) for d in search for n in names)
    raise FileNotFoundError(
        "benchlib not found. Build it with:\n"
        "  zig build benchlib -Doptimize=ReleaseFast\n"
        "Searched:\n  " + tried
    )


# --- Timing core ------------------------------------------------------------
def _median_ns(fn) -> tuple[float, float]:
    """Time `fn` and return (median ns/call, min ns/call) over REPEATS runs.

    Each repeat times ITERATIONS calls with perf_counter_ns after a warmup, so a
    single scheduling hiccup does not dominate: we take the median of the
    per-repeat means and also report the fastest repeat.
    """
    for _ in range(WARMUP):
        fn()
    per_repeat = []
    for _ in range(REPEATS):
        start = time.perf_counter_ns()
        for _ in range(ITERATIONS):
            fn()
        per_repeat.append((time.perf_counter_ns() - start) / ITERATIONS)
    return statistics.median(per_repeat), min(per_repeat)


# --- Binding setups ---------------------------------------------------------
def make_ctypes_calls(libpath: Path):
    lib = ctypes.CDLL(str(libpath))

    lib.nf_bench_add.argtypes = [ctypes.c_int64, ctypes.c_int64]
    lib.nf_bench_add.restype = ctypes.c_int64

    lib.nf_bench_strlen.argtypes = [ctypes.c_char_p]
    lib.nf_bench_strlen.restype = ctypes.c_int64

    lib.nf_bench_fill.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t, ctypes.c_uint8]
    lib.nf_bench_fill.restype = None

    s = b"hello"
    buf = (ctypes.c_uint8 * 16)()

    # Correctness sanity check before timing.
    assert lib.nf_bench_add(1, 2) == 3
    assert lib.nf_bench_strlen(s) == 5
    lib.nf_bench_fill(buf, 16, 1)
    assert list(buf) == [1] * 16

    return {
        "scalar (add i64)": lambda: lib.nf_bench_add(1, 2),
        "string (strlen)": lambda: lib.nf_bench_strlen(s),
        "zero-copy buffer (fill)": lambda: lib.nf_bench_fill(buf, 16, 1),
    }


def make_cffi_calls(libpath: Path):
    import cffi  # raises ImportError if not installed; caller handles it

    ffi = cffi.FFI()
    ffi.cdef(
        """
        int64_t nf_bench_add(int64_t a, int64_t b);
        int64_t nf_bench_strlen(const char* s);
        void    nf_bench_fill(uint8_t* buf, size_t len, uint8_t value);
        """
    )
    lib = ffi.dlopen(str(libpath))

    s = b"hello"
    buf = ffi.new("uint8_t[16]")

    assert lib.nf_bench_add(1, 2) == 3
    assert lib.nf_bench_strlen(s) == 5
    lib.nf_bench_fill(buf, 16, 1)
    assert list(buf) == [1] * 16

    return {
        "scalar (add i64)": lambda: lib.nf_bench_add(1, 2),
        "string (strlen)": lambda: lib.nf_bench_strlen(s),
        "zero-copy buffer (fill)": lambda: lib.nf_bench_fill(buf, 16, 1),
    }


def make_nano_calls():
    nano_buf = bytearray(16)

    assert nano_ffi.call("add", 1, 2) == 3
    assert nano_ffi.call("strlen", "hello") == 5
    assert nano_ffi.call("fill", nano_buf, 1) == 16

    return {
        "scalar (add i64)": lambda: nano_ffi.call("add", 1, 2),
        "string (strlen)": lambda: nano_ffi.call("strlen", "hello"),
        "zero-copy buffer (fill)": lambda: nano_ffi.call("fill", nano_buf, 1),
    }


def main() -> int:
    libpath = _benchlib_path()

    print(f"Nano-FFI {nano_ffi.version()} - binding-overhead comparison")
    print(f"benchlib: {libpath}")
    print(f"Python {sys.version.split()[0]} on {sys.platform}")
    print(f"{ITERATIONS:,} iterations x {REPEATS} repeats; reporting median ns/call (min in parens)")
    print("All figures measured live on this machine; ns/call is machine-dependent.\n")

    nano = make_nano_calls()
    ct = make_ctypes_calls(libpath)

    have_cffi = True
    try:
        cf = make_cffi_calls(libpath)
    except ImportError:
        have_cffi = False
        cf = None
        print("NOTE: cffi is not installed — skipping the cffi column. `pip install cffi` to include it.\n")

    call_kinds = ["scalar (add i64)", "string (strlen)", "zero-copy buffer (fill)"]

    # Measure everything up front.
    results = {}
    for kind in call_kinds:
        row = {}
        row["nano"] = _median_ns(nano[kind])
        row["ctypes"] = _median_ns(ct[kind])
        row["cffi"] = _median_ns(cf[kind]) if have_cffi else None
        results[kind] = row

    # --- Markdown table (paste-ready for the README) ---
    if have_cffi:
        print("| Call kind | Nano-FFI | ctypes | cffi | best speedup vs Nano-FFI |")
        print("|---|---|---|---|---|")
    else:
        print("| Call kind | Nano-FFI | ctypes | best speedup vs Nano-FFI |")
        print("|---|---|---|---|")

    for kind in call_kinds:
        r = results[kind]
        nano_med, nano_min = r["nano"]
        ct_med, ct_min = r["ctypes"]

        nano_cell = f"{nano_med:.0f} ({nano_min:.0f})"
        ct_cell = f"{ct_med:.0f} ({ct_min:.0f})"

        # "best speedup vs Nano-FFI": how many times faster Nano-FFI is than the
        # fastest of the other bindings (>1 means Nano-FFI wins).
        others = [ct_med]
        if have_cffi:
            cf_med, cf_min = r["cffi"]
            others.append(cf_med)
        best_other = min(others)
        speedup = best_other / nano_med
        speed_cell = f"{speedup:.2f}x"

        if have_cffi:
            cf_med, cf_min = r["cffi"]
            cf_cell = f"{cf_med:.0f} ({cf_min:.0f})"
            print(f"| {kind} | {nano_cell} | {ct_cell} | {cf_cell} | {speed_cell} |")
        else:
            print(f"| {kind} | {nano_cell} | {ct_cell} | {speed_cell} |")

    print("\nCells show median ns/call (min over repeats in parentheses). Lower is better.")
    print("'best speedup vs Nano-FFI' > 1.00x means Nano-FFI has the lowest overhead.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
