//! build.zig — Nano-FFI build script. Requires Zig 0.15.x.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    const lib = b.addLibrary(.{
        .name        = "nano_ffi",
        .root_module = mod,
        .linkage     = .dynamic,
    });

    // Python headers
    if (b.option([]const u8, "python-include", "Path to Python include dir")) |inc| {
        if (inc.len > 0) lib.addIncludePath(.{ .cwd_relative = inc });
    }

    lib.linkLibC();

    const py_lib = b.option([]const u8, "python-lib", "Path to Python lib dir");
    const os = target.result.os.tag;

    if (os == .windows) {
        if (py_lib) |lp| if (lp.len > 0) lib.addLibraryPath(.{ .cwd_relative = lp });
        const py_libname = b.option([]const u8, "python-libname", "Python lib name") orelse "python312";
        lib.linkSystemLibrary(py_libname);
    } else if (os == .macos) {
        // Python symbols resolved at runtime by the interpreter — no explicit link needed.
    }

    lib.linker_allow_shlib_undefined = true;

    if (os == .windows) {
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
}