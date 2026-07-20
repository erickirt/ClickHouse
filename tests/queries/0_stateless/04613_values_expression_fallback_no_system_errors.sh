#!/usr/bin/env bash
# Tags: no-parallel
# Tag no-parallel: The test checks global values in `system.errors` and `system.error_log`.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

fallback_query_id="04613_values_fallback_${CLICKHOUSE_DATABASE}_${RANDOM}"
overflow_query_id="04613_values_overflow_${CLICKHOUSE_DATABASE}_${RANDOM}"

$CLICKHOUSE_CLIENT -q "
    CREATE TABLE values_fallback
    (
        id UInt32,
        target_ids Array(String),
        target_tags Map(String, Array(String)),
        raw_json_as_string String,
        raw_json_as_map Map(String, String),
        activity_type Enum8('ADMINISTRATION' = 1, 'OTHER' = 2)
    )
    ENGINE = Memory"
$CLICKHOUSE_CLIENT -q "CREATE TABLE values_decimal (x Decimal32(2)) ENGINE = Memory"
$CLICKHOUSE_CLIENT -q "CREATE TABLE values_decimal_retry (x Decimal32(2)) ENGINE = Memory"

${CLICKHOUSE_CURL} -sS \
    "${CLICKHOUSE_URL}&query_id=${fallback_query_id}&async_insert=1&wait_for_async_insert=1&input_format_values_deduce_templates_of_expressions=0" \
    --data-binary "
        INSERT INTO values_fallback (id, target_tags, raw_json_as_string, raw_json_as_map, activity_type)
        VALUES (1 + 0, {'3f37a58df98ba6e2': ['aaaa']}, '{}', {}, 'ADMINISTRATION'),
               (+2, {}, '{}', {}, 'OTHER')" > /dev/null

$CLICKHOUSE_CLIENT -q "SELECT id, target_ids, target_tags, raw_json_as_string, raw_json_as_map, activity_type FROM values_fallback ORDER BY id"

flush_query_id=""
for _ in {1..60}; do
    $CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS asynchronous_insert_log, error_log"
    flush_query_id=$($CLICKHOUSE_CLIENT -q "
        SELECT flush_query_id
        FROM system.asynchronous_insert_log
        WHERE query_id = '${fallback_query_id}' AND database = currentDatabase() AND table = 'values_fallback'
        ORDER BY event_time_microseconds DESC
        LIMIT 1")
    [ -n "$flush_query_id" ] && break
    sleep 0.5
done

$CLICKHOUSE_CLIENT -q "SELECT count() = 0 FROM system.errors WHERE query_id = '${flush_query_id}'"
$CLICKHOUSE_CLIENT -q "SELECT count() = 0 FROM system.error_log WHERE last_error_query_id = '${flush_query_id}'"

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS error_log"
overflow_errors_before=$($CLICKHOUSE_CLIENT -q "SELECT any(value) FROM system.errors WHERE name = 'ARGUMENT_OUT_OF_BOUND'")
overflow_log_before=$($CLICKHOUSE_CLIENT -q "SELECT sum(value) FROM system.error_log WHERE error = 'ARGUMENT_OUT_OF_BOUND'")

${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}&query_id=${overflow_query_id}" \
    --data-binary "INSERT INTO values_decimal VALUES (12345678.91)" > /dev/null

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS error_log"
$CLICKHOUSE_CLIENT -q "SELECT value = ${overflow_errors_before} + 1 FROM system.errors WHERE name = 'ARGUMENT_OUT_OF_BOUND'"
$CLICKHOUSE_CLIENT -q "SELECT sum(value) > ${overflow_log_before} FROM system.error_log WHERE error = 'ARGUMENT_OUT_OF_BOUND'"

overflow_errors_before=$($CLICKHOUSE_CLIENT -q "SELECT any(value) FROM system.errors WHERE name = 'ARGUMENT_OUT_OF_BOUND'")
overflow_log_before=$($CLICKHOUSE_CLIENT -q "SELECT sum(value) FROM system.error_log WHERE error = 'ARGUMENT_OUT_OF_BOUND'")

${CLICKHOUSE_CURL} -sS "${CLICKHOUSE_URL}&input_format_values_deduce_templates_of_expressions=0" \
    --data-binary "INSERT INTO values_decimal_retry VALUES (1.20 + 0.03), (12345678.91)" > /dev/null

$CLICKHOUSE_CLIENT -q "SYSTEM FLUSH LOGS error_log"
$CLICKHOUSE_CLIENT -q "SELECT value = ${overflow_errors_before} + 1 FROM system.errors WHERE name = 'ARGUMENT_OUT_OF_BOUND'"
$CLICKHOUSE_CLIENT -q "SELECT sum(value) > ${overflow_log_before} FROM system.error_log WHERE error = 'ARGUMENT_OUT_OF_BOUND'"
