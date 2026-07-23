-- Query parameter substitution rewrites `{param:Type}` into `_CAST(value, 'Type')`, and the
-- serialized mutation entry must be parseable back when it is re-read from disk on table load.

DROP TABLE IF EXISTS t_mutation_param;

CREATE TABLE t_mutation_param (id UInt64, d Date, flag Nullable(Bool))
ENGINE = MergeTree PARTITION BY toYYYYMMDD(d) ORDER BY id;

INSERT INTO t_mutation_param SELECT number, '2026-06-24', NULL FROM numbers(10);
INSERT INTO t_mutation_param SELECT number + 100, '2026-06-25', NULL FROM numbers(10);

SET param_day = '20260624';
SET param_date = '2026-06-25';

ALTER TABLE t_mutation_param UPDATE flag = true IN PARTITION {day:UInt32} WHERE toYYYYMMDD(d) = {day:UInt32} SETTINGS mutations_sync = 2;

SELECT countIf(flag), count() FROM t_mutation_param;

-- The partition can also be specified as an explicitly written cast of a literal.
ALTER TABLE t_mutation_param UPDATE flag = false IN PARTITION _CAST(20260624, 'UInt32') WHERE 1 SETTINGS mutations_sync = 2;

-- Arbitrary expressions are still not allowed in the partition.
ALTER TABLE t_mutation_param UPDATE flag = true IN PARTITION toYYYYMMDD({date:Date}) WHERE 1 SETTINGS mutations_sync = 2; -- { clientError SYNTAX_ERROR }

SELECT countIf(flag), count() FROM t_mutation_param;

-- Make sure the mutation entries written to disk can be parsed back on table load.
DETACH TABLE t_mutation_param;
ATTACH TABLE t_mutation_param;

SELECT countIf(flag), count() FROM t_mutation_param;

ALTER TABLE t_mutation_param DROP PARTITION {day:UInt32};

SELECT count() FROM t_mutation_param;

DROP TABLE t_mutation_param;
