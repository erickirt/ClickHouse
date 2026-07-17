#!/usr/bin/env bash
# Tags: no-fasttest
# - no-fasttest: requires IcebergLocal (USE_AVRO build option)

# Regression test for https://github.com/ClickHouse/ClickHouse/issues/110877
#
# createEmptyMetadataFile initialized "last-column-id" to the number of
# TOP-LEVEL columns, ignoring the nested field ids that tuple/array/map children
# consume. For `(id Int64, t Tuple(a, b))` the field ids are id=1, t=2, t.a=3,
# t.b=4, but "last-column-id" was written as 2. A subsequent ADD COLUMN then
# reused id 3 (already held by t.a), publishing metadata with a duplicate field
# id: the ALTER succeeded but the next SELECT failed with
# `Code: 743 ... Duplicate field id 3 (ICEBERG_SPECIFICATION_VIOLATION)`.
#
# The fix records the max assigned field id (counting nested children) as
# "last-column-id" on initial table creation, and in generateAddColumnMetadata
# assigns nested children of a newly added complex column their own ids so every
# newly added field id is globally unique.
#
# Runs in `clickhouse local` (parallel-safe: isolated work dir, no shared
# server state) so no `no-parallel` tag is needed.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

WORK_DIR="${CLICKHOUSE_TMP}/iceberg_add_column_nested_110877_${CLICKHOUSE_TEST_UNIQUE_NAME}"
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT

# last-column-id of the latest on-disk metadata version.
last_column_id() {
    local table_dir="$1"
    local latest
    latest=$(find "${table_dir}/metadata" -name 'v*.metadata.json' | sort -V | tail -1)
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['last-column-id'])" "${latest}"
}

# The initial schema has a nested tuple, so nested children consume field ids
# past the top-level column count. ADD COLUMN of a scalar (c), of a complex
# nested column (s), and of another scalar (d) must all assign globally-unique
# ids. A SELECT after each ALTER re-reads the published metadata, so a duplicate
# field id surfaces immediately. The SELECT after two consecutive ALTERs (s then
# d) is what exercises the nested half of the fix: if generateAddColumnMetadata
# regressed to storing `new_field_id` instead of the max nested child id, `d`
# would reuse a child id of `s` and that SELECT would fail with a duplicate id.
TABLE_DIR="${WORK_DIR}/t0"
mkdir -p "${TABLE_DIR}"
${CLICKHOUSE_LOCAL} \
    --allow_insert_into_iceberg=1 \
    --enable_nullable_tuple_type=1 \
    --multiquery -q "
CREATE TABLE t0 (id Int64, t Tuple(a Int64, b Int64)) ENGINE = IcebergLocal('${TABLE_DIR}/');
INSERT INTO t0 VALUES (1, (10, 20));
ALTER TABLE t0 ADD COLUMN c Nullable(Int64);
SELECT id, t FROM t0 ORDER BY id;
ALTER TABLE t0 ADD COLUMN s Nullable(Tuple(x Int64, y Int64));
SELECT id, t FROM t0 ORDER BY id;
ALTER TABLE t0 ADD COLUMN d Nullable(Int64);
INSERT INTO t0 (id, t) VALUES (2, (30, 40));
SELECT id, t FROM t0 ORDER BY id;
" -- --user_files_path="${WORK_DIR}"
# ids: id=1 t=2 (t.a=3 t.b=4) c=5 s=6 (s.x=7 s.y=8) d=9 -> last-column-id=9.
echo "last-column-id=$(last_column_id "${TABLE_DIR}")"
