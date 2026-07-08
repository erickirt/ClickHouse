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
