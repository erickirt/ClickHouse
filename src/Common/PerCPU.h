#pragma once

#include <cstdint>
#include <base/defines.h>

#if defined(OS_LINUX)
#include <sched.h>
#endif

namespace PerCPU
{

/// Hard upper bound on the kernel cpu_id we'll route to. The BSS-backed per-CPU storage in
/// callers is sized with this constant, so it must be a compile-time value — but only the
/// first `getNumCPUs()` shards are used at runtime (and only those get faulted in).
constexpr uint32_t MAX_CPUS = 1024;

/// Runtime CPU count, capped at `MAX_CPUS`. Cached on first call.
/// `get_nprocs_conf()` on Linux, `sysconf(_SC_NPROCESSORS_ONLN)` elsewhere; 1 if unavailable.
uint32_t getNumCPUs() noexcept;

/// Current CPU id, or -1 if unavailable (callers must treat a negative value as "unknown" and
/// fall back to a fixed shard). The id is not guaranteed to be dense in [0, getNumCPUs()); callers
/// bound it (`cpu % N` or `cpu < N ? cpu : 0`). Cheap on every supported platform (no syscall).
ALWAYS_INLINE inline int32_t getCurrentCPU()
{
#if defined(OS_LINUX)
    /// TLS read via glibc rseq on modern kernels (see glibc-compatibility/musl/sched_getcpu.c).
    return sched_getcpu();
#elif defined(OS_DARWIN) && defined(__aarch64__)
    /// Apple Silicon: XNU keeps the current CPU number in the low bits of TPIDRRO_EL0, the same
    /// source libplatform's `_os_cpu_number` reads. A single register read. Only ~3 bits are
    /// meaningful (up to 8 distinct buckets), which is enough to spread work across shards.
    uint64_t tpidrro;
    __asm__ volatile("mrs %0, TPIDRRO_EL0" : "=r"(tpidrro));
    return static_cast<int32_t>(tpidrro & 0x7);
#elif defined(OS_DARWIN) && defined(__x86_64__)
    /// x86 macOS has no `sched_getcpu`. `rdtscp` is cheap and its aux register is CPU-correlated on
    /// platforms that program `IA32_TSC_AUX`; where it is not, callers just collapse to one shard.
    /// `cpuid` would give the exact APIC id but is serializing, too costly for hot per-event calls.
    unsigned aux = 0;
    __builtin_ia32_rdtscp(&aux);
    return static_cast<int32_t>(aux & 0xfff);
#else
    return -1;
#endif
}

}
