-- Tags: no-replicated-database, no-parallel-replicas
-- no-replicated-database: EXPLAIN output differs for replicated database.
-- no-parallel-replicas: EXPLAIN output differs for parallel replicas.
-- See `src/Storages/MergeTree/KeyCondition.cpp` (atom_map "isNotDistinctFrom",
-- reverseComparisonOperator, tryRewriteIsTrueCondition).

SET use_query_condition_cache = 0;
SET use_skip_indexes_on_data_read = 0;

DROP TABLE IF EXISTS pk;
DROP TABLE IF EXISTS pk_null;
DROP TABLE IF EXISTS mm;
DROP TABLE IF EXISTS part;

CREATE TABLE pk (k UInt32) ENGINE = MergeTree ORDER BY k
    SETTINGS index_granularity = 8192, add_minmax_index_for_numeric_columns = 0;
INSERT INTO pk SELECT number FROM numbers(100000);

CREATE TABLE pk_null (k Nullable(UInt32)) ENGINE = MergeTree ORDER BY k
    SETTINGS index_granularity = 8192, allow_nullable_key = 1, add_minmax_index_for_numeric_columns = 0;
INSERT INTO pk_null SELECT number FROM numbers(100000);
INSERT INTO pk_null SELECT NULL FROM numbers(5000);

CREATE TABLE mm (id UInt32, v UInt32, INDEX v_idx v TYPE minmax GRANULARITY 1) ENGINE = MergeTree ORDER BY id
    SETTINGS index_granularity = 1024, add_minmax_index_for_numeric_columns = 0;
INSERT INTO mm SELECT number, number FROM numbers(100000);

-- Partition pruning uses a separate KeyCondition path (PartitionPruner over the
-- partition value / minmax), not the primary-key granule path. The same rewrites
-- must apply there too.
CREATE TABLE part (b Bool, id UInt8) ENGINE = MergeTree PARTITION BY b ORDER BY id;
INSERT INTO part VALUES (false, 0), (false, 1), (true, 2), (true, 3);

SELECT '--- IS NOT DISTINCT FROM prunes via primary key (non-Nullable key) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE k IS NOT DISTINCT FROM 42) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k = c) IS TRUE prunes via primary key (non-Nullable key) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- IS NOT DISTINCT FROM prunes via primary key (Nullable key) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE k IS NOT DISTINCT FROM 42) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k = c) IS TRUE prunes via primary key (Nullable key) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE (k = 42) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- const on the left side prunes too ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE 42 IS NOT DISTINCT FROM k) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k < c) IS TRUE prunes an ordered condition ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k < 42) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- IS NOT DISTINCT FROM prunes via minmax skip index ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM mm WHERE v IS NOT DISTINCT FROM 42) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (v = c) IS TRUE prunes via minmax skip index ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM mm WHERE (v = 42) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- b = true prunes partitions (baseline) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT * FROM part WHERE b = true) WHERE explain ILIKE '%Parts: 1/2%';

SELECT '--- b IS TRUE prunes partitions the same as b = true ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT * FROM part WHERE b IS TRUE) WHERE explain ILIKE '%Parts: 1/2%';

SELECT '--- b IS NOT DISTINCT FROM true prunes partitions the same as b = true ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT * FROM part WHERE b IS NOT DISTINCT FROM true) WHERE explain ILIKE '%Parts: 1/2%';

SELECT '--- IS NOT DISTINCT FROM NULL must NOT reuse the "=" range (means IS NULL) ---';
-- No "Granules: 1/" pruning; correctness below proves it returns the NULL rows.
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE k IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- correctness is preserved across all forms ---';
SELECT 'ndf_nonnull', count() FROM pk WHERE k IS NOT DISTINCT FROM 42;
SELECT 'eq_nonnull', count() FROM pk WHERE k = 42;
SELECT 'istrue_eq', count() FROM pk WHERE (k = 42) IS TRUE;
SELECT 'istrue_lt', count() FROM pk WHERE (k < 42) IS TRUE;
SELECT 'ndf_nullable', count() FROM pk_null WHERE k IS NOT DISTINCT FROM 42;
SELECT 'ndf_null_is_null', count() FROM pk_null WHERE k IS NOT DISTINCT FROM NULL;
SELECT 'is_null', count() FROM pk_null WHERE k IS NULL;
-- non-boolean X: (k) IS TRUE means k = 1, NOT "k truthy"; must stay correct.
SELECT 'k_istrue_means_eq_1', count() FROM pk WHERE k IS TRUE;
SELECT 'kplus1_istrue_means_eq_1', count() FROM pk WHERE (k + 1) IS TRUE;
-- IS FALSE must not be rewritten to the IS TRUE path.
SELECT 'isfalse', count() FROM pk WHERE (k = 42) IS FALSE;
-- Partition pruning correctness: IS TRUE / IS NOT DISTINCT FROM match b = true.
SELECT 'part_eq', count() FROM part WHERE b = true;
SELECT 'part_istrue', count() FROM part WHERE b IS TRUE;
SELECT 'part_ndf', count() FROM part WHERE b IS NOT DISTINCT FROM true;

DROP TABLE pk;
DROP TABLE pk_null;
DROP TABLE mm;
DROP TABLE part;
