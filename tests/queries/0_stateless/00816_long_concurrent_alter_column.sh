#!/usr/bin/env bash
# Tags: long

set -e

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

echo "DROP TABLE IF EXISTS concurrent_alter_column" | ${CLICKHOUSE_CLIENT}
echo "CREATE TABLE concurrent_alter_column (ts DATETIME) ENGINE = MergeTree PARTITION BY toStartOfDay(ts) ORDER BY tuple()" | ${CLICKHOUSE_CLIENT}

function thread1()
{
    local TIMELIMIT=$((SECONDS+TIMEOUT))
    while [ $SECONDS -lt "$TIMELIMIT" ]
    do
        for i in {1..500}; do echo "ALTER TABLE concurrent_alter_column ADD COLUMN c$i DOUBLE;"; done | ${CLICKHOUSE_CLIENT} -n --query_id=alter_00816_1
    done
}

function thread2()
{
    local TIMELIMIT=$((SECONDS+TIMEOUT))
    while [ $SECONDS -lt "$TIMELIMIT" ]
    do
        echo "ALTER TABLE concurrent_alter_column ADD COLUMN d DOUBLE" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_2;
        sleep "$(echo 0.0$RANDOM)";
        echo "ALTER TABLE concurrent_alter_column DROP COLUMN d" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_2;
    done
}

function thread3()
{
    local TIMELIMIT=$((SECONDS+TIMEOUT))
    while [ $SECONDS -lt "$TIMELIMIT" ]
    do
        echo "ALTER TABLE concurrent_alter_column ADD COLUMN e DOUBLE" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_3;
        sleep "$(echo 0.0$RANDOM)";
        echo "ALTER TABLE concurrent_alter_column DROP COLUMN e" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_3;
    done
}

function thread4()
{
    local TIMELIMIT=$((SECONDS+TIMEOUT))
    while [ $SECONDS -lt "$TIMELIMIT" ]
    do
        echo "ALTER TABLE concurrent_alter_column ADD COLUMN f DOUBLE" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_4;
        sleep "$(echo 0.0$RANDOM)";
        echo "ALTER TABLE concurrent_alter_column DROP COLUMN f" | ${CLICKHOUSE_CLIENT} --query_id=alter_00816_4;
    done
}

TIMEOUT=20

thread1 2> /dev/null &
thread2 2> /dev/null &
thread3 2> /dev/null &
thread4 2> /dev/null &

wait

echo "DROP TABLE concurrent_alter_column SYNC" | ${CLICKHOUSE_CLIENT}   # SYNC has effect only for Atomic database

# Wait for alters and check for deadlocks (in case of deadlock this loop will not finish)
while true; do
    echo "SELECT * FROM system.processes WHERE query_id LIKE 'alter\\_00816\\_%'" | ${CLICKHOUSE_CLIENT} | grep -q -F 'alter' || break
    sleep 1;
done

echo 'did not crash'
