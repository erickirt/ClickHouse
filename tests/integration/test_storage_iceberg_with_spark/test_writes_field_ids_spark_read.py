import pytest

from helpers.iceberg_utils import (
    create_iceberg_table,
    get_uuid_str,
    default_download_directory,
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
