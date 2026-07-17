-- Tags: no-parallel-replicas
-- Regression test for https://github.com/ClickHouse/ClickHouse/issues/110795
--
-- A bare non-UInt8 column in WHERE is an implicit-boolean filter (`a != 0`).
-- The normal read path coerces it, but the projection read path
-- (optimize_use_projections = 1) and the parallel-replicas read path used to
-- reject it with ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER (Code 59). All three paths
-- must now agree.

DROP TABLE IF EXISTS t_04371;

CREATE TABLE t_04371 (a UInt32, b UInt32, PROJECTION p (SELECT b, count() GROUP BY b))
ENGINE = MergeTree ORDER BY a;
INSERT INTO t_04371 SELECT number, number % 5 FROM numbers(100);

SELECT '-- normal path';
SELECT b, count() FROM t_04371 WHERE a GROUP BY b ORDER BY b
SETTINGS optimize_use_projections = 0, enable_parallel_replicas = 0;

SELECT '-- projection path';
SELECT b, count() FROM t_04371 WHERE a GROUP BY b ORDER BY b
SETTINGS optimize_use_projections = 1, enable_parallel_replicas = 0;

SELECT '-- parallel replicas, local plan';
SELECT b, count() FROM t_04371 WHERE a GROUP BY b ORDER BY b
SETTINGS enable_parallel_replicas = 1, max_parallel_replicas = 3,
         parallel_replicas_for_non_replicated_merge_tree = 1,
         parallel_replicas_min_number_of_rows_per_replica = 0,
         cluster_for_parallel_replicas = 'test_cluster_one_shard_three_replicas_localhost',
         parallel_replicas_local_plan = 1;

SELECT '-- parallel replicas, remote plan';
SELECT b, count() FROM t_04371 WHERE a GROUP BY b ORDER BY b
SETTINGS enable_parallel_replicas = 1, max_parallel_replicas = 3,
         parallel_replicas_for_non_replicated_merge_tree = 1,
         parallel_replicas_min_number_of_rows_per_replica = 0,
         cluster_for_parallel_replicas = 'test_cluster_one_shard_three_replicas_localhost',
         parallel_replicas_local_plan = 0;

DROP TABLE t_04371;
