/**
 * registry.c
 *
 * Implementation of the nano-ffi function pointer registry.
 *
 * Hash function: FNV-1a (32-bit). Fast, branchless, and well-distributed for
 * short symbol names. Index is derived via bitmask (capacity must be pow-2).
 *
 * Collision resolution: linear probing with tombstone deletion.
 *
 * Memory locking:
 *   Linux   — mlock(2) on the NffiRegistry struct.
 *   Windows — VirtualLock on the same region.
 * Failure to lock is non-fatal; reg->locked stays 0 and a warning can be
 * surfaced to the Python layer via nffi_registry_init's return code.
 */

#include "registry.h"

#include <string.h>   /* memset, strncpy, strlen */
#include <stdint.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>   /* VirtualLock, VirtualUnlock */
#else
#  include <sys/mman.h>  /* mlock, munlock             */
#endif

/* -------------------------------------------------------------------------
 * Internal helpers
 * ---------------------------------------------------------------------- */

/**
 * fnv1a_32
 *
 * Computes the 32-bit FNV-1a hash of a NUL-terminated string.
 * Reference: http://www.isthe.com/chongo/tech/comp/fnv/
 *
 * @param s  NUL-terminated input string.
 * @return   32-bit hash value.
 */
static uint32_t fnv1a_32(const char *s)
{
    uint32_t hash = 0x811c9dc5u; /* FNV offset basis */
    while (*s) {
        hash ^= (uint8_t)(*s++);
        hash *= 0x01000193u;     /* FNV prime        */
    }
    return hash;
}

/**
 * slot_index
 *
 * Maps a hash value to a slot index within [0, NANO_FFI_REGISTRY_CAPACITY).
 * Relies on capacity being a power of two so the bitmask is exact.
 *
 * @param hash  32-bit hash value.
 * @return      Slot index.
 */
static uint32_t slot_index(uint32_t hash)
{
    return hash & (uint32_t)(NANO_FFI_REGISTRY_CAPACITY - 1);
}

/**
 * platform_lock
 *
 * Pins *reg's memory pages using the platform memory-locking API.
 *
 * @param reg  Registry whose pages should be locked.
 * @return     NANO_FFI_OK on success, NANO_FFI_ERR_LOCK on failure.
 */
static int platform_lock(NffiRegistry *reg)
{
#ifdef _WIN32
    if (!VirtualLock(reg, sizeof(NffiRegistry))) {
        return NANO_FFI_ERR_LOCK;
    }
#else
    if (mlock(reg, sizeof(NffiRegistry)) != 0) {
        return NANO_FFI_ERR_LOCK;
    }
#endif
    return NANO_FFI_OK;
}

/**
 * platform_unlock
 *
 * Releases the memory lock on *reg's pages. Safe to call if locking
 * previously failed (reg->locked == 0).
 *
 * @param reg  Registry to unlock.
 */
static void platform_unlock(NffiRegistry *reg)
{
    if (!reg->locked) return;
#ifdef _WIN32
    VirtualUnlock(reg, sizeof(NffiRegistry));
#else
    munlock(reg, sizeof(NffiRegistry));
#endif
}

/* -------------------------------------------------------------------------
 * Public API
 * ---------------------------------------------------------------------- */

int nffi_registry_init(NffiRegistry *reg)
{
    if (!reg) return NANO_FFI_ERR_NULL;

    memset(reg, 0, sizeof(NffiRegistry));

    int lock_result = platform_lock(reg);
    if (lock_result == NANO_FFI_OK) {
        reg->locked = 1;
    }
    /* Non-fatal: caller can inspect reg->locked to decide whether to warn. */

    return lock_result == NANO_FFI_OK ? NANO_FFI_OK : NANO_FFI_ERR_LOCK;
}

void nffi_registry_destroy(NffiRegistry *reg)
{
    if (!reg) return;
    platform_unlock(reg);
    memset(reg, 0, sizeof(NffiRegistry));
}

