//! python_ext.zig — Python C extension interface.
//!
//! The ONLY file in Nano-FFI that touches <Python.h>. Defines PyModuleDef,
//! PyMethodDef, and the PyInit_nano_ffi symbol that Python's import machinery
//! looks for when loading the shared library.
//!
//! Keeps all Python API calls in one place so the rest of the codebase stays
//! pure Zig with no CPython coupling.

const std     = @import("std");
const bridge  = @import("comptime_bridge.zig");
const reg     = @import("registry.zig");
const alloc   = @import("allocator.zig");

// ---------------------------------------------------------------------------
// CPython headers via Zig's cImport
// ---------------------------------------------------------------------------

const py = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");
    @cInclude("Python.h");
});

// ---------------------------------------------------------------------------
// Module-level registry (lives for the lifetime of the Python process)
// ---------------------------------------------------------------------------

var global_registry: reg.Registry = undefined;
var registry_ready: bool = false;

// ---------------------------------------------------------------------------
// Helper: convert a RawRet back to a PyObject*
// ---------------------------------------------------------------------------

fn rawRetToPy(ret: bridge.RawRet) ?*py.PyObject {
    return switch (ret) {
        .i64  => |v| py.PyLong_FromLongLong(v),
        .f64  => |v| py.PyFloat_FromDouble(v),
        .bool => |v| if (v) py.Py_True else py.Py_False,
    };
}

// ---------------------------------------------------------------------------
// Helper: convert a PyObject* to a RawArg given an expected ArgType
// ---------------------------------------------------------------------------

fn pyToRawArg(obj: *py.PyObject, typ: bridge.ArgType) !bridge.RawArg {
    return switch (typ) {
        .i64  => .{ .i64  = py.PyLong_AsLongLong(obj) },
        .f64  => .{ .f64  = py.PyFloat_AsDouble(obj) },
        .bool => .{ .bool = py.PyObject_IsTrue(obj) == 1 },
    };
}

// ---------------------------------------------------------------------------
// nano_ffi.call(name, *args) — the single Python-facing entry point
// ---------------------------------------------------------------------------
//
// Python usage:
//   import nano_ffi
//   result = nano_ffi.call("add", 3, 4)

fn py_call(self: ?*py.PyObject, args: ?*py.PyObject) callconv(.C) ?*py.PyObject {
    _ = self;

    // Parse first argument: function name as UTF-8 string
    var name_cstr: [*c]const u8 = null;
    var rest: ?*py.PyObject = null;

    if (py.PyArg_ParseTuple(args, "sO", &name_cstr, &rest) == 0) {
        return null; // TypeError already set by Python
    }

    const name = std.mem.span(name_cstr);

    // Look up function pointer in the global registry
    if (!registry_ready) {
        _ = py.PyErr_SetString(py.PyExc_RuntimeError, "nano_ffi registry not initialised");
        return null;
    }

    _ = global_registry.lookup(name) orelse {
        _ = py.PyErr_SetString(py.PyExc_KeyError, "nano_ffi: function not found");
        return null;
    };
    _ = rest;

    // For now: call the raw function pointer directly.
    // Full arg unpacking from `rest` is wired in once signature metadata
    // is stored alongside the function pointer in a future registry upgrade.
    // TODO(day-3): store Signature alongside FnPtr in registry, unpack
    // args tuple here using pyToRawArg, call trampoline, return rawRetToPy.
    _ = py.PyErr_SetString(py.PyExc_NotImplementedError,
        "nano_ffi.call: full dispatch not yet wired — see TODO(day-3)");
    return null;
}

// ---------------------------------------------------------------------------
// nano_ffi.version() — returns the library version string
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
    // Sentinel — required by CPython
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ---------------------------------------------------------------------------
// Module definition
// ---------------------------------------------------------------------------

var module_def = py.PyModuleDef{
    .m_base    = py.PyModuleDef_HEAD_INIT,
    .m_name    = "nano_ffi",
    .m_doc     = "Nano-FFI: minimalist Python-to-Zig FFI bridge via comptime trampolines.",
    .m_size    = -1,
    .m_methods = &methods,
    .m_slots   = null,
    .m_traverse = null,
    .m_clear   = null,
    .m_free    = null,
};

// ---------------------------------------------------------------------------
// Module initialiser — symbol Python's import looks for
// ---------------------------------------------------------------------------

export fn PyInit_nano_ffi() ?*py.PyObject {
    // Initialise the global registry
    global_registry = reg.Registry.init(alloc.nano_allocator);
    registry_ready  = true;

    return py.PyModule_Create(&module_def);
}
