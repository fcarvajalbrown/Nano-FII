//! root.zig — Nano-FFI library entry point.
//!
//! Imports all submodules. The Python module init symbol (PyInit_nano_ffi)
//! must be declared with `export` at this top level so the linker emits it
//! as an unmangled symbol that Python's import machinery can find.

const std = @import("std");

pub const registry  = @import("registry.zig");
pub const bridge    = @import("comptime_bridge.zig");
pub const allocator = @import("allocator.zig");
pub const python    = @import("python_ext.zig");

/// Force the linker to export PyInit_nano_ffi as an unmangled C symbol.
/// A `pub const` alias is NOT sufficient — must be a real `export fn`.
pub export fn PyInit_nano_ffi() callconv(.C) ?*anyopaque {
    return python.init();
}

pub const version: []const u8 = "0.1.0";

test {
    std.testing.refAllDeclsRecursive(@This());
}
