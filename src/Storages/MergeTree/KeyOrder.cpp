#include <Storages/MergeTree/KeyOrder.h>

#include <Common/FieldAccurateComparison.h>

namespace DB
{

int KeyOrder::compareTuples(const FieldRef * left, const FieldRef * right, size_t size) const
{
    for (size_t i = 0; i < size; ++i)
    {
        /// The (physicalStartExtreme, physicalEndExtreme) pair marks a column whose value is unknown
        /// at both boundaries; nothing can be concluded about the order of tuples that differ first
        /// at such a column.
        if (left[i] == physicalStartExtreme(i) && right[i] == physicalEndExtreme(i))
            return 0;

        if (accurateEquals(left[i], right[i]))
            continue;

        int cmp = accurateLess(left[i], right[i]) ? -1 : 1;
        return isReversed(i) ? -cmp : cmp;
    }
    return 0;
}

}
