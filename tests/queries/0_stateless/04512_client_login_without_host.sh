#!/usr/bin/env bash
# Tags: no-fasttest
# no-fasttest: the client in the fast test build is compiled without OAuth support, so --login does nothing there.

# `clickhouse client --login` without an explicit --host used to abort with a libc++ hardening
# assertion ("front() called on an empty vector") instead of reporting a proper error.
# https://github.com/ClickHouse/ClickHouse/issues/103603

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

env -u CLICKHOUSE_HOST $CLICKHOUSE_CLIENT_BINARY --login 2>&1 | grep -o -m1 "Could not retrieve authentication endpoints"
