#include <Common/PerCPU.h>

#if defined(OS_LINUX)
#include <sys/sysinfo.h>
#else
#include <unistd.h>
#endif

#include <algorithm>

namespace PerCPU
{

UInt32 getNumCPUs() noexcept
{
    static const UInt32 cached = []
    {
#if defined(OS_LINUX)
        const Int64 n = get_nprocs_conf();
#else
        const Int64 n = ::sysconf(_SC_NPROCESSORS_ONLN);
#endif
        if (n <= 0)
            return UInt32{1};
        return std::min(static_cast<UInt32>(n), MAX_CPUS);
    }();
    return cached;
}

}
