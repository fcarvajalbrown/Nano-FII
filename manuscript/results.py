"""
manuscript/results.py
======================
Single source of every COMPUTED number used by the per-journal manuscript
build scripts. Each builder imports compute_results() from here, so the
numbers reported in every journal version are produced from the live, built
extension and can never drift out of sync with the code.

Run `.\scripts\build_local.ps1` (or `zig build -Doptimize=ReleaseFast`) first so
a ReleaseFast nano_ffi module exists at the repo root or in zig-out/lib.
"""

import ctypes
import ctypes.util
import importlib.util
import sys
import time
import unittest
from pathlib import Path
from statistics import median

_ROOT = Path(__file__).resolve().parent.parent
for p in (_ROOT, _ROOT / "zig-out" / "lib"):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

import nano_ffi  # noqa: E402

ITERATIONS = 100_000
REPEATS = 5  # median over repeats to damp scheduler noise


def _bench(fn, iterations=ITERATIONS, repeats=REPEATS):
    for _ in range(1000):  # warm up
        fn()
    samples = []
    for _ in range(repeats):
        start = time.perf_counter_ns()
        for _ in range(iterations):
            fn()
        samples.append((time.perf_counter_ns() - start) / iterations)
    return median(samples)


def _ctypes_baseline():
    if sys.platform == "win32":
        lib = ctypes.CDLL("msvcrt")
        lib.abs.argtypes = [ctypes.c_int]
        lib.abs.restype = ctypes.c_int
        return _bench(lambda: lib.abs(1))
    libm = ctypes.CDLL(ctypes.util.find_library("m"))
    libm.fabs.argtypes = [ctypes.c_double]
    libm.fabs.restype = ctypes.c_double
    return _bench(lambda: libm.fabs(1.0))


def _count_tests():
    """Count test cases in tests/test_python.py without executing them."""
    path = _ROOT / "tests" / "test_python.py"
    mod_spec = importlib.util.spec_from_file_location("_nano_tests", path)
    mod = importlib.util.module_from_spec(mod_spec)
    mod_spec.loader.exec_module(mod)
    suite = unittest.TestLoader().loadTestsFromModule(mod)
    return suite.countTestCases()


# The 11 scalar/aggregate kinds the comptime bridge marshals.
SUPPORTED_TYPES = [
    "i64", "i32", "u64", "u32", "u8", "f64", "f32", "bool", "str", "bytes", "buffer",
]


def compute_results() -> dict:
    buf = bytearray(16)
    cases = {
        "scalar_add_i64": lambda: nano_ffi.call("add", 1, 2),
        "float_mul_f64": lambda: nano_ffi.call("mul", 1.5, 2.0),
        "string_strlen": lambda: nano_ffi.call("strlen", "hello"),
        "multi_return_divmod": lambda: nano_ffi.call("divmod", 17, 5),
        "buffer_fill": lambda: nano_ffi.call("fill", buf, 1),
    }
    overhead = {k: _bench(fn) for k, fn in cases.items()}
    ctypes_ns = _ctypes_baseline()
    add_ns = overhead["scalar_add_i64"]

    return {
        "version": nano_ffi.version(),
        "iterations": ITERATIONS,
        "repeats": REPEATS,
        "n_functions": len(nano_ffi.list_functions()),
        "functions": sorted(nano_ffi.list_functions()),
        "n_types": len(SUPPORTED_TYPES),
        "supported_types": SUPPORTED_TYPES,
        "overhead_ns": overhead,
        "ctypes_ns": ctypes_ns,
        "add_ns": add_ns,
        "speedup_vs_ctypes": ctypes_ns / add_ns,
        "n_tests": _count_tests(),
        "platform": sys.platform,
        "python": "%d.%d" % sys.version_info[:2],
    }


if __name__ == "__main__":
    import json
    print(json.dumps(compute_results(), indent=2))
