-- Tags: no-parallel-replicas
-- Regression test for https://github.com/ClickHouse/ClickHouse/issues/110795
--
-- A bare non-UInt8 column in WHERE is an implicit-boolean filter (`a != 0`).
-- The projection read path (optimize_use_projections = 1) and the parallel-replicas
-- read path used to reject it with ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER (Code 59).
-- All three paths must now agree AND each path must actually be taken: the assertions
-- below fail if the projection is silently not used or parallel replicas is not engaged,
-- so a fallback to a plain local read cannot leave the regression uncovered.

DROP TABLE IF EXISTS t_04371;

CREATE TABLE t_04371 (a UInt32, b UInt32, PROJECTION p (SELECT a, count() GROUP BY a))
ENGINE = MergeTree ORDER BY b;
INSERT INTO t_04371 SELECT number, number % 5 FROM numbers(100);

SELECT '-- normal path';
SELECT a, count() FROM t_04371 WHERE a GROUP BY a ORDER BY a LIMIT 5
SETTINGS optimize_use_projections = 0, enable_parallel_replicas = 0;

-- projection path: force_optimize_projection = 1 throws PROJECTION_NOT_USED if the
-- projection is not chosen, so this deterministically asserts the projection path is taken.
SELECT '-- projection path (projection actually used)';
SELECT a, count() FROM t_04371 WHERE a GROUP BY a ORDER BY a LIMIT 5
SETTINGS optimize_use_projections = 1, force_optimize_projection = 1, enable_parallel_replicas = 0;

SET automatic_parallel_replicas_mode = 0;
SET parallel_replicas_only_with_analyzer = 0;  -- necessary for CI run with disabled analyzer
SET enable_parallel_replicas = 1, max_parallel_replicas = 3,
    parallel_replicas_for_non_replicated_merge_tree = 1,
    parallel_replicas_min_number_of_rows_per_replica = 0,
    cluster_for_parallel_replicas = 'test_cluster_one_shard_three_replicas_localhost',
    optimize_use_projections = 0;

SELECT '-- parallel replicas, local plan';
SELECT a, count() FROM t_04371 WHERE a GROUP BY a ORDER BY a LIMIT 5
SETTINGS parallel_replicas_local_plan = 1, log_comment = '04371_pr_local';

SELECT '-- parallel replicas, remote plan';
SELECT a, count() FROM t_04371 WHERE a GROUP BY a ORDER BY a LIMIT 5
SETTINGS parallel_replicas_local_plan = 0, log_comment = '04371_pr_remote';

SYSTEM FLUSH LOGS query_log;

SELECT '-- parallel replicas engaged (both plans)';
SELECT log_comment, ProfileEvents['ParallelReplicasUsedCount'] > 0
FROM system.query_log
WHERE current_database = currentDatabase()
  AND log_comment IN ('04371_pr_local', '04371_pr_remote')
  AND type = 'QueryFinish' AND initial_query_id = query_id
ORDER BY log_comment
SETTINGS enable_parallel_replicas = 0;

DROP TABLE t_04371;
