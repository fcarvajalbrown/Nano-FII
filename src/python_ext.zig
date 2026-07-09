//! python_ext.zig — Python C extension interface.
//!
//! The ONLY file in Nano-FFI that touches <Python.h>. Defines PyModuleDef,
//! PyMethodDef, and exposes init() which root.zig exports as PyInit_nano_ffi.

const std = @import("std");
const bridge = @import("comptime_bridge.zig");
const reg = @import("registry.zig");
const alloc = @import("allocator.zig");
const version = @import("version.zig");

const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");
    @cInclude("Python.h");
});

// ---------------------------------------------------------------------------
// Module-level registry
// ---------------------------------------------------------------------------

var global_registry: reg.Registry = undefined;
var registry_ready: bool = false;

// ---------------------------------------------------------------------------
// Built-in example functions (registered at init for testing)
// ---------------------------------------------------------------------------

fn zigAdd(a: i64, b: i64) i64 {
    return a + b;
}
fn zigMul(a: f64, b: f64) f64 {
    return a * b;
}
fn zigAdd32(a: i32, b: i32) i32 {
    return a + b;
}
fn zigUMul(a: u64, b: u64) u64 {
    return a * b;
}
fn zigStrLen(s: []const u8) i64 {
    return @intCast(s.len);
}
fn zigEcho(s: []const u8) []const u8 {
    return s;
}
fn zigByteSum(b: []const u8) u64 {
    var sum: u64 = 0;
    for (b) |x| sum += x;
    return sum;
}

const AddTrampoline = bridge.makeTrampoline(zigAdd, .{
    .args = &.{
        .{ .name = "a", .typ = .i64 },
        .{ .name = "b", .typ = .i64 },
    },
    .ret = .i64,
});

const MulTrampoline = bridge.makeTrampoline(zigMul, .{
    .args = &.{
        .{ .name = "a", .typ = .f64 },
        .{ .name = "b", .typ = .f64 },
    },
    .ret = .f64,
});

const Add32Trampoline = bridge.makeTrampoline(zigAdd32, .{
    .args = &.{
        .{ .name = "a", .typ = .i32 },
        .{ .name = "b", .typ = .i32 },
    },
    .ret = .i32,
});

const UMulTrampoline = bridge.makeTrampoline(zigUMul, .{
    .args = &.{
        .{ .name = "a", .typ = .u64 },
        .{ .name = "b", .typ = .u64 },
    },
    .ret = .u64,
});

const StrLenTrampoline = bridge.makeTrampoline(zigStrLen, .{
    .args = &.{.{ .name = "s", .typ = .str }},
    .ret = .i64,
});

const EchoTrampoline = bridge.makeTrampoline(zigEcho, .{
    .args = &.{.{ .name = "s", .typ = .str }},
    .ret = .str,
});

const ByteSumTrampoline = bridge.makeTrampoline(zigByteSum, .{
    .args = &.{.{ .name = "b", .typ = .bytes }},
    .ret = .u64,
});

// ---------------------------------------------------------------------------
// Helper: PyObject* → RawArg
// ---------------------------------------------------------------------------

// Range-checked signed conversion. A Python int outside the target width
// raises ValueError instead of silently truncating.
fn signedInRange(obj: *py.PyObject, comptime T: type) !T {
    const v = py.PyLong_AsLongLong(obj);
    if (v == -1 and py.PyErr_Occurred() != null) return error.ConversionFailed;
    if (v < std.math.minInt(T) or v > std.math.maxInt(T)) {
        _ = py.PyErr_SetString(py.PyExc_ValueError, "nano_ffi: integer argument out of range for target type");
        return error.ConversionFailed;
    }
    return @intCast(v);
}

// Range-checked unsigned conversion for widths that fit in i64 (u8, u32).
fn unsignedInRange(obj: *py.PyObject, comptime T: type) !T {
    const v = py.PyLong_AsLongLong(obj);
    if (v == -1 and py.PyErr_Occurred() != null) return error.ConversionFailed;
    if (v < 0 or v > std.math.maxInt(T)) {
        _ = py.PyErr_SetString(py.PyExc_ValueError, "nano_ffi: integer argument out of range for target type");
        return error.ConversionFailed;
    }
    return @intCast(v);
}

