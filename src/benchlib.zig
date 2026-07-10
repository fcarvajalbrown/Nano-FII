//! benchlib.zig — Tiny plain-C-ABI shared library for the apples-to-apples
//! binding-overhead benchmark (benchmarks/benchmark_vs_libraries.py).
//!
//! It exports three trivial functions whose semantics match Nano-FFI's built-in
//! add / strlen / fill. ctypes and cffi bind to THESE exported symbols, while
//! Nano-FFI calls its own registered equivalents. Because all three bindings do
//! the same trivial native work, the measured delta is purely the per-call
//! BINDING overhead — which is what the benchmark compares.
//!
//! The bodies are deliberately trivial so native execution cost is ~equal
//! across all three paths. Built as a `.dynamic` library named
//! `nano_ffi_benchlib` -> nano_ffi_benchlib.dll / .so / .dylib.

const std = @import("std");

/// add(int64, int64) -> int64. Matches Nano-FFI's `add`.
export fn nf_bench_add(a: i64, b: i64) callconv(.c) i64 {
    return a +% b;
}

/// strlen(const char* NUL-terminated) -> int64. Matches Nano-FFI's `strlen`
/// contract (returns the byte length of the string). Uses the C NUL-terminated
/// convention so ctypes/cffi can pass a plain c_char_p, the most idiomatic and
/// lowest-overhead way those libraries marshal a Python str/bytes.
export fn nf_bench_strlen(s: [*:0]const u8) callconv(.c) i64 {
    return @intCast(std.mem.len(s));
}

/// fill(uint8_t* buf, size_t len, uint8_t value) -> void. Matches Nano-FFI's
/// zero-copy `fill`: writes `value` into every byte of the caller-owned buffer,
/// in place. Nano-FFI returns the length; here we keep a void return to stay a
/// plain, idiomatic C signature — the length is already known to the caller.
export fn nf_bench_fill(buf: [*]u8, len: usize, value: u8) callconv(.c) void {
    @memset(buf[0..len], value);
}
