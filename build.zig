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

    // Emit a file CPython can import directly: nano_ffi.pyd on Windows,
    // nano_ffi.so on Linux and macOS (Python extension modules use .so on
    // macOS too, not .dylib). Without this the artifact would be named
    // libnano_ffi.* and Python's import machinery would not find it.
    const module_name = if (os == .windows) "nano_ffi.pyd" else "nano_ffi.so";
    const install_module = b.addInstallFileWithDir(
        lib.getEmittedBin(),
        .lib,
        module_name,
    );
    install_module.step.dependOn(&lib.step);
    b.getInstallStep().dependOn(&install_module.step);

    // -----------------------------------------------------------------------
    // benchlib — a tiny plain-C-ABI shared library used ONLY by the
    // apples-to-apples binding-overhead benchmark
    // (benchmarks/benchmark_vs_libraries.py). It exports add/strlen/fill with
    // the same semantics as Nano-FFI's built-ins so ctypes and cffi can bind
    // to the exact same native work. Not part of the Python package.
    //
    // Emitted as nano_ffi_benchlib.dll (Windows) / libnano_ffi_benchlib.so
    // (Linux) / libnano_ffi_benchlib.dylib (macOS) into zig-out/lib.
    //
    // Build with:  zig build benchlib -Doptimize=ReleaseFast
    const benchlib_mod = b.createModule(.{
        .root_source_file = b.path("src/benchlib.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    const benchlib = b.addLibrary(.{
        .name        = "nano_ffi_benchlib",
        .root_module = benchlib_mod,
        .linkage     = .dynamic,
    });
    const install_benchlib = b.addInstallArtifact(benchlib, .{});
    const benchlib_step = b.step("benchlib", "Build the benchmark shared library (nano_ffi_benchlib)");
    benchlib_step.dependOn(&install_benchlib.step);

    // Pure-Zig unit tests. Uses test_root.zig (no <Python.h> dependency) so
    // `zig build test` runs without Python headers or libpython on the path.
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_root.zig"),
            .target           = target,
            .optimize         = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run all Zig unit tests");
    test_step.dependOn(&run_tests.step);
}