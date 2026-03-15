//! allocator.zig — Explicit allocator wrappers for Python-Zig memory boundary.
//!
//! Memory passed across the Python-Zig boundary must be explicitly managed.
//! Python owns its objects; Zig owns its allocations. This module provides
//! a clear contract: Zig allocates, Zig frees — Python never touches raw
//! Zig heap pointers directly.
//!
//! Uses Zig's GeneralPurposeAllocator in debug builds (catches leaks/double-frees)
//! and a plain C allocator in release builds (zero overhead).

const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// Global allocator selection
// ---------------------------------------------------------------------------

/// In debug builds: GPA catches leaks and double-frees.
/// In release builds: raw C allocator — malloc/free, no overhead.
const BackingAllocator = if (builtin.mode == .Debug)
    std.heap.GeneralPurposeAllocator(.{ .safety = true })
else
    void;

var backing: BackingAllocator = if (builtin.mode == .Debug)
    .{}
else
    {};

/// The allocator instance to use throughout Nano-FFI.
/// Pass this into Registry.init() and any other allocating component.
pub const nano_allocator: std.mem.Allocator = if (builtin.mode == .Debug)
    backing.allocator()
else
    std.heap.c_allocator;

// ---------------------------------------------------------------------------
// Buffer — a Zig-owned byte buffer safe to pass to Python as a read-only view
// ---------------------------------------------------------------------------

/// A heap-allocated buffer whose lifetime is explicitly controlled by Zig.
/// Python receives a pointer + length; Zig is responsible for freeing.
pub const Buffer = struct {
    data: []u8,
    allocator: std.mem.Allocator,

    /// Allocate a buffer of `size` bytes.
    pub fn alloc(allocator: std.mem.Allocator, size: usize) !Buffer {
        return .{
            .data      = try allocator.alloc(u8, size),
            .allocator = allocator,
        };
    }

    /// Free the buffer. Must be called exactly once.
    pub fn free(self: *Buffer) void {
        self.allocator.free(self.data);
        self.data = &.{};
    }

    /// Raw pointer for passing to Python (read-only from Python's side).
    pub fn ptr(self: *const Buffer) [*]const u8 {
        return self.data.ptr;
    }

    /// Length in bytes.
    pub fn len(self: *const Buffer) usize {
        return self.data.len;
    }
};

/// Call at program exit in debug builds to check for leaks.
/// No-op in release builds.
pub fn deinitAllocator() void {
    if (builtin.mode == .Debug) {
        _ = backing.deinit();
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "buffer alloc and free" {
    var buf = try Buffer.alloc(std.testing.allocator, 64);
    defer buf.free();

    try std.testing.expectEqual(@as(usize, 64), buf.len());
    try std.testing.expect(buf.ptr() != null);
}

test "buffer write and read" {
    var buf = try Buffer.alloc(std.testing.allocator, 4);
    defer buf.free();

    buf.data[0] = 0xDE;
    buf.data[1] = 0xAD;
    buf.data[2] = 0xBE;
    buf.data[3] = 0xEF;

    try std.testing.expectEqual(@as(u8, 0xDE), buf.data[0]);
    try std.testing.expectEqual(@as(u8, 0xEF), buf.data[3]);
}
