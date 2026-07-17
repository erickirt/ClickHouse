#include <Columns/ColumnObject.h>
#include <DataTypes/DataTypeFactory.h>
#include <DataTypes/Serializations/SerializationObject.h>
#include <DataTypes/Serializations/SerializationObjectHelpers.h>
#include <IO/ReadBufferFromString.h>
#include <IO/VarInt.h>
#include <IO/WriteBufferFromString.h>
#include <IO/WriteHelpers.h>
#include <Common/Exception.h>

#include <gtest/gtest.h>

#include <limits>

using namespace DB;

namespace DB::ErrorCodes
{
    extern const int INCORRECT_DATA;
}

TEST(ObjectSerialization, FieldBinarySerialization)
{
    auto type = DataTypeFactory::instance().get("JSON(max_dynamic_types=10, max_dynamic_paths=2, a.b UInt32, a.c Array(String))");
    auto serialization = type->getDefaultSerialization();
    Object object1 = Object{{"a.c", Array{"Str1", "Str2"}}, {"a.d", Field(42)}, {"a.e", Tuple{Field(43), "Str3"}}};
    WriteBufferFromOwnString ostr;
    serialization->serializeBinary(object1, ostr, FormatSettings());
    ReadBufferFromString istr(ostr.str());
    Field object2;
    serialization->deserializeBinary(object2, istr, FormatSettings());
    ASSERT_EQ(object1, object2.safeGet<Object>());
}


TEST(ObjectSerialization, ColumnBinarySerialization)
{
    auto type = DataTypeFactory::instance().get("JSON(max_dynamic_types=10, max_dynamic_paths=2, a.b UInt32, a.c Array(String))");
    auto serialization = type->getDefaultSerialization();
    auto col = type->createColumn();
    auto & col_object = assert_cast<ColumnObject &>(*col);
    col_object.insert(Object{{"a.c", Array{"Str1", "Str2"}}, {"a.d", Field(42)}, {"a.e", Tuple{Field(43), "Str3"}}});
    WriteBufferFromOwnString ostr1;
    serialization->serializeBinary(col_object, 0, ostr1, FormatSettings());
    ReadBufferFromString istr1(ostr1.str());
    serialization->deserializeBinary(col_object, istr1, FormatSettings());
    ASSERT_EQ(col_object[0], col_object[1]);
    col_object.insert(Object{{"a.c", Array{"Str1", "Str2"}}, {"a.e", Field(42)}, {"b.d", Field(42)}, {"b.e", Tuple{Field(43), "Str3"}}, {"b.g", Field("Str4")}});
    WriteBufferFromOwnString ostr2;
    serialization->serializeBinary(col_object, 2, ostr2, FormatSettings());
    ReadBufferFromString istr2(ostr2.str());
    serialization->deserializeBinary(col_object, istr2, FormatSettings());
    ASSERT_EQ(col_object[2], col_object[3]);
}

TEST(ObjectSerialization, JSONSerialization)
{
    auto type = DataTypeFactory::instance().get("JSON(max_dynamic_types=10, max_dynamic_paths=2, a.b UInt32, a.c Array(String))");
    auto serialization = type->getDefaultSerialization();
    auto col = type->createColumn();
    auto & col_object = assert_cast<ColumnObject &>(*col);
    col_object.insert(Object{{"a.c", Array{"Str1", "Str2"}}, {"a.d", Field(42)}, {"a.e", Tuple{Field(43), "Str3"}}});
    col_object.insert(Object{{"a.c", Array{"Str1", "Str2"}}, {"a", Tuple{Field(43), "Str3"}}, {"a.b.c", Field(42)}, {"a.b.e", Field(43)}, {"b.c.d.e", Field(42)}, {"b.c.d.g", Field(43)}, {"b.c.h.r", Field(44)}, {"c.g.h.t", Array{Field("Str"), Field("Str2")}}, {"h", Field("Str")}, {"j", Field("Str")}});
    WriteBufferFromOwnString buf1;
    serialization->serializeTextJSON(col_object, 1, buf1, FormatSettings());
    ASSERT_EQ(buf1.str(), R"({"a":[43,"Str3"],"a":{"b":0,"b":{"c":42,"e":43},"c":["Str1","Str2"]},"b":{"c":{"d":{"e":42,"g":43},"h":{"r":44}}},"c":{"g":{"h":{"t":["Str","Str2"]}}},"h":"Str","j":"Str"})");
    WriteBufferFromOwnString buf2;
    serialization->serializeTextJSONPretty(col_object, 1, buf2, FormatSettings(), 0);
    ASSERT_EQ(buf2.str(), R"({
    "a": [
        43,
        "Str3"
    ],
    "a": {
        "b": 0,
        "b": {
            "c": 42,
            "e": 43
        },
        "c": ["Str1","Str2"]
    },
    "b": {
        "c": {
            "d": {
                "e": 42,
                "g": 43
            },
            "h": {
                "r": 44
            }
        }
    },
    "c": {
        "g": {
            "h": {
                "t": ["Str","Str2"]
            }
        }
    },
    "h": "Str",
    "j": "Str"
})");

}

