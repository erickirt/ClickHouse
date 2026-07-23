import json
import os
import re
import traceback
from pathlib import Path

from praktika.info import Info
from praktika.utils import Shell

SYNC_REPO = "ClickHouse/clickhouse-private"


def get_linked_pr_numbers():
    """
    Extract linked PR numbers from the GitHub push event payload.

    The merge queue can merge several PRs in a single batch, so a single push to
    master may contain multiple merge commits, each corresponding to a different
    upstream PR (and therefore a different Sync PR). The push event payload lists
    every commit in the batch under "commits", so it is a reliable source for all
    of them - unlike the head commit message or local git state, which only
    reflect the latest PR.

    Merge commits produced by the merge queue look like:
        Merge pull request #77106 from XXXX
    """
    event_file_path = os.getenv("GITHUB_EVENT_PATH", "")
    if not event_file_path or not Path(event_file_path).is_file():
        msg = f"GITHUB_EVENT_PATH is not set or missing: '{event_file_path}' - skipping Sync PR merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return []

    with open(event_file_path, "r", encoding="utf-8") as f:
        github_event = json.load(f)

    commits = github_event.get("commits", [])
    if not commits:
        msg = "No commits found in the push event payload - skipping Sync PR merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return []

    pr_numbers = []
    for commit in commits:
        message = commit.get("message", "")
        match = re.search(r"pull request #(\d+)", message)
        if match:
            pr_number = int(match.group(1))
            if pr_number not in pr_numbers:
                pr_numbers.append(pr_number)
    return pr_numbers


def merge_sync_pr(linked_pr_number):
    raw = Shell.get_output(
        f"gh pr list --state open --head sync-upstream/pr/{linked_pr_number} --repo {SYNC_REPO} --json number --jq '.[].number'",
        verbose=True,
        retries=5,
    )
    if not raw:
        msg = f"Failed to retrieve Sync PR list for pr {linked_pr_number} after retries - skipping merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    sync_pr_numbers = [n.strip() for n in raw.splitlines() if n.strip()]

    if len(sync_pr_numbers) == 0:
        msg = f"No open Sync PR found for pr {linked_pr_number} - skipping merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    if len(sync_pr_numbers) > 1:
        msg = f"Expected at most one open Sync PR for branch sync-upstream/pr/{linked_pr_number}, found {len(sync_pr_numbers)}: {sync_pr_numbers} - skipping merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    sync_pr_number = sync_pr_numbers[0]
    if not sync_pr_number.isdigit() or not int(sync_pr_number):
        msg = f"Failed to retrieve Sync PR number for pr {linked_pr_number}"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    if not Shell.check(f"gh pr ready {sync_pr_number} --repo {SYNC_REPO}", verbose=True, retries=5):
        msg = f"Failed to set Sync PR {sync_pr_number} as ready"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    if not Shell.check(
        f"gh pr merge {sync_pr_number} --repo {SYNC_REPO} --merge",
        verbose=True,
        retries=5,
    ):
        msg = f"Failed to merge Sync PR {sync_pr_number}"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    print(f"Sync PR {sync_pr_number} merged (for pr {linked_pr_number})")


def check():
    linked_pr_numbers = get_linked_pr_numbers()

    if not linked_pr_numbers:
        msg = "No linked PR numbers found in the push event - skipping Sync PR merge"
        print(f"WARNING: {msg}")
        Info().add_workflow_warning(msg)
        return

    print(f"Found linked PR numbers to sync: {linked_pr_numbers}")
    for linked_pr_number in linked_pr_numbers:
        merge_sync_pr(linked_pr_number)


if __name__ == "__main__":
    try:
        check()
    except Exception:
        traceback.print_exc()
