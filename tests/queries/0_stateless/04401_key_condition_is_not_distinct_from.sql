-- Tags: no-replicated-database, no-parallel-replicas, no-random-merge-tree-settings
-- no-replicated-database: EXPLAIN output differs for replicated database.
-- no-parallel-replicas: EXPLAIN output differs for parallel replicas.
-- no-random-merge-tree-settings: the test asserts exact `Granules: N/M` counts, which depend on the
--   data layout; randomized MergeTree settings (index_granularity, use_const_adaptive_granularity, ...)
--   change the granule boundaries and flip the counts.
-- See `src/Storages/MergeTree/KeyCondition.cpp` (atom_map "isNotDistinctFrom",
-- reverseComparisonOperator, tryRewriteIsTrueCondition, tryRewriteInTruthyCondition).

SET use_query_condition_cache = 0;
SET use_skip_indexes_on_data_read = 0;
-- The implicit `_exact_count_projection` hides the ReadFromMergeTree step (and its Granules line)
-- from `EXPLAIN indexes = 1 SELECT count() ...`; disable it so the granule counts are visible.
SET optimize_use_implicit_projections = 0;

DROP TABLE IF EXISTS pk;
DROP TABLE IF EXISTS pk_null;
DROP TABLE IF EXISTS mm;
DROP TABLE IF EXISTS part;
DROP TABLE IF EXISTS spk;

-- Pin index_granularity_bytes = 0 (non-adaptive) on every table whose exact `Granules: N/M` count is
-- asserted below, so granule boundaries depend only on the row-count `index_granularity` and not on the
-- CI-randomized byte cap (a small cap makes tiny granules, splitting the matched key range across more
-- than one granule and flipping the count). min_bytes_for_wide_part = 0 forces Wide so the non-adaptive
-- granularity does not log the "can't create parts with adaptive granularity" warning (Fast test fails
-- on any stderr).
CREATE TABLE pk (k UInt32) ENGINE = MergeTree ORDER BY k
    SETTINGS index_granularity = 8192, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, add_minmax_index_for_numeric_columns = 0;
INSERT INTO pk SELECT number FROM numbers(100000);

CREATE TABLE pk_null (k Nullable(UInt32)) ENGINE = MergeTree ORDER BY k
    SETTINGS index_granularity = 8192, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, allow_nullable_key = 1, add_minmax_index_for_numeric_columns = 0;
INSERT INTO pk_null SELECT number FROM numbers(100000);
INSERT INTO pk_null SELECT NULL FROM numbers(5000);
-- The NULL rows arrive in a second part that sorts last; whether a background merge fires mid-test is
-- nondeterministic and flips whether the NULLs share a granule boundary with the non-NULL tail (1 vs 2
-- granules for `k IS NULL` / `<=> NULL`). Merge to a single part up front so the count is stable.
OPTIMIZE TABLE pk_null FINAL;

CREATE TABLE mm (id UInt32, v UInt32, INDEX v_idx v TYPE minmax GRANULARITY 1) ENGINE = MergeTree ORDER BY id
    SETTINGS index_granularity = 1024, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, add_minmax_index_for_numeric_columns = 0;
INSERT INTO mm SELECT number, number FROM numbers(100000);

-- Partition pruning uses a separate KeyCondition path (PartitionPruner over the
-- partition value / minmax), not the primary-key granule path. The same rewrites
-- must apply there too.
CREATE TABLE part (b Bool, id UInt8) ENGINE = MergeTree PARTITION BY b ORDER BY id;
INSERT INTO part VALUES (false, 0), (false, 1), (true, 2), (true, 3);

-- String primary key: the boolean-wrapper peel must reach the `startsWith` atom (a prunable boolean
-- atom that is NOT a comparison), not just `equals`/`less`.
CREATE TABLE spk (s String) ENGINE = MergeTree ORDER BY s
    SETTINGS index_granularity = 8192, index_granularity_bytes = 0, min_bytes_for_wide_part = 0, add_minmax_index_for_numeric_columns = 0;
INSERT INTO spk SELECT toString(number) FROM numbers(100000);

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

