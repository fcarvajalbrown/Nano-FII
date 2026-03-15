/**
 * bridge.c
 *
 * Fast-call dispatch and batch execution engine for nano-ffi.
 *
 * Design contract:
 *   - nffi_fast_call  : single function invocation via a raw pointer retrieved
 *                       from the registry. No symbol lookup occurs at call-time.
 *   - nffi_batch_call : executes an array of NffiBatchItem structs in a tight
 *                       loop, amortising the Python↔C transition cost across
 *                       N calls with a single boundary crossing.
 *
 * Calling convention:
 *   All dispatched functions must match the signature:
 *       void fn(void *args, void *result)
 *   where `args` and `result` are caller-managed buffers. This is intentionally
 *   low-level — the Python layer (api.py) is responsible for packing args and
 *   unpacking results using struct or ctypes.
 *
 * Zero-copy array support:
 *   When the caller passes a direct pointer to a NumPy array's data buffer as
 *   `args`, no copy occurs. The C kernel reads/writes the buffer in place.
 *   The caller must ensure the array is C-contiguous and not garbage-collected
 *   for the duration of the call (hold a Python reference).
 *
 * Compiler hints:
 *   NFFI_LIKELY / NFFI_UNLIKELY wrap __builtin_expect on GCC/Clang and are
 *   no-ops on MSVC, which has no equivalent intrinsic.
 */

#include "bridge.h"
#include "registry.h"

#include <string.h>  /* memset */

/* -------------------------------------------------------------------------
 * Portability macros
 * ---------------------------------------------------------------------- */

#if defined(__GNUC__) || defined(__clang__)
#  define NFFI_LIKELY(x)   __builtin_expect(!!(x), 1)
#  define NFFI_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
#  define NFFI_LIKELY(x)   (x)
#  define NFFI_UNLIKELY(x) (x)
#endif

/* -------------------------------------------------------------------------
 * Internal dispatcher
 * ---------------------------------------------------------------------- */

/**
 * dispatch
 *
 * Casts fn to the standard NffiKernelFn signature and invokes it.
 * Isolated into its own function so the compiler can apply TCO where
 * supported, and to keep the call frame minimal.
 *
 * On x86-64 and aarch64 at -O2 this typically compiles to a direct
 * register-indirect JMP with no additional frame overhead.
 *
 * @param fn      Function pointer retrieved from the registry.
 * @param args    Pointer to caller-managed argument buffer (may be NULL).
 * @param result  Pointer to caller-managed result buffer (may be NULL).
 */
static void dispatch(nffi_fn_t fn, void *args, void *result)
{
    ((NffiKernelFn)fn)(args, result);
}

/* -------------------------------------------------------------------------
 * Public API
 * ---------------------------------------------------------------------- */

int nffi_fast_call(NffiRegistry  *reg,
                   const char    *name,
                   void          *args,
                   void          *result)
{
    if (NFFI_UNLIKELY(!reg || !name)) return NANO_FFI_ERR_NULL;

    nffi_fn_t fn;
    int rc = nffi_lookup(reg, name, &fn);
    if (NFFI_UNLIKELY(rc != NANO_FFI_OK)) return rc;

    dispatch(fn, args, result);
    return NANO_FFI_OK;
}

int nffi_fast_call_ptr(nffi_fn_t  fn,
                       void      *args,
                       void      *result)
{
    if (NFFI_UNLIKELY(!fn)) return NANO_FFI_ERR_NULL;
    dispatch(fn, args, result);
    return NANO_FFI_OK;
}

int nffi_batch_call(NffiRegistry      *reg,
                    NffiBatchItem     *items,
                    uint32_t           count,
                    NffiBatchResult   *results)
{
    if (NFFI_UNLIKELY(!reg || !items || !results)) return NANO_FFI_ERR_NULL;
    if (NFFI_UNLIKELY(count == 0)) return NANO_FFI_OK;

    uint32_t errors = 0;

    for (uint32_t i = 0; i < count; i++) {
        NffiBatchItem   *item = &items[i];
        NffiBatchResult *res  = &results[i];

        /*
         * If the item carries a pre-resolved pointer, skip the registry
         * lookup entirely. The Python layer pre-resolves on first call and
         * caches the pointer, turning subsequent batch calls into pure
         * pointer dispatches with zero hash-map overhead.
         */
        nffi_fn_t fn = item->fn_ptr;

        if (NFFI_LIKELY(fn == NULL)) {
            int rc = nffi_lookup(reg, item->name, &fn);
            if (NFFI_UNLIKELY(rc != NANO_FFI_OK)) {
                res->status = rc;
                errors++;
                continue;
            }
            /* Cache the resolved pointer back into the item for future
             * batch passes over the same item array. */
            item->fn_ptr = fn;
        }

        dispatch(fn, item->args, item->result);
        res->status = NANO_FFI_OK;
    }

    return (errors == 0) ? NANO_FFI_OK : NANO_FFI_ERR_BATCH_PARTIAL;
}