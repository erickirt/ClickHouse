#include <gtest/gtest.h>

#include <Interpreters/QueryLog.h>
#include <Common/SystemLogBase.h>

#include <type_traits>

using namespace DB;

namespace
{

SystemLogQueueSettings makeSettings(size_t reserved_size_rows)
{
    SystemLogQueueSettings settings;
    settings.database = "system";
    settings.table = "test_query_log";
    settings.reserved_size_rows = reserved_size_rows;
    settings.max_size_rows = 1ULL << 20;
    settings.buffer_size_rows_flush_threshold = 1ULL << 19;
    settings.flush_interval_milliseconds = 1;
    settings.notify_flush_on_crash = false;
    settings.turn_off_logger = true;
    return settings;
}

void fill(SystemLogQueue<QueryLogElement> & queue, size_t size)
{
    for (size_t i = 0; i < size; ++i)
        queue.push(QueryLogElement{});
}
}

static_assert(!std::is_trivially_copyable_v<QueryLogElement>);

TEST(SystemLogQueue, EmptyFlushDoesNotAllocateConsumerBuffer)
{
    SystemLogQueue<QueryLogElement> queue(makeSettings(16));

    auto result = queue.pop();
    ASSERT_FALSE(result.is_shutdown);
    EXPECT_TRUE(result.logs.empty());
    EXPECT_EQ(result.logs.capacity(), 0);
}

TEST(SystemLogQueue, ReservationSurvivesFlush)
{
    constexpr size_t reserved = 16;
    SystemLogQueue<QueryLogElement> queue(makeSettings(reserved));

    const size_t initial_capacity = queue.getQueueCapacityForTest();
    ASSERT_GE(initial_capacity, reserved);

    fill(queue, reserved);
    EXPECT_EQ(queue.getQueueCapacityForTest(), initial_capacity);

    auto result = queue.pop();
    ASSERT_FALSE(result.is_shutdown);
    ASSERT_EQ(result.logs.size(), reserved);
    EXPECT_GE(queue.getQueueCapacityForTest(), reserved);
}

TEST(SystemLogQueue, NoReallocationAcrossFlushCycles)
{
    constexpr size_t reserved = 16;
    constexpr size_t cycles = 5;
    SystemLogQueue<QueryLogElement> queue(makeSettings(reserved));

    for (size_t cycle = 0; cycle < cycles; ++cycle)
    {
        const size_t capacity_before_fill = queue.getQueueCapacityForTest();
        ASSERT_GE(capacity_before_fill, reserved);

        fill(queue, reserved);
        EXPECT_EQ(queue.getQueueCapacityForTest(), capacity_before_fill);

        auto result = queue.pop();
        ASSERT_FALSE(result.is_shutdown);
        ASSERT_EQ(result.logs.size(), reserved);
    }
}

TEST(SystemLogQueue, RetainsHeadroomAndDecaysAfterSmallBatch)
{
    constexpr size_t reserved = 16;
    SystemLogQueue<QueryLogElement> queue(makeSettings(reserved));

    fill(queue, reserved + 1);
    const size_t expanded_capacity = queue.getQueueCapacityForTest();
    ASSERT_GT(expanded_capacity, reserved);

    auto result = queue.pop();
    ASSERT_EQ(result.logs.size(), reserved + 1);
    const size_t retained_capacity = queue.getQueueCapacityForTest();
    EXPECT_GT(retained_capacity, reserved + 1);
    EXPECT_LE(retained_capacity, (reserved + 1) * 2);

    fill(queue, reserved + 2);
    EXPECT_EQ(queue.getQueueCapacityForTest(), retained_capacity);
    result = queue.pop();
    ASSERT_EQ(result.logs.size(), reserved + 2);

    fill(queue, 1);
    result = queue.pop();
    ASSERT_EQ(result.logs.size(), 1);
    EXPECT_LT(queue.getQueueCapacityForTest(), retained_capacity);

    const size_t decayed_capacity = queue.getQueueCapacityForTest();
    ASSERT_GE(decayed_capacity, reserved);
    fill(queue, reserved);
    EXPECT_EQ(queue.getQueueCapacityForTest(), decayed_capacity);
}
