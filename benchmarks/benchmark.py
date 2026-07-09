"""
benchmark.py — Micro-call overhead for Nano-FFI, across representative call
kinds, versus a ctypes baseline. Emits a Markdown table matching the README.

Usage (after building the extension in ReleaseFast):
    python benchmarks/benchmark.py
"""

import ctypes
import ctypes.util
import sys
import time
from pathlib import Path

# Import the freshly built extension from the repo root or zig-out/lib.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "zig-out" / "lib"))

import nano_ffi  # noqa: E402

ITERATIONS = 100_000


def _time(fn, iterations=ITERATIONS):
    for _ in range(1000):  # warm up
        fn()
    start = time.perf_counter_ns()
    for _ in range(iterations):
        fn()
    return (time.perf_counter_ns() - start) / iterations


def ctypes_baseline():
    if sys.platform == "win32":
        lib = ctypes.CDLL("msvcrt")
        lib.abs.argtypes = [ctypes.c_int]
        lib.abs.restype = ctypes.c_int
        return _time(lambda: lib.abs(1))
    libm = ctypes.CDLL(ctypes.util.find_library("m"))
    libm.fabs.argtypes = [ctypes.c_double]
    libm.fabs.restype = ctypes.c_double
    return _time(lambda: libm.fabs(1.0))


def main():
    buf = bytearray(16)
    cases = {
        "scalar (add i64)": lambda: nano_ffi.call("add", 1, 2),
        "float (mul f64)": lambda: nano_ffi.call("mul", 1.5, 2.0),
        "string (strlen)": lambda: nano_ffi.call("strlen", "hello"),
        "multi-return (divmod)": lambda: nano_ffi.call("divmod", 17, 5),
        "zero-copy buffer (fill)": lambda: nano_ffi.call("fill", buf, 1),
    }

    print(f"Nano-FFI {nano_ffi.version()} — {ITERATIONS:,} iterations\n")
    print("| Call kind | ns/call |")
    print("|---|---|")
    for label, fn in cases.items():
        print(f"| {label} | {_time(fn):.1f} |")

    base = ctypes_baseline()
    add_ns = _time(lambda: nano_ffi.call("add", 1, 2))
    print(f"\nctypes baseline: {base:.1f} ns/call")
    print(f"Nano-FFI (add) is {base / add_ns:.2f}x faster than the ctypes baseline")


if __name__ == "__main__":
    main()
