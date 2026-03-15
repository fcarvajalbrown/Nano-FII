//! build.zig — Nano-FFI build script.
//!
//! Compiles the Zig core into a shared library (.so / .pyd) that Python can
//! import directly. scikit-build-core invokes `zig build` during `pip install`.
//!
//! Usage:
//!   zig build                  → debug build
//!   zig build -Doptimize=ReleaseFast  → production build
//!   zig build -Dtarget=x86_64-windows-gnu  → cross-compile for Windows

const std = @import("std");

pub fn build(b: *std.Build) void {
    // --- 1. Target & optimization mode (overridable via CLI flags) -----------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- 2. Shared library (.so on Linux, .pyd on Windows, .dylib on macOS) --
    const lib = b.addSharedLibrary(.{
        .name = "nano_ffi",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- 3. Link against Python headers (provided by scikit-build-core) ------
    // scikit-build-core sets PYTHON_INCLUDE_DIR in the environment.
    // Fall back to the system Python for plain `zig build` invocations.
    if (b.option([]const u8, "python-include", "Path to Python include dir")) |inc| {
        lib.addIncludePath(.{ .cwd_relative = inc });
    } else {
        // Best-effort: works when Python headers are on the default system path.
        lib.addIncludePath(.{ .cwd_relative = "/usr/include/python3" });
    }

    // --- 4. Link libc (required for C-ABI compatibility with Python) ---------
    lib.linkLibC();

    // --- 5. Install the compiled artifact into zig-out/lib/ ------------------
    b.installArtifact(lib);

    // --- 6. Unit test step (`zig build test`) ---------------------------------
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
}