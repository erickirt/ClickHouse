-- { echo }
-- Regression for signed Int64 overflow in the WITH FILL interval-step multiply (step * jumps_count)
-- routed through FillingRow::doLongJump. The multiply now wraps by construction via mulStepWrapping,
-- which doLongJump relies on to detect the overflowed jump. Each query below must terminate with no
-- UB and no hang.
--
-- The overflowing multiply is only reachable via the STALENESS shift path (FillingRow::shift ->
-- doLongJump), where step_len is doubled repeatedly. It is reached for the plain-modular kinds whose
-- Add*Impl truncates to a small domain: SECOND/MINUTE/HOUR on DateTime (UInt32) and WEEK on Date
-- (UInt16). The large per-jump delta wraps back into range and lets doLongJump keep doubling step_len
-- until step * jumps_count overflows Int64. The steps here are picked so the per-jump delta is half
-- the domain (2^31 for DateTime, 2^15 days for Date): odd jumps advance, even jumps land on the same
-- value, so step_len keeps doubling to the overflow point.
--
-- The MINUTE/HOUR/WEEK cases also drive the wrapped delta far enough that it used to overflow a
-- second time inside AddMinutesImpl/AddHoursImpl/AddWeeksImpl (delta * 60, delta * 3600, delta * 7).
-- Those helper overloads now compute in the UInt64 domain too and are no longer
-- NO_SANITIZE_UNDEFINED, so this test enforces the whole WITH FILL interval-step chain under UBSan.
--
-- DateTime64/Decimal64 and the calendar kinds (DAY/MONTH and WEEK on DateTime) cannot be driven to
-- that overflow in a terminating query: DateTime64 execute() works in the full Int64 tick domain (no
-- small-domain wrap, so a large delta immediately overshoots the target or overflows Int64 and
-- doLongJump stops doubling), and the calendar kinds converge via DateLUT. The DateTime64 case below
-- is therefore a correctness smoke test of the same code path (the Decimal64 branch uses the
-- identical mulStepWrapping via the same FOR_EACH_INTERVAL_KIND macro, so it is protected by
-- construction), not an overflow trigger.
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 2147483648 SECOND STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 536870912 MINUTE STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDateTime(arrayJoin([toUInt32(0), toUInt32(4294967295)])) AS d ORDER BY d WITH FILL STEP INTERVAL 134217728 HOUR STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
SELECT toDate(arrayJoin([toUInt16(0), toUInt16(65535)])) AS d ORDER BY d WITH FILL STEP INTERVAL 32768 WEEK STALENESS INTERVAL 1 DAY SETTINGS session_timezone = 'UTC';
SELECT toDateTime64(arrayJoin([toDateTime64('1970-01-01 00:00:00', 0), toDateTime64('2262-01-01 00:00:00', 0)]), 0) AS d ORDER BY d WITH FILL STEP INTERVAL 2147483648 SECOND STALENESS INTERVAL 1 SECOND SETTINGS session_timezone = 'UTC';
