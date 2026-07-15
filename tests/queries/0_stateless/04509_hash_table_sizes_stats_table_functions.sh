#!/usr/bin/env bash

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

settings=(
    --max_threads=1
    --enable_analyzer=1
    --collect_hash_table_stats_during_aggregation=1
    --max_size_to_preallocate_for_aggregation=1000000000000
)

big_query="SELECT number AS k FROM numbers(1e6) GROUP BY k FORMAT Null"
small_query="SELECT number AS k FROM numbers(800e3) GROUP BY k FORMAT Null"

query_id_prefix="${CLICKHOUSE_DATABASE}_04509_$RANDOM$RANDOM"

$CLICKHOUSE_CLIENT "${settings[@]}" --query_id="${query_id_prefix}_big" -q "$big_query"
$CLICKHOUSE_CLIENT "${settings[@]}" --query_id="${query_id_prefix}_big-prealloc" -q "$big_query"
$CLICKHOUSE_CLIENT "${settings[@]}" --query_id="${query_id_prefix}_small" -q "$small_query"
$CLICKHOUSE_CLIENT "${settings[@]}" --query_id="${query_id_prefix}_small-prealloc" -q "$small_query"

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS query_log"

$CLICKHOUSE_CLIENT -q "
    SELECT replace(query_id, '${query_id_prefix}_', ''), ProfileEvents['AggregationPreallocatedElementsInHashTables']
    FROM system.query_log
    WHERE event_date >= yesterday() AND type = 'QueryFinish'
    AND current_database = currentDatabase()
    AND startsWith(query_id, '$query_id_prefix')
    AND endsWith(query_id, '-prealloc')
    ORDER BY event_time_microseconds
"

# The same, but through a serialized query plan (distributed execution): the read is reconstructed
# on the shard by resolveStorages / ReadFromTableFunctionStep, which must also carry the table
# function subtree so numbers(1e6) and numbers(800e3) do not share one stats entry. The
# preallocation happens in the shard-side (secondary) aggregation, so it is read from the secondary
# query rows (is_initial_query = 0). process_query_plan_packet is enabled in the test server config.
dist_settings=(
    --max_threads=1
    --enable_analyzer=1
    --collect_hash_table_stats_during_aggregation=1
    --max_size_to_preallocate_for_aggregation=1000000000000
    --serialize_query_plan=1
    --prefer_localhost_replica=0
)

dist_big_query="SELECT number AS k FROM cluster('test_shard_localhost', numbers(1e6)) GROUP BY k FORMAT Null"
dist_small_query="SELECT number AS k FROM cluster('test_shard_localhost', numbers(800e3)) GROUP BY k FORMAT Null"

$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${query_id_prefix}_dist-big" -q "$dist_big_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${query_id_prefix}_dist-big-prealloc" -q "$dist_big_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${query_id_prefix}_dist-small" -q "$dist_small_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${query_id_prefix}_dist-small-prealloc" -q "$dist_small_query"

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS query_log"

$CLICKHOUSE_CLIENT -q "
    SELECT replace(initial_query_id, '${query_id_prefix}_', ''), ProfileEvents['AggregationPreallocatedElementsInHashTables']
    FROM system.query_log
    WHERE event_date >= yesterday() AND type = 'QueryFinish'
    AND is_initial_query = 0
    AND startsWith(initial_query_id, '$query_id_prefix')
    AND endsWith(initial_query_id, '-prealloc')
    ORDER BY event_time_microseconds
"

# Table expression modifiers must be part of the key as well: the same table function with and
# without FINAL sees different row sets (ReplacingMergeTree collapses duplicates under FINAL), so
# the two reads must not share one stats entry. FINAL is serialized out-of-band of the table
# function AST (in the ReadFromTableFunctionStep flags), so this also checks that resolveStorages
# restores it on the shard: if FINAL were dropped there, both queries would aggregate 1e6 groups
# and collide on one entry. The FINAL group count (600e3) must stay above the 500e3 lower bound
# under which getSizeHint does not preallocate at all.
$CLICKHOUSE_CLIENT -q "
    CREATE TABLE t_04509 (k UInt64, v UInt64) ENGINE = ReplacingMergeTree ORDER BY k;
    SYSTEM STOP MERGES t_04509;
    INSERT INTO t_04509 SELECT number, number FROM numbers(1e6);
    INSERT INTO t_04509 SELECT number, number % 600000 FROM numbers(1e6);
"

mod_query_id_prefix="${CLICKHOUSE_DATABASE}_04509_mod_$RANDOM$RANDOM"

final_query="SELECT v FROM cluster('test_shard_localhost', merge(currentDatabase(), '^t_04509$')) FINAL GROUP BY v FORMAT Null"
no_final_query="SELECT v FROM cluster('test_shard_localhost', merge(currentDatabase(), '^t_04509$')) GROUP BY v FORMAT Null"

$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${mod_query_id_prefix}_final" -q "$final_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${mod_query_id_prefix}_final-prealloc" -q "$final_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${mod_query_id_prefix}_no-final" -q "$no_final_query"
$CLICKHOUSE_CLIENT "${dist_settings[@]}" --query_id="${mod_query_id_prefix}_no-final-prealloc" -q "$no_final_query"

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS query_log"

$CLICKHOUSE_CLIENT -q "
    SELECT replace(initial_query_id, '${mod_query_id_prefix}_', ''), ProfileEvents['AggregationPreallocatedElementsInHashTables']
    FROM system.query_log
    WHERE event_date >= yesterday() AND type = 'QueryFinish'
    AND is_initial_query = 0
    AND startsWith(initial_query_id, '$mod_query_id_prefix')
    AND endsWith(initial_query_id, '-prealloc')
    ORDER BY event_time_microseconds
"

$CLICKHOUSE_CLIENT -q "DROP TABLE t_04509"
