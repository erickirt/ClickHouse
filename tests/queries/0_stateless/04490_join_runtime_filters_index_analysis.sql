DROP TABLE IF EXISTS sales1;
DROP TABLE IF EXISTS sales2;

CREATE TABLE sales1
(
    id UInt64,
    country String,
    amount UInt64,
    INDEX idx_country country TYPE set(100) GRANULARITY 1
)
ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 16;

CREATE TABLE sales2
(
    id UInt64,
    country String,
    region String
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO sales1 SELECT number, ['US', 'IN', 'JP', 'ZM'][number % 4 + 1], number * 10 FROM numbers(200);
INSERT INTO sales2 SELECT number, ['US', 'IN', 'JP', 'ZM'][number % 4 + 1], ['AMER', 'APAC', 'EMEA'][number % 3 + 1] FROM numbers(200);

SET enable_analyzer = 1;
SET enable_join_runtime_filters = 1;
SET enable_join_runtime_filters_index_analysis = 1;
SET use_skip_indexes_on_data_read = 1;
SET query_plan_join_swap_table = 'false';

-- PK join
SELECT s1.id, s1.country, s1.amount
FROM sales1 AS s1
INNER JOIN sales2 AS s2 ON s1.id = s2.id
WHERE s2.region = 'APAC'
ORDER BY s1.id;

-- skip index column in join
SELECT s1.country, count(), sum(s1.amount)
FROM sales1 AS s1
INNER JOIN sales2 AS s2 ON s1.country = s2.country
WHERE s2.region = 'EMEA'
GROUP BY s1.country
ORDER BY s1.country;

DROP TABLE IF EXISTS pe_fact;
DROP TABLE IF EXISTS pe_dim;
CREATE TABLE pe_fact (id UInt64, v UInt64) ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 16;
CREATE TABLE pe_dim (id UInt64, tag String) ENGINE = MergeTree ORDER BY id;
INSERT INTO pe_fact SELECT number, number FROM numbers(2000);
INSERT INTO pe_dim SELECT number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT d.tag, sum(f.v)
FROM pe_fact AS f
INNER JOIN pe_dim AS d ON f.id = d.id
WHERE d.tag = 'hot'
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS pe_fact2;
DROP TABLE IF EXISTS pe_dim2;
CREATE TABLE pe_fact2 (id UInt64, k UInt64, v UInt64, INDEX idx_k k TYPE minmax GRANULARITY 1)
ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 16;
CREATE TABLE pe_dim2 (k UInt64, tag String) ENGINE = MergeTree ORDER BY k;
INSERT INTO pe_fact2 SELECT number, number, number FROM numbers(2000);
INSERT INTO pe_dim2 SELECT number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT d.tag, sum(f.v)
FROM pe_fact2 AS f
INNER JOIN pe_dim2 AS d ON f.k = d.k
WHERE d.tag = 'hot'
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe_skip';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_skip' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS ckey_fact;
DROP TABLE IF EXISTS ckey_dim;
CREATE TABLE ckey_fact (a UInt64, b UInt64, v UInt64) ENGINE = MergeTree ORDER BY (a, b) SETTINGS index_granularity = 16;
CREATE TABLE ckey_dim (a UInt64, tag String) ENGINE = MergeTree ORDER BY a;
INSERT INTO ckey_fact SELECT number, number, number FROM numbers(2000);
INSERT INTO ckey_dim SELECT number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT d.tag, sum(f.v)
FROM ckey_fact AS f
INNER JOIN ckey_dim AS d ON f.a = d.a
WHERE d.tag = 'hot'
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe_ckey';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_ckey' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS str_fact;
DROP TABLE IF EXISTS str_dim;
CREATE TABLE str_fact (s String, v UInt64) ENGINE = MergeTree ORDER BY s SETTINGS index_granularity = 16;
CREATE TABLE str_dim (s String, tag String) ENGINE = MergeTree ORDER BY s;
INSERT INTO str_fact SELECT concat('k', leftPad(toString(number), 5, '0')), number FROM numbers(2000);
INSERT INTO str_dim SELECT concat('k', leftPad(toString(number), 5, '0')), if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT count(), sum(f.v)
FROM str_fact AS f
INNER JOIN str_dim AS d ON f.s = d.s
WHERE d.tag = 'hot'
FORMAT Null
SETTINGS log_comment = '04490_pe_str';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_str' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS dt_fact;
DROP TABLE IF EXISTS dt_dim;
CREATE TABLE dt_fact (d Date, v UInt64) ENGINE = MergeTree ORDER BY d SETTINGS index_granularity = 16;
CREATE TABLE dt_dim (d Date, tag String) ENGINE = MergeTree ORDER BY d;
INSERT INTO dt_fact SELECT toDate('2020-01-01') + number, number FROM numbers(2000);
INSERT INTO dt_dim SELECT toDate('2020-01-01') + number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT count(), sum(f.v)
FROM dt_fact AS f
INNER JOIN dt_dim AS d ON f.d = d.d
WHERE d.tag = 'hot'
FORMAT Null
SETTINGS log_comment = '04490_pe_dt';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_dt' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS lc_fact;
DROP TABLE IF EXISTS lc_dim;
CREATE TABLE lc_fact (s LowCardinality(String), v UInt64) ENGINE = MergeTree ORDER BY s SETTINGS index_granularity = 16;
CREATE TABLE lc_dim (s LowCardinality(String), tag String) ENGINE = MergeTree ORDER BY s;
INSERT INTO lc_fact SELECT concat('k', leftPad(toString(number), 5, '0')), number FROM numbers(2000);
INSERT INTO lc_dim SELECT concat('k', leftPad(toString(number), 5, '0')), if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT count(), sum(f.v)
FROM lc_fact AS f
INNER JOIN lc_dim AS d ON f.s = d.s
WHERE d.tag = 'hot'
FORMAT Null
SETTINGS log_comment = '04490_pe_lc';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_lc' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS bf_fact;
DROP TABLE IF EXISTS bf_dim;
CREATE TABLE bf_fact (id UInt64, k UInt64, v UInt64, INDEX idx_k k TYPE bloom_filter GRANULARITY 1)
ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 16;
CREATE TABLE bf_dim (k UInt64, tag String) ENGINE = MergeTree ORDER BY k;
INSERT INTO bf_fact SELECT number, number, number FROM numbers(2000);
INSERT INTO bf_dim SELECT number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT d.tag, sum(f.v)
FROM bf_fact AS f
INNER JOIN bf_dim AS d ON f.k = d.k
WHERE d.tag = 'hot'
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe_bf';

SYSTEM FLUSH LOGS query_log;

SELECT
    ProfileEvents['RuntimeFilterGranulesConsidered'] > 0,
    ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_bf' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS bf_fact_cap;
DROP TABLE IF EXISTS bf_dim_cap;
CREATE TABLE bf_fact_cap (id UInt64, k UInt64, v UInt64, INDEX idx_k k TYPE bloom_filter GRANULARITY 1)
ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 16;
CREATE TABLE bf_dim_cap (k UInt64, tag String) ENGINE = MergeTree ORDER BY k;
INSERT INTO bf_fact_cap SELECT number, number, number FROM numbers(2000);
INSERT INTO bf_dim_cap SELECT number, if(number < 64, 'hot', 'cold') FROM numbers(2000);

SELECT d.tag, sum(f.v)
FROM bf_fact_cap AS f
INNER JOIN bf_dim_cap AS d ON f.k = d.k
WHERE d.tag = 'hot'
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe_bf_cap', join_runtime_filter_exact_values_limit = 100;

SYSTEM FLUSH LOGS query_log;

SELECT ProfileEvents['RuntimeFilterGranulesDropped'] = 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_bf_cap' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE IF EXISTS jrf_fact;
DROP TABLE IF EXISTS jrf_dim;
CREATE TABLE jrf_fact (id UInt64, k Int32, v UInt64, INDEX idx_k k TYPE set(0) GRANULARITY 1)
ENGINE = MergeTree ORDER BY id SETTINGS index_granularity = 8192;
CREATE TABLE jrf_dim (k Int32, tag String) ENGINE = MergeTree ORDER BY k;
INSERT INTO jrf_fact SELECT number, number, number FROM numbers(50100);
-- two dense clusters with a large gap: an exact key set prunes the gap; a [min,max] range does not
INSERT INTO jrf_dim SELECT number, 'a' FROM numbers(100);
INSERT INTO jrf_dim SELECT number + 50000, 'a' FROM numbers(100);

-- join_algorithm='hash' + external-join disabled forces the single-level in-memory HashJoin
-- that converts to a FixedHashMap and publishes it as the runtime filter
SELECT d.tag, sum(f.v)
FROM jrf_fact AS f
INNER JOIN jrf_dim AS d ON f.k = d.k
GROUP BY d.tag
FORMAT Null
SETTINGS log_comment = '04490_pe_fht',
    join_algorithm = 'hash',
    max_bytes_before_external_join = 0,
    max_bytes_ratio_before_external_join = 0,
    enable_join_fixed_hash_table_conversion = 1,
    join_runtime_filter_from_fixed_hash_table = 1;

SYSTEM FLUSH LOGS query_log;

-- exact-set pruning must survive the FixedHashMap runtime filter, not degrade to a [min,max] range
SELECT ProfileEvents['RuntimeFilterGranulesDropped'] > 0
FROM system.query_log
WHERE current_database = currentDatabase() AND log_comment = '04490_pe_fht' AND type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;

DROP TABLE sales1;
DROP TABLE sales2;
DROP TABLE pe_fact;
DROP TABLE pe_dim;
DROP TABLE pe_fact2;
DROP TABLE pe_dim2;
DROP TABLE ckey_fact;
DROP TABLE ckey_dim;
DROP TABLE str_fact;
DROP TABLE str_dim;
DROP TABLE dt_fact;
DROP TABLE dt_dim;
DROP TABLE lc_fact;
DROP TABLE lc_dim;
DROP TABLE bf_fact;
DROP TABLE bf_dim;
DROP TABLE bf_fact_cap;
DROP TABLE bf_dim_cap;
DROP TABLE jrf_fact;
DROP TABLE jrf_dim;
