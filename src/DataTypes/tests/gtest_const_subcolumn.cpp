#include <Columns/ColumnConst.h>
#include <Columns/ColumnNullable.h>
#include <DataTypes/DataTypeNullable.h>
#include <DataTypes/DataTypesNumber.h>
#include <DataTypes/DataTypeString.h>

#include <gtest/gtest.h>

using namespace DB;

/// Regression for https://github.com/ClickHouse/ClickHouse/issues/104856:
/// extracting a subcolumn (e.g. the ".null" null-map) from a ColumnConst used to
/// throw "Bad cast from ColumnConst to ColumnNullable" (soft-failing to nullptr in
/// release, which surfaced as NOT_FOUND_COLUMN_IN_BLOCK). Iceberg synthesizes a
/// schema-evolved column absent from older data files as a ColumnConst, so
/// `WHERE col IS NULL` with optimize_functions_to_subcolumns=1 hit this path.
TEST(ConstSubcolumn, NullMapOfConstNullable)
{
    auto type = std::make_shared<DataTypeNullable>(std::make_shared<DataTypeString>());
    /// A size-5 constant NULL column, as produced for a missing schema-evolved column.
    ColumnPtr column = type->createColumnConstWithDefaultValue(5);

    auto null_map = type->tryGetSubcolumn("null", column);
    ASSERT_NE(null_map, nullptr);
    ASSERT_EQ(null_map->size(), 5u);

    auto null_type = type->tryGetSubcolumnType("null");
    ASSERT_NE(null_type, nullptr);

    /// Every row is NULL, so .null must be 1 everywhere.
    for (size_t i = 0; i < null_map->size(); ++i)
        ASSERT_EQ(null_map->getUInt(i), 1u);

    /// The throwing entry point must also work.
    ASSERT_NO_THROW(type->getSubcolumn("null", column));
}