int nffi_register(NffiRegistry *reg, const char *name, nffi_fn_t fn)
{
    if (!reg || !name || !fn) return NANO_FFI_ERR_NULL;
    if (strlen(name) >= NANO_FFI_MAX_NAME_LEN) return NANO_FFI_ERR_NAME_LEN;

    /* Refuse insert when the map is full (no live slots AND no tombstones). */
    if (reg->count >= NANO_FFI_REGISTRY_CAPACITY) return NANO_FFI_ERR_FULL;

    uint32_t hash  = fnv1a_32(name);
    uint32_t index = slot_index(hash);
    int      first_tomb = -1; /* index of first tombstone seen during probe */

    for (uint32_t i = 0; i < NANO_FFI_REGISTRY_CAPACITY; i++) {
        uint32_t   probe = (index + i) & (NANO_FFI_REGISTRY_CAPACITY - 1);
        NffiEntry *entry = &reg->entries[probe];

        if (entry->occupied) {
            /* Update in place if the name matches. */
            if (strncmp(entry->name, name, NANO_FFI_MAX_NAME_LEN) == 0) {
                entry->fn = fn;
                return NANO_FFI_OK;
            }
            continue;
        }

        if (entry->tombstone) {
            /* Remember first tombstone; keep probing for a duplicate name. */
            if (first_tomb < 0) first_tomb = (int)probe;
            continue;
        }

        /* Empty slot — use the earliest tombstone if one was found. */
        uint32_t target = (first_tomb >= 0) ? (uint32_t)first_tomb : probe;
        NffiEntry *dest  = &reg->entries[target];

        strncpy(dest->name, name, NANO_FFI_MAX_NAME_LEN - 1);
        dest->name[NANO_FFI_MAX_NAME_LEN - 1] = '\0';
        dest->fn         = fn;
        dest->occupied   = 1;
        dest->tombstone  = 0;
        reg->count++;
        return NANO_FFI_OK;
    }

    return NANO_FFI_ERR_FULL;
}

int nffi_lookup(const NffiRegistry *reg, const char *name, nffi_fn_t *out_fn)
{
    if (!reg || !name || !out_fn) return NANO_FFI_ERR_NULL;

    uint32_t hash  = fnv1a_32(name);
    uint32_t index = slot_index(hash);

    for (uint32_t i = 0; i < NANO_FFI_REGISTRY_CAPACITY; i++) {
        uint32_t         probe = (index + i) & (NANO_FFI_REGISTRY_CAPACITY - 1);
        const NffiEntry *entry = &reg->entries[probe];

        /* Empty, non-tombstone slot: name is definitely not in the map. */
        if (!entry->occupied && !entry->tombstone) {
            return NANO_FFI_ERR_NOT_FOUND;
        }

        if (entry->occupied &&
            strncmp(entry->name, name, NANO_FFI_MAX_NAME_LEN) == 0) {
            *out_fn = entry->fn;
            return NANO_FFI_OK;
        }
        /* Tombstone: skip and keep probing. */
    }

    return NANO_FFI_ERR_NOT_FOUND;
}

int nffi_unregister(NffiRegistry *reg, const char *name)
{
    if (!reg || !name) return NANO_FFI_ERR_NULL;

    uint32_t hash  = fnv1a_32(name);
    uint32_t index = slot_index(hash);

    for (uint32_t i = 0; i < NANO_FFI_REGISTRY_CAPACITY; i++) {
        uint32_t   probe = (index + i) & (NANO_FFI_REGISTRY_CAPACITY - 1);
        NffiEntry *entry = &reg->entries[probe];

        if (!entry->occupied && !entry->tombstone) {
            return NANO_FFI_ERR_NOT_FOUND;
        }

        if (entry->occupied &&
            strncmp(entry->name, name, NANO_FFI_MAX_NAME_LEN) == 0) {
            entry->fn        = NULL;
            entry->occupied  = 0;
            entry->tombstone = 1;
            memset(entry->name, 0, NANO_FFI_MAX_NAME_LEN);
            reg->count--;
            return NANO_FFI_OK;
        }
    }

    return NANO_FFI_ERR_NOT_FOUND;
}

uint32_t nffi_registry_count(const NffiRegistry *reg)
{
    if (!reg) return 0;
    return reg->count;
}