-- `key <=> NULL` means "key IS NULL", so it reuses the existing `isNull` atom and prunes the Nullable
-- index to the NULL granule exactly (NOT the "=" range). It must prune the same as bare `key IS NULL`.
SELECT '--- IS NOT DISTINCT FROM NULL prunes to the NULL granule like IS NULL ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE k IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- NULL IS NOT DISTINCT FROM key prunes too (const on the left) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE NULL IS NOT DISTINCT FROM k) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- bare IS NULL prunes to the NULL granule (reference for the above) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE k IS NULL) WHERE explain ILIKE '%Granules: 1/%';

-- A NULL-erasing wrapper (`ifNull`, `coalesce`, `assumeNotNull`) around the key must NOT be routed to
-- the `isNull` atom: `ifNull(k, 0) IS NOT DISTINCT FROM NULL` is always false (`ifNull(k, 0)` is never
-- NULL), but reusing `isNull(k)` would narrow the index to the NULL granule and mark it exact-true,
-- so exact-count / implicit-projection paths would count those rows for an always-false predicate.
-- It must fall back to a full scan (no `Granules: 1/` prune), under coalesce-rewrite on AND off.
SELECT '--- ifNull(k, 0) IS NOT DISTINCT FROM NULL does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE ifNull(k, 0) IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';
SELECT '--- ifNull(k, 0) IS NOT DISTINCT FROM NULL does NOT prune with coalesce rewrite off (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE ifNull(k, 0) IS NOT DISTINCT FROM NULL SETTINGS allow_key_condition_coalesce_rewrite = 0) WHERE explain ILIKE '%Granules: 1/%';
SELECT '--- coalesce(k, 0) IS NOT DISTINCT FROM NULL does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE coalesce(k, 0) IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';
SELECT '--- assumeNotNull(k) IS NOT DISTINCT FROM NULL does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE assumeNotNull(k) IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';
SELECT '--- bare isNull(ifNull(k, 0)) does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE isNull(ifNull(k, 0))) WHERE explain ILIKE '%Granules: 1/%';

-- The NULL-preservation guard is SEMANTIC (result type stays Nullable), not a name allowlist. A `CAST`
-- to a non-Nullable type erases NULL just like `ifNull`: `CAST(k, 'UInt32') IS NOT DISTINCT FROM NULL`
-- is always false, but reusing `isNull(k)` would prune to the NULL granule and mark it exact-true, so
-- exact-count paths would count rows for an always-false predicate. It must NOT prune.
SELECT '--- CAST(k, non-Nullable) IS NOT DISTINCT FROM NULL does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE CAST(k, 'UInt32') IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';
SELECT '--- bare isNull(CAST(k, non-Nullable)) does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE isNull(CAST(k, 'UInt32'))) WHERE explain ILIKE '%Granules: 1/%';
-- A NULL-PRESERVING conversion (`toUInt32(Nullable(UInt32))` stays `Nullable(UInt32)`) must STILL prune
-- to the NULL granule, exactly like bare `k IS NULL`: it maps NULL to NULL, so `isNull` reuse is sound.
SELECT '--- toUInt32(k) (NULL-preserving) IS NOT DISTINCT FROM NULL DOES prune to the NULL granule ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE toUInt32(k) IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';
-- A nested chain erases NULL if ANY step does: `toUInt32(ifNull(k, 0))` -> the inner ifNull erases.
SELECT '--- toUInt32(ifNull(k, 0)) IS NOT DISTINCT FROM NULL does NOT prune to the NULL granule (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk_null WHERE toUInt32(ifNull(k, 0)) IS NOT DISTINCT FROM NULL) WHERE explain ILIKE '%Granules: 1/%';

-- The boolean-wrapper peel must reach ANY prunable boolean atom, not just comparisons:
-- `startsWith(s, p) IS TRUE` / `!= false` / `IN (true)` must prune the String key the same as bare
-- `startsWith(s, p)` (the gate is derived from `atom_map` in `predicateIsBooleanResult`).
SELECT '--- startsWith(s, p) IS TRUE prunes via primary key like the bare atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM spk WHERE startsWith(s, '999') IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- bare startsWith(s, p) prunes via primary key (reference) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM spk WHERE startsWith(s, '999')) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- startsWith(s, p) != false prunes via primary key like the bare atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM spk WHERE startsWith(s, '999') != false) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- startsWith(s, p) IN (true) prunes via primary key like the bare atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM spk WHERE startsWith(s, '999') IN (true)) WHERE explain ILIKE '%Granules: 1/%';

