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
    // Pointer types (e.g. slices) are handled separately — see SliceArg.
};

/// Descriptor for a single function argument.
pub const ArgDesc = struct {
    name: []const u8,
    typ: ArgType,
};

/// Full signature descriptor passed to `makeTrampoline`.
pub const Signature = struct {
    args: []const ArgDesc,
    ret: ArgType,
};

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
            return pack(sig.ret, result);
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

pub const RawValue = extern union {
    i64: i64,
    f64: f64,
    bool: bool,
};

/// A raw argument passed from Python.
pub const RawArg = extern struct {
    tag: ArgType,
    val: RawValue,
};

/// A raw return value sent back to Python.
pub const RawRet = extern struct {
    tag: ArgType,
    val: RawValue,
};

// ---------------------------------------------------------------------------
// Internal helpers — not exported
// ---------------------------------------------------------------------------

/// Unpack a RawArg into the concrete Zig type expected by the function.
inline fn unpack(comptime typ: ArgType, arg: RawArg) switch (typ) {
    .i64 => i64,
    .f64 => f64,
    .bool => bool,
} {
    return switch (typ) {
        .i64 => arg.val.i64,
        .f64 => arg.val.f64,
        .bool => arg.val.bool,
    };
}

/// Pack a Zig return value into a RawRet.
inline fn pack(comptime typ: ArgType, value: anytype) RawRet {
    return switch (typ) {
        .i64 => .{ .tag = .i64, .val = .{ .i64 = value } },
        .f64 => .{ .tag = .f64, .val = .{ .f64 = value } },
        .bool => .{ .tag = .bool, .val = .{ .bool = value } },
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
