import glob

import pytest

from helpers.iceberg_utils import (
    create_iceberg_table,
    get_uuid_str,
    default_download_directory,
    default_upload_directory,
)


# Regression test for https://github.com/ClickHouse/ClickHouse/issues/109988.
# ClickHouse-written Avro/ORC Iceberg data files must embed Iceberg field IDs
# (Avro field-id, ORC iceberg.id) and ORC must store String columns as ORC
# string. Without them, iceberg-java falls back to name matching: after a
# RENAME COLUMN, Spark silently returns NULL for ClickHouse-written rows
# (Avro), or fails to read the table at all (ORC binary vs string). With the
# field IDs present, Spark projects by ID and reads the renamed column
# correctly - which is what this test asserts.
@pytest.mark.parametrize("format", ["Avro", "ORC"])
def test_writes_field_ids_spark_read_after_rename(
    started_cluster_iceberg_with_spark, format
):
    instance = started_cluster_iceberg_with_spark.instances["node1"]
    spark = started_cluster_iceberg_with_spark.spark_session
    storage_type = "local"
    TABLE_NAME = "test_field_ids_spark_read_" + format + "_" + get_uuid_str()
    local_path = f"/var/lib/clickhouse/user_files/iceberg_data/default/{TABLE_NAME}"

    create_iceberg_table(
        storage_type,
        instance,
        TABLE_NAME,
        started_cluster_iceberg_with_spark,
        "(id Int32, label String, score Float64)",
        2,
        format=format,
    )

    instance.query(
        f"INSERT INTO {TABLE_NAME} VALUES (1, 'alice', 1.5), (2, 'bob', 2.5), (3, 'charlie', 3.5)",
        settings={"allow_insert_into_iceberg": 1},
    )
    assert (
        instance.query(f"SELECT * FROM {TABLE_NAME} ORDER BY id")
        == "1\talice\t1.5\n2\tbob\t2.5\n3\tcharlie\t3.5\n"
    )

    # Rename the String column. Spark must still read the ClickHouse-written
    # values for the renamed column by projecting via the file field IDs.
    instance.query(
        f"ALTER TABLE {TABLE_NAME} RENAME COLUMN label TO name",
        settings={"allow_insert_into_iceberg": 1},
    )
    assert (
        instance.query(f"SELECT id, name, score FROM {TABLE_NAME} ORDER BY id")
        == "1\talice\t1.5\n2\tbob\t2.5\n3\tcharlie\t3.5\n"
    )

    default_download_directory(
        started_cluster_iceberg_with_spark,
        storage_type,
        f"{local_path}/",
        f"{local_path}/",
    )

    rows = spark.read.format("iceberg").load(local_path).orderBy("id").collect()

    assert len(rows) == 3
    # The renamed column must carry the ClickHouse-written values, not NULL.
    assert [(r.id, r.name, r.score) for r in rows] == [
        (1, "alice", 1.5),
        (2, "bob", 2.5),
        (3, "charlie", 3.5),
    ]


def _avro_field_ids(node_schema):
    """Collect every {path: field-id} pair from an avro record schema tree,
    descending through array/map wrappers exactly like the writer does."""
    import avro.schema

    result = {}

    def walk(schema, path):
        if isinstance(schema, avro.schema.RecordSchema):
            for field in schema.fields:
                child_path = f"{path}.{field.name}" if path else field.name
                fid = field.other_props.get("field-id")
                if fid is not None:
                    result[child_path] = fid
                walk(field.type, child_path)
        elif isinstance(schema, avro.schema.UnionSchema):
            for member in schema.schemas:
                walk(member, path)
        elif isinstance(schema, avro.schema.ArraySchema):
            walk(schema.items, f"{path}.element")
        elif isinstance(schema, avro.schema.MapSchema):
            walk(schema.values, f"{path}.value")

    walk(node_schema, "")
    return result


# Regression for the wrapped-nested Avro case (bot review on #109994): the Avro
# field-id writer must descend through array / union wrappers to reach a record
# nested inside e.g. Array(Tuple(...)). The previous writer stopped at the first
# non-record node, so a struct wrapped in an array received no nested field-ids
# and iceberg-java would fall back to name matching for those subfields. This
# test writes such a column from ClickHouse and asserts the nested subfield IDs
# are present in the Avro data file (and that Spark can read the file back).
def test_writes_field_ids_nested_avro(started_cluster_iceberg_with_spark):
    import avro.datafile
    import avro.io

    instance = started_cluster_iceberg_with_spark.instances["node1"]
    spark = started_cluster_iceberg_with_spark.spark_session
    storage_type = "local"
    TABLE_NAME = "test_field_ids_nested_avro_" + get_uuid_str()
    local_path = f"/var/lib/clickhouse/user_files/iceberg_data/default/{TABLE_NAME}"

    create_iceberg_table(
        storage_type,
        instance,
        TABLE_NAME,
        started_cluster_iceberg_with_spark,
        "(id Int32, info Array(Tuple(a Int32, b String)))",
        2,
        format="Avro",
    )

    instance.query(
        f"INSERT INTO {TABLE_NAME} VALUES (1, [(10, 'x'), (11, 'y')]), (2, [(20, 'z')])",
        settings={"allow_insert_into_iceberg": 1},
    )
    assert (
        instance.query(f"SELECT * FROM {TABLE_NAME} ORDER BY id")
        == "1\t[(10,'x'),(11,'y')]\n2\t[(20,'z')]\n"
    )

    default_download_directory(
        started_cluster_iceberg_with_spark,
        storage_type,
        f"{local_path}/",
        f"{local_path}/",
    )

    data_files = glob.glob(f"{local_path}/data/*.avro")
    assert data_files, "no Avro data file was written"

    with open(data_files[0], "rb") as f:
        reader = avro.datafile.DataFileReader(f, avro.io.DatumReader())
        writer_schema = reader.datum_reader.writers_schema
        reader.close()

    field_ids = _avro_field_ids(writer_schema)
    # The nested struct subfields must carry field-ids reached through the array
    # wrapper. Without the wrapper recursion these keys would be absent.
    assert "info.element.a" in field_ids, field_ids
    assert "info.element.b" in field_ids, field_ids
    assert field_ids["info.element.a"] != field_ids["info.element.b"]

    rows = spark.read.format("iceberg").load(local_path).orderBy("id").collect()
    assert [(r.id, [(e.a, e.b) for e in r.info]) for r in rows] == [
        (1, [(10, "x"), (11, "y")]),
        (2, [(20, "z")]),
    ]


