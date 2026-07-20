-- ALTER validation and mutations must not abort with LOGICAL_ERROR "No set is registered
-- for key" when the table has an ALIAS column referencing another ALIAS column that uses an
-- IN expression. Expanding such ALIAS expressions runs PlannerActionsVisitor, which resolves
-- IN via the prepared sets, so the sets must be registered (collectSets) before the columns
-- are collected. Covers the DROP COLUMN validator and the DELETE/UPDATE mutation paths.

SET mutations_sync = 2;

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

INSERT INTO t_alias_in_set (id, category) VALUES (1, 'electronics'), (2, 'other'), (3, 'food');

-- DROP COLUMN validation expands ALIAS expressions (AlterCommands::validate).
ALTER TABLE t_alias_in_set DROP COLUMN extra;
SELECT 'after drop', id, is_special, label FROM t_alias_in_set ORDER BY id;

-- Mutation predicate references ALIAS -> ALIAS -> IN (MutationsInterpreter).
ALTER TABLE t_alias_in_set DELETE WHERE label = 'YES';
SELECT 'after delete', id, is_special, label FROM t_alias_in_set ORDER BY id;

-- Mutation update value references ALIAS -> ALIAS -> IN (MutationsInterpreter).
ALTER TABLE t_alias_in_set UPDATE category = if(is_special, 'clothing', 'food') WHERE id = 2;
SELECT 'after update', id, is_special, label FROM t_alias_in_set ORDER BY id;

-- Lightweight DELETE goes through the same mutation preparation.
DELETE FROM t_alias_in_set WHERE label = 'YES';
SELECT 'after lightweight delete', count() FROM t_alias_in_set;

ALTER TABLE t_alias_in_set DROP COLUMN IF EXISTS nonexistent_col;

DROP TABLE t_alias_in_set;
