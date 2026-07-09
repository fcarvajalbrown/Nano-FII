//! comptime_bridge.zig — Comptime trampoline generator.
//!
//! This is the core of Nano-FFI. Given a Zig function at comptime, it generates
//! a type-safe "trampoline" — a wrapper that unpacks raw Python arguments into
//! the correct Zig types, calls the function, and repacks the return value.
//!
//! No runtime type inspection. All branching is resolved at compile time,
//! which is why call overhead drops to <110ns.

const std = @import("std");
const registry = @import("registry.zig");

/// Supported scalar types for automatic marshalling.
/// Extend this enum to add new type support.
pub const ArgType = enum(u8) {
    i64,
    f64,
    bool,
    i32,
    u32,
    u64,
    f32,
    u8,
    // Variable-length byte views. Both marshal to a Zig `[]const u8`; they
    // differ only in how Python packs/unpacks them (str = UTF-8 text,
    // bytes = raw). See RawSlice for the C-ABI-safe representation.
    str,
    bytes,
};

/// Descriptor for a single function argument.
pub const ArgDesc = struct {
    name: []const u8,
    typ: ArgType,
};

/// Full signature descriptor passed to `makeTrampoline`.
///
/// A function returns either a single value (`ret`, with `rets` empty) or,
/// when `rets` is non-empty, a Zig tuple whose fields map element-wise onto
/// `rets` and surface in Python as a tuple.
pub const Signature = struct {
    args: []const ArgDesc,
    ret: ArgType = .i64,
    rets: []const ArgType = &.{},
};

/// Maximum number of values a multi-return function may hand back.
pub const MAX_RETS = 8;

/// Scratch buffer for multi-value returns. The GIL serialises calls, so a
/// single module-global buffer is safe: python_ext reads it immediately after
/// the trampoline returns, before any re-entry. Only used when `n_rets > 1`.
pub var multi_ret: [MAX_RETS]RawRet = undefined;

/// Comptime trampoline factory.
///
/// Given a comptime-known `func` and its `sig`, returns a new function whose
/// signature is `fn (args: [*]const RawArg) callconv(.c) RawRet`.
/// Python calls this instead of `func` directly.
///
/// Example:
///   const trampoline = makeTrampoline(myAdd, .{
///       .args = &.{ .{ .name = "a", .typ = .i64 }, .{ .name = "b", .typ = .i64 } },
///       .ret  = .i64,
///   });
pub fn makeTrampoline(
    comptime func: anytype,
    comptime sig_param: Signature,
) type {
    return struct {
        /// The signature used to generate this trampoline — stored alongside
        /// the function pointer in the registry so the dispatcher can unpack args.
        pub const sig: Signature = sig_param;

        /// The generated wrapper — this is what gets registered in the registry
        /// and called from python_ext.zig.
        pub fn call(args: [*]const RawArg) callconv(.c) RawRet {
            // Unpack each argument at comptime-known offsets — no runtime loop.
            const result = comptime_call: {
                var typed_args: std.meta.ArgsTuple(@TypeOf(func)) = undefined;
                inline for (sig_param.args, 0..) |desc, i| {
                    typed_args[i] = unpack(desc.typ, args[i]);
                }
                break :comptime_call @call(.auto, func, typed_args);
            };

            // Multi-value return: the function handed back a Zig tuple; pack
            // each field into the shared buffer and flag the count. Resolved at
            // comptime, so single-return functions never see this path.
            if (comptime sig_param.rets.len > 0) {
                inline for (sig_param.rets, 0..) |rt, i| {
                    multi_ret[i] = pack(rt, result[i]);
                }
                return .{
                    .tag = sig.ret,
                    .val = std.mem.zeroes(RawValue),
                    .n_rets = @intCast(sig_param.rets.len),
                };
            }

            // If the wrapped function returns an error union, unwrap it: on
            // error, carry @errorName back so python_ext can raise. The branch
            // is resolved at comptime — non-erroring functions keep the
            // straight-line path with no runtime check.
            if (comptime @typeInfo(@TypeOf(result)) == .error_union) {
                if (result) |ok| {
                    return pack(sig.ret, ok);
                } else |err| {
                    const name = @errorName(err);
                    return .{
                        .tag = sig.ret,
                        .val = std.mem.zeroes(RawValue),
                        .err_ptr = name.ptr,
                        .err_len = name.len,
                    };
                }
            } else {
                return pack(sig.ret, result);
            }
        }

        /// Cast the trampoline to a registry-compatible FnPtr.
        pub fn asPtr() registry.FnPtr {
            return @ptrCast(&call);
        }
    };
}

