//! root.zig — Nano-FFI library entry point.
//!
//! Imports all submodules and re-exports the Python extension initializer
//! (`PyInit_nano_ffi`) that Python's import machinery looks for when loading
//! the shared library.

const std = @import("std");

pub const registry = @import("registry.zig");
pub const bridge = @import("comptime_bridge.zig");
pub const allocator = @import("allocator.zig");
pub const python = @import("python_ext.zig");

// Re-export the Python module init symbol at the top level so the linker
// finds it without extra flags.
pub const PyInit_nano_ffi = python.PyInit_nano_ffi;

// Expose the version as a comptime constant — readable from Python via
// nano_ffi.__version__ once wired in python_ext.zig.
pub const version: []const u8 = "0.1.0";

test {
    // Pull in all tests from submodules with a single statement.
    std.testing.refAllDeclsRecursive(@This());
}
