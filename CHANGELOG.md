# Changelog

## [0.7.0] — 2026-07-09

### Added
- Multi-value returns: a Zig function returning a tuple (e.g. `struct { i64, i64 }`) surfaces in Python as a tuple
- `Signature.rets` (a `[]const ArgType`); when non-empty the trampoline packs each field, resolved at comptime
- Built-in examples `divmod` (i64, i64) and `signmag` (bool, u64 — mixed types)
- `signature()` reports a list of return types for multi-value functions

### Changed
- `Signature.ret` now defaults to `.i64` and is ignored when `rets` is non-empty
- Single-return functions keep the branch-free hot path; the multi-return branch is comptime-gated

## [0.6.0] — 2026-07-09

### Added
- `nano_ffi.list_functions()` — names of every registered Zig function, read from the live registry
- `nano_ffi.signature(name)` — `{"args": [(name, type), ...], "ret": type}` describing a function
- PEP 561 type stubs (`nano_ffi.pyi`) and a `py.typed` marker, packaged in the wheel
- Type names in `signature()` come straight from the `ArgType` tag (`i64`, `str`, `bytes`, ...)

## [0.5.0] — 2026-07-09

### Added
- Zig error unions (`E!T`) are now first-class: a returned error surfaces as a Python `RuntimeError` carrying the Zig `@errorName` (e.g. `DivisionByZero`)
- `RawRet` gains an error channel (`err_ptr` / `err_len`); `err_ptr == null` means success
- The trampoline unwraps error unions at comptime — non-fallible functions keep the branch-free path
- Built-in fallible example `div` (raises on divide-by-zero)

### Changed
- Conversion failures already raised precise `ValueError`/`TypeError` (v0.3.0); runtime Zig errors now raise instead of returning a zero value

## [0.4.0] — 2026-07-09

### Added
- `str` and `bytes` argument/return kinds — variable-length data across the boundary
- `RawSlice` (`ptr` + `len`), a C-ABI-safe view carried inside `RawValue`
- Python `str` <-> Zig `[]const u8` via borrowed UTF-8 view; Python `bytes` <-> `[]const u8`
- Return marshalling copies the slice into a fresh Python object, so no Zig memory dangles
- Built-in examples `strlen` (str -> i64), `echo` (str -> str), `bytesum` (bytes -> u64)

### Notes
- Ownership contract: a Zig-returned slice must be valid at the moment of return (static data, or a view into the input arguments). Returning heap-allocated slices is deferred to the v0.8.0 buffer work.

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