"""Type stubs for the nano_ffi compiled extension (PEP 561).

nano_ffi is a Python-to-Zig FFI bridge. Zig functions are registered by name
and invoked through call(); the module is self-describing via list_functions()
and signature().
"""

from typing import Any

def call(name: str, *args: Any) -> Any:
    """Invoke a registered Zig function by name and return its result.

    Raises:
        KeyError: no function is registered under ``name``.
        TypeError: wrong number of arguments, or an argument of the wrong kind.
        ValueError: an integer argument is out of range for the target width.
        RuntimeError: the Zig function returned an error (message is the Zig
            ``@errorName``).
    """
    ...

def version() -> str:
    """Return the Nano-FFI library version string (e.g. ``"0.6.0"``)."""
    ...

def list_functions() -> list[str]:
    """Return the names of every registered Zig function."""
    ...

def signature(name: str) -> dict[str, Any]:
    """Describe a registered function.

    Returns a dict of the form::

        {"args": [(arg_name, type_name), ...], "ret": type_name}

    where ``type_name`` is one of ``i64``, ``i32``, ``u64``, ``u32``, ``u8``,
    ``f64``, ``f32``, ``bool``, ``str``, ``bytes``.

    Raises:
        KeyError: no function is registered under ``name``.
    """
    ...
