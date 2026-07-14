-- Test uniqCombined/uniqCombined64 batched no-key path over FixedString columns.
DROP TABLE IF EXISTS t_uniq_fs;
CREATE TABLE t_uniq_fs (s FixedString(8)) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO t_uniq_fs SELECT toFixedString(concat('s', toString(number % 100)), 8) FROM numbers(5000);

SELECT 'fixedstring cardinality, no key';
SELECT uniqCombined(s), uniqCombined64(s), uniqCombined(12)(s), uniqCombined64(12)(s) FROM t_uniq_fs;

SELECT 'fixedstring matches uniqExact';
SELECT uniqCombined(s) = uniqExact(s), uniqCombined64(s) = uniqExact(s) FROM t_uniq_fs;

DROP TABLE t_uniq_fs;