// ---------------------------------------------------------------------------
// Raw argument / return value types (C-ABI safe extern structs)
// ---------------------------------------------------------------------------
// Tagged unions cannot cross the C ABI boundary. We use an extern struct with
// an explicit tag + a C-compatible union instead.

/// A C-ABI-safe view of borrowed bytes (ptr + len). Zig's native slice is a
/// fat pointer with no guaranteed layout across `extern`, so we carry the two
/// fields explicitly and rebuild the slice on the Zig side.
pub const RawSlice = extern struct {
    ptr: [*]const u8,
    len: usize,
};

pub const RawValue = extern union {
    i64: i64,
    f64: f64,
    bool: bool,
    i32: i32,
    u32: u32,
    u64: u64,
    f32: f32,
    u8: u8,
    slice: RawSlice,
};

/// A raw argument passed from Python.
pub const RawArg = extern struct {
    tag: ArgType,
    val: RawValue,
};

/// A raw return value sent back to Python.
///
/// `err_ptr == null` means success and `val` holds the result. Otherwise the
/// wrapped Zig function returned an error and `err_ptr[0..err_len]` is its
/// `@errorName`; `val` is unspecified and must be ignored.
pub const RawRet = extern struct {
    tag: ArgType,
    val: RawValue,
    err_ptr: ?[*]const u8 = null,
    err_len: usize = 0,
    // 0 or 1 => a single value lives in `val`. >1 => the values live in
    // `multi_ret[0..n_rets]` and Python builds a tuple from them.
    n_rets: u8 = 0,
};

// ---------------------------------------------------------------------------
// Internal helpers — not exported
// ---------------------------------------------------------------------------

/// Unpack a RawArg into the concrete Zig type expected by the function.
inline fn unpack(comptime typ: ArgType, arg: RawArg) switch (typ) {
    .i64 => i64,
    .f64 => f64,
    .bool => bool,
    .i32 => i32,
    .u32 => u32,
    .u64 => u64,
    .f32 => f32,
    .u8 => u8,
    .str, .bytes => []const u8,
} {
    return switch (typ) {
        .i64 => arg.val.i64,
        .f64 => arg.val.f64,
        .bool => arg.val.bool,
        .i32 => arg.val.i32,
        .u32 => arg.val.u32,
        .u64 => arg.val.u64,
        .f32 => arg.val.f32,
        .u8 => arg.val.u8,
        .str, .bytes => arg.val.slice.ptr[0..arg.val.slice.len],
    };
}