// u64 needs the full unsigned-long-long range, above i64 max.
fn convertU64(obj: *py.PyObject) !u64 {
    const v = py.PyLong_AsUnsignedLongLong(obj);
    if (py.PyErr_Occurred() != null) return error.ConversionFailed;
    return @intCast(v);
}

fn pyToRawArg(obj: *py.PyObject, typ: bridge.ArgType) !bridge.RawArg {
    return switch (typ) {
        .i64 => .{ .tag = .i64, .val = .{ .i64 = try signedInRange(obj, i64) } },
        .i32 => .{ .tag = .i32, .val = .{ .i32 = try signedInRange(obj, i32) } },
        .u8 => .{ .tag = .u8, .val = .{ .u8 = try unsignedInRange(obj, u8) } },
        .u32 => .{ .tag = .u32, .val = .{ .u32 = try unsignedInRange(obj, u32) } },
        .u64 => .{ .tag = .u64, .val = .{ .u64 = try convertU64(obj) } },
        .f64 => .{ .tag = .f64, .val = .{ .f64 = py.PyFloat_AsDouble(obj) } },
        .f32 => .{ .tag = .f32, .val = .{ .f32 = @floatCast(py.PyFloat_AsDouble(obj)) } },
        .bool => .{ .tag = .bool, .val = .{ .bool = py.PyObject_IsTrue(obj) == 1 } },
        .str => try strToRawArg(obj),
        .bytes => try bytesToRawArg(obj),
    };
}

// Python str -> borrowed UTF-8 view. The pointer is owned by the PyUnicode
// object and stays valid for the duration of the call; the marshaller copies
// it into a fresh Python object before returning, so nothing dangles.
fn strToRawArg(obj: *py.PyObject) !bridge.RawArg {
    var size: py.Py_ssize_t = 0;
    const p = py.PyUnicode_AsUTF8AndSize(obj, &size);
    if (p == null) return error.ConversionFailed; // PyUnicode_* set a TypeError
    return .{ .tag = .str, .val = .{ .slice = .{ .ptr = @ptrCast(p), .len = @intCast(size) } } };
}

// Python bytes -> borrowed view over the object's buffer.
fn bytesToRawArg(obj: *py.PyObject) !bridge.RawArg {
    var buf: [*c]u8 = undefined;
    var size: py.Py_ssize_t = 0;
    if (py.PyBytes_AsStringAndSize(obj, &buf, &size) != 0) return error.ConversionFailed;
    return .{ .tag = .bytes, .val = .{ .slice = .{ .ptr = @ptrCast(buf), .len = @intCast(size) } } };
}

// ---------------------------------------------------------------------------
// Helper: RawRet → PyObject*
// ---------------------------------------------------------------------------

fn rawRetToPy(ret: bridge.RawRet) ?*py.PyObject {
    return switch (ret.tag) {
        .i64 => py.PyLong_FromLongLong(ret.val.i64),
        .i32 => py.PyLong_FromLong(ret.val.i32),
        .u8 => py.PyLong_FromUnsignedLong(ret.val.u8),
        .u32 => py.PyLong_FromUnsignedLong(ret.val.u32),
        .u64 => py.PyLong_FromUnsignedLongLong(ret.val.u64),
        .f64 => py.PyFloat_FromDouble(ret.val.f64),
        .f32 => py.PyFloat_FromDouble(@floatCast(ret.val.f32)),
        .bool => py.PyBool_FromLong(if (ret.val.bool) 1 else 0),
        // Both copy the bytes into a new, Python-owned object.
        .str => py.PyUnicode_FromStringAndSize(@ptrCast(ret.val.slice.ptr), @intCast(ret.val.slice.len)),
        .bytes => py.PyBytes_FromStringAndSize(@ptrCast(ret.val.slice.ptr), @intCast(ret.val.slice.len)),
    };
}

// ---------------------------------------------------------------------------
// nano_ffi.call(name, *args)
// ---------------------------------------------------------------------------

