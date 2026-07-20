#!/usr/bin/env bash

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

user="user_${CLICKHOUSE_DATABASE}"
profile="profile_${CLICKHOUSE_DATABASE}"

${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${user}"
${CLICKHOUSE_CLIENT} --query "DROP SETTINGS PROFILE IF EXISTS ${profile}"

# Pin a setting read-only in a profile: an explicit value plus a CONST constraint. This mirrors the recommended
# lockdown of s3_allow_server_credentials_in_user_queries for untrusted users.
${CLICKHOUSE_CLIENT} --query "CREATE SETTINGS PROFILE ${profile} SETTINGS s3_allow_server_credentials_in_user_queries = 0 CONST"
${CLICKHOUSE_CLIENT} --query "CREATE USER ${user} IDENTIFIED WITH no_password SETTINGS PROFILE ${profile}"

# An old compatibility is resolved by the native client, which then transmits the reverted value of the pinned
# setting as an explicit change. This must not fail the query; the pinned value stays in force.
${CLICKHOUSE_CLIENT} --user "${user}" --compatibility 24.1 --query "SELECT getSetting('s3_allow_server_credentials_in_user_queries')"

# A genuine attempt to change the read-only setting is still rejected.
${CLICKHOUSE_CLIENT} --user "${user}" --s3_allow_server_credentials_in_user_queries 1 --query "SELECT 1" 2>&1 | grep -o -m1 "SETTING_CONSTRAINT_VIOLATION"

${CLICKHOUSE_CLIENT} --query "DROP USER IF EXISTS ${user}"
${CLICKHOUSE_CLIENT} --query "DROP SETTINGS PROFILE IF EXISTS ${profile}"
