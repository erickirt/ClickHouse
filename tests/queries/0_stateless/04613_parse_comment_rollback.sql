-- Regression test: `parseComment` must roll back `pos` when `COMMENT` is consumed but the
-- following string literal fails to parse. Otherwise `CREATE VIEW v COMMENT AS SELECT 1`
-- silently succeeds (the view is created without a comment) instead of raising a syntax error.
DROP VIEW IF EXISTS v_04613;
CREATE VIEW v_04613 COMMENT AS SELECT 1; -- { clientError SYNTAX_ERROR }
SELECT count() FROM system.tables WHERE name = 'v_04613' AND database = currentDatabase();
DROP VIEW IF EXISTS v_04613;
