---
description: 'Documentation for Table Engines'
slug: /engines/table-engines/
toc_folder_title: 'Table Engines'
toc_priority: 26
toc_title: 'Introduction'
title: 'Table Engines'
---

# Table engines

The table engine (type of table) determines:

- How and where data is stored, where to write it to, and where to read it from.
- Which queries are supported, and how.
- Concurrent data access.
- Use of indexes, if present.
- Whether multithread request execution is possible.
- Data replication parameters.

## Engine families {#engine-families}

### MergeTree {#mergetree}

The most universal and functional table engines for high-load tasks. The property shared by these engines is quick data insertion with subsequent background data processing. `MergeTree` family engines support data replication (with [Replicated\*](/engines/table-engines/mergetree-family/replication) versions of engines), partitioning, secondary data-skipping indexes, and other features not supported in other engines.

Engines in the family:

| MergeTree Engines                                                                                                                         |
|-------------------------------------------------------------------------------------------------------------------------------------------|
| [MergeTree](/engines/table-engines/mergetree-family/mergetree)                                                          |
| [ReplacingMergeTree](/engines/table-engines/mergetree-family/replacingmergetree)                               |
| [SummingMergeTree](/engines/table-engines/mergetree-family/summingmergetree)                                     |
| [AggregatingMergeTree](/engines/table-engines/mergetree-family/aggregatingmergetree)                         |
| [CollapsingMergeTree](/engines/table-engines/mergetree-family/collapsingmergetree)               |
| [VersionedCollapsingMergeTree](/engines/table-engines/mergetree-family/versionedcollapsingmergetree) |
| [GraphiteMergeTree](/engines/table-engines/mergetree-family/graphitemergetree)                                  |
| [CoalescingMergeTree](/engines/table-engines/mergetree-family/coalescingmergetree)                                     |

### Log {#log}

Lightweight [engines](../../engines/table-engines/log-family/index.md) with minimum functionality. They're the most effective when you need to quickly write many small tables (up to approximately 1 million rows) and read them later as a whole.

Engines in the family:

| Log Engines                                                                |
|----------------------------------------------------------------------------|
| [TinyLog](/engines/table-engines/log-family/tinylog)       |
| [StripeLog](/engines/table-engines/log-family/stripelog) |
| [Log](/engines/table-engines/log-family/log)                   |

### Integration engines {#integration-engines}

Engines for communicating with other data storage and processing systems.

Engines in the family:

| Integration Engines                                                             |
|---------------------------------------------------------------------------------|
| [ODBC](../../engines/table-engines/integrations/odbc.md)                        |
| [JDBC](../../engines/table-engines/integrations/jdbc.md)                        |
| [MySQL](../../engines/table-engines/integrations/mysql.md)                      |
| [MongoDB](../../engines/table-engines/integrations/mongodb.md)                  |
| [Redis](../../engines/table-engines/integrations/redis.md)                      |
| [HDFS](../../engines/table-engines/integrations/hdfs.md)                        |
| [S3](../../engines/table-engines/integrations/s3.md)                            |
| [Kafka](../../engines/table-engines/integrations/kafka.md)                      |
| [EmbeddedRocksDB](../../engines/table-engines/integrations/embedded-rocksdb.md) |
| [RabbitMQ](../../engines/table-engines/integrations/rabbitmq.md)                |
| [PostgreSQL](../../engines/table-engines/integrations/postgresql.md)            |
| [S3Queue](../../engines/table-engines/integrations/s3queue.md)                  |
| [TimeSeries](../../engines/table-engines/integrations/time-series.md)           |

### Special engines {#special-engines}

Engines in the family:

| Special Engines                                               |
|---------------------------------------------------------------|
| [Distributed](/engines/table-engines/special/distributed)     |
| [Dictionary](/engines/table-engines/special/dictionary)       |
| [Merge](/engines/table-engines/special/merge)                 |
| [Executable](/engines/table-engines/special/executable)       |
| [File](/engines/table-engines/special/file)                   |
| [Null](/engines/table-engines/special/null)                   |
| [Set](/engines/table-engines/special/set)                     |
| [Join](/engines/table-engines/special/join)                   |
| [URL](/engines/table-engines/special/url)                     |
| [View](/engines/table-engines/special/view)                   |
| [Memory](/engines/table-engines/special/memory)               |
| [Buffer](/engines/table-engines/special/buffer)               |
| [External Data](/engines/table-engines/special/external-data) |
| [GenerateRandom](/engines/table-engines/special/generate)     |
| [KeeperMap](/engines/table-engines/special/keeper-map)        |
| [FileLog](/engines/table-engines/special/filelog)                                                   |

## Virtual columns {#table_engines-virtual_columns}

A virtual column is an integral table engine attribute that is defined in the engine source code.

You shouldn't specify virtual columns in the `CREATE TABLE` query, and you can't see them in `SHOW CREATE TABLE` and `DESCRIBE TABLE` query results. Virtual columns are also read-only, so you can't insert data into virtual columns.

To select data from a virtual column, you must specify its name in the `SELECT` query. `SELECT *` does not return values from virtual columns.

If you create a table with a column that has the same name as one of the table virtual columns, the virtual column becomes inaccessible. We do not recommend doing this. To help avoid conflicts, virtual column names are usually prefixed with an underscore.

- `_table` — Contains the name of the table from which data was read. Type: [String](../../sql-reference/data-types/string.md).

    Regardless of the table engine being used, each table includes a universal virtual column named `_table`.

    When querying a table with the merge table engine, you can set the constant conditions on `_table` in the `WHERE/PREWHERE` clause (for example, `WHERE _table='xyz'`). In this case the read operation is performed only for that tables where the condition on `_table` is satisfied, so the `_table` column acts as an index.

    When using queries formatted like `SELECT ... FROM (... UNION ALL ...)`, we can determine which actual table the returned rows originate from by specifying the `_table` column.
