//! registry.zig — Function pointer registry.
//!
//! Maintains a runtime map of name → function pointer so Python can look up
//! and invoke registered Zig functions by string key. Intentionally has zero
//! knowledge of Python internals — all types are plain C-ABI compatible.
//!
//! Uses Zig's AutoHashMap for O(1) average lookup. The registry owns its
//! memory via an explicit allocator passed at init time, satisfying the P1
//! memory safety requirement.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A raw function pointer with C calling convention.
/// All registered functions must conform to this signature at the ABI level;
/// type-safe dispatch is handled upstream in comptime_bridge.zig.
pub const FnPtr = *const fn () callconv(.C) void;

/// A single registry entry.
pub const Entry = struct {
    name: []const u8,
    ptr:  FnPtr,
};

/// The registry itself. Create one per module with `Registry.init(allocator)`.
pub const Registry = struct {
    map:       std.StringHashMap(FnPtr),
    allocator: Allocator,

    /// Initialise the registry. `allocator` must outlive the registry.
    pub fn init(allocator: Allocator) Registry {
        return .{
            .map       = std.StringHashMap(FnPtr).init(allocator),
            .allocator = allocator,
        };
    }

    /// Release all map memory. Does NOT free the keys — callers own key slices.
    pub fn deinit(self: *Registry) void {
        self.map.deinit();
    }

    /// Register a function pointer under `name`.
    /// Returns error.OutOfMemory if the map cannot grow.
    pub fn register(self: *Registry, name: []const u8, ptr: FnPtr) !void {
        try self.map.put(name, ptr);
    }

    /// Look up a function by name. Returns null if not found.
    pub fn lookup(self: *const Registry, name: []const u8) ?FnPtr {
        return self.map.get(name);
    }

    /// Number of registered functions.
    pub fn count(self: *const Registry) usize {
        return self.map.count();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "register and lookup" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const dummy: FnPtr = @ptrCast(&dummyFn);
    try reg.register("add", dummy);

    const found = reg.lookup("add");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(dummy, found.?);
}

test "lookup missing key returns null" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try std.testing.expect(reg.lookup("nonexistent") == null);
}

test "count reflects registrations" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const dummy: FnPtr = @ptrCast(&dummyFn);
    try reg.register("a", dummy);
    try reg.register("b", dummy);

    try std.testing.expectEqual(@as(usize, 2), reg.count());
}

/// Dummy function used only in tests — never called, just address-taken.
fn dummyFn() callconv(.C) void {}
