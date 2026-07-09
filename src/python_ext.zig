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
fn zigCheckedDiv(a: i64, b: i64) error{DivisionByZero}!i64 {
    if (b == 0) return error.DivisionByZero;
    return @divTrunc(a, b);
}
fn zigDivMod(a: i64, b: i64) struct { i64, i64 } {
    return .{ @divTrunc(a, b), @mod(a, b) };
}
fn zigSignMag(x: i64) struct { bool, u64 } {
    return .{ x < 0, @abs(x) };
}
fn zigFill(buf: []u8, val: u8) u64 {
    for (buf) |*b| b.* = val;
    return buf.len;
}
fn zigBufMax(buf: []const u8) u8 {
    var m: u8 = 0;
    for (buf) |b| {
        if (b > m) m = b;
    }
    return m;
}
fn zigSum8(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) i64 {
    return a + b + c + d + e + f + g + h;
}
fn zigScaleF32(x: f32) f32 {
    return x * 2.0;
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

const DivTrampoline = bridge.makeTrampoline(zigCheckedDiv, .{
    .args = &.{
        .{ .name = "a", .typ = .i64 },
        .{ .name = "b", .typ = .i64 },
    },
    .ret = .i64,
});

const DivModTrampoline = bridge.makeTrampoline(zigDivMod, .{
    .args = &.{
        .{ .name = "a", .typ = .i64 },
        .{ .name = "b", .typ = .i64 },
    },
    .rets = &.{ .i64, .i64 },
});

const SignMagTrampoline = bridge.makeTrampoline(zigSignMag, .{
    .args = &.{.{ .name = "x", .typ = .i64 }},
    .rets = &.{ .bool, .u64 },
});

const FillTrampoline = bridge.makeTrampoline(zigFill, .{
    .args = &.{
        .{ .name = "buf", .typ = .buffer },
        .{ .name = "val", .typ = .u8 },
    },
    .ret = .u64,
});

const BufMaxTrampoline = bridge.makeTrampoline(zigBufMax, .{
    .args = &.{.{ .name = "buf", .typ = .buffer }},
    .ret = .u8,
});

const Sum8Trampoline = bridge.makeTrampoline(zigSum8, .{
    .args = &.{
        .{ .name = "a", .typ = .i64 }, .{ .name = "b", .typ = .i64 },
        .{ .name = "c", .typ = .i64 }, .{ .name = "d", .typ = .i64 },
        .{ .name = "e", .typ = .i64 }, .{ .name = "f", .typ = .i64 },
        .{ .name = "g", .typ = .i64 }, .{ .name = "h", .typ = .i64 },
    },
    .ret = .i64,
});

const ScaleF32Trampoline = bridge.makeTrampoline(zigScaleF32, .{
    .args = &.{.{ .name = "x", .typ = .f32 }},
    .ret = .f32,
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
        // Buffers are acquired/released in py_call (they need explicit
        // teardown after the trampoline runs), never through this path.
        .buffer => error.ConversionFailed,
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
    // Multi-value return: build a Python tuple from the shared buffer.
    if (ret.n_rets > 1) {
        const tup = py.PyTuple_New(@intCast(ret.n_rets)) orelse return null;
        var i: usize = 0;
        while (i < ret.n_rets) : (i += 1) {
            const item = rawRetToPy(bridge.multi_ret[i]) orelse {
                py.Py_DecRef(tup);
                return null;
            };
            _ = py.PyTuple_SetItem(tup, @intCast(i), item); // steals ref
        }
        return tup;
    }
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
        // `buffer` is argument-only; never a return tag.
        .buffer => null,
    };
}

// Release every Py_buffer acquired for the current call.
fn releaseViews(views: *[8]py.Py_buffer, n: usize) void {
    var j: usize = 0;
    while (j < n) : (j += 1) py.PyBuffer_Release(&views[j]);
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

    // Unpack Python args into RawArg array (max 8 args). Buffer arguments
    // acquire a zero-copy view here and must be released after the call, so
    // track the acquired Py_buffers and tear them down in one place.
    var raw_args: [8]bridge.RawArg = undefined;
    var views: [8]py.Py_buffer = undefined;
    var n_views: usize = 0;

    for (sig.args, 0..) |desc, i| {
        const py_arg = py.PyTuple_GetItem(args, @intCast(i + 1)) orelse {
            releaseViews(&views, n_views);
            return null;
        };

        if (desc.typ == .buffer) {
            if (py.PyObject_GetBuffer(py_arg, &views[n_views], py.PyBUF_WRITABLE) != 0) {
                // GetBuffer set a BufferError (e.g. object is read-only).
                releaseViews(&views, n_views);
                return null;
            }
            raw_args[i] = .{ .tag = .buffer, .val = .{ .slice = .{
                .ptr = @ptrCast(views[n_views].buf),
                .len = @intCast(views[n_views].len),
            } } };
            n_views += 1;
        } else {
            raw_args[i] = pyToRawArg(py_arg, desc.typ) catch {
                // Preserve a precise exception already set by the converter
                // (e.g. ValueError on out-of-range); only fall back otherwise.
                if (py.PyErr_Occurred() == null) {
                    _ = py.PyErr_SetString(py.PyExc_TypeError, "nano_ffi: argument type mismatch");
                }
                releaseViews(&views, n_views);
                return null;
            };
        }
    }

    // Call the trampoline
    const trampoline: *const fn ([*]const bridge.RawArg) callconv(.c) bridge.RawRet = @ptrCast(@alignCast(entry.ptr));
    const ret = trampoline(&raw_args);

    // Zig is done with the buffers; release the views before marshalling.
    releaseViews(&views, n_views);

    // A Zig error union that resolved to an error surfaces as a Python
    // RuntimeError carrying the Zig error name (e.g. "DivisionByZero").
    if (ret.err_ptr) |p| {
        const msg = py.PyUnicode_FromStringAndSize(@ptrCast(p), @intCast(ret.err_len));
        if (msg) |m| {
            py.PyErr_SetObject(py.PyExc_RuntimeError, m);
            py.Py_DecRef(m);
        } else {
            _ = py.PyErr_SetString(py.PyExc_RuntimeError, "nano_ffi: zig function returned an error");
        }
        return null;
    }

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
// nano_ffi.list_functions() — names of every registered function
// ---------------------------------------------------------------------------

fn py_list_functions(self: ?*py.PyObject, _: ?*py.PyObject) callconv(.c) ?*py.PyObject {
    _ = self;
    if (!registry_ready) {
        _ = py.PyErr_SetString(py.PyExc_RuntimeError, "nano_ffi registry not initialised");
        return null;
    }
    const list = py.PyList_New(0) orelse return null;
    var it = global_registry.map.iterator();
    while (it.next()) |e| {
        const name = e.key_ptr.*;
        const s = py.PyUnicode_FromStringAndSize(@ptrCast(name.ptr), @intCast(name.len)) orelse {
            py.Py_DecRef(list);
            return null;
        };
        const rc = py.PyList_Append(list, s);
        py.Py_DecRef(s);
        if (rc != 0) {
            py.Py_DecRef(list);
            return null;
        }
    }
    return list;
}

// ---------------------------------------------------------------------------
// nano_ffi.signature(name) -> {"args": [(name, type), ...], "ret": type}
// ---------------------------------------------------------------------------

fn py_signature(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
    _ = self;
    if (!registry_ready) {
        _ = py.PyErr_SetString(py.PyExc_RuntimeError, "nano_ffi registry not initialised");
        return null;
    }

    var name_cstr: [*c]const u8 = undefined;
    if (py.PyArg_ParseTuple(args, "s", &name_cstr) == 0) return null;
    const name = std.mem.span(name_cstr);

    const entry = global_registry.lookup(name) orelse {
        _ = py.PyErr_SetString(py.PyExc_KeyError, "nano_ffi: function not found");
        return null;
    };

    const dict = py.PyDict_New() orelse return null;
    const arg_list = py.PyList_New(0) orelse {
        py.Py_DecRef(dict);
        return null;
    };

    for (entry.sig.args) |desc| {
        const nm = py.PyUnicode_FromStringAndSize(@ptrCast(desc.name.ptr), @intCast(desc.name.len));
        const ty = py.PyUnicode_FromString(@tagName(desc.typ));
        const pair = py.PyTuple_Pack(2, nm, ty);
        if (nm) |x| py.Py_DecRef(x);
        if (ty) |x| py.Py_DecRef(x);
        if (pair) |p| {
            _ = py.PyList_Append(arg_list, p);
            py.Py_DecRef(p);
        }
    }

    _ = py.PyDict_SetItemString(dict, "args", arg_list);
    py.Py_DecRef(arg_list);

    if (entry.sig.rets.len > 0) {
        // Multi-value return: "ret" is a list of type names.
        const ret_list = py.PyList_New(0);
        if (ret_list) |rl| {
            for (entry.sig.rets) |rt| {
                const ty = py.PyUnicode_FromString(@tagName(rt));
                if (ty) |t| {
                    _ = py.PyList_Append(rl, t);
                    py.Py_DecRef(t);
                }
            }
            _ = py.PyDict_SetItemString(dict, "ret", rl);
            py.Py_DecRef(rl);
        }
    } else {
        const ret_ty = py.PyUnicode_FromString(@tagName(entry.sig.ret));
        if (ret_ty) |r| {
            _ = py.PyDict_SetItemString(dict, "ret", r);
            py.Py_DecRef(r);
        }
    }
    return dict;
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
    .{
        .ml_name = "list_functions",
        .ml_meth = py_list_functions,
        .ml_flags = py.METH_NOARGS,
        .ml_doc = "list_functions() -> list[str]\n\nNames of every registered Zig function.",
    },
    .{
        .ml_name = "signature",
        .ml_meth = py_signature,
        .ml_flags = py.METH_VARARGS,
        .ml_doc = "signature(name) -> dict\n\nDescribe a function's argument names/types and return type.",
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
    global_registry.register("div", DivTrampoline.asPtr(), DivTrampoline.sig) catch return null;
    global_registry.register("divmod", DivModTrampoline.asPtr(), DivModTrampoline.sig) catch return null;
    global_registry.register("signmag", SignMagTrampoline.asPtr(), SignMagTrampoline.sig) catch return null;
    global_registry.register("fill", FillTrampoline.asPtr(), FillTrampoline.sig) catch return null;
    global_registry.register("bufmax", BufMaxTrampoline.asPtr(), BufMaxTrampoline.sig) catch return null;
    global_registry.register("sum8", Sum8Trampoline.asPtr(), Sum8Trampoline.sig) catch return null;
    global_registry.register("scalef32", ScaleF32Trampoline.asPtr(), ScaleF32Trampoline.sig) catch return null;

    return py.PyModule_Create(&module_def);
}
