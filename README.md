# Nano-FFI

> Minimalist Python-to-Zig FFI bridge via comptime trampolines.

**Philosophy:** Zig Performance. Python Brain. Comptime Safety.

---

## What it is

Nano-FFI lets Python call Zig functions with near-zero overhead. Instead of runtime type inspection (like ctypes/cffi), it uses Zig's `comptime` engine to generate type-safe wrapper functions at compile time — no branches, no dynamic dispatch, no surprises.

```python
import nano_ffi

result = nano_ffi.call("add", 3, 4)      # → 7
result = nano_ffi.call("mul", 2.5, 4.0)  # → 10.0
```

---

## Benchmark

| Library       | Avg call overhead | vs Nano-FFI |
|---------------|-------------------|-------------|
| ctypes        | ~340 ns           | 4.28x slower |
| **Nano-FFI**  | **79.6 ns**       | **baseline** |

> Measured on x86_64 Windows, `ReleaseFast` build, 100k iterations.
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
zig build -Doptimize=ReleaseFast \
  -Dpython-include=<path/to/python/include> \
  -Dpython-lib=<path/to/python/libs>
```

The compiled library lands in `zig-out/lib/`.

---

## Usage

### Calling a registered function

```python
import nano_ffi

# Integer addition (built-in example)
result = nano_ffi.call("add", 3, 4)        # → 7

# Float multiplication (built-in example)
result = nano_ffi.call("mul", 2.5, 4.0)   # → 10.0

# Check library version
print(nano_ffi.version())                  # → "0.1.0"
```

### Registering your own Zig function

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

// Register at init time:
try my_registry.register("add", AddTrampoline.asPtr(), AddTrampoline.sig);
```

---

## Architecture

```
src/
├── root.zig            # Entry point, exports PyInit_nano_ffi
├── registry.zig        # StringHashMap storing FnPtr + Signature
├── comptime_bridge.zig # Comptime trampoline generator (core)
├── allocator.zig       # Python-Zig memory boundary management
└── python_ext.zig      # CPython C extension (only file touching Python.h)
```

**Key constraint:** only `python_ext.zig` is allowed to import `<Python.h>`. Everything else is pure Zig with C-ABI compatible types.

**How the speed works:** `makeTrampoline` uses Zig's `inline for` over the signature at compile time — the compiler sees explicit typed assignments, not a loop. No branches, no runtime type checks in the hot path.

---

## Running tests

```bash
# Zig unit tests
zig build test

# Python end-to-end + benchmark (debug)
zig build
python tests/test_python.py

# Benchmark (production numbers)
zig build -Doptimize=ReleaseFast \
  -Dpython-include=<path> \
  -Dpython-lib=<path>
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

- Supported argument types: `i64`, `f64`, `bool` — slices and strings planned for v0.2.0
- Max 8 arguments per function call

---

## License

MIT