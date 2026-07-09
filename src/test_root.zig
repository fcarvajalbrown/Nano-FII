//! test_root.zig — Root for `zig build test`.
//!
//! Covers the pure-Zig core (comptime bridge, registry, allocator, version).
//! Deliberately excludes python_ext.zig: that module imports <Python.h> and
//! only makes sense linked into the CPython extension, so its behaviour is
//! exercised by the Python end-to-end suite (tests/test_python.py) instead.

const std = @import("std");

pub const registry = @import("registry.zig");
pub const bridge = @import("comptime_bridge.zig");
pub const allocator = @import("allocator.zig");
pub const version = @import("version.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
