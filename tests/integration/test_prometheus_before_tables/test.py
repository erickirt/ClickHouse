import re
import time

import pytest
import requests

from helpers.cluster import ClickHouseCluster

cluster = ClickHouseCluster(__file__)
node = cluster.add_instance("node", main_configs=["configs/prom_conf.xml"])

LOG_FILE = "/var/log/clickhouse-server/clickhouse-server.log"


@pytest.fixture(scope="module")
def start_cluster():
    try:
        cluster.start()
        yield cluster
    finally:
        cluster.shutdown()


def first_log_line_number(pattern):
    # `grep -n` prints "<line>:<text>"; `-m1` stops at the first match.
    output = node.exec_in_container(
        ["bash", "-c", f"grep -n -m1 '{pattern}' {LOG_FILE}"]
    )
    assert output, f"log line not found: {pattern}"
    return int(output.split(":", 1)[0])


def get_metrics(retries=10):
    last_exc = None
    for _ in range(retries + 1):
        try:
            response = requests.get(
                "http://{host}:{port}/metrics".format(host=node.ip_address, port=8001),
                allow_redirects=False,
                # less than default keep-alive timeout (10 seconds)
                timeout=5,
            )
            response.raise_for_status()
            break
        except Exception as exc:
            last_exc = exc
            time.sleep(0.5)
    else:
        raise last_exc

    assert response.headers["content-type"].startswith("text/plain")

    results = {}
    for line in response.text.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([a-zA-Z_:][a-zA-Z0-9_:]+)(\{.*\})?\s+(-?[\d.eE+]+)", line)
        assert match, line
        name, _, val = match.groups()
        results[name] = float(val)
    return results


def test_prometheus_starts_before_tables_are_loaded(start_cluster):
    # A metrics-only Prometheus endpoint (no `prometheus.handlers`) is started before metadata
    # (tables) loading begins. This keeps metrics observable during the (potentially long) metadata
    # loading phase. Previously it would start only after "Loaded metadata.".
    prometheus_listen_line = first_log_line_number("Listening for Prometheus")
    loaded_metadata_line = first_log_line_number("Loaded metadata.")
    assert prometheus_listen_line < loaded_metadata_line


def test_prometheus_exposes_metrics(start_cluster):
    metrics = get_metrics()
    # Profile events and current metrics are available immediately.
    assert metrics["ClickHouseProfileEvents_Query"] >= 0
    # Asynchronous metrics are collected by a thread that is now started before tables are loaded;
    # check that they are still exposed (e.g. the server uptime).
    assert any(name.startswith("ClickHouseAsyncMetrics_") for name in metrics)


def test_system_stop_start_listen(start_cluster):
    # Although the Prometheus server is started early, it lives in the regular `servers` list, so
    # the `SYSTEM START/STOP LISTEN` contract must keep working for it.
    node.query("SYSTEM STOP LISTEN PROMETHEUS")
    with pytest.raises(requests.exceptions.ConnectionError):
        requests.get(
            "http://{host}:{port}/metrics".format(host=node.ip_address, port=8001),
            allow_redirects=False,
            timeout=5,
        )
    node.query("SYSTEM START LISTEN PROMETHEUS")
    metrics = get_metrics()
    assert metrics["ClickHouseProfileEvents_Query"] >= 0
