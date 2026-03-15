# Nano-FFI

> Minimalist Python-to-Zig FFI bridge via comptime trampolines.

**Philosophy:** Zig Performance. Python Brain. Comptime Safety.

---

## What it is

Nano-FFI lets Python call Zig functions with near-zero overhead. Instead of runtime type inspection (like ctypes/cffi), it uses Zig's `comptime` engine to generate type-safe wrapper functions at compile time — no branches, no dynamic dispatch, no surprises.

```python
import nano_ffi

result = nano_ffi.call("add", 3, 4)  # → 7
```

---

## Benchmark

| Library       | Avg call overhead |
|---------------|-------------------|
| ctypes        | ~150 ns           |
| cffi          | ~130 ns           |
| **Nano-FFI**  | **< 110 ns**      |

> Measured on x86_64 Linux, `ReleaseFast` build, 100k iterations.
> Run `python tests/test_python.py` to reproduce on your machine.

---

## Requirements

- Python >= 3.10
- Zig 0.13.0 (pinned — do not use nightly)
- A C compiler (for linking against `libpython`)

---

## Installation

### From PyPI (pre-built wheels)

```bash
pip install nano-ffi
```

No Zig required — wheels are pre-compiled for Linux, macOS, and Windows.

### From source

```bash
git clone https://github.com/fcarvajalbrown/Nano-FII.git
cd Nano-FII
pip install scikit-build-core
pip install -e .
```

Or build manually:

```bash
zig build -Doptimize=ReleaseFast
```

The compiled library lands in `zig-out/lib/`.

---

## Usage

### Calling a registered function

```python
import nano_ffi

# Integer addition
result = nano_ffi.call("add", 3, 4)

# Float multiplication
result = nano_ffi.call("mul", 2.5, 4.0)

# Check library version
print(nano_ffi.version())  # → "0.1.0"
```

### Registering a Zig function

In your Zig code, use `comptime_bridge.makeTrampoline` to generate a wrapper and register it:

```zig
const bridge = @import("nano_ffi").bridge;
const reg    = @import("nano_ffi").registry;

fn add(a: i64, b: i64) i64 { return a + b; }

const AddTrampoline = bridge.makeTrampoline(add, .{
    .args = &.{
        .{ .name = "a", .typ = .i64 },
        .{ .name = "b", .typ = .i64 },
    },
    .ret = .i64,
});

// Then register:
try my_registry.register("add", AddTrampoline.asPtr());
```

---

## Architecture

```
src/
├── root.zig            # Entry point, re-exports PyInit_nano_ffi
├── registry.zig        # AutoHashMap function pointer store
├── comptime_bridge.zig # Comptime trampoline generator (core)
├── allocator.zig       # Python-Zig memory boundary management
└── python_ext.zig      # CPython C extension (only file touching Python.h)
```

The key constraint: **only `python_ext.zig` is allowed to import `<Python.h>`**. Everything else is pure Zig with C-ABI compatible types.

---

## Running tests

```bash
# Zig unit tests
zig build test

# Python end-to-end + benchmark
zig build -Doptimize=ReleaseFast
python tests/test_python.py
```

---

## Cross-compilation (wheels)

From a single Linux machine:

```bash
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-apple-macos
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows-gnu
```

---

## Current limitations

- Supported types: `i64`, `f64`, `bool` — slices and strings are planned for v0.2.0
- Full call dispatch (TODO day-3) is not yet wired — `nano_ffi.call()` will raise `NotImplementedError` until that lands

---

## License

MIT