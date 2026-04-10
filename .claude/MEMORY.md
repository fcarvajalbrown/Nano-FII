# Nano-FFI — Project Memory

## What this is
A minimalist Python-to-Zig FFI bridge using comptime trampolines. Python calls Zig functions via a string-keyed registry. All type dispatch is resolved at compile time — no runtime branching in the hot path.

## Current state
- Version: 0.2.0
- Zig: 0.15.2 (pinned)
- Status: Windows x64 + macOS ARM64 confirmed working, Linux pending

## Benchmarks (ReleaseFast)
- Windows x64: 109.4ns, 3.82x faster than ctypes
- macOS ARM64: 39.2ns, 3.89x faster than ctypes
- Target: <110ns ✓

## Architecture rules
- Only `python_ext.zig` may import `<Python.h>` — never any other file
- One file at a time, diffs/snippets only, no full-file regeneration unless asked
- No multi-line comments — 1-line comments only
- Fix bugs at root cause, never patch tests to pass

## Key design decisions
- `RawArg`/`RawRet` are `extern struct` with `tag: ArgType` + `val: RawValue` union — NOT tagged unions (C-ABI incompatible)
- `ArgType` is `enum(u8)` — must be u8 for extern compatibility
- `linker_allow_shlib_undefined = true` on Linux/macOS — Python symbols resolved at runtime by interpreter
- Windows must link `python3XX.lib` explicitly (e.g. `-Dpython-libname=python314`)
- `PyModuleDef_HEAD_INIT` cannot be used via cImport — use `std.mem.zeroes(py.PyModuleDef_Base)`
- `Py_True`/`Py_False` macros not translatable — use `PyBool_FromLong`
- Arg parsing uses `PyTuple_GetItem` not `PyArg_ParseTuple` (variadic support)

## Zig 0.15 breaking changes from 0.13
- `addSharedLibrary` → `addLibrary` with `linkage = .dynamic`
- `callconv(.C)` → `callconv(.c)`
- `linkSystemLibrary(name, .{})` → `linkSystemLibrary(name)`
- `build.zig.zon` requires `.name = .identifier` (no hyphens) and `fingerprint` field

## Build commands
**Windows:**
```powershell
zig build -Doptimize=ReleaseFast `
  -Dpython-lib="...\libs" `
  -Dpython-include="...\include" `
  -Dpython-libname=python314
```

**macOS:**
```bash
zig build -Doptimize=ReleaseFast \
  -Dpython-include="$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")"
```

## Test
```bash
PYTHONPATH=. python tests/test_python.py   # macOS/Linux
python tests/test_python.py                # Windows (with nano_ffi.pyd in root)
```

## PyPI
- Package name: `nano-ffi`
- Repo: https://github.com/fcarvajalbrown/Nano-FII
- Distribution: pre-built wheels (no build-on-install)
- v0.1.0: Windows x64 only
- v0.2.0: Windows x64 + macOS ARM64

## Pending (v0.3.0)
- Linux wheel
- Slice/string argument types
- Version string bug: returns "0.1" instead of "0.1.0" — fix in `py_version`
- GitHub Actions CI (blocked on cross-platform Zig build issues)
- `TODO(day-3)` label cleanup now that dispatch is wired