"""
Guard test for the storage placement of the MinIO webhook log tables created in
ClickHouseProc.create_minio_log_tables (ci/jobs/scripts/clickhouse_proc.py).

Background
----------
`system.minio_server_logs` is a diagnostic table that captures the MinIO server
webhook stream during a run. It is a plain `ENGINE = MergeTree` table, so unless
pinned it inherits the server's default merge_tree storage policy. On s3 storage
runs that default is S3 (s3_storage_policy_for_merge_tree_by_default.xml sets
<merge_tree><storage_policy>s3</storage_policy>), and in the private/cloud repo
the `default` policy itself is cloud-based. Either way the table would live ON
S3, which is bad for a table that records S3 activity: every webhook insert
writes parts to S3 (more S3 traffic to log), and the post-run
`select * ... into outfile` dump in dump_system_tables reads it all back from
S3, risking the DUMP_SYSTEM_TABLE_TIMEOUT cap on the "Scraping system tables"
step.

The fix pins the table to a dedicated LOCAL disk with an explicit
`SETTINGS disk = disk(type = 'local', path = '/var/lib/clickhouse/disks/...')`.
That path is inside custom_local_disks_base_directory (set by
custom_disks_base_path.xml, which install.sh always installs), so the disk is
created locally regardless of what `default` maps to - correct in both the
public repo (where `default` is local) and the private/cloud repo (where
`default` is object storage). This test guards against a future edit dropping
that pin, or reverting to `storage_policy = 'default'`, and silently putting the
table back on S3.

The former `system.minio_audit_logs` table (one audit event per S3 API request)
was dropped entirely: on s3 runs it ballooned to millions of rows and is not
needed as ClickHouse diagnostics. This test also guards against reintroducing it.

Lifecycle: the pinned disk path lives OUTSIDE the per-run server data directory
(run_path*) that ClickHouseProc.start wipes, so a restart destroys the table's
metadata but not its data. create_minio_log_tables therefore resets the disk
directory itself before re-creating the table - otherwise every bugfix-validation
binary swap leaks the previous incarnation's parts. This test also guards that
reset step, that it covers exactly the pinned disk path, and that it stays
symlink-safe: a plain `rm -rf .../` would follow a stale or planted symlink there
and recursively delete whatever it points at.
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
        # quotes are backslash-escaped (\\'local\\'); drop the backslashes to
        # compare against the SQL as clickhouse-client will see it.
        sql = stmt.replace("\\", "")
        # A CREATE that ends at `ORDER BY tuple()` with no explicit disk would
        # inherit the server default (S3 on s3 runs, cloud in private). Require an
        # explicit local disk right after the ORDER BY, pinned inside
        # custom_local_disks_base_directory so the placement is explicit, local,
        # and independent of what `default` resolves to.
        assert re.search(
            r"ORDER BY tuple\(\)\s+SETTINGS\s+disk = disk\(\s*type = 'local',\s*"
            r"path = '/var/lib/clickhouse/disks/[^']+'\s*\)",
            sql,
        ), (
            "minio log table must be pinned to an explicit local disk under "
            "/var/lib/clickhouse/disks/ so its dump is not read back from S3 "
            f"(and not left on the cloud `default` policy in private); got: {sql}"
        )


def test_minio_log_table_disks_are_reset_before_create():
    src = _SRC.read_text()
    pinned_paths = {
        m.replace("\\", "")
        for m in re.findall(
            r"path = \\?'(/var/lib/clickhouse/disks/[^'\\]+)", src
        )
    }
    assert len(pinned_paths) == 1, (
        f"expected 1 pinned minio log disk path, found: {sorted(pinned_paths)}"
    )
    # The pinned paths are outside the run_path* directory that start() wipes,
    # so stale data survives every server restart unless create_minio_log_tables
    # removes it before re-creating the tables. A shell `rm -rf .../` would
    # follow a stale or planted symlink at either path and recursively delete
    # whatever it points at, so the reset must not use that form.
    assert not re.search(r'"rm -rf /var/lib/clickhouse/disks', src), (
        "the minio log disk reset must not shell out to `rm -rf` - a symlink "
        "at the pinned path would turn it into a recursive delete of an "
        "arbitrary host directory; use a symlink-safe removal instead"
    )
    reset_tuple = re.search(r"_MINIO_LOG_DISK_PATHS\s*=\s*\((.*?)\)", src, re.DOTALL)
    assert reset_tuple, "expected a _MINIO_LOG_DISK_PATHS tuple of the reset paths"
    reset_paths = set(
        re.findall(r"[\"'](/var/lib/clickhouse/disks/[^\"']+)[\"']", reset_tuple.group(1))
    )
    assert reset_paths == pinned_paths, (
        "the reset step must remove exactly the pinned minio log disk paths; "
        f"resets {sorted(reset_paths)}, pinned {sorted(pinned_paths)}"
    )
    assert "is_symlink()" in src, (
        "the reset step must refuse to follow a symlink at the pinned disk "
        "path before removing it"
    )
