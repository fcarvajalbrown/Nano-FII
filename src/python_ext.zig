//! python_ext.zig — Python C extension interface.
//!
//! The ONLY file in Nano-FFI that touches <Python.h>. Defines PyModuleDef,
//! PyMethodDef, and exposes init() which root.zig exports as PyInit_nano_ffi.

const std   = @import("std");
const bridge = @import("comptime_bridge.zig");
const reg   = @import("registry.zig");
const alloc = @import("allocator.zig");

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

fn zigAdd(a: i64, b: i64) i64 { return a + b; }
fn zigMul(a: f64, b: f64) f64 { return a * b; }

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

// ---------------------------------------------------------------------------
// Helper: PyObject* → RawArg
// ---------------------------------------------------------------------------

fn pyToRawArg(obj: *py.PyObject, typ: bridge.ArgType) !bridge.RawArg {
    return switch (typ) {
        .i64  => .{ .tag = .i64,  .val = .{ .i64  = @intCast(py.PyLong_AsLongLong(obj)) } },
        .f64  => .{ .tag = .f64,  .val = .{ .f64  = py.PyFloat_AsDouble(obj) } },
        .bool => .{ .tag = .bool, .val = .{ .bool = py.PyObject_IsTrue(obj) == 1 } },
    };
}

// ---------------------------------------------------------------------------
// Helper: RawRet → PyObject*
// ---------------------------------------------------------------------------

fn rawRetToPy(ret: bridge.RawRet) ?*py.PyObject {
    return switch (ret.tag) {
        .i64  => py.PyLong_FromLongLong(ret.val.i64),
        .f64  => py.PyFloat_FromDouble(ret.val.f64),
        .bool => py.PyBool_FromLong(if (ret.val.bool) 1 else 0),
    };
}

// ---------------------------------------------------------------------------
// nano_ffi.call(name, *args)
// ---------------------------------------------------------------------------

fn py_call(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.C) ?*py.PyObject {
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
            _ = py.PyErr_SetString(py.PyExc_TypeError, "nano_ffi: argument type mismatch");
            return null;
        };
    }

    // Call the trampoline
    const trampoline: *const fn ([*]const bridge.RawArg) callconv(.C) bridge.RawRet = @alignCast(@ptrCast(entry.ptr));
    const ret = trampoline(&raw_args);

    return rawRetToPy(ret);
}

// ---------------------------------------------------------------------------
// nano_ffi.version()
// ---------------------------------------------------------------------------

fn py_version(self: ?*py.PyObject, _: ?*py.PyObject) callconv(.C) ?*py.PyObject {
    _ = self;
    return py.PyUnicode_FromString("0.1.0");
}

// ---------------------------------------------------------------------------
// Method table
// ---------------------------------------------------------------------------

var methods = [_]py.PyMethodDef{
    .{
        .ml_name  = "call",
        .ml_meth  = py_call,
        .ml_flags = py.METH_VARARGS,
        .ml_doc   = "call(name, *args) -> object\n\nInvoke a registered Zig function by name.",
    },
    .{
        .ml_name  = "version",
        .ml_meth  = py_version,
        .ml_flags = py.METH_NOARGS,
        .ml_doc   = "version() -> str\n\nReturn the Nano-FFI library version.",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ---------------------------------------------------------------------------
// Module definition
// ---------------------------------------------------------------------------

var module_def = py.PyModuleDef{
    .m_base     = std.mem.zeroes(py.PyModuleDef_Base),
    .m_name     = "nano_ffi",
    .m_doc      = "Nano-FFI: minimalist Python-to-Zig FFI bridge via comptime trampolines.",
    .m_size     = -1,
    .m_methods  = &methods,
    .m_slots    = null,
    .m_traverse = null,
    .m_clear    = null,
    .m_free     = null,
};

// ---------------------------------------------------------------------------
// Module init — called from root.zig's exported PyInit_nano_ffi
// ---------------------------------------------------------------------------

pub fn init() ?*py.PyObject {
    global_registry = reg.Registry.init(alloc.nano_allocator);
    registry_ready  = true;

    // Register built-in example functions
    global_registry.register("add", AddTrampoline.asPtr(), AddTrampoline.sig) catch return null;
    global_registry.register("mul", MulTrampoline.asPtr(), MulTrampoline.sig) catch return null;

    return py.PyModule_Create(&module_def);
}
