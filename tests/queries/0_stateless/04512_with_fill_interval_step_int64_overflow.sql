-- { echo }
-- Each query drives FillingRow::doLongJump (reached only via the STALENESS shift path) to a
-- jumps_count large enough that step * jumps_count overflows Int64. The step is picked so the
-- per-jump delta is 2^31 in the UInt32 DateTime domain: odd jumps advance, even jumps land on the
-- same value, so doLongJump keeps doubling step_len until the multiply overflows. Must terminate
-- with no UB (the multiply wraps by construction) and no hang. SECOND/MINUTE/HOUR use plain modular
-- arithmetic on the DateTime domain, which is what reaches the overflowing multiply; calendar kinds
-- (DAY/WEEK/MONTH) converge via DateLUT and cannot drive jumps_count that high, so are not covered.
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 2147483648 SECOND STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDateTime64(arrayJoin([toDateTime64('1970-01-01 00:00:00', 0), toDateTime64('2262-01-01 00:00:00', 0)]), 0) AS d ORDER BY d WITH FILL STEP INTERVAL 2147483648 SECOND STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 536870912 MINUTE STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 134217728 HOUR STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
