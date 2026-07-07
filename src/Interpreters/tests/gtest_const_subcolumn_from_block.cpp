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

/// Regression for https://github.com/ClickHouse/ClickHouse/issues/104856.
///
/// A schema-evolved column absent from older data files (e.g. an Iceberg table) is materialized as
/// a ColumnConst. Extracting its ".null" subcolumn used to fail: the datatype-level extraction
/// (IDataType::tryGetSubcolumn) expects the concrete column (ColumnNullable), so on a ColumnConst
/// it soft-failed to nullptr (surfacing as NOT_FOUND_COLUMN_IN_BLOCK, or "Bad cast ColumnConst to
/// ColumnNullable" in sanitizer builds). Const is just a wrapper (like Sparse or Replicated), so
/// the caller must strip it before extracting. This is not reachable from SQL because the insert
/// and read pipelines materialize constants before subcolumn extraction, so it is covered here.
///
/// The unwrap lives in the shared helper tryGetSubcolumnUnwrappingConst and is exercised through
/// both caller families: tryGetColumnFromBlock (in-memory storage read path) and
/// Block::getSubcolumnByName (used by MergeTree to materialize key/skip-index subcolumns).

namespace
{
    void checkNullMapAllOne(const ColumnPtr & null_map, size_t expected_size)
    {
        ASSERT_NE(null_map, nullptr);
        ASSERT_EQ(null_map->size(), expected_size);
        /// Every row is NULL, so .null must be 1 everywhere.
        ColumnPtr full = null_map->convertToFullColumnIfConst();
        for (size_t i = 0; i < full->size(); ++i)
            ASSERT_EQ(full->getUInt(i), 1u);
    }
}

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
    checkNullMapAllOne(null_map, 5u);
}

TEST(ConstSubcolumnFromBlock, BlockGetSubcolumnByNameOfConstNullable)
{
    auto type = std::make_shared<DataTypeNullable>(std::make_shared<DataTypeString>());

    /// A size-5 constant NULL column, as it reaches MergeTree when materializing a partition key
    /// or skip index defined on `c.null`.
    ColumnPtr const_column = type->createColumnConstWithDefaultValue(5);

    Block block{ColumnWithTypeAndName(const_column, type, "c")};

    std::optional<ColumnWithTypeAndName> subcolumn;
    ASSERT_NO_THROW(subcolumn = block.findSubcolumnByName("c.null"));
    ASSERT_TRUE(subcolumn.has_value());
    checkNullMapAllOne(subcolumn->column, 5u);
}
