-- Regression test for the "Virtual row boundary violated in MergingSortedAlgorithm" logical error
-- (STID 2651-3359). ORDER BY builds a read-in-order virtual row for the sort-key prefix it needs
-- (here CounterID). distinct-in-order then widens the read to a longer prefix (CounterID, EventDate)
-- without rebuilding the virtual row, so the extra column was default-filled and, in reverse order,
-- announced a boundary (0) smaller than the real values, tripping the assertion in debug builds and
-- silently mis-ordering the merge in release builds.

DROP TABLE IF EXISTS t_virtual_row_distinct;

CREATE TABLE t_virtual_row_distinct (CounterID UInt32, EventDate UInt64, s String)
ENGINE = MergeTree ORDER BY (CounterID, EventDate)
SETTINGS index_granularity = 8;

-- Several unmerged parts with small granules so an in-order merge across parts is used.
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(20000);
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(20000, 20000);
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(40000, 20000);
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(60000, 20000);
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(80000, 20000);
INSERT INTO t_virtual_row_distinct SELECT number % 5, 16000 + (number % 1000), toString(number) FROM numbers(100000, 20000);

SET optimize_read_in_order = 1, read_in_order_use_virtual_row = 1, optimize_distinct_in_order = 1,
    read_in_order_two_level_merge_threshold = 3, max_threads = 2, max_block_size = 64;

-- Must not throw and must return the correct distinct set.
-- Reverse order is the case that previously tripped the boundary check.
SELECT count() FROM (SELECT DISTINCT CounterID, EventDate FROM t_virtual_row_distinct ORDER BY CounterID DESC);
SELECT count() FROM (SELECT DISTINCT CounterID, EventDate FROM t_virtual_row_distinct ORDER BY 1 ASC, CounterID DESC);

-- Result must match the unoptimized read.
SELECT
    (SELECT groupArray((CounterID, EventDate)) FROM (SELECT DISTINCT CounterID, EventDate FROM t_virtual_row_distinct ORDER BY CounterID DESC, EventDate))
  = (SELECT groupArray((CounterID, EventDate)) FROM (SELECT DISTINCT CounterID, EventDate FROM t_virtual_row_distinct ORDER BY CounterID DESC, EventDate SETTINGS optimize_read_in_order = 0, read_in_order_use_virtual_row = 0));

DROP TABLE t_virtual_row_distinct;

-- The stale-conversion drop must fire ONLY for a widening request. A fixed middle key
-- (WHERE b = 1 ORDER BY a, c on key (a, b, c)) builds a conversion that is intentionally
-- narrower than the used sort-key prefix on its FIRST (ORDER BY) request; it must be preserved,
-- otherwise the virtual row optimization is lost (and behind a join the high-read-amp path is
-- re-enabled). Assert the conversion is still present in the plan.
DROP TABLE IF EXISTS t_virtual_row_fixed_key;

CREATE TABLE t_virtual_row_fixed_key (a UInt32, b UInt32, c UInt32)
ENGINE = MergeTree ORDER BY (a, b, c)
SETTINGS index_granularity = 8;

INSERT INTO t_virtual_row_fixed_key SELECT number % 10, 1, number % 7 FROM numbers(2000);
INSERT INTO t_virtual_row_fixed_key SELECT number % 10, 1, number % 7 FROM numbers(2000, 2000);

SELECT count() > 0
FROM (EXPLAIN actions = 1 SELECT a, c FROM t_virtual_row_fixed_key WHERE b = 1 ORDER BY a, c
      SETTINGS optimize_read_in_order = 1, read_in_order_use_virtual_row = 1)
WHERE explain ILIKE '%Virtual row conversions%';

DROP TABLE t_virtual_row_fixed_key;