/// Pack a Zig return value into a RawRet.
inline fn pack(comptime typ: ArgType, value: anytype) RawRet {
    return switch (typ) {
        .i64 => .{ .tag = .i64, .val = .{ .i64 = value } },
        .f64 => .{ .tag = .f64, .val = .{ .f64 = value } },
        .bool => .{ .tag = .bool, .val = .{ .bool = value } },
        .i32 => .{ .tag = .i32, .val = .{ .i32 = value } },
        .u32 => .{ .tag = .u32, .val = .{ .u32 = value } },
        .u64 => .{ .tag = .u64, .val = .{ .u64 = value } },
        .f32 => .{ .tag = .f32, .val = .{ .f32 = value } },
        .u8 => .{ .tag = .u8, .val = .{ .u8 = value } },
        .str => .{ .tag = .str, .val = .{ .slice = .{ .ptr = value.ptr, .len = value.len } } },
        .bytes => .{ .tag = .bytes, .val = .{ .slice = .{ .ptr = value.ptr, .len = value.len } } },
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn addInts(a: i64, b: i64) i64 {
    return a + b;
}
fn mulFloats(a: f64, b: f64) f64 {
    return a * b;
}

test "trampoline: integer add" {
    const T = makeTrampoline(addInts, .{
        .args = &.{
            .{ .name = "a", .typ = .i64 },
            .{ .name = "b", .typ = .i64 },
        },
        .ret = .i64,
    });

    const args = [_]RawArg{ .{ .tag = .i64, .val = .{ .i64 = 3 } }, .{ .tag = .i64, .val = .{ .i64 = 4 } } };
    const ret = T.call(&args);
    try std.testing.expectEqual(@as(i64, 7), ret.val.i64);
}

fn subI32(a: i32, b: i32) i32 {
    return a - b;
}

test "trampoline: i32 subtract" {
    const T = makeTrampoline(subI32, .{
        .args = &.{
            .{ .name = "a", .typ = .i32 },
            .{ .name = "b", .typ = .i32 },
        },
        .ret = .i32,
    });

    const args = [_]RawArg{ .{ .tag = .i32, .val = .{ .i32 = 10 } }, .{ .tag = .i32, .val = .{ .i32 = 3 } } };
    const ret = T.call(&args);
    try std.testing.expectEqual(@as(i32, 7), ret.val.i32);
}

fn divModZ(a: i64, b: i64) struct { i64, i64 } {
    return .{ @divTrunc(a, b), @mod(a, b) };
}

test "trampoline: multi-value return packs into shared buffer" {
    const T = makeTrampoline(divModZ, .{
        .args = &.{ .{ .name = "a", .typ = .i64 }, .{ .name = "b", .typ = .i64 } },
        .rets = &.{ .i64, .i64 },
    });
    const args = [_]RawArg{ .{ .tag = .i64, .val = .{ .i64 = 17 } }, .{ .tag = .i64, .val = .{ .i64 = 5 } } };
    const ret = T.call(&args);
    try std.testing.expectEqual(@as(u8, 2), ret.n_rets);
    try std.testing.expectEqual(@as(i64, 3), multi_ret[0].val.i64);
    try std.testing.expectEqual(@as(i64, 2), multi_ret[1].val.i64);
}

fn divZ(a: i64, b: i64) error{DivByZero}!i64 {
    if (b == 0) return error.DivByZero;
    return @divTrunc(a, b);
}

test "trampoline: error union carries success value and error name" {
    const T = makeTrampoline(divZ, .{
        .args = &.{ .{ .name = "a", .typ = .i64 }, .{ .name = "b", .typ = .i64 } },
        .ret = .i64,
    });

    const ok_args = [_]RawArg{ .{ .tag = .i64, .val = .{ .i64 = 10 } }, .{ .tag = .i64, .val = .{ .i64 = 2 } } };
    const ok = T.call(&ok_args);
    try std.testing.expect(ok.err_ptr == null);
    try std.testing.expectEqual(@as(i64, 5), ok.val.i64);

    const bad_args = [_]RawArg{ .{ .tag = .i64, .val = .{ .i64 = 10 } }, .{ .tag = .i64, .val = .{ .i64 = 0 } } };
    const bad = T.call(&bad_args);
    try std.testing.expect(bad.err_ptr != null);
    try std.testing.expectEqualStrings("DivByZero", bad.err_ptr.?[0..bad.err_len]);
}

fn strLenZ(s: []const u8) i64 {
    return @intCast(s.len);
}
fn echoZ(s: []const u8) []const u8 {
    return s;
}

test "trampoline: string length" {
    const T = makeTrampoline(strLenZ, .{
        .args = &.{.{ .name = "s", .typ = .str }},
        .ret = .i64,
    });
    const hello: []const u8 = "hello";
    const args = [_]RawArg{.{ .tag = .str, .val = .{ .slice = .{ .ptr = hello.ptr, .len = hello.len } } }};
    const ret = T.call(&args);
    try std.testing.expectEqual(@as(i64, 5), ret.val.i64);
}

test "trampoline: string echo round-trips ptr/len" {
    const T = makeTrampoline(echoZ, .{
        .args = &.{.{ .name = "s", .typ = .str }},
        .ret = .str,
    });
    const src: []const u8 = "world!";
    const args = [_]RawArg{.{ .tag = .str, .val = .{ .slice = .{ .ptr = src.ptr, .len = src.len } } }};
    const ret = T.call(&args);
    try std.testing.expectEqual(src.len, ret.val.slice.len);
    try std.testing.expectEqualStrings(src, ret.val.slice.ptr[0..ret.val.slice.len]);
}

test "trampoline: float multiply" {
    const T = makeTrampoline(mulFloats, .{
        .args = &.{
            .{ .name = "a", .typ = .f64 },
            .{ .name = "b", .typ = .f64 },
        },
        .ret = .f64,
    });

    const args = [_]RawArg{ .{ .tag = .f64, .val = .{ .f64 = 2.5 } }, .{ .tag = .f64, .val = .{ .f64 = 4.0 } } };
    const ret = T.call(&args);
    try std.testing.expectEqual(@as(f64, 10.0), ret.val.f64);
}
