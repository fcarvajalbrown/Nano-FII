# AI_AGENT_INSTRUCTIONS.md

Instructions for any AI agent working on the nano-ffi codebase.
Read this file before reading any other file. Do not skip sections.

---

## Project overview

nano-ffi is a Python C-extension library that dispatches Python calls to C
functions with minimal overhead. It consists of a C core (registry + bridge)
and a thin Python API layer. The compiled extension is `nano_ffi/_core.pyd`
(Windows) or `nano_ffi/_core.<platform-tag>.so` (Linux).

---

## File roles

```
src/registry.h      Struct definitions and API declarations for the function
                    pointer hash map. Single source of truth for error codes
                    and tunables (NANO_FFI_REGISTRY_CAPACITY, NANO_FFI_MAX_NAME_LEN).

src/registry.c      Hash map implementation. FNV-1a hashing, open addressing,
                    tombstone deletion. Platform memory locking (mlock / VirtualLock).

src/bridge.h        Declarations for NffiKernelFn, NffiBatchItem, NffiBatchResult,
                    and the fast_call / batch_call API.

src/bridge.c        Dispatch engine. nffi_fast_call (lookup + dispatch),
                    nffi_fast_call_ptr (direct pointer dispatch, no lookup),
                    nffi_batch_call (N calls, single boundary crossing).

src/module.c        CPython extension entry point. Compiled with Py_LIMITED_API.
                    Exposes the C API to Python. Do not put business logic here.

nano_ffi/__init__.py    Re-exports the public Python API.
nano_ffi/api.py         @register and @fast_call decorators. Marshals Python
                        args into void* buffers using struct / ctypes.

tests/conftest.py       Pytest fixtures. Loads compiled test kernels from
                        tests/fixtures/ via ctypes.CDLL.
tests/fixtures/         Minimal C source files (e.g. add_two_ints.c) compiled
                        as shared libraries for use in tests only.
bench/                  Standalone benchmark scripts. Not part of the test suite.
                        Run manually; do not import from nano_ffi tests.

CMakeLists.txt          Builds _core extension. Handles per-platform flags and
                        the Py_LIMITED_API version pin.
pyproject.toml          scikit-build-core config, cibuildwheel settings, metadata.
pytest.ini              testpaths = tests. Markers: unit, integration, slow.
```

---

## Coding conventions

### C

- Standard: C11. No compiler extensions except `__builtin_expect` (guarded by
  `#if defined(__GNUC__) || defined(__clang__)`).
- Every function and file must have a docblock comment. No exceptions.
- Error handling: all functions return an int error code from the
  `NANO_FFI_*` set defined in `registry.h`. Never use errno directly in
  public API functions.
- New error codes go in `registry.h` only. Keep them contiguous and negative.
  Document each one with a comment.
- Memory: no heap allocation in the hot path. The registry is a fixed-size
  struct; the batch item array is caller-owned.
- Do not add `printf`, `fprintf`, or any I/O to C source. Surface errors via
  return codes to the Python layer.
- `NANO_FFI_REGISTRY_CAPACITY` must always be a power of two. Assert this in
  `nffi_registry_init` with a compile-time check:
  `_Static_assert((NANO_FFI_REGISTRY_CAPACITY & (NANO_FFI_REGISTRY_CAPACITY-1)) == 0, "...")`.
- All registered kernels must match `NffiKernelFn`: `void fn(void*, void*)`.
  nano-ffi performs no signature checking.

### Python

- Style: PEP 8. Type hints on all public functions.
- Every function and file must have a docstring. No exceptions.
- Do not import `ctypes` in `__init__.py`. Keep it confined to `api.py`.
- Do not catch bare `Exception` in the API layer. Use specific types.
- `api.py` owns all marshalling logic (struct.pack / ctypes buffer creation).
  `module.c` must not contain marshalling logic.

### General

- Fix bugs at the root cause. Never patch tests to make them pass.
- Do not introduce new dependencies without updating `pyproject.toml` and
  noting the reason in a comment.
- Do not modify `tests/` to work around a bug in `src/`. Fix `src/`.

---

## Build commands

### Prerequisites

- CMake >= 3.21
- Python >= 3.12 with `pip install scikit-build-core`
- On Linux: gcc or clang
- On Windows: MSVC (via Visual Studio Build Tools) or clang-cl

### Development build (editable)

```bash
pip install --no-build-isolation -e .
```

### Full wheel build

```bash
pip install cibuildwheel
cibuildwheel --platform linux   # manylinux
cibuildwheel --platform windows # win-amd64
```

### CMake directly (for C-only iteration)

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

---

## Test commands

```bash
# All tests
pytest

# Unit tests only
pytest -m unit

# Exclude slow tests
pytest -m "not slow"

# Single file
pytest tests/test_registry.py -v

# With coverage
pytest --cov=nano_ffi --cov-report=term-missing
```

Tests in `tests/fixtures/` are C source files, not Python tests. They are
compiled by CMake as part of the build. Do not run them directly.

---

## Constraints — do not violate

- `Py_LIMITED_API` must remain set to `0x030C0000` (Python 3.12 minimum).
  Do not use any CPython internal API that is not in the Limited API.
- `NANO_FFI_REGISTRY_CAPACITY` must be a power of two.
- The registry must not allocate heap memory after `nffi_registry_init`.
- All C kernels must match `NffiKernelFn`. No exceptions.
- Do not add platform-specific code outside of the existing `#ifdef _WIN32`
  blocks in `registry.c` and `bridge.c`.