#include <Common/PerCPU.h>

#if defined(OS_LINUX)
#include <sys/sysinfo.h>
#else
#include <unistd.h>
#endif

#include <algorithm>

namespace PerCPU
{

uint32_t getNumCPUs() noexcept
{
    static const uint32_t cached = []
    {
#if defined(OS_LINUX)
        const long n = get_nprocs_conf();
#else
        const long n = ::sysconf(_SC_NPROCESSORS_ONLN);
#endif
        if (n <= 0)
            return uint32_t{1};
        return std::min(static_cast<uint32_t>(n), MAX_CPUS);
    }();
    return cached;
}

}
