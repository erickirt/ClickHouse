#pragma once

#include <base/defines.h>
#include <base/types.h>

#if defined(OS_LINUX)
#include <sched.h>
#endif

namespace PerCPU
{

/// Hard upper bound on the kernel cpu_id we'll route to. The BSS-backed per-CPU storage in
/// callers is sized with this constant, so it must be a compile-time value — but only the
/// first `getNumCPUs()` shards are used at runtime (and only those get faulted in).
constexpr UInt32 MAX_CPUS = 1024;

/// Runtime CPU count, capped at `MAX_CPUS`. Cached on first call.
/// `get_nprocs_conf()` on Linux, `sysconf(_SC_NPROCESSORS_ONLN)` elsewhere; 1 if unavailable.
UInt32 getNumCPUs() noexcept;

/// Current CPU id, or -1 if unavailable (callers must treat a negative value as "unknown" and
/// fall back to a fixed shard). The id is not guaranteed to be dense in [0, getNumCPUs()); callers
/// bound it (`cpu % N` or `cpu < N ? cpu : 0`). Cheap on every supported platform (no syscall).
ALWAYS_INLINE inline Int32 getCurrentCPU()
{
#if defined(OS_LINUX)
    /// TLS read via glibc rseq on modern kernels (see glibc-compatibility/musl/sched_getcpu.c).
    return sched_getcpu();
#elif defined(OS_DARWIN) && defined(__aarch64__)
    /// macOS has no `sched_getcpu`. XNU exposes the current CPU number to userspace in the low 12
    /// bits of a per-CPU register, extracted exactly as libsyscall's `_os_cpu_number` (up to 4096
    /// CPUs): https://github.com/apple-oss-distributions/xnu/blob/1031c584a5e37aff177559b9f69dbd3c8c3fd30a/libsyscall/os/tsd.h
    /// The layout is Apple-internal and documented there as "subject to change"; if it ever does,
    /// callers still bound the value, so the worst case is degraded sharding, not incorrectness.
    UInt64 tpidr;
    __asm__ volatile("mrs %0, TPIDR_EL0" : "=r"(tpidr));
    return static_cast<Int32>(tpidr & 0xfff);
#elif defined(OS_DARWIN) && defined(__x86_64__)
    /// Same source as above (`_os_cpu_number`): the CPU number is in the low 12 bits of the
    /// per-CPU IDT base, read cheaply via `sidt`.
    struct { UInt64 limit_and_base_low; UInt64 base_high; } idtr;
    __asm__ volatile("sidt %0" : "=m"(idtr));
    return static_cast<Int32>(idtr.limit_and_base_low & 0xfff);
#else
    return -1;
#endif
}

}
