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

| Platform | Library | Avg call overhead | vs Nano-FFI |
|----------|---------|-------------------|-------------|
| Windows x64 | ctypes | ~417 ns | 3.82x slower |
| Windows x64 | **Nano-FFI** | **109.4 ns** | **baseline** |
| macOS ARM64 | ctypes | ~152 ns | 3.89x slower |
| macOS ARM64 | **Nano-FFI** | **39.2 ns** | **baseline** |

> `ReleaseFast` build, 100k iterations. Run `python tests/test_python.py` to reproduce.

---

## Requirements

- Python >= 3.10
- Zig 0.15.2
- A C compiler (for linking against `libpython`)

---

## Installation

### From PyPI (pre-built wheels)

```bash
pip install nano-ffi
```

No Zig required — wheels are pre-compiled for Windows and macOS.

### From source

```bash
git clone https://github.com/fcarvajalbrown/Nano-FII.git
cd Nano-FII
```

**Windows:**
```powershell
zig build -Doptimize=ReleaseFast `
  -Dpython-include="<path\to\python\include>" `
  -Dpython-lib="<path\to\python\libs>" `
  -Dpython-libname=python314
```

**macOS / Linux:**
```bash
zig build -Doptimize=ReleaseFast \
  -Dpython-include="$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")"
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
print(nano_ffi.version())                  # → "0.2.0"
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

# Python end-to-end + benchmark
PYTHONPATH=. python tests/test_python.py
```

---

## Current limitations

- Supported argument types: `i64`, `f64`, `bool` — slices and strings planned for v0.3.0
- Max 8 arguments per function call
- Linux wheels not yet available (coming in v0.3.0)

---

## License

MIT