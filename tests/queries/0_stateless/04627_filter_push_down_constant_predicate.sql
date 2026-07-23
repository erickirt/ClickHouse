-- Tags: no-parallel-replicas

-- A constant-true predicate (`AND 1`) combined with a `LEFT JOIN`, `ORDER BY` and `LIMIT` used to
-- throw `NOT_FOUND_COLUMN_IN_BLOCK`: with filter push down, merge expressions, top-k-through-join and
-- lazy materialization all active, the merged outer filter was left as a dangling input pass-through
-- in the lazy half of the plan, referencing a column no input block provides. Regression from #104268,
-- fixed on master. Issue #111452.
--
-- All optimizations that must be enabled to reach the fixed code path are pinned so the runner cannot
-- silently disable the path (which would let this test pass even on a broken build). The `*_max_limit_*`
-- caps use 0 = unlimited so they never drop below the query's `LIMIT`. `no-parallel-replicas` (like the
-- other lazy-materialization tests): parallel replicas rewrite the read before lazy materialization runs.

SET enable_analyzer = 1;
SET query_plan_filter_push_down = 1;
SET query_plan_merge_expressions = 1;
SET query_plan_top_k_through_join = 1;
SET query_plan_optimize_lazy_materialization = 1;
SET query_plan_max_limit_for_lazy_materialization = 0;
SET query_plan_max_limit_for_top_k_optimization = 0;

DROP TABLE IF EXISTS traces_04627;

CREATE TABLE traces_04627 (cluster String, ts UInt64, trace_id String) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO traces_04627 VALUES ('cluster1', 1, 'trace007');

-- Liveness oracle: the plan must actually take the lazy-materialization-through-join path this test targets.
SELECT count() > 0
FROM
(
    EXPLAIN actions = 1
    SELECT ts
    FROM
    (
        SELECT t.cluster, t.ts
        FROM traces_04627 AS t
        LEFT ANY JOIN (SELECT '' AS cluster, '' AS trace_id) AS a USING (cluster, trace_id)
        WHERE t.ts BETWEEN 0 AND 10
    ) AS v
    WHERE cluster = 'cluster1' AND 1
    ORDER BY ts DESC
    LIMIT 10
)
WHERE explain ILIKE '%JoinLazyColumnsStep%';

-- The regression itself: must return a single row, ts = 1.
SELECT ts
FROM
(
    SELECT t.cluster, t.ts
    FROM traces_04627 AS t
    LEFT ANY JOIN (SELECT '' AS cluster, '' AS trace_id) AS a USING (cluster, trace_id)
    WHERE t.ts BETWEEN 0 AND 10
) AS v
WHERE cluster = 'cluster1' AND 1
ORDER BY ts DESC
LIMIT 10;

DROP TABLE traces_04627;
