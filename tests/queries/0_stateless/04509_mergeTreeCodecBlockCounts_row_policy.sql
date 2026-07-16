DROP TABLE IF EXISTS t_row_policy;

CREATE TABLE t_row_policy (a UInt64, b UInt64)
ENGINE = MergeTree ORDER BY tuple()
SETTINGS min_bytes_for_wide_part = 0;

INSERT INTO t_row_policy SELECT number, number FROM numbers(1000);

CREATE ROW POLICY 04509_policy ON t_row_policy FOR SELECT USING a < 100 TO CURRENT_USER;

SELECT 'with row policy, metadata columns stay readable';
SELECT DISTINCT column FROM mergeTreeCodecBlockCounts(currentDatabase(), t_row_policy) ORDER BY column;
SELECT count() FROM t_row_policy;

SELECT 'with row policy, codec_block_counts denied';
SELECT * FROM mergeTreeCodecBlockCounts(currentDatabase(), t_row_policy); -- { serverError ACCESS_DENIED }
SELECT part_name FROM mergeTreeCodecBlockCounts(currentDatabase(), t_row_policy) WHERE mapContains(codec_block_counts, 'LZ4'); -- { serverError ACCESS_DENIED }

DROP ROW POLICY 04509_policy ON t_row_policy;

SELECT 'row policy dropped';
SELECT DISTINCT mapKeys(codec_block_counts) FROM mergeTreeCodecBlockCounts(currentDatabase(), t_row_policy);

CREATE ROW POLICY 04509_policy_none ON t_row_policy FOR SELECT USING a < 100 TO NONE;

SELECT 'row policy targeting nobody';
SELECT DISTINCT mapKeys(codec_block_counts) FROM mergeTreeCodecBlockCounts(currentDatabase(), t_row_policy);
SELECT count() FROM t_row_policy;

DROP ROW POLICY 04509_policy_none ON t_row_policy;

DROP TABLE t_row_policy;
