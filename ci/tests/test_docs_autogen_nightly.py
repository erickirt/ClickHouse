import os
import sys
from types import SimpleNamespace

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../.."))

from ci.jobs import docs_autogen_nightly


def test_current_base_branch_accepts_current_master(monkeypatch):
    checks = []
    outputs = {
        "git rev-parse HEAD": "abc123\n",
        "git rev-parse FETCH_HEAD": "abc123\n",
    }

    monkeypatch.setattr(
        docs_autogen_nightly,
        "Info",
        lambda: SimpleNamespace(git_branch=docs_autogen_nightly.BASE_BRANCH),
    )
    monkeypatch.setattr(
        docs_autogen_nightly.Shell,
        "check",
        lambda command, **kwargs: checks.append((command, kwargs)) or True,
    )
    monkeypatch.setattr(
        docs_autogen_nightly.Shell,
        "get_output",
        lambda command: outputs[command],
    )

    assert docs_autogen_nightly.on_current_base_branch()
    assert checks == [
        (
            "git fetch --no-tags origin master",
            {"verbose": True},
        )
    ]


def test_current_base_branch_rejects_stale_master(monkeypatch, capsys):
    outputs = {
        "git rev-parse HEAD": "old123\n",
        "git rev-parse FETCH_HEAD": "new456\n",
    }

    monkeypatch.setattr(
        docs_autogen_nightly,
        "Info",
        lambda: SimpleNamespace(git_branch=docs_autogen_nightly.BASE_BRANCH),
    )
    monkeypatch.setattr(
        docs_autogen_nightly.Shell,
        "check",
        lambda *_args, **_kwargs: True,
    )
    monkeypatch.setattr(
        docs_autogen_nightly.Shell,
        "get_output",
        lambda command: outputs[command],
    )

    assert not docs_autogen_nightly.on_current_base_branch()
    assert (
        "HEAD (old123) is not the current 'master' tip (new456)"
        in capsys.readouterr().err
    )


def test_current_base_branch_rejects_feature_branch_before_fetch(monkeypatch):
    monkeypatch.setattr(
        docs_autogen_nightly,
        "Info",
        lambda: SimpleNamespace(git_branch="feature"),
    )

    def unexpected_call(*_args, **_kwargs):
        raise AssertionError(
            "workflow fetched or mutated state before checking the branch"
        )

    monkeypatch.setattr(docs_autogen_nightly.Shell, "check", unexpected_call)
    monkeypatch.setattr(docs_autogen_nightly.Shell, "get_output", unexpected_call)

    assert not docs_autogen_nightly.on_current_base_branch()


def test_regenerate_runs_all_generator_families(monkeypatch):
    checks = []
    monkeypatch.setattr(
        docs_autogen_nightly.Shell,
        "check",
        lambda command, **kwargs: checks.append((command, kwargs)) or True,
    )

    assert docs_autogen_nightly.regenerate()
    assert len(checks) == 1
    command, kwargs = checks[0]
    assert "autogenerate_docs.py --write" in command
    assert "--binary ci/tmp/clickhouse" in command
    assert "--docs-dir docs" in command
    assert "--only" not in command
    assert kwargs == {"verbose": True}


def test_push_uses_shared_git_helper(monkeypatch):
    pushes = []
    monkeypatch.setattr(
        docs_autogen_nightly,
        "Info",
        lambda: SimpleNamespace(repo_name="ClickHouse/ClickHouse"),
    )
    monkeypatch.setattr(
        docs_autogen_nightly.Git,
        "push",
        lambda *args, **kwargs: pushes.append((args, kwargs)) or True,
    )

    assert docs_autogen_nightly._push_branch()
    assert pushes == [
        (
            ("ClickHouse/ClickHouse", "HEAD:refs/heads/robot/docs-autogen"),
            {"force": True},
        )
    ]
