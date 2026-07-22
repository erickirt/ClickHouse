-- Tags: shard

-- A columnless remote()/Remote/Distributed table infers its schema from the remote side.
-- If the inference yields a Nullable(Nothing) column (e.g. a view doing SELECT NULL),
-- CREATE must reject it, matching the check done on ATTACH/startup load, instead of
-- persisting metadata that can never be loaded back (issue #111242).

DROP VIEW IF EXISTS v_null_04626;
DROP TABLE IF EXISTS t_rf_04626;
DROP TABLE IF EXISTS t_remote_04626;
DROP TABLE IF EXISTS t_dist_04626;
DROP TABLE IF EXISTS base_04626;
DROP TABLE IF EXISTS t_ok_04626;

CREATE VIEW v_null_04626 AS SELECT NULL AS c0;

-- Columnless CREATE AS remote() over the Nullable(Nothing) view: rejected at CREATE.
CREATE TABLE t_rf_04626 AS remote('127.0.0.1', currentDatabase(), 'v_null_04626'); -- { serverError DATA_TYPE_CANNOT_BE_USED_IN_TABLES }

-- Columnless ENGINE = Remote over the same view (the reproducer from the issue): rejected at CREATE.
CREATE TABLE t_remote_04626 ENGINE = Remote('127.0.0.1', currentDatabase(), 'v_null_04626'); -- { serverError DATA_TYPE_CANNOT_BE_USED_IN_TABLES }

-- Columnless ENGINE = Distributed over the same view: rejected at CREATE.
CREATE TABLE t_dist_04626 ENGINE = Distributed('test_shard_localhost', currentDatabase(), 'v_null_04626'); -- { serverError DATA_TYPE_CANNOT_BE_USED_IN_TABLES }

-- None of the poisoned tables must have been persisted.
SELECT count() FROM system.tables WHERE database = currentDatabase() AND name IN ('t_rf_04626', 't_remote_04626', 't_dist_04626');

-- Control: columnless remote() over a normal table still works.
CREATE TABLE base_04626 (a UInt32, b String) ENGINE = Memory;
INSERT INTO base_04626 VALUES (1, 'x');
CREATE TABLE t_ok_04626 AS remote('127.0.0.1', currentDatabase(), 'base_04626');
SELECT a, b FROM t_ok_04626 ORDER BY a;

DROP TABLE t_ok_04626;
DROP TABLE base_04626;
DROP VIEW v_null_04626;
