-- Dropping a column must not abort with LOGICAL_ERROR "No set is registered for key"
-- when the table has an ALIAS column referencing another ALIAS column that uses an IN
-- expression. Validation expands ALIAS expressions via PlannerActionsVisitor, so the IN
-- set must be registered (collectSets) before collectSourceColumns runs.

DROP TABLE IF EXISTS t_alias_in_set;

CREATE TABLE t_alias_in_set
(
    id UInt64,
    category String,
    extra UInt32 DEFAULT 0,
    is_special UInt8 ALIAS category IN ('electronics', 'clothing', 'food'),
    label String ALIAS if(is_special, 'YES', 'NO')
)
ENGINE = MergeTree()
ORDER BY id;

ALTER TABLE t_alias_in_set DROP COLUMN extra;

INSERT INTO t_alias_in_set (id, category) VALUES (1, 'electronics'), (2, 'other');
SELECT id, is_special, label FROM t_alias_in_set ORDER BY id;

ALTER TABLE t_alias_in_set DROP COLUMN IF EXISTS nonexistent_col;

DROP TABLE t_alias_in_set;
