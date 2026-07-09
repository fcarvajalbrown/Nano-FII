# Changelog

## [0.3.0] — 2026-07-09

### Added
- Expanded scalar type system: `i32`, `u32`, `u64`, `f32`, `u8` join `i64`, `f64`, `bool`
- Range-checked narrowing on Python -> Zig integers: out-of-range values raise `ValueError` instead of silently truncating
- `u64` conversion via `PyLong_AsUnsignedLongLong` (supports values above `i64` max)
- Built-in example functions `add32` (i32) and `umul` (u64)
- `src/version.zig` — single source of truth for the version string
- `src/test_root.zig` — dedicated pure-Zig test root (no `<Python.h>` dependency)
- `build_local.ps1` — reproducible local Windows build helper
- `ROADMAP.md` — milestones from 0.2 to 1.0

### Fixed
- `version()` returned the stale `"0.1.0"`; now reads from `version.zig` (fixes the `0.1.0`/`0.2.0` drift)
- `allocator.zig` test compared a non-optional pointer with `null` (Zig 0.15 compile error)
- `zig build test` no longer pulls in `python_ext.zig`, so it runs without Python headers

### Changed
- Argument converters set precise Python exceptions; the dispatcher no longer overwrites them with a generic `TypeError`
- Removed stale `TODO(day-3)` markers now that dispatch is wired
- Python test runner auto-discovers all `TestCase` classes in the module

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