fn py_call(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
    _ = self;

    const tuple_size = py.PyTuple_Size(args);
    if (tuple_size < 1) {
        _ = py.PyErr_SetString(py.PyExc_TypeError, "call() requires at least a function name");
        return null;
    }

    // Extract function name
    const name_obj = py.PyTuple_GetItem(args, 0) orelse return null;
    const name_cstr = py.PyUnicode_AsUTF8(name_obj) orelse {
        _ = py.PyErr_SetString(py.PyExc_TypeError, "call() first argument must be a string");
        return null;
    };
    const name = std.mem.span(name_cstr);

    if (!registry_ready) {
        _ = py.PyErr_SetString(py.PyExc_RuntimeError, "nano_ffi registry not initialised");
        return null;
    }

    // Look up entry (FnPtr + Signature)
    const entry = global_registry.lookup(name) orelse {
        _ = py.PyErr_SetString(py.PyExc_KeyError, "nano_ffi: function not found");
        return null;
    };

    const sig = entry.sig;
    const expected_args = sig.args.len;
    const provided_args = @as(usize, @intCast(tuple_size - 1));

    if (provided_args != expected_args) {
        _ = py.PyErr_SetString(py.PyExc_TypeError, "nano_ffi: wrong number of arguments");
        return null;
    }

    // Unpack Python args into RawArg array (max 8 args)
    var raw_args: [8]bridge.RawArg = undefined;
    for (sig.args, 0..) |desc, i| {
        const py_arg = py.PyTuple_GetItem(args, @intCast(i + 1)) orelse return null;
        raw_args[i] = pyToRawArg(py_arg, desc.typ) catch {
            // Preserve a precise exception already set by the converter
            // (e.g. ValueError on out-of-range); only fall back otherwise.
            if (py.PyErr_Occurred() == null) {
                _ = py.PyErr_SetString(py.PyExc_TypeError, "nano_ffi: argument type mismatch");
            }
            return null;
        };
    }

    // Call the trampoline
    const trampoline: *const fn ([*]const bridge.RawArg) callconv(.c) bridge.RawRet = @ptrCast(@alignCast(entry.ptr));
    const ret = trampoline(&raw_args);

    return rawRetToPy(ret);
}

// ---------------------------------------------------------------------------
// nano_ffi.version()
// ---------------------------------------------------------------------------

fn py_version(self: ?*py.PyObject, _: ?*py.PyObject) callconv(.c) ?*py.PyObject {
    _ = self;
    return py.PyUnicode_FromString(version.literal);
}

// ---------------------------------------------------------------------------
// Method table
// ---------------------------------------------------------------------------

var methods = [_]py.PyMethodDef{
    .{
        .ml_name = "call",
        .ml_meth = py_call,
        .ml_flags = py.METH_VARARGS,
        .ml_doc = "call(name, *args) -> object\n\nInvoke a registered Zig function by name.",
    },
    .{
        .ml_name = "version",
        .ml_meth = py_version,
        .ml_flags = py.METH_NOARGS,
        .ml_doc = "version() -> str\n\nReturn the Nano-FFI library version.",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ---------------------------------------------------------------------------
// Module definition
// ---------------------------------------------------------------------------

var module_def = py.PyModuleDef{
    .m_base = std.mem.zeroes(py.PyModuleDef_Base),
    .m_name = "nano_ffi",
    .m_doc = "Nano-FFI: minimalist Python-to-Zig FFI bridge via comptime trampolines.",
    .m_size = -1,
    .m_methods = &methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

// ---------------------------------------------------------------------------
// Module init — called from root.zig's exported PyInit_nano_ffi
// ---------------------------------------------------------------------------

pub fn init() ?*py.PyObject {
    global_registry = reg.Registry.init(alloc.nano_allocator);
    registry_ready = true;

    // Register built-in example functions
    global_registry.register("add", AddTrampoline.asPtr(), AddTrampoline.sig) catch return null;
    global_registry.register("mul", MulTrampoline.asPtr(), MulTrampoline.sig) catch return null;
    global_registry.register("add32", Add32Trampoline.asPtr(), Add32Trampoline.sig) catch return null;
    global_registry.register("umul", UMulTrampoline.asPtr(), UMulTrampoline.sig) catch return null;
    global_registry.register("strlen", StrLenTrampoline.asPtr(), StrLenTrampoline.sig) catch return null;
    global_registry.register("echo", EchoTrampoline.asPtr(), EchoTrampoline.sig) catch return null;
    global_registry.register("bytesum", ByteSumTrampoline.asPtr(), ByteSumTrampoline.sig) catch return null;

    return py.PyModule_Create(&module_def);
}
