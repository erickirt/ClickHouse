"""
Regression test for the per-table wall-clock cap in
ClickHouseProc.dump_system_tables (ci/jobs/scripts/clickhouse_proc.py).

Background
----------
After all functional tests pass, the job's "Collect logs" phase dumps ~12
system tables one by one with `clickhouse local ... select * from system.<t>
into outfile ...`. On amd_tsan + s3 runs the JSON-typed `system.minio_audit_logs`
table can grow huge and `clickhouse local` can hang reading it. Because the dump
command had NO per-command timeout, a single stuck table consumed the rest of
the 9000s job budget; the job watchdog then SIGKILLed everything and the job
finished with a job-level ERROR (exit code 125 / -15) and results:[] - no
individual test failed. Observed on PRs #107307, #103402, #103706 and on master.

The fix wraps each dump in `timeout --signal=TERM --kill-after=60 <N>` so one
stuck table is bounded and reported as a failed dump instead of killing the job.

These tests exercise the `timeout` wrapper mechanism (the same coreutil and
flags the fix builds into `dump_prefix`), proving both directions with a small
cap: a hanging command is killed within the cap and returns 124; a SIGTERM-
ignoring command is escalated after --kill-after and returns 137; a fast command
passes through untouched. They also assert the production code still builds the
timeout prefix from the class constant and classifies both expiry codes.
"""

import subprocess
import time
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
_SRC = _REPO_ROOT / "ci" / "jobs" / "scripts" / "clickhouse_proc.py"


def _prefix(timeout_s, kill_after_s=60):
    # Mirror the exact prefix the fix builds in dump_system_tables. The
    # production code uses --kill-after=60; tests that need to observe the
    # escalation path pass a small kill_after_s so the test does not wait 60s.
    return f"timeout --signal=TERM --kill-after={kill_after_s} {timeout_s} "


