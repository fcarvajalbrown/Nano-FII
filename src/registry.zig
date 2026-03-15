//! registry.zig — Function pointer registry.
//!
//! Stores name → (FnPtr, Signature) so the dispatcher in python_ext.zig
//! knows how to unpack Python arguments before calling the trampoline.

const std       = @import("std");
const bridge    = @import("comptime_bridge.zig");
const Allocator = std.mem.Allocator;

/// A raw function pointer with C calling convention.
pub const FnPtr = *const fn () callconv(.C) void;

/// A registry entry: function pointer + its type signature.
pub const Entry = struct {
    ptr: FnPtr,
    sig: bridge.Signature,
};

/// The registry. Create one per module with `Registry.init(allocator)`.
pub const Registry = struct {
    map:       std.StringHashMap(Entry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Registry {
        return .{
            .map       = std.StringHashMap(Entry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Registry) void {
        self.map.deinit();
    }

    /// Register a function pointer and its signature under `name`.
    pub fn register(self: *Registry, name: []const u8, ptr: FnPtr, sig: bridge.Signature) !void {
        try self.map.put(name, .{ .ptr = ptr, .sig = sig });
    }

    /// Look up an entry by name. Returns null if not found.
    pub fn lookup(self: *const Registry, name: []const u8) ?Entry {
        return self.map.get(name);
    }

    pub fn count(self: *const Registry) usize {
        return self.map.count();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "register and lookup with signature" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const dummy: FnPtr = @ptrCast(&dummyFn);
    const sig = bridge.Signature{
        .args = &.{ .{ .name = "a", .typ = .i64 }, .{ .name = "b", .typ = .i64 } },
        .ret  = .i64,
    };

    try reg.register("add", dummy, sig);

    const entry = reg.lookup("add");
    try std.testing.expect(entry != null);
    try std.testing.expectEqual(dummy, entry.?.ptr);
    try std.testing.expectEqual(@as(usize, 2), entry.?.sig.args.len);
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
    const sig = bridge.Signature{ .args = &.{}, .ret = .i64 };

    try reg.register("a", dummy, sig);
    try reg.register("b", dummy, sig);
    try std.testing.expectEqual(@as(usize, 2), reg.count());
}

fn dummyFn() callconv(.C) void {}
