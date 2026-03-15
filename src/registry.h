/**
 * registry.h
 *
 * Function pointer registry for nano-ffi.
 *
 * Maintains a fixed-size open-addressing hash map of named function pointers
 * stored in a non-paged memory region. The registry is the single source of
 * truth for all callable C symbols; no dynamic linker lookup occurs at
 * call-time.
 *
 * Platform notes:
 *   - Linux : mlock(2) pins the map pages; requires RLIMIT_MEMLOCK headroom.
 *   - Windows: VirtualLock pins the working-set pages; requires
 *              SetProcessWorkingSetSize if the default quota is exceeded.
 */

#ifndef NANO_FFI_REGISTRY_H
#define NANO_FFI_REGISTRY_H

#include <stddef.h>   /* size_t        */
#include <stdint.h>   /* uint32_t etc. */

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 * Tunables (override via -D at compile time)
 * ---------------------------------------------------------------------- */

/** Total number of slots in the hash map. Must be a power of two. */
#ifndef NANO_FFI_REGISTRY_CAPACITY
#define NANO_FFI_REGISTRY_CAPACITY 256
#endif

/** Maximum length of a registered function name, including NUL terminator. */
#ifndef NANO_FFI_MAX_NAME_LEN
#define NANO_FFI_MAX_NAME_LEN 64
#endif

/* -------------------------------------------------------------------------
 * Error codes
 * ---------------------------------------------------------------------- */

/** Operation succeeded. */
#define NANO_FFI_OK              0

/** The registry has no free slots. */
#define NANO_FFI_ERR_FULL       -1

/** No entry with the given name was found. */
#define NANO_FFI_ERR_NOT_FOUND  -2

/** A NULL pointer was passed where one is not permitted. */
#define NANO_FFI_ERR_NULL       -3

/** The supplied name exceeds NANO_FFI_MAX_NAME_LEN. */
#define NANO_FFI_ERR_NAME_LEN   -4

/** mlock / VirtualLock failed; errno / GetLastError holds the reason. */
#define NANO_FFI_ERR_LOCK       -5

/* -------------------------------------------------------------------------
 * Core types
 * ---------------------------------------------------------------------- */

/**
 * A generic function pointer type.
 *
 * All registered functions are stored as nffi_fn_t and cast back to their
 * true signature at the call site. The caller is responsible for supplying
 * the correct signature — nano-ffi performs no type checking.
 */
typedef void (*nffi_fn_t)(void);

/**
 * A single slot in the open-addressing hash map.
 *
 * An entry is considered occupied when fn != NULL.
 * Deletion uses tombstoning: fn is set to NULL but occupied is cleared
 * separately so that probe chains are not broken during lookup.
 */
typedef struct {
    char       name[NANO_FFI_MAX_NAME_LEN]; /* key: NUL-terminated symbol name */
    nffi_fn_t  fn;                          /* value: function pointer          */
    uint8_t    occupied;                    /* 1 = live entry, 0 = empty/tomb   */
    uint8_t    tombstone;                   /* 1 = deleted, probe chain intact  */
    uint8_t    _pad[2];                     /* explicit padding for alignment    */
} NffiEntry;

/**
 * The registry itself.
 *
 * Embed one of these as a global (or heap-allocate and pass around).
 * Call nffi_registry_init() before any other operation.
 */
typedef struct {
    NffiEntry entries[NANO_FFI_REGISTRY_CAPACITY]; /* hash map slots        */
    uint32_t  count;                               /* live entries          */
    uint8_t   locked;                              /* 1 if pages are mlocked */
    uint8_t   _pad[3];
} NffiRegistry;

/* -------------------------------------------------------------------------
 * API
 * ---------------------------------------------------------------------- */

/**
 * nffi_registry_init
 *
 * Zero-initialises *reg and attempts to pin its memory pages so they are
 * never swapped out. On failure to lock, the registry is still usable but
 * reg->locked will be 0 and the latency guarantee may not hold.
 *
 * @param reg  Pointer to an uninitialised NffiRegistry.
 * @return     NANO_FFI_OK or NANO_FFI_ERR_NULL / NANO_FFI_ERR_LOCK.
 */
int nffi_registry_init(NffiRegistry *reg);

/**
 * nffi_registry_destroy
 *
 * Unlocks pages (if locked) and zero-wipes *reg.
 * Safe to call on a partially-initialised registry.
 *
 * @param reg  Pointer to an initialised NffiRegistry.
 */
void nffi_registry_destroy(NffiRegistry *reg);

/**
 * nffi_register
 *
 * Inserts or replaces a (name → fn) mapping in *reg.
 *
 * @param reg   Registry to insert into.
 * @param name  NUL-terminated symbol name (< NANO_FFI_MAX_NAME_LEN bytes).
 * @param fn    Function pointer to store.
 * @return      NANO_FFI_OK, NANO_FFI_ERR_FULL, NANO_FFI_ERR_NULL,
 *              or NANO_FFI_ERR_NAME_LEN.
 */
int nffi_register(NffiRegistry *reg, const char *name, nffi_fn_t fn);

/**
 * nffi_lookup
 *
 * Retrieves the function pointer registered under *name*.
 *
 * @param reg    Registry to search.
 * @param name   NUL-terminated symbol name.
 * @param out_fn Receives the function pointer on success.
 * @return       NANO_FFI_OK or NANO_FFI_ERR_NOT_FOUND / NANO_FFI_ERR_NULL.
 */
int nffi_lookup(const NffiRegistry *reg, const char *name, nffi_fn_t *out_fn);

/**
 * nffi_unregister
 *
 * Removes the entry for *name* by tombstoning its slot.
 *
 * @param reg   Registry to modify.
 * @param name  NUL-terminated symbol name.
 * @return      NANO_FFI_OK or NANO_FFI_ERR_NOT_FOUND / NANO_FFI_ERR_NULL.
 */
int nffi_unregister(NffiRegistry *reg, const char *name);

/**
 * nffi_registry_count
 *
 * Returns the number of live (non-tombstoned) entries.
 *
 * @param reg  Registry to query.
 * @return     Entry count, or 0 if reg is NULL.
 */
uint32_t nffi_registry_count(const NffiRegistry *reg);

#ifdef __cplusplus
}
#endif

#endif /* NANO_FFI_REGISTRY_H */