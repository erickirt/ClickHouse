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
#include <vector>

#include <fmt/format.h>
#include <jemalloc/jemalloc.h>

#if defined(OS_LINUX)
#include <sched.h>
#endif

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
/// Maps an absolute CPU id (from `getCurrentCPU`) to a slot in `arena_indices`. Sized to
/// `MAX_CPUS`. Built so every created arena is reachable regardless of the CPU-affinity mask.
std::vector<UInt32> slot_by_cpu;
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

/// CPUs this process may run on, in ascending order. Honors the affinity mask on Linux, so a
/// cpuset-limited process only routes to the CPUs it actually uses; falls back to
/// [0, getNumCPUs()) elsewhere.
std::vector<UInt32> getAllowedCPUs()
{
    std::vector<UInt32> cpus;
#if defined(OS_LINUX)
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof(set), &set) == 0)
    {
        for (UInt32 cpu = 0; cpu < PerCPU::MAX_CPUS; ++cpu)
            if (CPU_ISSET(cpu, &set))
                cpus.push_back(cpu);
    }
#endif
    if (cpus.empty())
    {
        for (UInt32 cpu = 0; cpu < PerCPU::getNumCPUs(); ++cpu)
            cpus.push_back(cpu);
    }
    return cpus;
}

}

void initialize(size_t num_arenas)
{
    /// Startup-only; ignore repeated calls (e.g. a config reload).
    if (initialized.load(std::memory_order_acquire))
        return;

    if (num_arenas > 0)
    {
        /// Size the pool to the CPUs we can actually route to and build a dense CPU->slot map, so
        /// every created arena receives allocations even under a restrictive or sparse affinity
        /// mask (`cpu_id % N` alone would leave arenas unreachable and overstate the count).
        const std::vector<UInt32> allowed_cpus = getAllowedCPUs();
        num_arenas = std::min(num_arenas, allowed_cpus.size());

        std::vector<unsigned> indices;
        indices.reserve(num_arenas);
        for (size_t i = 0; i < num_arenas; ++i)
        {
            auto index = createArena();
            if (!index)
                break; /// Keep whatever we managed to create; the rest falls back to the default arena.
            indices.push_back(*index);
        }

        if (!indices.empty())
        {
            slot_by_cpu.assign(PerCPU::MAX_CPUS, 0);
            for (size_t dense = 0; dense < allowed_cpus.size(); ++dense)
            {
                const UInt32 cpu = allowed_cpus[dense];
                if (cpu < PerCPU::MAX_CPUS)
                    slot_by_cpu[cpu] = static_cast<UInt32>(dense % indices.size());
            }
        }

        arena_indices = std::move(indices);
    }

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

    const Int32 cpu = PerCPU::getCurrentCPU();
    if (cpu < 0 || static_cast<size_t>(cpu) >= slot_by_cpu.size())
        return arena_indices[0];
    return arena_indices[slot_by_cpu[cpu]];
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
