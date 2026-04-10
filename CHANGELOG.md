# Changelog

## [0.2.0] — 2026-03-15

### Added
- macOS ARM64 support (Apple Silicon) — 39.2ns call overhead
- Zig 0.15.2 compatibility (`addLibrary`, `callconv(.c)`, new `.zon` format)
- `fingerprint` field in `build.zig.zon` (required by Zig 0.15)
- `linker_allow_shlib_undefined` for Linux and macOS — Python symbols resolved at runtime

### Changed
- Pinned Zig version from 0.13.0 → 0.15.2
- `build.zig` rewritten for Zig 0.15 API (`addLibrary` + `linkage = .dynamic`)
- `pyproject.toml` license field updated to SPDX string format (fixes setuptools deprecation warnings)
- `callconv(.C)` → `callconv(.c)` across all source files
- Benchmark table updated with Windows and macOS numbers

### Fixed
- Windows lib path now correctly points to `libs/` subdirectory
- `PyModuleDef_HEAD_INIT` macro replaced with `std.mem.zeroes(py.PyModuleDef_Base)`
- `Py_True`/`Py_False` macros replaced with `PyBool_FromLong` (Python 3.14 compatibility)
- Arg parsing in `py_call` switched from `PyArg_ParseTuple` to `PyTuple_GetItem` to support variadic args
- `RawArg`/`RawRet` changed from tagged unions to `extern struct` for C-ABI compatibility
- `ArgType` enum backing type set to `u8` for extern compatibility

---

## [0.1.0] — 2026-03-15

### Added
- Initial release
- Comptime trampoline generator (`comptime_bridge.zig`)
- Function pointer registry with `Signature` metadata (`registry.zig`)
- Python C extension interface (`python_ext.zig`) — only file touching `<Python.h>`
- Explicit allocator boundary (`allocator.zig`) with GPA in debug, C allocator in release
- Built-in example functions: `add` (i64) and `mul` (f64)
- Full dispatch pipeline: Python args → `RawArg` → trampoline → `RawRet` → Python object
- 5/5 tests passing
- Windows x64 wheel published to PyPI
- Benchmark: 79.6ns call overhead, 4.28x faster than ctypes (Windows ReleaseFast)