#include <Common/JemallocMergeTreeArena.h>

#include "config.h"

#if USE_JEMALLOC

#include <Common/Jemalloc.h>
#include <Common/PerCPU.h>
#include <Common/ProfileEvents.h>
#include <Common/Stopwatch.h>
#include <Common/logger_useful.h>

#include <algorithm>
#include <atomic>
#include <optional>

#include <fmt/format.h>
#include <jemalloc/jemalloc.h>

namespace ProfileEvents
{
    extern const Event MemoryAllocatorPurge;
    extern const Event MemoryAllocatorPurgeTimeMicroseconds;
}

namespace DB::JemallocMergeTreeArena
{

namespace
{

/// Written once by `initialize` before `initialized` is published; read-only afterwards.
std::vector<unsigned> arena_indices;
std::atomic<bool> initialized = false;

std::optional<unsigned> createArena()
{
    unsigned arena_index = 0;
    size_t arena_index_size = sizeof(arena_index);
    int err = je_mallctl("arenas.create", &arena_index, &arena_index_size, nullptr, 0);
    if (err)
    {
        LOG_ERROR(
            &Poco::Logger::get("JemallocMergeTreeArena"),
            "Failed to create dedicated jemalloc MergeTree arena (mallctl error: {}). "
            "MergeTree allocations will use the default arena.",
            err);
        return {};
    }
    return arena_index;
}

}

void initialize(size_t num_arenas)
{
    /// Startup-only; ignore repeated calls (e.g. a config reload).
    if (initialized.load(std::memory_order_acquire))
        return;

    /// Routing is `cpu_id % N`, so arenas beyond the CPU count would never be selected.
    if (num_arenas > 1)
        num_arenas = std::min(num_arenas, static_cast<size_t>(PerCPU::getNumCPUs()));

    std::vector<unsigned> indices;
    indices.reserve(num_arenas);
    for (size_t i = 0; i < num_arenas; ++i)
    {
        auto index = createArena();
        if (!index)
            break; /// Keep whatever we managed to create; the rest falls back to the default arena.
        indices.push_back(*index);
    }

    arena_indices = std::move(indices);
    initialized.store(true, std::memory_order_release);
}

unsigned getArenaIndex()
{
    if (!initialized.load(std::memory_order_acquire))
        return 0;

    const size_t n = arena_indices.size();
    if (n == 0)
        return 0;
    if (n == 1)
        return arena_indices[0];

    Int32 cpu = PerCPU::getCurrentCPU();
    size_t slot = cpu < 0 ? 0 : static_cast<UInt32>(cpu) % n;
    return arena_indices[slot];
}

const std::vector<unsigned> & getArenaIndices()
{
    return arena_indices;
}

bool isEnabled()
{
    return initialized.load(std::memory_order_acquire) && !arena_indices.empty();
}

void purge()
{
    if (!isEnabled())
        return;

    Stopwatch watch;
    for (unsigned index : arena_indices)
    {
        Jemalloc::MibCache<unsigned> purge_mib(fmt::format("arena.{}.purge", index).c_str());
        purge_mib.run();
    }
    ProfileEvents::increment(ProfileEvents::MemoryAllocatorPurge);
    ProfileEvents::increment(ProfileEvents::MemoryAllocatorPurgeTimeMicroseconds, watch.elapsedMicroseconds());
}

}

#else

namespace DB::JemallocMergeTreeArena
{

void initialize(size_t) {}
unsigned getArenaIndex() { return 0; }
const std::vector<unsigned> & getArenaIndices() { static const std::vector<unsigned> empty; return empty; }
bool isEnabled() { return false; }
void purge() {}

}

#endif
