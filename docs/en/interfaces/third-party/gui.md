---
description: 'List of third-party GUI tools and applications for working with ClickHouse'
sidebar_label: 'Visual Interfaces'
sidebar_position: 28
slug: /interfaces/third-party/gui
title: 'Visual Interfaces from Third-party Developers'
---

# Visual interfaces from third-party developers

## Open-source {#open-source}

### agx {#agx}

[agx](https://github.com/agnosticeng/agx) is a desktop application built with Tauri and SvelteKit that provides a modern interface for exploring and querying data using ClickHouse's embedded database engine (chdb).

- Leverage ch-db when running the native application.
- Can connect to a Clickhouse instance when running the web instance.
- Monaco editor so you'll feel at home.
- Multiple and evolving data visualizations.

### ch-ui {#ch-ui}

[ch-ui](https://github.com/caioricciuti/ch-ui) is a simple React.js app interface for ClickHouse databases designed for executing queries and visualizing data. Built with React and the ClickHouse client for web, it offers a sleek and user-friendly UI for easy database interactions.

Features:

- ClickHouse Integration: Easily manage connections and execute queries.
- Responsive Tab Management: Dynamically handle multiple tabs, such as query and table tabs.
- Performance Optimizations: Utilizes Indexed DB for efficient caching and state management.
- Local Data Storage: All data is stored locally in the browser, ensuring no data is sent anywhere else.

### ChartDB {#chartdb}

[ChartDB](https://chartdb.io) is a free and open-source tool for visualizing and designing database schemas, including ClickHouse, with a single query. Built with React, it provides a seamless and user-friendly experience, requiring no database credentials or signup to get started.

Features:

- Schema Visualization: Instantly import and visualize your ClickHouse schema, including ER diagrams with materialized views and standard views, showing references to tables.
- AI-Powered DDL Export: Generate DDL scripts effortlessly for better schema management and documentation.
- Multi-SQL Dialect Support: Compatible with a range of SQL dialects, making it versatile for various database environments.
- No Signup or Credentials Needed: All functionality is accessible directly in the browser, keeping it frictionless and secure.

[ChartDB Source Code](https://github.com/chartdb/chartdb).

### DataPup {#datapup}

[DataPup](https://github.com/DataPupOrg/DataPup) is a modern, AI-assisted, cross-platform database client with native ClickHouse support.

Features:

- AI-powered SQL query assistance with intelligent suggestions
- Native ClickHouse connection support with secure credential handling
- Beautiful, accessible interface with multiple themes (Light, Dark, and colorful variants)
- Advanced query result filtering and exploration
- Cross-platform support (macOS, Windows, Linux)
- Fast and responsive performance
- Open-source and MIT licensed

### ClickHouse Schema Flow Visualizer {#clickhouse-schemaflow-visualizer}

[ClickHouse Schema Flow Visualizer](https://github.com/FulgerX2007/clickhouse-schemaflow-visualizer) is a powerful open-source web application for visualizing ClickHouse table relationships using Mermaid.js diagrams. Browse databases and tables with an intuitive interface, explore table metadata with optional row counts and size information, and export interactive schema diagrams.

Features:

- Browse ClickHouse databases and tables with an intuitive interface
- Visualize table relationships with Mermaid.js diagrams
- Color-coded icons matching table types for better visualization
- View direction of data flow between tables
- Export diagrams as standalone HTML files
- Toggle metadata visibility (table rows and size information)
- Secure connection to ClickHouse with TLS support
- Responsive web interface for all devices

[ClickHouse Schema Flow Visualizer - source code](https://github.com/FulgerX2007/clickhouse-schemaflow-visualizer)

### Tabix {#tabix}

Web interface for ClickHouse in the [Tabix](https://github.com/tabixio/tabix) project.

Features:

- Works with ClickHouse directly from the browser without the need to install additional software.
- Query editor with syntax highlighting.
- Auto-completion of commands.
- Tools for graphical analysis of query execution.
- Colour scheme options.

[Tabix documentation](https://tabix.io/doc/).

### HouseOps {#houseops}

[HouseOps](https://github.com/HouseOps/HouseOps) is a UI/IDE for OSX, Linux and Windows.

Features:

- Query builder with syntax highlighting. View the response in a table or JSON view.
- Export query results as CSV or JSON.
- List of processes with descriptions. Write mode. Ability to stop (`KILL`) a process.
- Database graph. Shows all tables and their columns with additional information.
- A quick view of the column size.
- Server configuration.

The following features are planned for development:

- Database management.
- User management.
- Real-time data analysis.
- Cluster monitoring.
- Cluster management.
- Monitoring replicated and Kafka tables.

### LightHouse {#lighthouse}

[LightHouse](https://github.com/VKCOM/lighthouse) is a lightweight web interface for ClickHouse.

Features:

- Table list with filtering and metadata.
- Table preview with filtering and sorting.
- Read-only query execution.

### Redash {#redash}

[Redash](https://github.com/getredash/redash) is a platform for data visualization.

Supports for multiple data sources including ClickHouse, Redash can join results of queries from different data sources into one final dataset.

Features:

- Powerful editor of queries.
- Database explorer.
- Visualization tool that allows you to represent data in different forms.

### Grafana {#grafana}

[Grafana](https://grafana.com/grafana/plugins/grafana-clickhouse-datasource/) is a platform for monitoring and visualization.

"Grafana allows you to query, visualize, alert on and understand your metrics no matter where they are stored. Create, explore, and share dashboards with your team and foster a data-driven culture. Trusted and loved by the community" &mdash; grafana.com.

ClickHouse data source plugin provides support for ClickHouse as a backend database.

### qryn {#qryn}

[qryn](https://metrico.in) is a polyglot, high-performance observability stack for ClickHouse _(formerly cLoki)_ with native Grafana integrations allowing users to ingest and analyze logs, metrics and telemetry traces from any agent supporting Loki/LogQL, Prometheus/PromQL, OTLP/Tempo, Elastic, InfluxDB and many more.

Features:

- Built-in Explore UI and LogQL CLI for querying, extracting and visualizing data
- Native Grafana APIs support for querying, processing, ingesting, tracing and alerting without plugins
- Powerful pipeline to dynamically search, filter and extract data from logs, events, traces and beyond
- Ingestion and PUSH APIs transparently compatible with LogQL, PromQL, InfluxDB, Elastic and many more
- Ready to use with Agents such as Promtail, Grafana-Agent, Vector, Logstash, Telegraf and many others

### DBeaver {#dbeaver}

[DBeaver](https://dbeaver.io/) - universal desktop database client with ClickHouse support.

Features:

- Query development with syntax highlight and autocompletion.
- Table list with filters and metadata search.
- Table data preview.
- Full-text search.

By default, DBeaver does not connect using a session (the CLI for example does). If you require session support (for example to set settings for your session), edit the driver connection properties and set `session_id` to a random string (it uses the http connection under the hood). Then you can use any setting from the query window.

### clickhouse-cli {#clickhouse-cli}

[clickhouse-cli](https://github.com/hatarist/clickhouse-cli) is an alternative command-line client for ClickHouse, written in Python 3.

Features:

- Autocompletion.
- Syntax highlighting for the queries and data output.
- Pager support for the data output.
- Custom PostgreSQL-like commands.

### clickhouse-flamegraph {#clickhouse-flamegraph}

[clickhouse-flamegraph](https://github.com/Slach/clickhouse-flamegraph) is a specialized tool to visualize the `system.trace_log` as [flamegraph](http://www.brendangregg.com/flamegraphs.html).

### clickhouse-plantuml {#clickhouse-plantuml}

[cickhouse-plantuml](https://pypi.org/project/clickhouse-plantuml/) is a script to generate [PlantUML](https://plantuml.com/) diagram of tables' schemes.

### ClickHouse table graph {#clickhouse-table-graph}

[ClickHouse table graph](https://github.com/mbaksheev/clickhouse-table-graph) is a simple CLI tool for visualizing dependencies between ClickHouse tables. This tool retrieves connections between tables from `system.tables` table and builds dependencies flowchart in [mermaid](https://mermaid.js.org/syntax/flowchart.html) format.  With this tool you can easily visualize table dependencies and understand the data flow in your ClickHouse database. Thanks to mermaid, the resulting flowchart looks attractive and can be easily added to your markdown documentation.

### xeus-clickhouse {#xeus-clickhouse}

[xeus-clickhouse](https://github.com/wangfenjin/xeus-clickhouse) is a Jupyter kernal for ClickHouse, which supports query CH data using SQL in Jupyter.

### MindsDB Studio {#mindsdb}

[MindsDB](https://mindsdb.com/) is an open-source AI layer for databases including ClickHouse that allows you to effortlessly develop, train and deploy state-of-the-art machine learning models. MindsDB Studio(GUI) allows you to train new models from database, interpret predictions made by the model, identify potential data biases, and evaluate and visualize model accuracy using the Explainable AI function to adapt and tune your Machine Learning models faster.

### DBM {#dbm}

[DBM](https://github.com/devlive-community/dbm) DBM is a visual management tool for ClickHouse!

Features:

- Support query history (pagination, clear all, etc.)
- Support selected sql clauses query
- Support terminating query
- Support table management (metadata, delete, preview)
- Support database management (delete, create)
- Support custom query
- Support multiple data sources management(connection test, monitoring)
- Support monitor (processor, connection, query)
- Support migrating data

### Bytebase {#bytebase}

[Bytebase](https://bytebase.com) is a web-based, open source schema change and version control tool for teams. It supports various databases including ClickHouse.

Features:

- Schema review between developers and DBAs.
- Database-as-Code, version control the schema in VCS such GitLab and trigger the deployment upon code commit.
- Streamlined deployment with per-environment policy.
- Full migration history.
- Schema drift detection.
- Backup and restore.
- RBAC.

### Zeppelin-Interpreter-for-ClickHouse {#zeppelin-interpreter-for-clickhouse}

[Zeppelin-Interpreter-for-ClickHouse](https://github.com/SiderZhang/Zeppelin-Interpreter-for-ClickHouse) is a [Zeppelin](https://zeppelin.apache.org) interpreter for ClickHouse. Compared with the JDBC interpreter, it can provide better timeout control for long-running queries.

### ClickCat {#clickcat}

[ClickCat](https://github.com/clickcat-project/ClickCat) is a friendly user interface that lets you search, explore and visualize your ClickHouse Data.

Features:

- An online SQL editor which can run your SQL code without any installing.
- You can observe all processes and mutations. For those unfinished processes, you can kill them in ui.
- The Metrics contain Cluster Analysis, Data Analysis, and Query Analysis.

### ClickVisual {#clickvisual}

[ClickVisual](https://clickvisual.net/) ClickVisual is a lightweight open source log query, analysis and alarm visualization platform.

Features:

- Supports one-click creation of analysis log libraries
- Supports log collection configuration management
- Supports user-defined index configuration
- Supports alarm configuration
- Support permission granularity to library and table permission configuration

### ClickHouse-Mate {#clickmate}

[ClickHouse-Mate](https://github.com/metrico/clickhouse-mate) is an angular web client + user interface to search and explore data in ClickHouse.

Features:

- ClickHouse SQL Query autocompletion
- Fast Database and Table tree navigation
- Advanced result Filtering and Sorting
- Inline ClickHouse SQL documentation
- Query Presets and History
- 100% browser based, no server/backend

The client is available for instant usage through github pages: https://metrico.github.io/clickhouse-mate/

### Uptrace {#uptrace}

[Uptrace](https://github.com/uptrace/uptrace) is an APM tool that provides distributed tracing and metrics powered by OpenTelemetry and ClickHouse.

Features:

- [OpenTelemetry tracing](https://uptrace.dev/opentelemetry/distributed-tracing.html), metrics, and logs.
- Email/Slack/PagerDuty notifications using AlertManager.
- SQL-like query language to aggregate spans.
- Promql-like language to query metrics.
- Pre-built metrics dashboards.
- Multiple users/projects via YAML config.

### clickhouse-monitoring {#clickhouse-monitoring}

[clickhouse-monitoring](https://github.com/duyet/clickhouse-monitoring) is a simple Next.js dashboard that relies on `system.*` tables to help monitor and provide an overview of your ClickHouse cluster.

Features:

- Query monitor: current queries, query history, query resources (memory, parts read, file_open, ...), most expensive queries, most used tables or columns, etc.
- Cluster monitor: total memory/CPU usage, distributed queue, global settings, mergetree settings, metrics, etc.
- Tables and parts information: size, row count, compression, part size, etc., at the column level detail.
- Useful tools: Zookeeper data exploration, query EXPLAIN, kill queries, etc.
- Visualization metric charts: queries and resource usage, number of merges/mutation, merge performance, query performance, etc.

### CKibana {#ckibana}

[CKibana](https://github.com/TongchengOpenSource/ckibana) is a lightweight service that allows you to effortlessly search, explore, and visualize ClickHouse data using the native Kibana UI.

Features:

- Translates chart requests from the native Kibana UI into ClickHouse query syntax.
- Supports advanced features such as sampling and caching to enhance query performance.
- Minimizes the learning cost for users after migrating from ElasticSearch to ClickHouse.

### Telescope {#telescope}

[Telescope](https://iamtelescope.net/) is a modern web interface for exploring logs stored in ClickHouse. It provides a user-friendly UI for querying, visualizing, and managing log data with fine-grained access control.

Features:

- Clean, responsive UI with powerful filters and customizable field selection.
- FlyQL syntax for intuitive and expressive log filtering.
- Time-based graph with group-by support, including nested JSON, Map, and Array fields.
- Optional raw SQL `WHERE` query support for advanced filtering (with permission checks).
- Saved Views: persist and share custom UI configurations for queries and layout.
- Role-based access control (RBAC) and GitHub authentication integration.
- No extra agents or components required on the ClickHouse side.

[Telescope Source Code](https://github.com/iamtelescope/telescope) · [Live Demo](https://demo.iamtelescope.net)

## Commercial {#commercial}

### DataGrip {#datagrip}

[DataGrip](https://www.jetbrains.com/datagrip/) is a database IDE from JetBrains with dedicated support for ClickHouse. It is also embedded in other IntelliJ-based tools: PyCharm, IntelliJ IDEA, GoLand, PhpStorm and others.

Features:

- Very fast code completion.
- ClickHouse syntax highlighting.
- Support for features specific to ClickHouse, for example, nested columns, table engines.
- Data Editor.
- Refactorings.
- Search and Navigation.

### Yandex DataLens {#yandex-datalens}

[Yandex DataLens](https://cloud.yandex.ru/services/datalens) is a service of data visualization and analytics.

Features:

- Wide range of available visualizations, from simple bar charts to complex dashboards.
- Dashboards could be made publicly available.
- Support for multiple data sources including ClickHouse.
- Storage for materialized data based on ClickHouse.

DataLens is [available for free](https://cloud.yandex.com/docs/datalens/pricing) for low-load projects, even for commercial use.

- [DataLens documentation](https://cloud.yandex.com/docs/datalens/).
- [Tutorial](https://cloud.yandex.com/docs/solutions/datalens/data-from-ch-visualization) on visualizing data from a ClickHouse database.

### Holistics Software {#holistics-software}

[Holistics](https://www.holistics.io/) is a full-stack data platform and business intelligence tool.

Features:

- Automated email, Slack and Google Sheet schedules of reports.
- SQL editor with visualizations, version control, auto-completion, reusable query components and dynamic filters.
- Embedded analytics of reports and dashboards via iframe.
- Data preparation and ETL capabilities.
- SQL data modelling support for relational mapping of data.

### Looker {#looker}

[Looker](https://looker.com) is a data platform and business intelligence tool with support for 50+ database dialects including ClickHouse. Looker is available as a SaaS platform and self-hosted. Users can use Looker via the browser to explore data, build visualizations and dashboards, schedule reports, and share their insights with colleagues. Looker provides a rich set of tools to embed these features in other applications, and an API
to integrate data with other applications.

Features:

- Easy and agile development using LookML, a language which supports curated
    [Data Modeling](https://looker.com/platform/data-modeling) to support report writers and end-users.
- Powerful workflow integration via Looker's [Data Actions](https://looker.com/platform/actions).

[How to configure ClickHouse in Looker.](https://docs.looker.com/setup-and-management/database-config/clickhouse)

### SeekTable {#seektable}

[SeekTable](https://www.seektable.com) is a self-service BI tool for data exploration and operational reporting. It is available both as a cloud service and a self-hosted version. Reports from SeekTable may be embedded into any web-app.

Features:

- Business users-friendly reports builder.
- Powerful report parameters for SQL filtering and report-specific query customizations.
- Can connect to ClickHouse both with a native TCP/IP endpoint and a HTTP(S) interface (2 different drivers).
- It is possible to use all power of ClickHouse SQL dialect in dimensions/measures definitions.
- [Web API](https://www.seektable.com/help/web-api-integration) for automated reports generation.
- Supports reports development flow with account data [backup/restore](https://www.seektable.com/help/self-hosted-backup-restore); data models (cubes) / reports configuration is a human-readable XML and can be stored under version control system.

SeekTable is [free](https://www.seektable.com/help/cloud-pricing) for personal/individual usage.

[How to configure ClickHouse connection in SeekTable.](https://www.seektable.com/help/clickhouse-pivot-table)

### Chadmin {#chadmin}

[Chadmin](https://github.com/bun4uk/chadmin) is a simple UI where you can visualize your currently running queries on your ClickHouse cluster and info about them and kill them if you want.

### TABLUM.IO {#tablum_io}

[TABLUM.IO](https://tablum.io/) — an online query and analytics tool for ETL and visualization. It allows connecting to ClickHouse, query data via a versatile SQL console as well as to load data from static files and 3rd party services. TABLUM.IO can visualize data results as charts and tables.

Features:
- ETL: data loading from popular databases, local and remote files, API invocations.
- Versatile SQL console with syntax highlight and visual query builder.
- Data visualization as charts and tables.
- Data materialization and sub-queries.
- Data reporting to Slack, Telegram or email.
- Data pipelining via proprietary API.
- Data export in JSON, CSV, SQL, HTML formats.
- Web-based interface.

TABLUM.IO can be run as a self-hosted solution (as a docker image) or in the cloud.
License: [commercial](https://tablum.io/pricing) product with 3-month free period.

Try it out for free [in the cloud](https://tablum.io/try).
Learn more about the product at [TABLUM.IO](https://tablum.io/)

### CKMAN {#ckman}

[CKMAN](https://www.github.com/housepower/ckman) is a tool for managing and monitoring ClickHouse clusters!

Features:

- Rapid and convenient automated deployment of clusters through a browser interface
- Clusters can be scaled or scaled
- Load balance the data of the cluster
- Upgrade the cluster online
- Modify the cluster configuration on the page
- Provides cluster node monitoring and zookeeper monitoring
- Monitor the status of tables and partitions, and monitor slow SQL statements
- Provides an easy-to-use SQL execution page
