//! build.zig — Nano-FFI build script.
//!
//! Compiles the Zig core into a shared library (.so / .pyd) that Python can
//! import directly. scikit-build-core invokes `zig build` during `pip install`.
//!
//! Usage:
//!   zig build                          -> debug build
//!   zig build -Doptimize=ReleaseFast   -> production build
//!   zig build -Dtarget=x86_64-windows-gnu  -> cross-compile for Windows

const std = @import("std");

pub fn build(b: *std.Build) void {
    // --- 1. Target & optimization mode ----------------------------------------
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- 2. Shared library ----------------------------------------------------
    const lib = b.addSharedLibrary(.{
        .name = "nano_ffi",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // --- 3. Python headers ----------------------------------------------------
    if (b.option([]const u8, "python-include", "Path to Python include dir")) |inc| {
        lib.addIncludePath(.{ .cwd_relative = inc });
    } else {
        lib.addIncludePath(.{ .cwd_relative = "C:/usr/include/python3" });
    }

    // --- 4. Link libc + Python ------------------------------------------------
    lib.linkLibC();

    // On Windows, link the Python import library explicitly.
    if (target.result.os.tag == .windows) {
        if (b.option([]const u8, "python-lib", "Path to Python libs dir (Windows)")) |lib_path| {
            lib.addLibraryPath(.{ .cwd_relative = lib_path });
        }
        lib.linkSystemLibrary("python314");
    }

    // --- 5. Install -----------------------------------------------------------
    // On Windows Python expects nano_ffi.pyd, not nano_ffi.dll.
    if (target.result.os.tag == .windows) {
        const install_pyd = b.addInstallFileWithDir(
            lib.getEmittedBin(),
            .lib,
            "nano_ffi.pyd",
        );
        install_pyd.step.dependOn(&lib.step);
        b.getInstallStep().dependOn(&install_pyd.step);
    } else {
        b.installArtifact(lib);
    }

    // --- 6. Unit tests --------------------------------------------------------
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
}
