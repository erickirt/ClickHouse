#!/usr/bin/env bash

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

# Table expression modifiers must be part of the hash-table-stats cache key: the same table
# function with and without FINAL sees different row sets (ReplacingMergeTree collapses duplicates
# under FINAL), so the two reads must not share one stats entry. FINAL is serialized out-of-band of
# the table function AST (in the ReadFromTableFunctionStep flags), so this also checks that
# resolveStorages restores it on the shard: if FINAL were dropped there, both queries would
# aggregate 650e3 groups and collide on one entry. The FINAL group count (520e3) must stay above
# the 500e3 lower bound under which getSizeHint does not preallocate at all, which also dictates
# the table size - do not shrink it further.
#
# Each pair below runs the same query twice: the first run populates the hash-table-stats cache,
# the second one (-prealloc) must preallocate from it, which is checked through the
# AggregationPreallocatedElementsInHashTables profile event. The preallocation happens in the
# shard-side (secondary) aggregation, so it is read from the secondary query rows
# (is_initial_query = 0). process_query_plan_packet is enabled in the test server config.
# The pairs are independent, so they run in parallel to keep the test fast on slow
# (debug/sanitizer) builds; only the two runs within a pair are sequential.

run_pair()
{
    local query_id_prefix=$1 name=$2 query=$3
    shift 3
    $CLICKHOUSE_CLIENT "$@" --query_id="${query_id_prefix}_${name}" -q "$query"
    $CLICKHOUSE_CLIENT "$@" --query_id="${query_id_prefix}_${name}-prealloc" -q "$query"
}

settings=(
    --max_threads=1
    --enable_analyzer=1
    --collect_hash_table_stats_during_aggregation=1
    --max_size_to_preallocate_for_aggregation=1000000000000
    --serialize_query_plan=1
    --prefer_localhost_replica=0
)

mod_prefix="${CLICKHOUSE_DATABASE}_04613_mod_$RANDOM$RANDOM"

$CLICKHOUSE_CLIENT -q "
    CREATE TABLE t_04613 (k UInt64, v UInt64) ENGINE = ReplacingMergeTree ORDER BY k;
    SYSTEM STOP MERGES t_04613;
    INSERT INTO t_04613 SELECT number, number FROM numbers(650e3);
    INSERT INTO t_04613 SELECT number, number % 520000 FROM numbers(650e3);
"

final_query="SELECT v FROM cluster('test_shard_localhost', merge(currentDatabase(), '^t_04613$')) FINAL GROUP BY v FORMAT Null"
no_final_query="SELECT v FROM cluster('test_shard_localhost', merge(currentDatabase(), '^t_04613$')) GROUP BY v FORMAT Null"

run_pair "$mod_prefix" final "$final_query" "${settings[@]}" &
run_pair "$mod_prefix" no-final "$no_final_query" "${settings[@]}" &

wait

# The labels happen to sort in the order the reference expects, and unlike event_time the sort is
# stable under the parallel execution above.
$CLICKHOUSE_CLIENT -q "
    SYSTEM FLUSH LOGS query_log;

    SELECT replace(initial_query_id, '${mod_prefix}_', ''), ProfileEvents['AggregationPreallocatedElementsInHashTables']
    FROM system.query_log
    WHERE event_date >= yesterday() AND type = 'QueryFinish'
    AND is_initial_query = 0
    AND startsWith(initial_query_id, '$mod_prefix')
    AND endsWith(initial_query_id, '-prealloc')
    ORDER BY 1;

    DROP TABLE t_04613;
"