# Regression for the ORC rewrite path (bot review on #109994): the mapper-driven
# String -> ORC `string` rule must also apply when ClickHouse-written data files
# are rewritten by compaction (OPTIMIZE), not only on the initial write. The
# compaction writer is given an Iceberg column mapper, so it must force ORC
# `string` for String columns regardless of output_format_orc_string_as_string
# (which defaults to true). We drive the OPTIMIZE with that setting explicitly
# disabled; if the rewrite ignored the mapper it would emit ORC binary, and
# reading the renamed String column back (via field IDs) would break.
#
# Compaction only rewrites data files that have positional deletes applied, so
# Spark issues a merge-on-read DELETE against the ClickHouse-written ORC data
# before OPTIMIZE rewrites those files.
def test_writes_field_ids_orc_compaction_rewrite(started_cluster_iceberg_with_spark):
    instance = started_cluster_iceberg_with_spark.instances["node1"]
    spark = started_cluster_iceberg_with_spark.spark_session
    storage_type = "local"
    TABLE_NAME = "test_field_ids_orc_compaction_" + get_uuid_str()
    local_path = f"/var/lib/clickhouse/user_files/iceberg_data/default/{TABLE_NAME}"

    create_iceberg_table(
        storage_type,
        instance,
        TABLE_NAME,
        started_cluster_iceberg_with_spark,
        "(id Int32, label String)",
        2,
        format="ORC",
        use_version_hint=True,
    )

    instance.query(
        f"INSERT INTO {TABLE_NAME} VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie'), (4, 'dave')",
        settings={"allow_insert_into_iceberg": 1},
    )

    # Bring the ClickHouse-written ORC data + version-hint out to where Spark
    # reads (container -> host), let Spark add a positional delete (merge-on-read)
    # via the hadoop catalog, then push the delete file back (host -> container).
    default_download_directory(
        started_cluster_iceberg_with_spark,
        storage_type,
        f"{local_path}/",
        f"{local_path}/",
    )
    spark_table = f"spark_catalog.default.{TABLE_NAME}"
    spark.sql(f"REFRESH TABLE {spark_table}")
    spark.sql(f"DELETE FROM {spark_table} WHERE id = 2")
    default_upload_directory(
        started_cluster_iceberg_with_spark,
        storage_type,
        f"/iceberg_data/default/{TABLE_NAME}/",
        f"/iceberg_data/default/{TABLE_NAME}/",
    )

    assert (
        instance.query(f"SELECT id, label FROM {TABLE_NAME} ORDER BY id")
        == "1\talice\n3\tcharlie\n4\tdave\n"
    )

    # Compaction rewrites the ClickHouse-written ORC data files (applying the
    # delete). The rewrite runs with output_format_orc_string_as_string=0 to
    # prove the String -> ORC string forcing is mapper-driven, not setting-driven.
    instance.query(
        f"OPTIMIZE TABLE {TABLE_NAME}",
        settings={
            "allow_experimental_iceberg_compaction": 1,
            "output_format_orc_string_as_string": 0,
        },
    )
    assert (
        instance.query(f"SELECT id, label FROM {TABLE_NAME} ORDER BY id")
        == "1\talice\n3\tcharlie\n4\tdave\n"
    )

    # Rename the String column so a correct read depends on file field IDs, then
    # let Spark read the compaction-rewritten ORC file.
    instance.query(
        f"ALTER TABLE {TABLE_NAME} RENAME COLUMN label TO name",
        settings={"allow_insert_into_iceberg": 1},
    )

    default_download_directory(
        started_cluster_iceberg_with_spark,
        storage_type,
        f"{local_path}/",
        f"{local_path}/",
    )

    rows = spark.read.format("iceberg").load(local_path).orderBy("id").collect()
    assert [(r.id, r.name) for r in rows] == [
        (1, "alice"),
        (3, "charlie"),
        (4, "dave"),
    ]
