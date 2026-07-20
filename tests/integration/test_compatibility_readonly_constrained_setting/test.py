import pytest

from helpers.cluster import ClickHouseCluster

cluster = ClickHouseCluster(__file__)
node = cluster.add_instance("node", user_configs=["configs/users.xml"])

# Any version before `s3_allow_server_credentials_in_user_queries` was introduced (26.7), so that
# `compatibility` reverts it to its old default and the client transmits that reverted value.
OLD_COMPATIBILITY = "24.1"

SETTING = "s3_allow_server_credentials_in_user_queries"


@pytest.fixture(scope="module")
def start_cluster():
    try:
        cluster.start()
        yield cluster
    finally:
        cluster.shutdown()


def test_old_compatibility_keeps_readonly_pinned_setting(start_cluster):
    # The native client resolves `compatibility` locally and sends the reverted value of the pinned
    # setting as an explicit change. With the pin in place the query must still succeed, and the
    # pinned value must stay in force.
    assert node.query("SELECT 1", settings={"compatibility": OLD_COMPATIBILITY}).strip() == "1"
    assert (
        node.query(
            f"SELECT getSetting('{SETTING}')", settings={"compatibility": OLD_COMPATIBILITY}
        ).strip()
        == "false"
    )


def test_explicit_override_of_readonly_setting_is_rejected(start_cluster):
    # A genuine attempt to change the read-only setting (no `compatibility` involved) is still refused.
    error = node.query_and_get_error("SELECT 1", settings={SETTING: 1})
    assert "should not be changed" in error


def test_http_compatibility_unaffected(start_cluster):
    # Over HTTP `compatibility` is resolved server-side against the already-pinned value, so this path
    # was never broken; guard it so the native and HTTP paths stay consistent.
    assert (
        node.http_query("SELECT 1", params={"compatibility": OLD_COMPATIBILITY}).strip() == "1"
    )
