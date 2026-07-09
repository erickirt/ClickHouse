#!/usr/bin/env bash
# Tags: no-tsan, no-asan, no-msan, no-ubsan, no-sanitize-coverage, no-llvm-coverage

# Focused check that the CPU query profiler emits trace_type='CPU' rows in system.trace_log.
# On macOS the CPU profiler is a separate implementation (a sampler thread that polls per-thread CPU
# time via Mach thread_info and delivers the pause signal with pthread_kill), so this guards that path
# specifically, on top of the real-time profiler coverage elsewhere.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

query_id="04509_cpu_profiler_${CLICKHOUSE_DATABASE}"

# CPU-bound query with a small CPU-time period; trace_profile_events is disabled because it can
# inhibit the sampling profiler (it competes for the same trace pipe).
${CLICKHOUSE_CLIENT} --query_id="$query_id" --query "
    SELECT count() FROM numbers_mt(1000000000)
    SETTINGS query_profiler_real_time_period_ns = 0,
             query_profiler_cpu_time_period_ns = 1000000,
             trace_profile_events = 0,
             max_rows_to_read = 0
    FORMAT Null"

${CLICKHOUSE_CLIENT} --query "SYSTEM FLUSH LOGS trace_log"

${CLICKHOUSE_CLIENT} --query "
    SELECT count() > 0
    FROM system.trace_log
    WHERE event_date >= yesterday() AND event_time >= now() - 600
      AND query_id = '$query_id' AND trace_type = 'CPU'"
