-- Test: `additional_table_filters` with a non-boolean filter type bypasses analyzer
-- validateFilters and must be rejected by the FilterStep/projection type check.
DROP TABLE IF EXISTS t_04509;
SET enable_analyzer = 1;
SET query_plan_remove_unused_columns = 1;

DROP TABLE IF EXISTS t_04509;
CREATE TABLE t_04509 (c0 Int32, c1 Int32) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_04509 VALUES (1, 10), (2, 20);

-- String filter, plain read path (FilterTransform::transformHeader type check).
SELECT c1 FROM t_04509 ORDER BY c1
SETTINGS additional_table_filters = {'t_04509':'toString(c0)'}, optimize_use_projections = 0; -- { serverError ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER }

-- Decimal filter, plain read path.
SELECT c1 FROM t_04509 ORDER BY c1
SETTINGS additional_table_filters = {'t_04509':'toDecimal64(c0, 2)'}, optimize_use_projections = 0; -- { serverError ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER }

-- String filter, implicit-projection path (projectionsCommon findInOutputs type check).
SELECT count() FROM t_04509
SETTINGS additional_table_filters = {'t_04509':'toString(c0)'}, optimize_use_projections = 1, optimize_use_implicit_projections = 1, optimize_trivial_count_query = 0; -- { serverError ILLEGAL_TYPE_OF_COLUMN_FOR_FILTER }

-- Native filter still runs and the policy is applied (regression guard for the lenient check).
SELECT c1 FROM t_04509 ORDER BY c1
SETTINGS additional_table_filters = {'t_04509':'c0'};

DROP TABLE t_04509;