-- The positive-boolean-wrapper peel composes with the existing `ifNull(X, 0)` / `coalesce(X, 0)`
-- boolean rewrite (gated by `allow_key_condition_coalesce_rewrite`): `ifNull(k = 42, 0) IS TRUE`
-- (and the `!= false` / `IN (true)` forms) must prune the same as bare `ifNull(k = 42, 0)`.
SELECT '--- ifNull(k = 42, 0) IS TRUE prunes via primary key like the bare wrapped atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE ifNull(k = 42, 0) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- bare ifNull(k = 42, 0) prunes via primary key (reference) ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE ifNull(k = 42, 0)) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- coalesce(k = 42, 0) IS TRUE prunes via primary key like the bare wrapped atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE coalesce(k = 42, 0) IS TRUE) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- ifNull(k = 42, 0) != false prunes via primary key like the bare wrapped atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE ifNull(k = 42, 0) != false) WHERE explain ILIKE '%Granules: 1/%';

SELECT '--- ifNull(k = 42, 0) IN (true) prunes via primary key like the bare wrapped atom ---';
SELECT count() > 0 FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE ifNull(k = 42, 0) IN (true)) WHERE explain ILIKE '%Granules: 1/%';

-- With the coalesce rewrite disabled the composed peel must NOT prune (behavior preserved when off).
SELECT '--- ifNull(k = 42, 0) IS TRUE does NOT prune when allow_key_condition_coalesce_rewrite = 0 (0/) ---';
SELECT count() FROM (EXPLAIN indexes = 1 SELECT count() FROM pk WHERE ifNull(k = 42, 0) IS TRUE SETTINGS allow_key_condition_coalesce_rewrite = 0) WHERE explain ILIKE '%Granules: 1/%';

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
-- `key <=> NULL` returns the NULL rows (like IS NULL); the const-on-left form matches too.
SELECT 'ndf_null_left', count() FROM pk_null WHERE NULL IS NOT DISTINCT FROM k;
-- NULL-erasing wrappers over the key are ALWAYS FALSE against NULL (never match), unlike bare `k <=> NULL`.
SELECT 'ifnull_ndf_null', count() FROM pk_null WHERE ifNull(k, 0) IS NOT DISTINCT FROM NULL;
SELECT 'coalesce_ndf_null', count() FROM pk_null WHERE coalesce(k, 0) IS NOT DISTINCT FROM NULL;
SELECT 'assumenotnull_ndf_null', count() FROM pk_null WHERE assumeNotNull(k) IS NOT DISTINCT FROM NULL;
SELECT 'ifnull_isnull', count() FROM pk_null WHERE isNull(ifNull(k, 0));
SELECT 'ifnull_ndf_null_corw_off', count() FROM pk_null WHERE ifNull(k, 0) IS NOT DISTINCT FROM NULL SETTINGS allow_key_condition_coalesce_rewrite = 0;
-- A NULL-preserving conversion (`toUInt32(Nullable)` stays Nullable) matches the NULL rows like bare
-- `k <=> NULL`; wrapping it in a NULL-erasing `ifNull` makes it always-false again.
SELECT 'touint32_ndf_null', count() FROM pk_null WHERE toUInt32(k) IS NOT DISTINCT FROM NULL;
SELECT 'touint32_ifnull_ndf_null', count() FROM pk_null WHERE toUInt32(ifNull(k, 0)) IS NOT DISTINCT FROM NULL;
-- ifNull / coalesce composed wrapper forms match the bare wrapped atom.
SELECT 'ifnull_bare', count() FROM pk WHERE ifNull(k = 42, 0);
SELECT 'ifnull_istrue', count() FROM pk WHERE ifNull(k = 42, 0) IS TRUE;
SELECT 'coalesce_istrue', count() FROM pk WHERE coalesce(k = 42, 0) IS TRUE;
SELECT 'ifnull_ne_false', count() FROM pk WHERE ifNull(k = 42, 0) != false;
SELECT 'ifnull_in_true', count() FROM pk WHERE ifNull(k = 42, 0) IN (true);
-- startsWith wrapper forms match the bare atom.
SELECT 'startswith_bare', count() FROM spk WHERE startsWith(s, '999');
SELECT 'startswith_istrue', count() FROM spk WHERE startsWith(s, '999') IS TRUE;
SELECT 'startswith_ne_false', count() FROM spk WHERE startsWith(s, '999') != false;
SELECT 'startswith_in_true', count() FROM spk WHERE startsWith(s, '999') IN (true);
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
DROP TABLE spk;
