#include <Storages/MergeTree/KeyOrder.h>

#include <Common/FieldAccurateComparison.h>

namespace DB
{

int KeyOrder::compareTuples(const FieldRef * left, const FieldRef * right, size_t size) const
{
    for (size_t i = 0; i < size; ++i)
    {
        if (left[i].isNegativeInfinity() && right[i].isPositiveInfinity())
            return 0;

        if (accurateEquals(left[i], right[i]))
            continue;

        int cmp = accurateLess(left[i], right[i]) ? -1 : 1;
        return isReversed(i) ? -cmp : cmp;
    }
    return 0;
}

}
