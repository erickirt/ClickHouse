-- Tags: no-parallel
-- Tag no-parallel: SQL user-defined functions are global (not per-database), so a fixed
-- function name collides across concurrent runs (e.g. the flaky check) with FUNCTION_ALREADY_EXISTS.

-- Regression test for https://github.com/ClickHouse/ClickHouse/issues/111438:
-- `DROP COLUMN` failed with `UNKNOWN_IDENTIFIER` when a sibling `ALIAS` column's expression
-- defined and later referenced an inline alias (here `array(length(event) AS l1, l1 + l1)`).

SET enable_analyzer = 1;

DROP FUNCTION IF EXISTS 04627_udf_with_alias;
CREATE FUNCTION 04627_udf_with_alias AS event -> array(length(event) AS l1, (l1 + l1) AS l2);

DROP TABLE IF EXISTS event_test;
CREATE TABLE event_test
(
    id UInt64,
    event String,
    x__event String ALIAS 04627_udf_with_alias(event)
)
ENGINE = MergeTree
ORDER BY id;

-- The UDF is substituted at CREATE TABLE, so the inline aliases (the bug trigger) are kept.
SELECT default_expression FROM system.columns
WHERE database = currentDatabase() AND table = 'event_test' AND name = 'x__event';

INSERT INTO event_test VALUES (1, 'ab'), (2, 'abcd');

SELECT 'before drop', id, event, x__event FROM event_test ORDER BY id;

ALTER TABLE event_test ADD COLUMN time DateTime64(3) ALIAS toDateTime64(JSONExtract(event, 'time', 'String'), 3);
SELECT 'time added', count() FROM system.columns
WHERE database = currentDatabase() AND table = 'event_test' AND name = 'time';

-- The DROP that used to throw UNKNOWN_IDENTIFIER while scanning the x__event dependency.
ALTER TABLE event_test DROP COLUMN time;
SELECT 'time dropped', count() FROM system.columns
WHERE database = currentDatabase() AND table = 'event_test' AND name = 'time';

-- The UDF-backed ALIAS column still resolves after the DROP.
SELECT 'after drop', id, event, x__event FROM event_test ORDER BY id;

-- The same dependency scan must still reject dropping a column the ALIAS depends on.
-- `event` is not part of the sorting key, so the rejection is due to the x__event ALIAS.
ALTER TABLE event_test DROP COLUMN event; -- { serverError ILLEGAL_COLUMN }

DROP TABLE event_test;
DROP FUNCTION 04627_udf_with_alias;
