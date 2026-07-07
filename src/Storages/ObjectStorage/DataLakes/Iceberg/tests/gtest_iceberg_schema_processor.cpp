#include <gtest/gtest.h>

#include <DataTypes/IDataType.h>
#include <Storages/ObjectStorage/DataLakes/Iceberg/SchemaProcessor.h>
#include <Common/Exception.h>

#include <Poco/JSON/Object.h>
#include <Poco/JSON/Parser.h>

using namespace DB::Iceberg;

namespace
{
Poco::JSON::Object::Ptr parseSchema(const std::string & json)
{
    Poco::JSON::Parser parser;
    return parser.parse(json).extract<Poco::JSON::Object::Ptr>();
}
}

TEST(IcebergSchemaProcessor, GetSimpleTypeBoolean)
{
    auto type = IcebergSchemaProcessor::getSimpleType("boolean");
    EXPECT_EQ(type->getName(), "Bool");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeInt)
{
    auto type = IcebergSchemaProcessor::getSimpleType("int");
    EXPECT_EQ(type->getName(), "Int32");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeLong)
{
    auto type = IcebergSchemaProcessor::getSimpleType("long");
    EXPECT_EQ(type->getName(), "Int64");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeBigint)
{
    auto type = IcebergSchemaProcessor::getSimpleType("bigint");
    EXPECT_EQ(type->getName(), "Int64");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeFloat)
{
    auto type = IcebergSchemaProcessor::getSimpleType("float");
    EXPECT_EQ(type->getName(), "Float32");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeDouble)
{
    auto type = IcebergSchemaProcessor::getSimpleType("double");
    EXPECT_EQ(type->getName(), "Float64");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeDate)
{
    auto type = IcebergSchemaProcessor::getSimpleType("date");
    EXPECT_EQ(type->getName(), "Date32");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeTime)
{
    auto type = IcebergSchemaProcessor::getSimpleType("time");
    EXPECT_EQ(type->getName(), "Int64");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeTimestamp)
{
    auto type = IcebergSchemaProcessor::getSimpleType("timestamp");
    EXPECT_EQ(type->getName(), "DateTime64(6)");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeTimestamptz)
{
    auto type = IcebergSchemaProcessor::getSimpleType("timestamptz");
    EXPECT_EQ(type->getName(), "DateTime64(6, 'UTC')");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeTimestampNs)
{
    auto type = IcebergSchemaProcessor::getSimpleType("timestamp_ns");
    EXPECT_EQ(type->getName(), "DateTime64(9)");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeTimestamptzNs)
{
    auto type = IcebergSchemaProcessor::getSimpleType("timestamptz_ns");
    EXPECT_EQ(type->getName(), "DateTime64(9, 'UTC')");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeString)
{
    auto type = IcebergSchemaProcessor::getSimpleType("string");
    EXPECT_EQ(type->getName(), "String");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeBinary)
{
    auto type = IcebergSchemaProcessor::getSimpleType("binary");
    EXPECT_EQ(type->getName(), "String");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeUuid)
{
    auto type = IcebergSchemaProcessor::getSimpleType("uuid");
    EXPECT_EQ(type->getName(), "UUID");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeFixed)
{
    auto type = IcebergSchemaProcessor::getSimpleType("fixed[16]");
    EXPECT_EQ(type->getName(), "FixedString(16)");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeDecimal)
{
    auto type = IcebergSchemaProcessor::getSimpleType("decimal(10, 2)");
    EXPECT_EQ(type->getName(), "Decimal(10, 2)");
}

TEST(IcebergSchemaProcessor, GetSimpleTypeUnknownThrows)
{
    EXPECT_THROW(IcebergSchemaProcessor::getSimpleType("unknown_type"), DB::Exception);
}

/// Regression test for https://github.com/ClickHouse/ClickHouse/issues/109642
/// The same schema-id can be serialized by different Iceberg writers with different
/// whitespace in parameterized primitive type strings, e.g. the table metadata JSON
/// emits "decimal(20,0)" while the manifest Avro metadata emits "decimal(20, 0)".
/// Both denote the identical type per the Iceberg spec, so re-adding the schema-id
/// must NOT be rejected as a rebinding to a different schema.
TEST(IcebergSchemaProcessor, DecimalTypeWhitespaceIsInsensitive)
{
    auto first = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":"decimal(20,0)"}]})json");
    auto second = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":"decimal(20, 0)"}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_NO_THROW(processor.addIcebergTableSchema(second));
}

/// A genuinely different type bound to the same schema-id must still be rejected.
TEST(IcebergSchemaProcessor, RebindingSchemaIdToDifferentTypeStillRejected)
{
    auto first = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":"decimal(20,0)"}]})json");
    auto second = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":"decimal(20,2)"}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_THROW(processor.addIcebergTableSchema(second), DB::Exception);
}

/// A renamed field bound to the same schema-id must still be rejected (issue #107316).
TEST(IcebergSchemaProcessor, RebindingSchemaIdToRenamedFieldStillRejected)
{
    auto first = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":"long"}]})json");
    auto second = parseSchema(R"json({"schema-id":0,"fields":[{"id":1,"name":"c9","required":false,"type":"long"}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_THROW(processor.addIcebergTableSchema(second), DB::Exception);
}

/// The whitespace-insensitive comparison must reach into list/map wrappers: the nested
/// element/key/value primitive types (here list<decimal>) can also be serialized with
/// different spacing across metadata files.
TEST(IcebergSchemaProcessor, ListElementDecimalWhitespaceIsInsensitive)
{
    auto first = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"list","element-id":2,"element-required":false,"element":"decimal(20,0)"}}]})json");
    auto second = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"list","element-id":2,"element-required":false,"element":"decimal(20, 0)"}}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_NO_THROW(processor.addIcebergTableSchema(second));
}

/// Same for map key/value primitive types (here map<decimal, decimal>).
TEST(IcebergSchemaProcessor, MapKeyValueDecimalWhitespaceIsInsensitive)
{
    auto first = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"map","key-id":2,"key":"decimal(20,0)","value-id":3,"value-required":false,"value":"decimal(10,2)"}}]})json");
    auto second = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"map","key-id":2,"key":"decimal(20, 0)","value-id":3,"value-required":false,"value":"decimal(10, 2)"}}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_NO_THROW(processor.addIcebergTableSchema(second));
}

/// A genuinely different nested type inside a list wrapper must still be rejected.
TEST(IcebergSchemaProcessor, RebindingListElementToDifferentTypeStillRejected)
{
    auto first = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"list","element-id":2,"element-required":false,"element":"decimal(20,0)"}}]})json");
    auto second = parseSchema(
        R"json({"schema-id":0,"fields":[{"id":1,"name":"c0","required":false,"type":{"type":"list","element-id":2,"element-required":false,"element":"decimal(20,2)"}}]})json");
    IcebergSchemaProcessor processor;
    processor.addIcebergTableSchema(first);
    EXPECT_THROW(processor.addIcebergTableSchema(second), DB::Exception);
}
