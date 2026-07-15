-- Tags: no-parallel-replicas
-- no-parallel-replicas: the test checks the shape of the local query plan.

DROP TABLE IF EXISTS t_lazy_final_gates;

CREATE TABLE t_lazy_final_gates (k UInt64, v UInt64, s String) ENGINE = ReplacingMergeTree ORDER BY k;

SYSTEM STOP MERGES t_lazy_final_gates;

INSERT INTO t_lazy_final_gates SELECT number, if(number < 20000, 7, 999), toString(number) FROM numbers(100000);
INSERT INTO t_lazy_final_gates SELECT number, if(number < 20000, 7, 999), 'updated' FROM numbers(100000);

SET enable_analyzer = 1, query_plan_optimize_lazy_final = 1, optimize_read_in_order = 1, max_threads = 4;

-- Filter without ORDER BY and LIMIT: lazy FINAL applies.
SELECT 'no order, no limit:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7);

-- Read-in-order: lazy FINAL must be disabled (the replacement plan does not produce rows in sorting key order).
SELECT 'read-in-order:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7 ORDER BY k);

SELECT 'read-in-order, limit:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7 ORDER BY k LIMIT 10);

-- A small LIMIT without ORDER BY stops reading early: lazy FINAL must be disabled.
SELECT 'small limit:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7 LIMIT 10);

-- A LIMIT not smaller than the number of selected rows cannot stop reading early: lazy FINAL applies.
SELECT 'large limit:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7 LIMIT 1000000);

-- A LIMIT above a full sort consumes the whole stream: lazy FINAL applies.
SELECT 'limit above full sort:', countIf(explain LIKE '%InputSelector%') > 0
FROM (EXPLAIN SELECT k FROM t_lazy_final_gates FINAL WHERE v = 7 ORDER BY s LIMIT 10);

-- The results must be the same with and without the optimization.
SELECT k, v, s FROM t_lazy_final_gates FINAL WHERE v = 7 ORDER BY k LIMIT 5;
SELECT k, v, s FROM t_lazy_final_gates FINAL WHERE v = 7 ORDER BY k LIMIT 5
SETTINGS query_plan_optimize_lazy_final = 0;

DROP TABLE t_lazy_final_gates;
