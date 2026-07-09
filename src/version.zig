//! version.zig — Single source of truth for the Nano-FFI version string.
//! Both root.zig (Zig-side `version`) and python_ext.zig (`nano_ffi.version()`)
//! read from here so the number can never drift between them.

pub const literal = "1.0.0";
