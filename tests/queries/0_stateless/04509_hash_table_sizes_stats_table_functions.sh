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
