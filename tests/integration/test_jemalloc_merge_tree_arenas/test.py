#!/usr/bin/env python3

# Exercises the `jemalloc_merge_tree_arenas` server setting, which controls the dedicated
# jemalloc arena pool for long-lived MergeTree metadata. It is a startup-only server setting, so
# each value needs its own server instance. We assert:
#   - the setting is read (system.server_settings),
#   - the resulting arena count is exposed via jemalloc.mergetree_arena.count and matches the value
#     (0 disabled, 1 single, N sharded, capped at the CPU core count),
#   - routing follows the count (disabled -> no active_bytes metric; a pool -> arena fills up).

import pytest

from helpers.cluster import ClickHouseCluster

cluster = ClickHouseCluster(__file__)

node_disabled = cluster.add_instance("node_disabled", main_configs=["configs/disabled.xml"])
node_single = cluster.add_instance("node_single", main_configs=["configs/single.xml"])
node_pool = cluster.add_instance("node_pool", main_configs=["configs/pool.xml"])
node_capped = cluster.add_instance("node_capped", main_configs=["configs/capped.xml"])


@pytest.fixture(scope="module")
def started_cluster():
    try:
        cluster.start()
        yield cluster
    finally:
        cluster.shutdown()


def jemalloc_built_in(node):
    return (
        node.query(
            "SELECT value IN ('ON', '1') FROM system.build_options WHERE name = 'USE_JEMALLOC'"
        ).strip()
        == "1"
    )


def configured_value(node):
    return int(
        node.query(
            "SELECT value FROM system.server_settings WHERE name = 'jemalloc_merge_tree_arenas'"
        ).strip()
    )


def arena_count(node):
    node.query("SYSTEM RELOAD ASYNCHRONOUS METRICS")
    return int(
        node.query(
            "SELECT value FROM system.asynchronous_metrics WHERE metric = 'jemalloc.mergetree_arena.count'"
        ).strip()
    )


def num_cpus(node):
    return int(node.exec_in_container(["nproc"]).strip())


def test_setting_is_read(started_cluster):
    assert configured_value(node_disabled) == 0
    assert configured_value(node_single) == 1
    assert configured_value(node_pool) == 4
    assert configured_value(node_capped) == 1000000


def test_arena_count_matches_setting(started_cluster):
    if not jemalloc_built_in(node_single):
        pytest.skip("built without jemalloc")

    assert arena_count(node_disabled) == 0
    assert arena_count(node_single) == 1
    # Capped at the number of CPU cores the container sees.
    assert arena_count(node_pool) == min(4, num_cpus(node_pool))
    # A value far above the core count collapses to the core count (<= MAX_CPUS), proving the cap.
    capped = arena_count(node_capped)
    assert 1 <= capped <= 1024
    assert capped < 1000000


def test_disabled_does_not_route_to_a_dedicated_arena(started_cluster):
    if not jemalloc_built_in(node_disabled):
        pytest.skip("built without jemalloc")

    node_disabled.query("DROP TABLE IF EXISTS t SYNC")
    node_disabled.query("CREATE TABLE t (a UInt64, b String) ENGINE = MergeTree ORDER BY a")
    node_disabled.query("INSERT INTO t SELECT number, toString(number) FROM numbers(100000)")
    node_disabled.query("SYSTEM RELOAD ASYNCHRONOUS METRICS")

    # With the pool disabled, the per-arena byte metrics are not emitted at all.
    assert (
        node_disabled.query(
            "SELECT count() FROM system.asynchronous_metrics WHERE metric = 'jemalloc.mergetree_arena.active_bytes'"
        ).strip()
        == "0"
    )


def test_pool_arena_accumulates(started_cluster):
    if not jemalloc_built_in(node_pool):
        pytest.skip("built without jemalloc")

    node_pool.query("DROP TABLE IF EXISTS t SYNC")
    node_pool.query("CREATE TABLE t (a UInt64, b String) ENGINE = MergeTree ORDER BY a")
    node_pool.query("INSERT INTO t SELECT number, toString(number) FROM numbers(100000)")
    node_pool.query("SYSTEM RELOAD ASYNCHRONOUS METRICS")

    active_bytes = int(
        node_pool.query(
            "SELECT value FROM system.asynchronous_metrics WHERE metric = 'jemalloc.mergetree_arena.active_bytes'"
        ).strip()
    )
    assert active_bytes > 0
