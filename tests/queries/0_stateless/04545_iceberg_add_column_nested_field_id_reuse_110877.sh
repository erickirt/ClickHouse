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
# "last-column-id", both on initial table creation and when ADD COLUMN adds a
# complex column, so every newly added field id is globally unique.
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

TABLE_DIR="${WORK_DIR}/t0"
mkdir -p "${TABLE_DIR}"

# Initial schema has a nested tuple, so nested children consume field ids past
# the top-level column count. ADD COLUMN of a scalar and of a complex (nested)
# column must both assign globally-unique ids; the following SELECT reads the
# table back, which fails if any duplicate field id was published.
${CLICKHOUSE_LOCAL} \
    --allow_insert_into_iceberg=1 \
    --enable_nullable_tuple_type=1 \
    --multiquery -q "
CREATE TABLE t0 (id Int64, t Tuple(a Int64, b Int64)) ENGINE = IcebergLocal('${TABLE_DIR}/');
INSERT INTO t0 VALUES (1, (10, 20));
ALTER TABLE t0 ADD COLUMN c Nullable(Int64);
ALTER TABLE t0 ADD COLUMN s Nullable(Tuple(x Int64, y Int64));
INSERT INTO t0 (id, t) VALUES (2, (30, 40));
SELECT id, t FROM t0 ORDER BY id;
" -- --user_files_path="${WORK_DIR}"
