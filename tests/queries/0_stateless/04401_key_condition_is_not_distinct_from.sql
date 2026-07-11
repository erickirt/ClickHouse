-- Tags: no-replicated-database, no-parallel-replicas
-- no-replicated-database: EXPLAIN output differs for replicated database.
-- no-parallel-replicas: EXPLAIN output differs for parallel replicas.
-- See `src/Storages/MergeTree/KeyCondition.cpp` (atom_map "isNotDistinctFrom",
-- reverseComparisonOperator, tryRewriteIsTrueCondition, tryRewriteInTruthyCondition).

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

-- `X != false` (`notEquals(X, false)`) is truth-equivalent to `X` for a boolean-valued `X`, so it
-- must prune the same as the bare atom across all index families.
SELECT '--- (k = c) != false prunes via primary key ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) != false) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (v = c) != false prunes via minmax skip index ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM mm WHERE (v = 42) != false) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- b != false prunes partitions the same as b = true ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT * FROM part WHERE b != false) WHERE explain ILIKE '%Parts: 1/2%';

-- `X != true` (`notEquals(X, true)`) is NOT truth-equivalent to `X`, so it must NOT be rewritten.
SELECT '--- (k = c) != true does NOT get the IS TRUE pruning ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) != true) WHERE explain ILIKE '%Granules: 1/%';

-- `X IN (<all-true const set>)` is truth-equivalent to `X` for a boolean-valued `X`.
SELECT '--- (k = c) IN (true) prunes via primary key ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) IN (true)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k = c) IN (true, true) prunes via primary key ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) IN (true, true)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (v = c) IN (true) prunes via minmax skip index ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM mm WHERE (v = 42) IN (true)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- b IN (true) prunes partitions the same as b = true ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT * FROM part WHERE b IN (true)) WHERE explain ILIKE '%Parts: 1/2%';

-- `X IN (false)`, `X IN (true, false)`, `X IN (2)` and `X NOT IN (true)` are NOT truth-equivalent to
-- `X`, so they must NOT get the IS TRUE pruning.
SELECT '--- (k = c) IN (false) does NOT get the pruning ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) IN (false)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k = c) IN (true, false) does NOT get the pruning ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) IN (true, false)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- (k = c) NOT IN (true) does NOT get the pruning ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE (k = 42) NOT IN (true)) WHERE explain ILIKE '%Granules: 1/%';

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
-- `!= false` / `IN (truthy)` forms match the bare atom; the non-equivalent forms match their own semantics.
SELECT 'ne_false_eq', count() FROM pk WHERE (k = 42) != false;
SELECT 'ne_true_eq', count() FROM pk WHERE (k = 42) != true;
SELECT 'in_true_eq', count() FROM pk WHERE (k = 42) IN (true);
SELECT 'in_truetrue_eq', count() FROM pk WHERE (k = 42) IN (true, true);
SELECT 'in_false_eq', count() FROM pk WHERE (k = 42) IN (false);
SELECT 'in_truefalse_eq', count() FROM pk WHERE (k = 42) IN (true, false);
SELECT 'notin_true_eq', count() FROM pk WHERE (k = 42) NOT IN (true);
-- non-boolean X: `k IN (true)` means `k = 1`, not "k truthy"; must stay correct.
SELECT 'k_in_true_means_eq_1', count() FROM pk WHERE k IN (true);
-- Partition pruning correctness: IS TRUE / IS NOT DISTINCT FROM / != false / IN (true) match b = true.
SELECT 'part_eq', count() FROM part WHERE b = true;
SELECT 'part_istrue', count() FROM part WHERE b IS TRUE;
SELECT 'part_ndf', count() FROM part WHERE b IS NOT DISTINCT FROM true;
SELECT 'part_ne_false', count() FROM part WHERE b != false;
SELECT 'part_in_true', count() FROM part WHERE b IN (true);

-- The `IN (truthy)` key-condition rewrite must NOT force-build the set during analysis:
-- for a subquery set (`(k = 42) IN (SELECT ...)`) the set is left for execution, so EXPLAIN
-- does not run the subquery. Regression for a server abort where the subquery was executed
-- during key analysis (see 02707_skip_index_with_in). The plan keeps a deferred `CreatingSet`.
SELECT 'explain_in_subquery_not_built', count() > 0
FROM (EXPLAIN SELECT count() FROM pk WHERE (k = 42) IN (SELECT throwIf(1)) SETTINGS use_skip_indexes = 0)
WHERE explain ILIKE '%CreatingSet%';

-- A `LowCardinality` key compared with a `LowCardinality` constant drives a monotonic-function chain
-- (UInt8->Bool `CAST`) in `applyFunction`. Regression for a server abort where the raw
-- `ColumnLowCardinality` reached a wrapper doing `checkAndGetColumn<ColumnUInt8>` (bad cast). The
-- constant comes from a subquery so it is not folded away before key analysis.
SET allow_suspicious_low_cardinality_types = 1;
DROP TABLE IF EXISTS lc_bool;
CREATE TABLE lc_bool (b LowCardinality(Bool)) ENGINE = MergeTree ORDER BY tuple(b) SETTINGS index_granularity = 8, index_granularity_bytes = 0, min_bytes_for_wide_part = 0;
INSERT INTO lc_bool SELECT multiIf(number < 8, false, number < 16, true, NULL) FROM numbers(24);
SELECT 'lc_less', count() FROM lc_bool WHERE toLowCardinality((SELECT false)) < b;
SELECT 'lc_eq', count() FROM lc_bool WHERE toLowCardinality((SELECT false)) = b;
SELECT 'lc_istrue', count() FROM lc_bool WHERE b IS TRUE;
SELECT 'lc_ndf', count() FROM lc_bool WHERE b IS NOT DISTINCT FROM false;
DROP TABLE lc_bool;

DROP TABLE pk;
DROP TABLE pk_null;
DROP TABLE mm;
DROP TABLE part;