def test_hanging_dump_is_bounded_by_timeout():
    # A dump that would hang forever must be killed within the cap and report
    # timeout's exit code 124 - not run unbounded until the job watchdog fires.
    cap = 2
    start = time.monotonic()
    res = subprocess.run(
        _prefix(cap) + "sleep 30",
        shell=True,
        executable="/bin/bash",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    elapsed = time.monotonic() - start
    assert res.returncode == 124, (
        f"expected timeout exit 124, got {res.returncode}; the dump was not bounded"
    )
    assert elapsed < 15, (
        f"command took {elapsed:.1f}s (>= 15s); timeout did not enforce the {cap}s cap"
    )


def test_without_timeout_the_dump_runs_unbounded():
    # Demonstrate the pre-fix behavior: without the timeout prefix the same
    # hanging command runs to completion (here a short sleep stands in for a
    # dump that would hang for the rest of the 9000s budget).
    start = time.monotonic()
    res = subprocess.run(
        "sleep 3",
        shell=True,
        executable="/bin/bash",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    elapsed = time.monotonic() - start
    assert res.returncode == 0
    assert elapsed >= 3, (
        f"sleep returned after {elapsed:.1f}s; expected it to run unbounded (>= 3s)"
    )


def test_term_ignoring_dump_is_killed_and_reports_137():
    # Worst case: a dump that ignores SIGTERM (e.g. a child stuck in an
    # uninterruptible section, or one that traps TERM). timeout escalates to
    # SIGKILL after --kill-after and the wrapper exits 128+9 = 137, NOT 124.
    # The fix must still classify this as a timeout, so 137 is asserted here and
    # in _annotate_timeout's exit-code set (see the guard test below).
    cap = 1
    start = time.monotonic()
    # Run through the default shell and in the `cd ... && timeout ...` shape used
    # by dump_system_tables (via Shell.get_res_stdout_stderr), so the wrapping
    # shell survives and surfaces timeout's 137 exit code (the exit code the
    # production code inspects), not the raw SIGKILL.
    res = subprocess.run(
        "cd . && " + _prefix(cap, kill_after_s=1) + 'sh -c \'trap "" TERM; sleep 30\'',
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    elapsed = time.monotonic() - start
    assert res.returncode == 137, (
        f"expected escalation exit 137, got {res.returncode}; the TERM-ignoring "
        "dump was not killed via --kill-after"
    )
    assert elapsed < 15, (
        f"command took {elapsed:.1f}s (>= 15s); --kill-after did not enforce the cap"
    )


def test_fast_dump_passes_through_untouched():
    # A dump that finishes well within the cap must succeed unchanged.
    res = subprocess.run(
        _prefix(60) + "echo ok",
        shell=True,
        executable="/bin/bash",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert res.returncode == 0
    assert res.stdout.strip() == "ok"


def test_production_code_bounds_each_dump_with_timeout():
    # Guard against a regression that drops the timeout wrapper: the source must
    # build the timeout prefix from the class constant and apply it to the dump.
    src = _SRC.read_text()
    assert "DUMP_SYSTEM_TABLE_TIMEOUT" in src
    # --verbose is required so timeout prints its own KILL diagnostic (used to
    # disambiguate a 137 escalation from an OOM/external SIGKILL).
    assert "timeout --verbose --signal=TERM --kill-after=60" in src
    assert "{dump_prefix}clickhouse local" in src
    # Both timeout expiry codes must be classified: 124 (child died on SIGTERM)
    # and 137 (SIGTERM-ignoring child escalated to SIGKILL via --kill-after).
    assert "_TIMEOUT_EXIT_CODES = (124, 137)" in src
    # The annotation helper must be applied to every dump branch (replica 0/1/2).
    assert src.count("self._annotate_timeout(res, stderr)") == 3


# --- info-only bounded timeout on minio_* diagnostic tables ------------------
#
# A bounded 600s timeout on system.minio_audit_logs / minio_server_logs is
# expected volume on s3 runs (minio's own webhook-fed operational logs), not a
# ClickHouse bug, so it must stay VISIBLE in the report but not turn the
# "Scraping system tables" check FAIL. Every other dump failure (real CH system
# tables, non-timeout minio errors, too-many-rows, replica dumps) is a genuine
# signal and still fails the check.

import importlib

_MODULE = None


def _load_proc_class():
    global _MODULE
    if _MODULE is None:
        import sys

        sys.path.insert(0, str(_REPO_ROOT))
        _MODULE = importlib.import_module("ci.jobs.scripts.clickhouse_proc")
    return _MODULE.ClickHouseProc


# `timeout --verbose` prints exactly this to stderr when IT escalates to
# SIGKILL after --kill-after. It is the proof that a 137 exit came from our
# wrapper, not from an OOM/external SIGKILL of `clickhouse local`.
_KILL_DIAG = "timeout: sending signal KILL to command 'clickhouse'"


def test_timeout_wrapper_expired_distinguishes_137_kill_source():
    # 124 is an unambiguous timeout (child died on the initial SIGTERM).
    # 137 is ambiguous: our own `timeout --kill-after` escalation exits 137, but
    # so does an OOM/external SIGKILL of the wrapped command. Only trust 137 as a
    # timeout when timeout's --verbose KILL diagnostic is present in stderr.
    proc_cls = _load_proc_class()
    e = proc_cls._timeout_wrapper_expired
    assert e(124, "") is True
    assert e(124, "anything") is True
    # 137 WITH timeout's own KILL diagnostic -> our wrapper escalated -> timeout
    assert e(137, "timeout: sending signal TERM to command 'clickhouse'\n" + _KILL_DIAG) is True
    # 137 WITHOUT the diagnostic -> OOM/external SIGKILL -> NOT a timeout
    assert e(137, "") is False
    assert e(137, "Killed") is False  # bare shell "Killed" is not proof
    # non-timeout exit codes are never a timeout
    assert e(1, _KILL_DIAG) is False
    assert e(0, "") is False


def test_info_only_classifier_matches_only_proven_minio_timeouts():
    proc_cls = _load_proc_class()
    m = proc_cls._is_info_only_dump_failure
    # minio_* + 124 -> unambiguous timeout -> info-only
    assert m("minio_audit_logs", 124, "") is True
    assert m("minio_server_logs", 124, "") is True
    # minio_* + 137 WITH timeout's KILL diagnostic -> proven timeout -> info-only
    assert m("minio_audit_logs", 137, _KILL_DIAG) is True
    # minio_* + 137 WITHOUT the diagnostic (OOM/external kill) -> NOT info-only
    assert m("minio_audit_logs", 137, "") is False
    # minio_* but a NON-timeout error (e.g. real dump error) -> NOT info-only
    assert m("minio_audit_logs", 1, "") is False
    assert m("minio_audit_logs", 0, "") is False
    # a real CH system table timing out is NOT info-only -> still a real failure
    assert m("query_log", 124, "") is False
    assert m("trace_log", 137, _KILL_DIAG) is False
    assert m("part_log", 1, "") is False


def test_source_makes_minio_timeout_info_only_but_still_visible():
    # The production code must record info for every failure (so the report shows
    # it) yet flip the check to FAIL only on a genuine failure, gated by the
    # real_failure flag and the info-only classifier.
    src = _SRC.read_text()
    assert "def _is_info_only_dump_failure(cls, table, res, stderr):" in src
    assert 'return "minio" in table and cls._timeout_wrapper_expired(res, stderr)' in src
    # The 137 exit code must NOT be blindly trusted: it is info-only only when
    # timeout's own --verbose KILL diagnostic proves the wrapper sent SIGKILL.
    assert 'timeout --verbose' in src
    assert '_TIMEOUT_KILL_DIAG = "sending signal KILL to command"' in src
    assert "def _timeout_wrapper_expired(cls, res, stderr):" in src
    # A real_failure flag drives the final FAIL decision, not merely the presence
    # of info -- otherwise an info-only minio timeout would still redden the check.
    assert "real_failure = False" in src
    assert "if real_failure:" in src
    assert "scraping_system_table.set_status(Result.Status.FAIL)" in src
    # The dump-failure branch must consult the classifier and only set
    # real_failure when the failure is not info-only.
    assert "info_only = self._is_info_only_dump_failure(table, res, stderr)" in src
    assert "if not info_only:" in src


def test_dump_only_runs_on_already_failed_jobs():
    # Caller-wiring context (clickhouse-gh[bot] Finding A). The ONLY publisher of
    # the "Scraping system tables" result is functional_tests.py's Collect-logs
    # stage, and it dumps system tables only when the job already failed:
    #     CH.prepare_logs(all=test_result and not test_result.is_ok())
    # `dump_system_tables` runs inside prepare_logs' `if all:` block, so on a
    # green job it never runs and never produces a Scraping result at all. The
    # reclassification therefore cannot, by itself, keep an otherwise-green PR
    # green -- there is nothing to reclassify. Its real effect is on an
    # already-red job: a bounded minio_* timeout no longer adds a spurious extra
    # failed sub-result (which would otherwise inflate the failure count past the
    # <4 "do not block pipeline" threshold and muddy triage). This test pins that
    # gating so a future refactor cannot silently start dumping on green jobs.
    ft = (_REPO_ROOT / "ci" / "jobs" / "functional_tests.py").read_text()
    assert "CH.prepare_logs(all=test_result and not test_result.is_ok(), info=info)" in ft
    proc = _SRC.read_text()
    # dump_system_tables is reached only through prepare_logs' `if all:` branch.
    assert "def prepare_logs(self, info, all=False):" in proc
    assert "if all:" in proc
    assert "res += self.dump_system_tables()" in proc


def _decide(failures):
    # Mirror dump_system_tables' per-table decision using the REAL classifier and
    # the REAL Result API: record info for every failure, but only flip FAIL on a
    # genuine (non-info-only) one. `failures` is a list of (table, res, stderr).
    proc_cls = _load_proc_class()
    from ci.praktika.result import Result

    result = Result(name="Scraping system tables", status=Result.Status.OK)
    real_failure = False
    for table, res, stderr in failures:
        result.set_info(f"Failed to dump system table: {table}")
        if not proc_cls._is_info_only_dump_failure(table, res, stderr):
            real_failure = True
    if result.info and real_failure:
        result.set_status(Result.Status.FAIL)
    return result


def test_only_a_minio_timeout_keeps_the_check_green_but_visible():
    # Direction A: an already-red job whose only dump problem is a bounded 600s
    # timeout on minio_audit_logs must not add a Scraping FAIL, with the detail
    # still recorded. Covers both the 124 case and the proven-137 case.
    from ci.praktika.result import Result

    result = _decide([("minio_audit_logs", 124, "")])
    assert result.status == Result.Status.OK
    assert "minio_audit_logs" in result.info  # still visible in the report

    result = _decide([("minio_server_logs", 137, _KILL_DIAG)])
    assert result.status == Result.Status.OK
    assert "minio_server_logs" in result.info


def test_a_real_system_table_failure_still_fails_the_check():
    # Direction B: a genuine failure (a real CH system table, a minio table
    # failing for a non-timeout reason, or a minio table 137 that is actually an
    # OOM/external SIGKILL rather than our wrapper's escalation) must still FAIL,
    # even alongside an info-only minio timeout.
    from ci.praktika.result import Result

    assert _decide([("query_log", 124, "")]).status == Result.Status.FAIL
    assert _decide([("minio_audit_logs", 1, "")]).status == Result.Status.FAIL
    # 137 with no KILL diagnostic = OOM/external kill of clickhouse local -> FAIL
    assert _decide([("minio_audit_logs", 137, "")]).status == Result.Status.FAIL
    assert (
        _decide([("minio_audit_logs", 124, ""), ("part_log", 137, _KILL_DIAG)]).status
        == Result.Status.FAIL
    )
