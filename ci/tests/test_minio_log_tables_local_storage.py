"""
Guard test for the storage placement of the MinIO webhook log tables created in
ClickHouseProc.create_minio_log_tables (ci/jobs/scripts/clickhouse_proc.py).

Background
----------
`system.minio_server_logs` is a diagnostic table that captures the MinIO server
webhook stream during a run. It is a plain `ENGINE = MergeTree` table, so on s3
storage runs it would inherit the overridden default merge_tree policy
(s3_storage_policy_for_merge_tree_by_default.xml sets
<merge_tree><storage_policy>s3</storage_policy>) and live ON S3. That is bad for
a table that records S3 activity: every webhook insert would write parts to S3
(generating more S3 traffic to log), and the post-run
`select * ... into outfile` dump in dump_system_tables would read it all back
from S3, risking the DUMP_SYSTEM_TABLE_TIMEOUT cap on the "Scraping system
tables" step.

The fix pins the table to the local `default` policy with an explicit
`SETTINGS storage_policy = 'default'`. `default` is a local policy on every
stateless config (nothing remaps it), so the dump reads locally. This test
guards against a future edit dropping that setting and silently putting the
table back on S3.

The former `system.minio_audit_logs` table (one audit event per S3 API request)
was dropped entirely: on s3 runs it ballooned to millions of rows and is not
needed as ClickHouse diagnostics. This test also guards against reintroducing
it without the local storage pin.
"""

import re
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
_SRC = _REPO_ROOT / "ci" / "jobs" / "scripts" / "clickhouse_proc.py"


def _create_statements(src):
    # Every `CREATE TABLE system.minio_*_logs ...` SQL string built in the
    # source, up to the closing double quote of the clickhouse-client --query.
    return re.findall(r"CREATE TABLE system\.minio_\w+_logs[^\"]*", src)


def test_minio_log_tables_are_pinned_to_local_storage():
    src = _SRC.read_text()
    statements = _create_statements(src)
    # Only the server log table is created; the audit log table was dropped.
    assert len(statements) == 1, (
        f"expected 1 minio log table CREATE statement, found {len(statements)}: {statements}"
    )
    assert "minio_server_logs" in statements[0], (
        f"expected the surviving minio log table to be system.minio_server_logs; got: {statements[0]}"
    )
    for stmt in statements:
        # The captured text is a Python source fragment, so the SQL string
        # quotes are backslash-escaped (\\'default\\'); drop the backslashes to
        # compare against the SQL as clickhouse-client will see it.
        sql = stmt.replace("\\", "")
        # A CREATE that ends at `ORDER BY tuple()` with no storage_policy would
        # inherit the s3-overridden default on s3 runs. Require the local pin
        # right after the ORDER BY, so the placement is explicit and local.
        assert re.search(r"ORDER BY tuple\(\)\s+SETTINGS\s+storage_policy = 'default'", sql), (
            "minio log table must be pinned to the local 'default' storage policy "
            f"so its dump is not read back from S3; got: {sql}"
        )
