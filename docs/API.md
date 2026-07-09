# Nano-FFI API Reference

The compiled module exposes four functions. Type stubs live in `nano_ffi.pyi`
(PEP 561), so editors and type checkers see these signatures directly.

## `call(name, *args) -> object`

Invoke a registered Zig function by name and return its result.

```python
nano_ffi.call("add", 3, 4)        # 7
nano_ffi.call("echo", "hola")     # "hola"
nano_ffi.call("divmod", 17, 5)    # (3, 2)
```

Raises:

| Exception | When |
|---|---|
| `KeyError` | no function is registered under `name` |
| `TypeError` | wrong argument count, or an argument of the wrong kind |
| `ValueError` | an integer argument is out of range for the target width |
| `BufferError` | a `buffer` argument was given a non-writable object |
| `RuntimeError` | the Zig function returned an error (message is its `@errorName`) |

## `version() -> str`

Return the library version string (single-sourced from `src/version.zig`).

## `list_functions() -> list[str]`

Return the names of every registered Zig function, read from the live registry.

## `signature(name) -> dict`

Describe a registered function:

```python
nano_ffi.signature("add")
# {"args": [("a", "i64"), ("b", "i64")], "ret": "i64"}

nano_ffi.signature("divmod")
# {"args": [("a", "i64"), ("b", "i64")], "ret": ["i64", "i64"]}
```

`"ret"` is a single type name for scalar returns, or a list of type names for
multi-value (tuple) returns. Raises `KeyError` if `name` is unknown.

## Supported types

Argument and return type names, as reported by `signature()`:

| Name | Zig type | Python type | Notes |
|---|---|---|---|
| `i64` | `i64` | `int` | 64-bit signed |
| `i32` | `i32` | `int` | range-checked |
| `u64` | `u64` | `int` | full unsigned range |
| `u32` | `u32` | `int` | range-checked |
| `u8` | `u8` | `int` | range-checked |
| `f64` | `f64` | `float` | |
| `f32` | `f32` | `float` | |
| `bool` | `bool` | `bool` | |
| `str` | `[]const u8` | `str` | borrowed UTF-8 in; copied out |
| `bytes` | `[]const u8` | `bytes` | borrowed in; copied out |
| `buffer` | `[]u8` | writable buffer | zero-copy, in-place; argument-only |

Out-of-range integers raise `ValueError` rather than truncating silently.

## Built-in example functions

These ship with the module and back the test suite:

| Name | Signature | Purpose |
|---|---|---|
| `add` | `(i64, i64) -> i64` | integer add |
| `mul` | `(f64, f64) -> f64` | float multiply |
| `add32` | `(i32, i32) -> i32` | 32-bit add |
| `umul` | `(u64, u64) -> u64` | unsigned multiply |
| `strlen` | `(str) -> i64` | UTF-8 byte length |
| `echo` | `(str) -> str` | string round-trip |
| `bytesum` | `(bytes) -> u64` | sum of bytes |
| `div` | `(i64, i64) -> i64` | fallible divide (raises on 0) |
| `divmod` | `(i64, i64) -> (i64, i64)` | quotient and remainder |
| `signmag` | `(i64) -> (bool, u64)` | sign flag and magnitude |
| `fill` | `(buffer, u8) -> u64` | fill buffer in place, return length |
| `bufmax` | `(buffer) -> u8` | maximum byte in a buffer |

## Registering your own function (Zig side)

See the README for `bridge.makeTrampoline`. Every registered function carries
its `Signature`, so `signature()` and `list_functions()` describe it for free.
