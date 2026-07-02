#!/usr/bin/env bash
# Tags: replica, zookeeper, no-fasttest, no-sanitizers-lsan, long
# Test that KILL QUERY works for ALTER DELETE with mutations_sync=1 on ReplicatedMergeTree.
# Ref: https://github.com/ClickHouse/ClickHouse/issues/97535

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

query_id="kill_query_mutation_sync_${CLICKHOUSE_DATABASE}_$RANDOM"
alter_stderr="${CLICKHOUSE_TMP}/kill_query_mutation_sync_${CLICKHOUSE_DATABASE}_$RANDOM.stderr"

$CLICKHOUSE_CLIENT --query "
    CREATE TABLE ${CLICKHOUSE_DATABASE}.t_kill_mutation
    (
        id UInt64,
        value String
    )
    ENGINE = ReplicatedMergeTree('/clickhouse/tables/$CLICKHOUSE_TEST_ZOOKEEPER_PREFIX/t_kill_mutation', '1')
    ORDER BY id
"

$CLICKHOUSE_CLIENT --query "INSERT INTO ${CLICKHOUSE_DATABASE}.t_kill_mutation SELECT number, toString(number) FROM numbers(100)"

# Stop merges so the mutation entry is created but never executed by the background pool.
# The mutation stays incomplete forever, so with mutations_sync=1 the ALTER blocks inside
# waitMutationToFinishOnReplicas (the code path fixed by #97589). This makes the test
# deterministic and CPU-independent: it does not rely on a long-running or memory-heavy
# mutation to keep the query alive, and it leaves no in-flight background work to stall
# teardown.
$CLICKHOUSE_CLIENT --query "SYSTEM STOP MERGES ${CLICKHOUSE_DATABASE}.t_kill_mutation"

$CLICKHOUSE_CLIENT --query_id="$query_id" --query "
    ALTER TABLE ${CLICKHOUSE_DATABASE}.t_kill_mutation DELETE WHERE value = 'nonexistent'
    SETTINGS mutations_sync = 1
" >/dev/null 2>"$alter_stderr" &
alter_pid=$!

wait_for_query_to_start "$query_id"

# KILL QUERY must unblock the ALTER waiting on the mutation. The background ALTER client
# exits once the server returns the cancellation error.
$CLICKHOUSE_CURL -sS "$CLICKHOUSE_URL" -d "KILL QUERY WHERE query_id = '$query_id'" >/dev/null

# Wait (bounded) for the background ALTER client to exit after the kill. On a build without
# the cancellation check in waitMutationToFinishOnReplicas, the ALTER would ignore the kill
# and stay blocked forever; the timeout below turns that into an explicit failure instead of
# hanging for the whole test time limit.
for _ in $(seq 1 600); do
    kill -0 "$alter_pid" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$alter_pid" 2>/dev/null; then
    echo "ALTER still running 60s after KILL QUERY" >&2
    kill "$alter_pid" 2>/dev/null
fi
wait "$alter_pid" 2>/dev/null

# Assert the ALTER exited via cancellation, not by the mutation completing on its own:
# the client prints QUERY_WAS_CANCELLED only when KILL QUERY cancelled the waiting ALTER.
# Without this check the test is a false positive (wait_for_query_to_start only proves the
# query was observed once).
grep -oF "QUERY_WAS_CANCELLED" "$alter_stderr"

# Remove the never-executed mutation entry so the table can be dropped cleanly.
$CLICKHOUSE_CURL -sS "$CLICKHOUSE_URL" -d "KILL MUTATION WHERE database = '${CLICKHOUSE_DATABASE}' AND table = 't_kill_mutation'" >/dev/null 2>&1 || true

$CLICKHOUSE_CURL -sS "$CLICKHOUSE_URL" -d "DROP TABLE IF EXISTS ${CLICKHOUSE_DATABASE}.t_kill_mutation SYNC"

rm -f "$alter_stderr"