/// flattenAndBucketSharedDataPaths must densify each shared-data path into a column that has one
/// entry per row (the stored value where the path is present, a default where it is absent), for an
/// arbitrary subrange [start, end). This exercises rows with different, overlapping and missing paths,
/// empty rows and trailing gaps -- the exact shape the merge/serialization path produces.
namespace
{
using DensePath = std::vector<std::optional<UInt64>>;

void checkFlattenedSharedData(
    const ColumnObject & col_object,
    size_t start,
    size_t end,
    const std::map<String, DensePath> & expected)
{
    auto buckets = flattenAndBucketSharedDataPaths(*col_object.getSharedDataPtr(), start, end, col_object.getDynamicType(), 1);
    ASSERT_EQ(buckets.size(), 1u);

    std::map<String, ColumnPtr> path_to_column;
    for (const auto & [path, column] : buckets[0])
        path_to_column[path] = column;

    ASSERT_EQ(path_to_column.size(), expected.size());
    for (const auto & [path, values] : expected)
    {
        auto it = path_to_column.find(path);
        ASSERT_NE(it, path_to_column.end()) << "missing path " << path;
        const auto & column = *it->second;
        /// Every path column must be densified to exactly (end - start) rows.
        ASSERT_EQ(column.size(), values.size()) << "wrong size for path " << path;
        for (size_t i = 0; i != values.size(); ++i)
        {
            Field f = column[i];
            if (values[i].has_value())
                ASSERT_EQ(f.safeGet<UInt64>(), *values[i]) << "wrong value for path " << path << " row " << i;
            else
                ASSERT_TRUE(f.isNull()) << "expected default (null) for path " << path << " row " << i;
        }
    }
}
}

TEST(ObjectSerialization, FlattenAndBucketSharedDataPaths)
{
    /// max_dynamic_paths=0 forces every path into shared data.
    auto type = DataTypeFactory::instance().get("JSON(max_dynamic_paths=0)");
    auto col = type->createColumn();
    auto & col_object = assert_cast<ColumnObject &>(*col);

    /// Row 0: a, b ; row 1: {} ; row 2: b, c ; row 3: a ; row 4: {} ; row 5: a, b, c
    col_object.insert(Object{{"a", Field(UInt64(10))}, {"b", Field(UInt64(11))}});
    col_object.insert(Object{});
    col_object.insert(Object{{"b", Field(UInt64(21))}, {"c", Field(UInt64(22))}});
    col_object.insert(Object{{"a", Field(UInt64(30))}});
    col_object.insert(Object{});
    col_object.insert(Object{{"a", Field(UInt64(50))}, {"b", Field(UInt64(51))}, {"c", Field(UInt64(52))}});

    ASSERT_EQ(col_object.size(), 6u);

    /// Full range. std::nullopt = default (path absent in that row).
    checkFlattenedSharedData(col_object, 0, 6, {
        {"a", {10, std::nullopt, std::nullopt, 30, std::nullopt, 50}},
        {"b", {11, std::nullopt, 21, std::nullopt, std::nullopt, 51}},
        {"c", {std::nullopt, std::nullopt, 22, std::nullopt, std::nullopt, 52}},
    });

    /// Subrange [1, 4) = rows {} , {b,c} , {a}. Densification is relative to `start`.
    checkFlattenedSharedData(col_object, 1, 4, {
        {"a", {std::nullopt, std::nullopt, 30}},
        {"b", {std::nullopt, 21, std::nullopt}},
        {"c", {std::nullopt, 22, std::nullopt}},
    });

    /// Subrange [2, 5) = rows {b,c} , {a} , {}. Trailing empty row must be padded with a default.
    checkFlattenedSharedData(col_object, 2, 5, {
        {"a", {std::nullopt, 30, std::nullopt}},
        {"b", {21, std::nullopt, std::nullopt}},
        {"c", {22, std::nullopt, std::nullopt}},
    });
}

/// The shared-data-paths statistics count in the ObjectStructure prefix is only read when
/// `object_and_dynamic_read_statistics` is enabled -- the MergeTree part read path, which the
/// `Native` input format (covered by 04350_json_native_too_many_paths) never reaches, since it
/// always leaves statistics disabled. A corrupted count there must be rejected with a clean
/// `INCORRECT_DATA` error instead of escaping as an uncaught `std::bad_alloc` /
/// `std::length_error` / `std::bad_array_new_length` from the hash-table `reserve`.
TEST(ObjectSerialization, TooManySharedDataPathsStatistics)
{
    auto type = DataTypeFactory::instance().get("JSON");
    auto serialization = type->getDefaultSerialization();

    /// Hand-crafted V1 (version = 0) ObjectStructure prefix:
    ///   [UInt64 LE version = 0]
    ///   [VarUInt max_dynamic_paths = 0]                            (V1 only)
    ///   [VarUInt number of dynamic paths = 0]
    ///   [VarUInt shared-data-paths statistics count = SIZE_MAX]    <- corrupted
    WriteBufferFromOwnString structure;
    writeBinaryLittleEndian(static_cast<UInt64>(0), structure); /// SerializationVersion::V1
    writeVarUInt(static_cast<UInt64>(0), structure);            /// max_dynamic_paths
    writeVarUInt(static_cast<UInt64>(0), structure);            /// number of dynamic paths
    writeVarUInt(std::numeric_limits<size_t>::max(), structure);/// shared-data-paths count
    std::string structure_bytes = structure.str();
    ReadBufferFromString structure_stream(structure_bytes);

    ISerialization::DeserializeBinaryBulkSettings settings;
    settings.object_and_dynamic_read_statistics = true;
    settings.getter = [&](const ISerialization::SubstreamPath & path) -> ReadBuffer *
    {
        if (!path.empty() && path.back().type == ISerialization::Substream::ObjectStructure)
            return &structure_stream;
        return nullptr;
    };

    ISerialization::DeserializeBinaryBulkStatePtr state;
    try
    {
        serialization->deserializeBinaryBulkStatePrefix(settings, state, nullptr);
        FAIL() << "Expected INCORRECT_DATA for a corrupted shared-data-paths statistics count";
    }
    catch (const Exception & e)
    {
        ASSERT_EQ(e.code(), ErrorCodes::INCORRECT_DATA) << e.message();
        ASSERT_NE(e.message().find("too many paths"), std::string::npos) << e.message();
    }
}
