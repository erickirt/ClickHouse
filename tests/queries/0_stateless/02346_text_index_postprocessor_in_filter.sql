-- Tests the filter-only postprocessor hybrid fast path for stop-word filters spelled as
-- if(token IN (...), '', token), NOT IN, an array right-hand side, and the equivalent
-- multiIf / CASE form. All spellings must drop the same tokens during index build.

SET allow_experimental_full_text_index = 1;

DROP TABLE IF EXISTS tab_in;
DROP TABLE IF EXISTS tab_notin;
DROP TABLE IF EXISTS tab_array;
DROP TABLE IF EXISTS tab_multiif;

SELECT '1. if(token IN (tuple)): listed stop words dropped';
CREATE TABLE tab_in (id UInt32, s String,
    INDEX idx(s) TYPE text(tokenizer = 'splitByNonAlpha', postprocessor = if(s IN ('the', 'a', 'is'), '', s)))
ENGINE = MergeTree ORDER BY id;
INSERT INTO tab_in VALUES (1, 'the quick brown fox'), (2, 'a fox is here'), (3, 'is the end');
SELECT arrayStringConcat(arraySort(groupArray(token)), ' ') FROM mergeTreeTextIndex(currentDatabase(), tab_in, idx);
SELECT count() FROM tab_in WHERE hasToken(s, 'fox');
SELECT count() FROM tab_in WHERE hasToken(s, 'end');

SELECT '2. if(token NOT IN (keep-set)): only the keep-set survives';
CREATE TABLE tab_notin (id UInt32, s String,
    INDEX idx(s) TYPE text(tokenizer = 'splitByNonAlpha', postprocessor = if(s NOT IN ('the', 'fox'), '', s)))
ENGINE = MergeTree ORDER BY id;
INSERT INTO tab_notin VALUES (1, 'the quick brown fox'), (2, 'a fox is here'), (3, 'is the end');
SELECT arrayStringConcat(arraySort(groupArray(token)), ' ') FROM mergeTreeTextIndex(currentDatabase(), tab_notin, idx);

SELECT '3. if(token IN (array)): array right-hand side, same as tuple';
CREATE TABLE tab_array (id UInt32, s String,
    INDEX idx(s) TYPE text(tokenizer = 'splitByNonAlpha', postprocessor = if(s IN ['the', 'a', 'is'], '', s)))
ENGINE = MergeTree ORDER BY id;
INSERT INTO tab_array VALUES (1, 'the quick brown fox'), (2, 'a fox is here'), (3, 'is the end');
SELECT arrayStringConcat(arraySort(groupArray(token)), ' ') FROM mergeTreeTextIndex(currentDatabase(), tab_array, idx);

SELECT '4. multiIf(token IN (tuple)): CASE spelling drops the same tokens';
CREATE TABLE tab_multiif (id UInt32, s String,
    INDEX idx(s) TYPE text(tokenizer = 'splitByNonAlpha', postprocessor = multiIf(s IN ('the', 'a', 'is'), '', s)))
ENGINE = MergeTree ORDER BY id;
INSERT INTO tab_multiif VALUES (1, 'the quick brown fox'), (2, 'a fox is here'), (3, 'is the end');
SELECT arrayStringConcat(arraySort(groupArray(token)), ' ') FROM mergeTreeTextIndex(currentDatabase(), tab_multiif, idx);

DROP TABLE tab_in;
DROP TABLE tab_notin;
DROP TABLE tab_array;
DROP TABLE tab_multiif;
