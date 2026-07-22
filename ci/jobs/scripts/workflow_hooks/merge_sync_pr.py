import re
import traceback

from praktika.utils import Shell

SYNC_REPO = "ClickHouse/clickhouse-private"

# The merge queue can merge several PRs in a single batch, so a single push to
# master may contain multiple merge commits, each corresponding to a different
# upstream PR (and therefore a different Sync PR). Look back this many commits on
# master to make sure all of them get their Sync PRs merged, not just the PR for
# the latest commit.
NUM_COMMITS = 5


def get_linked_pr_numbers():
    """
    Extract linked PR numbers from the last NUM_COMMITS commits on master.

    Merge commits produced by the merge queue look like:
        Merge pull request #77106 from XXXX
    Uses --first-parent so only the merge commits on master are inspected, not
    the individual commits from the merged branches.
    """
    raw = Shell.get_output(
        f"git log --first-parent -n {NUM_COMMITS} --format=%s HEAD",
        verbose=True,
    )
    pr_numbers = []
    for line in raw.splitlines():
        match = re.search(r"pull request #(\d+)", line)
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
        print(
            f"WARNING: Failed to retrieve Sync PR list for pr {linked_pr_number} after retries - skipping merge"
        )
        return

    sync_pr_numbers = [n.strip() for n in raw.splitlines() if n.strip()]

    if len(sync_pr_numbers) == 0:
        print(f"WARNING: No open Sync PR found for pr {linked_pr_number} - skipping merge")
        return

    if len(sync_pr_numbers) > 1:
        print(
            f"WARNING: Expected at most one open Sync PR for branch sync-upstream/pr/{linked_pr_number}, "
            f"found {len(sync_pr_numbers)}: {sync_pr_numbers} - skipping merge"
        )
        return

    sync_pr_number = sync_pr_numbers[0]
    if not sync_pr_number.isdigit() or not int(sync_pr_number):
        print(f"WARNING: Failed to retrieve Sync PR number for pr {linked_pr_number}")
        return

    if not Shell.check(
        f"gh pr ready {sync_pr_number} --repo {SYNC_REPO}", verbose=True, retries=5
    ):
        print(f"WARNING: Failed to set Sync PR {sync_pr_number} as ready")
        return

    if not Shell.check(
        f"gh pr merge {sync_pr_number} --repo {SYNC_REPO} --merge",
        verbose=True,
        retries=5,
    ):
        print(f"WARNING: Failed to merge Sync PR {sync_pr_number}")
        return

    print(f"Sync PR {sync_pr_number} merged (for pr {linked_pr_number})")


def check():
    linked_pr_numbers = get_linked_pr_numbers()

    if not linked_pr_numbers:
        print(
            f"WARNING: No linked PR numbers found in the last {NUM_COMMITS} commits - skipping merge"
        )
        return

    print(f"Found linked PR numbers to sync: {linked_pr_numbers}")
    for linked_pr_number in linked_pr_numbers:
        merge_sync_pr(linked_pr_number)


if __name__ == "__main__":
    try:
        check()
    except Exception:
        traceback.print_exc()
