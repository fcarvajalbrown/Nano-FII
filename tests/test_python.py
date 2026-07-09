"""
test_python.py — End-to-end Python tests and micro-call benchmark for Nano-FFI.

Run after building the extension:
    zig build -Doptimize=ReleaseFast
    python tests/test_python.py

Requirements:
    pip install pytest
"""

import sys
import time
import unittest

# The compiled extension must be on sys.path.
# `zig build` places it in zig-out/lib/ — add it if running directly.
sys.path.insert(0, "zig-out/lib")

try:
    import nano_ffi
except ImportError as e:
    raise SystemExit(
        "Could not import nano_ffi. Run `zig build -Doptimize=ReleaseFast` first.\n"
        f"Detail: {e}"
    )


# ---------------------------------------------------------------------------
# Smoke tests
# ---------------------------------------------------------------------------

# Bump this in lockstep with src/version.zig on every release.
EXPECTED_VERSION = "0.3.0"


class TestVersion(unittest.TestCase):
    def test_version_returns_string(self):
        v = nano_ffi.version()
        self.assertIsInstance(v, str)

    def test_version_value(self):
        self.assertEqual(nano_ffi.version(), EXPECTED_VERSION)


class TestCallDispatch(unittest.TestCase):
    def test_call_unknown_function_raises_key_error(self):
        with self.assertRaises(KeyError):
            nano_ffi.call("nonexistent", 1, 2)

    def test_call_add_integers(self):
        result = nano_ffi.call("add", 3, 4)
        self.assertEqual(result, 7)

    def test_call_multiply_floats(self):
        result = nano_ffi.call("mul", 2.5, 4.0)
        self.assertAlmostEqual(result, 10.0)


class TestScalarTypes(unittest.TestCase):
    """v0.3.0: expanded scalar type system with range-checked narrowing."""

    def test_call_add32(self):
        self.assertEqual(nano_ffi.call("add32", 100, 23), 123)

    def test_call_umul_u64(self):
        # A value that exceeds i64 range but fits u64.
        big = 2**40
        self.assertEqual(nano_ffi.call("umul", big, 2), big * 2)

    def test_i32_overflow_raises_value_error(self):
        with self.assertRaises(ValueError):
            nano_ffi.call("add32", 2**40, 1)

    def test_u64_negative_raises(self):
        with self.assertRaises((ValueError, OverflowError)):
            nano_ffi.call("umul", -1, 2)


# ---------------------------------------------------------------------------
# Micro-call benchmark
# ---------------------------------------------------------------------------

BENCHMARK_ITERATIONS = 100_000


def benchmark_nano_ffi():
    """
    Measures average call overhead for nano_ffi.call().
    Target: <110ns per call on ReleaseFast build.
    """
    # Warm up
    for _ in range(1000):
        try:
            nano_ffi.call("add", 1, 2)
        except Exception:
            pass

    start = time.perf_counter_ns()
    for _ in range(BENCHMARK_ITERATIONS):
        try:
            nano_ffi.call("add", 1, 2)
        except Exception:
            pass
    elapsed = time.perf_counter_ns() - start

    avg_ns = elapsed / BENCHMARK_ITERATIONS
    print(f"\n[benchmark] nano_ffi.call — {avg_ns:.1f} ns/call avg over {BENCHMARK_ITERATIONS:,} iterations")
    print(f"[benchmark] target: <110 ns  |  {'PASS' if avg_ns < 110 else f'FAIL ({avg_ns:.0f}ns — run ReleaseFast for real numbers)'}")
    return avg_ns


def benchmark_ctypes_baseline():
    """
    Baseline: equivalent ctypes call overhead for comparison.
    Uses msvcrt on Windows, libm on Linux/macOS.
    """
    import ctypes
    import ctypes.util
    import sys

    if sys.platform == "win32":
        lib = ctypes.CDLL("msvcrt")
        lib.abs.argtypes = [ctypes.c_int]
        lib.abs.restype  = ctypes.c_int
        fn = lambda: lib.abs(1)
    else:
        libm = ctypes.CDLL(ctypes.util.find_library("m"))
        libm.fabs.argtypes = [ctypes.c_double]
        libm.fabs.restype  = ctypes.c_double
        fn = lambda: libm.fabs(1.0)

    # Warm up
    for _ in range(1000):
        fn()

    start = time.perf_counter_ns()
    for _ in range(BENCHMARK_ITERATIONS):
        fn()
    elapsed = time.perf_counter_ns() - start

    avg_ns = elapsed / BENCHMARK_ITERATIONS
    print(f"[benchmark] ctypes baseline  — {avg_ns:.1f} ns/call avg over {BENCHMARK_ITERATIONS:,} iterations")
    return avg_ns


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=== Nano-FFI Test Suite ===\n")

    # Run every TestCase defined in this module (new releases just add classes).
    loader = unittest.TestLoader()
    suite  = loader.loadTestsFromModule(sys.modules[__name__])

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    # Run benchmarks
    print("\n=== Micro-Call Benchmark ===")
    nano_ns   = benchmark_nano_ffi()
    ctypes_ns = benchmark_ctypes_baseline()

    if ctypes_ns > 0:
        speedup = ctypes_ns / nano_ns
        print(f"\n[benchmark] nano_ffi is {speedup:.2f}x vs ctypes baseline")

    sys.exit(0 if result.wasSuccessful() else 1)