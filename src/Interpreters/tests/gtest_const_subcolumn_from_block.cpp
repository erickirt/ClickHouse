#include <Columns/ColumnConst.h>
#include <Columns/ColumnsNumber.h>
#include <Core/Block.h>
#include <Core/NamesAndTypes.h>
#include <DataTypes/DataTypeNullable.h>
#include <DataTypes/DataTypeString.h>
#include <DataTypes/DataTypesNumber.h>
#include <Interpreters/getColumnFromBlock.h>

#include <gtest/gtest.h>

using namespace DB;

/// Regression for https://github.com/ClickHouse/ClickHouse/issues/104856:
/// a schema-evolved column absent from older data files (e.g. an Iceberg table) is
/// materialized as a ColumnConst. Reading its ".null" subcolumn via getColumnFromBlock
/// used to fail: the datatype-level extraction expects the concrete column (ColumnNullable),
/// so on a ColumnConst it soft-failed to nullptr (surfacing as NOT_FOUND_COLUMN_IN_BLOCK,
/// or "Bad cast ColumnConst to ColumnNullable" in sanitizer builds). The caller must strip
/// the Const wrapper before extracting, like it does for other wrappers.
TEST(ConstSubcolumnFromBlock, NullMapOfConstNullable)
{
    auto type = std::make_shared<DataTypeNullable>(std::make_shared<DataTypeString>());

    /// A size-5 constant NULL column, as produced for a missing schema-evolved column.
    ColumnPtr const_column = type->createColumnConstWithDefaultValue(5);

    Block block{ColumnWithTypeAndName(const_column, type, "c")};

    auto null_type = type->getSubcolumnType("null");
    NameAndTypePair requested_subcolumn("c", "null", type, null_type);

    ColumnPtr null_map;
    ASSERT_NO_THROW(null_map = tryGetColumnFromBlock(block, requested_subcolumn));
    ASSERT_NE(null_map, nullptr);
    ASSERT_EQ(null_map->size(), 5u);

    /// Every row is NULL, so .null must be 1 everywhere.
    ColumnPtr full = null_map->convertToFullColumnIfConst();
    for (size_t i = 0; i < full->size(); ++i)
        ASSERT_EQ(full->getUInt(i), 1u);
}
