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
-- The DateTime64/Decimal64 branch and the calendar kinds cannot be driven to the step * jumps_count
-- overflow in a terminating query: DateTime64 execute() works in the full Int64 tick domain (no
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
-- The WITH FILL step functions delegate to the interval Add##NAME##sImpl helpers, some of which do a
-- further signed multiply/addition on the delta: AddWeeksImpl on DateTime64/Time64 (delta * 7) and
-- addMonthsIndex (values.month + delta), reached by MONTH/QUARTER on Date/DateTime. Those extra
-- operations overflow Int64 for a large enough delta and used to be UB. They cannot be driven from a
-- terminating WITH FILL query (the DateTime64 step is capped at Decimal(18, 0), and a saturating
-- calendar step makes the fill loop non-terminating), so they are exercised directly through the
-- interval functions with an Int64-overflowing delta. Each must terminate and saturate deterministically.
SELECT addWeeks(toDateTime64('1970-01-01 00:00:00', 0, 'UTC'), 9223372036854775807);
SELECT addWeeks(toDateTime64('1970-01-01 00:00:00.000', 3, 'UTC'), 9223372036854775807);
SELECT addMonths(toDateTime('2000-01-01 00:00:00', 'UTC'), 9223372036854775807);
SELECT addMonths(toDate('2000-01-01'), 9223372036854775807);
SELECT addMonths(toDateTime('2000-01-01 00:00:00', 'UTC'), -9223372036854775808);
SELECT addQuarters(toDateTime('2000-01-01 00:00:00', 'UTC'), 9223372036854775807);
SELECT addQuarters(toDate('2000-01-01'), 9223372036854775807);
-- getStepFunction allows sub-day interval kinds (SECOND/MINUTE/HOUR) on Date/Date32 when the interval
-- is at least one day in seconds, and next() invokes the step lambda with jumps_count == 1, so a single
-- huge STEP reaches the AddSecondsImpl/AddMinutesImpl/AddHoursImpl Date (UInt16) and Date32 (Int32)
-- overloads immediately. Those did fromDayNum(d) + delta (and Date32 (... + delta) * 1000, delta * 60,
-- delta * 3600) in signed Int64, which is UB on overflow. They now compute in the UInt64 domain like the
-- UInt32/DateTime64 overloads. A WITH FILL query that triggers the overflow does not terminate (saturating
-- step stalls the fill loop), so the fixed lines are exercised directly with an Int64-overflowing delta.
SELECT addSeconds(toDate('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
SELECT addSeconds(toDate32('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
SELECT addMinutes(toDate('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
SELECT addMinutes(toDate32('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
SELECT addHours(toDate('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
SELECT addHours(toDate32('2000-01-01'), 9223372036854775807) SETTINGS session_timezone = 'UTC';
