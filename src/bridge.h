/**
 * bridge.h
 *
 * Public interface for the nano-ffi fast-call dispatch and batch engine.
 *
 * All dispatched C kernels must conform to NffiKernelFn:
 *
 *     void my_kernel(void *args, void *result);
 *
 * The args/result buffers are owned and managed entirely by the caller.
 * nano-ffi never allocates, copies, or inspects their contents.
 */

#ifndef NANO_FFI_BRIDGE_H
#define NANO_FFI_BRIDGE_H

#include "registry.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 * Kernel function signature
 * ---------------------------------------------------------------------- */

/**
 * NffiKernelFn
 *
 * The mandatory signature for any C function registered with nano-ffi.
 *
 * @param args    Pointer to input buffer. Layout is caller-defined.
 * @param result  Pointer to output buffer. Layout is caller-defined.
 */
typedef void (*NffiKernelFn)(void *args, void *result);

/* -------------------------------------------------------------------------
 * Batch types
 * ---------------------------------------------------------------------- */

/**
 * NffiBatchItem
 *
 * Describes a single call within a batch. If fn_ptr is non-NULL it is used
 * directly, bypassing the registry lookup. The bridge will populate fn_ptr
 * on first execution so subsequent passes over the same item array are
 * lookup-free.
 */
typedef struct {
    const char *name;    /* registry key; ignored when fn_ptr is set */
    nffi_fn_t   fn_ptr;  /* pre-resolved pointer; NULL = resolve lazily */
    void       *args;    /* input buffer passed to the kernel            */
    void       *result;  /* output buffer passed to the kernel           */
} NffiBatchItem;

/**
 * NffiBatchResult
 *
 * Per-item outcome from nffi_batch_call. Parallel array to NffiBatchItem[].
 */
typedef struct {
    int status;  /* NANO_FFI_OK or a NANO_FFI_ERR_* code */
} NffiBatchResult;

/** One or more items in a batch failed; inspect NffiBatchResult[i].status. */
#define NANO_FFI_ERR_BATCH_PARTIAL -6

/* -------------------------------------------------------------------------
 * API
 * ---------------------------------------------------------------------- */

/**
 * nffi_fast_call
 *
 * Looks up `name` in the registry and dispatches immediately.
 * Use nffi_fast_call_ptr for hot paths where the pointer is already cached.
 *
 * @param reg     Initialised registry.
 * @param name    NUL-terminated function name.
 * @param args    Input buffer (may be NULL if the kernel ignores it).
 * @param result  Output buffer (may be NULL if the kernel ignores it).
 * @return        NANO_FFI_OK, NANO_FFI_ERR_NULL, or NANO_FFI_ERR_NOT_FOUND.
 */
int nffi_fast_call(NffiRegistry *reg,
                   const char   *name,
                   void         *args,
                   void         *result);

/**
 * nffi_fast_call_ptr
 *
 * Dispatches directly via a raw function pointer — zero registry overhead.
 * Intended for callers that cache the pointer after a one-time lookup.
 *
 * @param fn      Function pointer (must not be NULL).
 * @param args    Input buffer.
 * @param result  Output buffer.
 * @return        NANO_FFI_OK or NANO_FFI_ERR_NULL.
 */
int nffi_fast_call_ptr(nffi_fn_t  fn,
                       void      *args,
                       void      *result);

/**
 * nffi_batch_call
 *
 * Executes `count` items in a single tight loop, crossing the Python↔C
 * boundary exactly once for the entire batch.
 *
 * Items with fn_ptr == NULL are resolved on first execution and cached
 * in-place, so repeated batch calls over the same item array become
 * fully lookup-free after the first pass.
 *
 * @param reg      Initialised registry.
 * @param items    Array of NffiBatchItem (count elements).
 * @param count    Number of items to execute.
 * @param results  Caller-allocated array of NffiBatchResult (count elements).
 * @return         NANO_FFI_OK if all items succeeded,
 *                 NANO_FFI_ERR_BATCH_PARTIAL if any item failed,
 *                 NANO_FFI_ERR_NULL if a required pointer is NULL.
 */
int nffi_batch_call(NffiRegistry    *reg,
                    NffiBatchItem   *items,
                    uint32_t         count,
                    NffiBatchResult *results);

#ifdef __cplusplus
extern "C" {
#endif

#endif /* NANO_FFI_BRIDGE_H */