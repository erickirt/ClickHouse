#pragma once

#include <cstddef>
#include <vector>

namespace DB::JemallocMergeTreeArena
{

/// Dedicated jemalloc arena(s) for long-lived MergeTree heap state:
///   - per-part metadata: `NamesAndTypesList`, `SerializationInfoByName`, the `serializations`
///     map, `column_name_to_position`, `MergeTreeDataPartChecksums` tree, `ColumnsSubstreams`,
///     the per-part `ColumnSize`/`IndexSize` maps, `MinMaxIndex`, `index_granularity`, and the
///     primary index arrays.
///   - per-table metadata: `ColumnsDescription`, `VirtualColumnsDescription`,
///     `StorageInMemoryMetadata` clones, the `serialization_hints` aggregation, and the
///     `columns_descriptions_cache`.
/// Isolating these off the default arenas reduces fragmentation of query-lifetime allocations.
///
/// Callers route allocations here for a bounded scope via `ScopedJemallocThreadArena` from
/// `Common/Jemalloc.h`. Frees auto-route via jemalloc's per-extent metadata, so only allocation
/// paths need scoping.

/// Configure the arena pool. Call once at startup, before parts are loaded. Startup-only:
/// subsequent calls are ignored.
///   num_arenas == 0 -> disabled: `getArenaIndex` returns 0 (default arena selection), a no-op.
///   num_arenas == 1 -> one shared arena.
///   num_arenas  > 1 -> a pool sharded by CPU (`cpu_id % N`). Capped at the CPU count, since
///                      routing is per-CPU and any arena beyond that would never be selected;
///                      pass a large value (or the core count) to get one arena per CPU.
void initialize(size_t num_arenas);

/// Arena index for the calling thread's current CPU, or 0 (default arena) when disabled or not
/// yet initialized. Resolved per call from the current CPU rather than cached per thread, so a
/// thread that migrates CPUs follows its CPU's arena instead of pinning a foreign one.
unsigned getArenaIndex();

/// All arena indices in the pool (empty when disabled). For metrics aggregation and purge.
const std::vector<unsigned> & getArenaIndices();

/// Whether the pool is enabled (at least one arena created).
bool isEnabled();

/// Purge dirty pages in every pool arena, returning memory to the OS. No-op when disabled.
void purge();

}
