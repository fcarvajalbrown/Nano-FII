//! build.zig — Nano-FFI build script.
//!
//! Usage:
//!   zig build                          -> debug build
//!   zig build -Doptimize=ReleaseFast   -> production build

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name             = "nano_ffi",
        .root_source_file = b.path("src/root.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    // Python headers — required on all platforms
    if (b.option([]const u8, "python-include", "Path to Python include dir")) |inc| {
        if (inc.len > 0) lib.addIncludePath(.{ .cwd_relative = inc });
    }

    lib.linkLibC();

    // Python lib dir — accepted on all platforms, used where needed
    const py_lib = b.option([]const u8, "python-lib", "Path to Python lib dir");

    if (target.result.os.tag == .windows) {
        if (py_lib) |lp| {
            if (lp.len > 0) lib.addLibraryPath(.{ .cwd_relative = lp });
        }
        const py_libname = b.option([]const u8, "python-libname", "Python lib name e.g. python312") orelse "python312";
        lib.linkSystemLibrary(py_libname);
    }

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

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
}
