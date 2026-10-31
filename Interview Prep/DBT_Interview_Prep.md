# dbt Interview Prep (Snowflake-focused)

Read this in order. **Part A** is the basics, **Part B** covers the core concepts with the lines to say in an interview, **Part C** is a hands-on lab you can do in about 60–90 minutes in Snowflake, **Part D** has the interview Q&A, and **Part E** covers the scenarios.

---

## Part A: Basics in 5 minutes

**What is dbt?** dbt (data build tool) handles the **T in ELT**. You write `SELECT` statements as `.sql` files, and dbt turns them into tables and views in Snowflake. It also handles dependencies, tests, docs, and lineage.

**What dbt does NOT do:** it doesn't extract or load data. Fivetran, Snowpipe, Airflow, or COPY INTO do that. It doesn't schedule itself either. dbt Cloud, Airflow, or Snowflake Tasks do the scheduling.

**One-line pitch:**
> "dbt brings software engineering to SQL: modular models, version control, testing, documentation, CI/CD and environments, while all the compute runs inside Snowflake."

**dbt Core vs dbt Cloud vs dbt on Snowflake**
| | dbt Core | dbt Cloud | dbt Projects on Snowflake |
|---|---|---|---|
| What | Open-source CLI (Python) | SaaS: IDE, scheduler, CI, docs hosting | Native `DBT PROJECT` object in Snowflake |
| Run | `dbt run` locally or in Airflow | Jobs in the UI | `EXECUTE DBT PROJECT ...`, scheduled with Snowflake Tasks |
| Auth | `profiles.yml` | Managed | Snowflake session (no passwords) |

**How dbt fits with your Airflow DAG:** your `DAILY_MASTER_METRIC` DAG calls stored procedures for S0 → S1 → ADL → MDW. In a dbt world, each layer becomes a folder of models. Airflow (or Snowflake Tasks) just triggers `dbt build`, and dbt works out the order through `ref()`.
```
S0  (raw)       → sources
S1  (staging)   → models/staging      (views)
ADL (integrated)→ models/intermediate
MDW (facts/dims)→ models/marts        (tables / incremental)
CDC Type1 SP    → incremental merge model
SCD Type2       → snapshot
validation task → dbt tests
```
**This is a strong interview story: "I'd migrate our stored-procedure pipeline into dbt layers."**

---

## Part B: Core concepts (in the order you'd explain them)

### 1. Project structure
```
my_project/
├── dbt_project.yml        # project config (name, paths, folder-level configs)
├── profiles.yml           # connection (account, role, warehouse, db, schema, target)
├── packages.yml           # dbt_utils, dbt_expectations ...
├── models/
│   ├── staging/           # stg_*  1:1 with source, rename/cast only
│   ├── intermediate/      # int_*  joins, business logic
│   └── marts/             # fct_* / dim_*  consumed by BI
├── snapshots/             # SCD2
├── seeds/                 # small CSVs (lookup/mapping tables)
├── macros/                # reusable Jinja functions
├── tests/                 # singular SQL tests
└── analyses/              # ad-hoc SQL, compiled not run
```
```yaml
# dbt_project.yml
name: my_project
profile: my_project
models:
  my_project:
    staging:      { +materialized: view,  +schema: staging }
    intermediate: { +materialized: ephemeral }
    marts:        { +materialized: table, +schema: marts, +snowflake_warehouse: transform_wh }
```
**Config precedence (lowest to highest):** `dbt_project.yml` → `.yml` properties → `{{ config() }}` in the model.

### 2. Materializations (always asked)
| Type | What gets built | When to use |
|---|---|---|
| `view` | A view | Staging, light logic. Always fresh, no storage cost. |
| `table` | `CREATE OR REPLACE TABLE AS` | Marts queried often |
| `incremental` | Inserts or merges only new/changed rows | Large fact tables |
| `ephemeral` | Nothing. Inlined as a CTE | Small helper logic |
| `materialized_view` / `dynamic_table` | Snowflake MV / Dynamic Table | Near-real-time, with Snowflake handling the refresh |
| `snapshot` | SCD2 table | History tracking |

### 3. `source()` vs `ref()`
```sql
select * from {{ source('raw_sales', 'orders') }}   -- raw table that dbt doesn't build
select * from {{ ref('stg_orders') }}               -- another dbt model
```
> "ref() builds the DAG, so dbt works out run order and lineage. It also resolves the right database and schema per environment, so dev writes to my dev schema and prod writes to prod. **Never hard-code table names.**"

Sources also give you **freshness checks** (`dbt source freshness`) and lineage from raw data.

#### Sources: full example (an expanded version of `dbt_lab/models/staging/_sources.yml`)
```yaml
version: 2

sources:
  - name: raw                      # logical name used in source('raw', ...)
    description: "Raw tables loaded by Snowpipe / Airflow"
    database: DBT_LAB              # actual Snowflake database
    schema: RAW                    # actual Snowflake schema
    loaded_at_field: _loaded_at    # column dbt uses for freshness
    freshness:                     # default for every table in this source
      warn_after:  {count: 12, period: hour}
      error_after: {count: 30, period: day}
    tables:
      - name: orders               # source('raw','orders') → DBT_LAB.RAW.ORDERS
        description: "One row per order"
        columns:
          - name: order_id
            data_tests: [unique, not_null]   # you can test raw data too
      - name: customers
        identifier: CUSTOMERS      # optional: real table name if it differs from `name`
        freshness: null            # turn off freshness (no _loaded_at column here)
```

**Using it in a model:**
```sql
-- models/staging/stg_orders.sql
select order_id, customer_id, upper(status) as status
from {{ source('raw', 'orders') }}
```

**What dbt compiles it to** (check `target/compiled/...`):
```sql
select order_id, customer_id, upper(status) as status
from DBT_LAB.RAW.orders
```

**Commands:**
```bash
dbt source freshness                    # check all sources → PASS / WARN / ERROR
dbt source freshness -s source:raw.orders
dbt test -s source:raw                  # run tests defined on sources
dbt run  -s source:raw+                 # run every model downstream of the raw source
```

**Key points to say in the interview:**
| Key | Meaning |
|---|---|
| `name` | Logical name used in `source()`. It can differ from the real schema name. |
| `database` / `schema` | Where the raw tables really live. Change them in one place and every model follows. |
| `identifier` | Real table name, when it differs from the logical `name` |
| `loaded_at_field` + `freshness` | SLA on the raw data. With `error_after`, the freshness command fails, and that can block the pipeline in Airflow. |
| Tests on sources | Catch bad raw data *before* it reaches staging |
| Lineage | Sources show up as green nodes in `dbt docs` |

> "I never hard-code raw table names. I declare them once as sources, add freshness and basic tests, and every staging model reads through `source()`. If the raw schema moves, I change one YAML line."

### 4. Incremental models (most likely deep-dive)
```sql
{{ config(materialized='incremental', unique_key='order_id',
          incremental_strategy='merge', on_schema_change='sync_all_columns') }}
select order_id, customer_id, status, amount, updated_at
from {{ ref('stg_orders') }}
{% if is_incremental() %}
  where updated_at > (select dateadd('day', -3, max(updated_at)) from {{ this }})
{% endif %}
```
- `is_incremental()` is true only when the table already exists, the model is incremental, and the run isn't `--full-refresh`.
- `{{ this }}` refers to the model's existing table.
- The lookback window catches late-arriving data.
- **Strategies on Snowflake:** `merge` (default; updates and inserts by key), `delete+insert` (good for large partition-style reloads), `append` (insert-only logs), `microbatch` (dbt 1.9+; processes time batches with `event_time`, `batch_size`, and `lookback`).
- `on_schema_change`: `ignore` (default), `fail`, `append_new_columns`, `sync_all_columns`.
- **The 3-day lookback is NOT a limit on which rows can change.** It's measured from the target's `max(updated_at)`. An old order updated today has today's `updated_at`, so it's picked up and MERGEd. The lookback only catches *late-arriving* rows whose `updated_at` is older than what's already loaded.

#### Other incremental strategies (examples on the lab tables)

**`append`: insert-only, for event and log data**
```sql
{{ config(materialized='incremental', incremental_strategy='append') }}   -- no unique_key
select order_id, status, updated_at as event_ts, current_timestamp() as dbt_loaded_at
from {{ ref('stg_orders') }}
{% if is_incremental() %}
  where updated_at > (select max(event_ts) from {{ this }})
{% endif %}
```
`INSERT INTO ... SELECT` is the fastest and cheapest. Use it for logs, clickstream, and API responses. The risk is duplicates if data is re-sent.

**`delete+insert`: reload whole days or partitions**
```sql
{{ config(materialized='incremental', incremental_strategy='delete+insert',
          unique_key='order_date') }}          -- the partition to replace
select to_date(updated_at) as order_date, count(*) as order_count, sum(amount) as total_amount
from {{ ref('stg_orders') }}
{% if is_incremental() %}
  where to_date(updated_at) >= (select dateadd('day', -3, max(order_date)) from {{ this }})
{% endif %}
group by 1
```
It runs `DELETE ... WHERE order_date IN (new dates)` and then `INSERT`. Good for daily aggregates and very large tables.

**`microbatch`: time-sliced batches (dbt 1.9+)**
```sql
{{ config(materialized='incremental', incremental_strategy='microbatch',
          event_time='updated_at', batch_size='day', lookback=3, begin='2026-10-01') }}
select order_id, customer_id, status, amount, updated_at
from {{ ref('stg_orders') }}                  -- no is_incremental() block needed
```
dbt runs one query per day. You can backfill a window with `--event-time-start 2026-10-20 --event-time-end 2026-10-23`, and failed batches can be retried on their own. Set `event_time` on the upstream model too, otherwise dbt reads the whole upstream model for each batch.

| Strategy | `unique_key` | SQL | Best for |
|---|---|---|---|
| `merge` (default) | Row key | MERGE | Rows that get updated |
| `append` | None | INSERT | Insert-only events and logs |
| `delete+insert` | Partition key | DELETE + INSERT | Reloading days or partitions |
| `microbatch` | None (`event_time`) | One query per batch | Big time-series data, backfills |

> "I pick `merge` when rows change, `append` for immutable events, `delete+insert` when I reload whole partitions, and `microbatch` for large time-series data where I want batch-level retries and backfills."

- **Gotchas:** hard deletes in the source aren't captured (use soft-delete flags or a periodic `--full-refresh`). Without `unique_key` you get duplicates. If `unique_key` isn't really unique, merge fails with a "duplicate row" error.

### 5. Tests
```yaml
# models/marts/_schema.yml
version: 2
models:
  - name: fct_orders
    columns:
      - name: order_id
        data_tests: [unique, not_null]          # older dbt: `tests:`
      - name: status
        data_tests:
          - accepted_values: { values: ['PLACED','SHIPPED','RETURNED'] }
      - name: customer_id
        data_tests:
          - relationships: { to: ref('dim_customers'), field: customer_id }
```
- **4 built-in generic tests:** `unique`, `not_null`, `accepted_values`, `relationships`.
- **Singular test:** a SQL file in `tests/`. If it returns any rows, the test fails.
- **Custom generic test:** `{% test is_positive(model, column_name) %} select * from {{ model }} where {{ column_name }} < 0 {% endtest %}`
- **Config:** `severity: warn`, `error_if: ">10"`, `store_failures: true` (saves the failing rows to a table for debugging).
- **Unit tests** (dbt 1.8+): mock inputs and assert the expected output of a model's logic.
- **Packages:** `dbt_utils` and `dbt_expectations` add more tests.

#### Custom test examples

**1. Singular test: a one-off business rule or reconciliation**
```sql
-- tests/assert_lifetime_value_matches_orders.sql
select d.customer_id, d.lifetime_value, sum(f.amount) as fct_total
from {{ ref('dim_customers') }} d
join {{ ref('fct_orders') }} f using (customer_id)
group by 1, 2
having d.lifetime_value != sum(f.amount)
```

**2. Custom generic test: reusable, with arguments**
```sql
-- tests/generic/is_positive.sql
{% test is_positive(model, column_name) %}
select * from {{ model }} where {{ column_name }} <= 0
{% endtest %}

-- tests/generic/value_between.sql
{% test value_between(model, column_name, min_value, max_value) %}
select * from {{ model }}
where {{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }}
{% endtest %}
```
```yaml
      - name: amount
        data_tests:
          - is_positive
          - value_between: { min_value: 0, max_value: 100000 }
```
dbt passes in `model` and `column_name` for you.

**3. Test configs**
```yaml
          - value_between:
              min_value: 0
              max_value: 100000
              config:
                severity: warn
                warn_if: ">0"
                error_if: ">10"                 # fail only if more than 10 bad rows
                where: "status <> 'RETURNED'"   # test only some of the rows
                store_failures: true            # bad rows go to <schema>_dbt_test__audit
```

**4. Model-level test: recency of a dbt model**
```sql
-- tests/generic/recency_check.sql
{% test recency_check(model, column_name, hours) %}
select max({{ column_name }}) as latest from {{ model }}
having max({{ column_name }}) < dateadd('hour', -{{ hours }}, current_timestamp())
{% endtest %}
```
```yaml
models:
  - name: fct_orders
    data_tests:
      - recency_check: { column_name: updated_at, hours: 24 }
```

**5. Package tests (`dbt_utils`, install with `dbt deps`)**
```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```
```yaml
models:
  - name: fct_orders
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns: [order_id, customer_id]
    columns:
      - name: amount
        data_tests:
          - dbt_utils.expression_is_true: { expression: ">= 0" }
```

**6. Unit test (dbt 1.8+): checks the logic on fake input rows**
```yaml
unit_tests:
  - name: test_cents_conversion
    model: stg_orders
    given:
      - input: source('raw', 'orders')
        rows:
          - {order_id: 1, customer_id: 1, status: 'placed', amount_cents: 12345, updated_at: '2026-10-01'}
    expect:
      rows:
        - {order_id: 1, status: 'PLACED', amount: 123.45}
```
A data test checks the real data. A unit test checks the SQL logic.

> "Built-in tests cover keys and relationships. I write singular tests for business rules, custom generic tests with arguments for reusable checks, and I use `severity` and `error_if` thresholds plus `store_failures` so failing rows can be investigated. Unit tests check the transformation logic itself."

### 6. Snapshots (SCD Type 2)
```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='snapshots', unique_key='customer_id',
          strategy='timestamp', updated_at='updated_at') }}
select * from {{ source('raw_sales','customers') }}
{% endsnapshot %}
```
dbt adds `dbt_scd_id`, `dbt_updated_at`, `dbt_valid_from`, and `dbt_valid_to` (NULL means it's the current row). If there's no reliable timestamp, use `strategy='check', check_cols=['email','tier']`. Use `invalidate_hard_deletes=True` (in newer versions, `hard_deletes='invalidate'`) to close out rows that were deleted in the source.

#### Snapshot strategies with examples

**1. `timestamp` (preferred).** A row counts as changed when its `updated_at` is newer than the one in the snapshot.
```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='DEV', unique_key='customer_id',
          strategy='timestamp', updated_at='updated_at') }}
select * from {{ source('raw', 'customers') }}
{% endsnapshot %}
```
It's fast because dbt compares one column. **Risk:** if the source changes a value but not `updated_at`, the change is missed.

**2. `check` (no reliable timestamp).** dbt compares the actual column values.
```sql
{% snapshot customers_snapshot_check %}
{{ config(target_schema='DEV', unique_key='customer_id',
          strategy='check', check_cols=['tier', 'region']) }}   -- or check_cols='all'
select * from {{ source('raw', 'customers') }}
{% endsnapshot %}
```
It works without a timestamp, and you choose which columns count as history. It's slower on wide or large tables, and `'all'` creates versions for minor changes too.

**Result (either strategy).** Customer 2 goes from SILVER to PLATINUM:
| customer_id | tier | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| 2 | SILVER | 2026-10-01 | 2026-10-28 |
| 2 | PLATINUM | 2026-10-28 | NULL (current) |

dbt also adds `dbt_scd_id` and `dbt_updated_at`. Current rows: `where dbt_valid_to is null`.

**Hard deletes.** `hard_deletes='ignore' | 'invalidate' | 'new_record'` (dbt 1.9+; older syntax: `invalidate_hard_deletes=True`).
- `ignore` (default): a deleted source row stays "current" forever.
- `invalidate`: sets `dbt_valid_to` on the deleted row.
- `new_record`: adds a row with `dbt_is_deleted = true`.

**dbt 1.9+ YAML syntax**
```yaml
# snapshots/snapshots.yml
snapshots:
  - name: customers_snapshot
    relation: source('raw', 'customers')
    config:
      schema: DEV
      unique_key: customer_id
      strategy: timestamp
      updated_at: updated_at
      hard_deletes: invalidate
```

| | `timestamp` | `check` |
|---|---|---|
| Detects change by | A newer `updated_at` | Different column values |
| Needs | A reliable timestamp | `check_cols` (a list or `'all'`) |
| Speed | Fast | Slower on wide or large tables |
| Misses changes if | The timestamp isn't updated | Never, for the listed columns |

> "I use the timestamp strategy when the source has a trustworthy `updated_at`. Otherwise I use `check` with only the business-relevant columns, and I set `hard_deletes='invalidate'` so deleted records get closed out."

**Lab:** `UPDATE DBT_LAB.RAW.CUSTOMERS SET tier='PLATINUM', updated_at=current_timestamp() WHERE customer_id=2;` then run `dbt snapshot`. That gives 2 rows. Then run `UPDATE ... SET region='APAC' WHERE customer_id=2;` without changing `updated_at`. The timestamp snapshot misses that change, but a check snapshot catches it.

**SCD1 vs SCD2:** SCD1 overwrites the old value (like your `CDC_TYPE1` stored procedure; in dbt that's an incremental merge). SCD2 keeps the history (snapshot).

### 7. Jinja and macros
```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(col, scale=2) %} round({{ col }}/100, {{ scale }}) {% endmacro %}

-- pivot with a loop
{% set statuses = ['placed','shipped','returned'] %}
select customer_id,
{% for s in statuses %}
  sum(iff(status='{{ s }}',1,0)) as {{ s }}_orders{{ "," if not loop.last }}
{% endfor %}
from {{ ref('stg_orders') }} group by 1
```
- `{{ }}` outputs a value, `{% %}` is logic, `{# #}` is a comment.
- Useful functions: `var('x')`, `env_var('X')`, `target.name`, `run_query()`, `log()`.
- The most common override is **`generate_schema_name`**, which controls how custom schemas are named. By default it's `<target_schema>_<custom_schema>`.
- `dbt_utils.generate_surrogate_key(['order_id','line_no'])` builds a hashed key from columns.

### 8. Hooks and operations
```sql
{{ config(post_hook="grant select on {{ this }} to role analyst_role") }}
```
- `pre_hook` / `post_hook` run per model.
- `on-run-start` / `on-run-end` are set in `dbt_project.yml` and run once per invocation.
- `dbt run-operation my_macro --args '{x: 1}'` runs a macro on its own.

### 9. Snowflake-specific configs (your strength, so connect each one to cost)
```sql
{{ config(materialized='table',
          transient=true,          -- no Fail-safe → cheaper (dbt default on Snowflake is transient=true)
          cluster_by=['order_date'],
          copy_grants=true,        -- keep grants on rebuild
          snowflake_warehouse='heavy_wh',  -- per-model warehouse sizing
          query_tag='dbt_fct_orders',      -- trace in QUERY_HISTORY (same idea as your Airflow QUERY_TAG)
          secure=true)             -- secure view
}}
```
Others: `automatic_clustering`, the `dynamic_table` materialization (`target_lag`, `snowflake_warehouse`), Iceberg tables (`table_format='iceberg'`), and **zero-copy clone** for dev/CI environments.

### 9a. Iceberg tables in Snowflake
An **Iceberg table** is a Snowflake table stored in the open **Apache Iceberg** format (Parquet data files plus Iceberg metadata). Snowflake can read and write it, and so can other engines like Spark, Trino, Flink, Databricks, and DuckDB. A native Snowflake table uses Snowflake's own format, so only Snowflake can read it.

> "An Iceberg table gives Snowflake's performance and SQL on an **open table format**, so the same data can be shared with other engines without copying it."

**Building blocks**
| Term | Meaning |
|---|---|
| Iceberg format | Parquet data files plus metadata (snapshots, manifests, schema). Supports ACID transactions, schema evolution, hidden partitioning, and time travel through snapshots. |
| Catalog | Tracks the current metadata file for each table. Either **Snowflake** or an **external catalog** (AWS Glue, Open Catalog/Polaris, Unity) connected through a **catalog integration**. |
| Storage | **Snowflake storage** (`EXTERNAL_VOLUME = SNOWFLAKE_MANAGED`; Snowflake bills for it and Fail-safe applies) or **your own S3/GCS/Azure bucket** through an **external volume** (your cloud provider bills for it; no Fail-safe). |

**Two types**
| | Snowflake-managed (Snowflake is the catalog) | Externally managed (external catalog) |
|---|---|---|
| Writes | Snowflake. External engines can also read and write through Horizon Catalog's Iceberg REST API. | The external engine. Snowflake reads it, and can write when the catalog is a REST catalog. |
| Maintenance | Snowflake handles compaction and cleanup | The external system handles it |
| Snowflake features | Full | Limited |
| Use case | New lakehouse tables shared with Spark or Trino | Query an existing lake (Glue, Databricks) without copying the data |

A **catalog-linked database** automatically discovers and syncs all the tables in a remote Iceberg REST catalog.

**Example: Snowflake-managed table on Snowflake storage**
```sql
CREATE ICEBERG TABLE DBT_LAB.DEV.ORDERS_ICEBERG (
    order_id INT, customer_id INT, status STRING, amount NUMBER(12,2), updated_at TIMESTAMP_NTZ
)
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'SNOWFLAKE_MANAGED';
```
For your own bucket, first run `CREATE EXTERNAL VOLUME ...` with an IAM role, then use `EXTERNAL_VOLUME = 'my_s3_vol'` and `BASE_LOCATION = 'orders/'`.

| | Native table | Iceberg table |
|---|---|---|
| Format | Proprietary | Open (Iceberg + Parquet) |
| Other engines can read it | No | Yes |
| Storage billed by | Snowflake | Snowflake, or your cloud provider |
| Fail-safe | Yes | Only on Snowflake storage |
| Best for | Pure Snowflake workloads | Lakehouse, multiple engines, avoiding lock-in |

**In dbt** (the exact config keys depend on the dbt version):
```sql
{{ config(materialized='table', table_format='iceberg',
          external_volume='my_s3_vol', base_location_subpath='fct_orders') }}
```

> "With Snowflake as the catalog we get full features and automatic maintenance, and Spark or Trino can still use the same tables through Horizon's Iceberg REST catalog. For an existing lake in Glue or Databricks, we use a catalog integration to query it in place, without copying the data."

### 10. Environments, targets, and deployment
```yaml
# profiles.yml
my_project:
  target: dev
  outputs:
    dev:  { type: snowflake, account: xy12345, user: me, role: DEV_ROLE,
            warehouse: DEV_WH, database: ANALYTICS_DEV, schema: DBT_THAZ, threads: 4,
            authenticator: snowflake_jwt, private_key_path: ~/.ssh/rsa_key.p8 }
    prod: { ..., database: ANALYTICS, schema: PROD, role: TRANSFORMER }
```
`dbt run --target prod`. `threads` is how many models run in parallel.

**CI/CD (Slim CI):** `dbt build -s state:modified+ --defer --state prod-artifacts/` builds only the changed models and their downstream models, and reads unchanged parents from prod.

### 11. Artifacts and docs
- `target/manifest.json` holds the full project graph (used by state, Cosmos, and docs).
- `run_results.json` has per-node status and timing.
- `catalog.json` has column metadata.
- `dbt docs generate && dbt docs serve` gives you a website with a lineage graph.

### 12. Other things that come up
- **Seeds:** `dbt seed` loads small CSVs, like country codes or mapping tables. Don't use it for big data.
- **Exposures:** declare dashboards that depend on models, so they show up in lineage.
- **Model contracts** (`contract: {enforced: true}`): enforce column names and types. Versions and access (`public`/`private`) belong to dbt Mesh.
- **Semantic Layer / MetricFlow:** define metrics once.
- **Packages:** `dbt deps` installs what's listed in `packages.yml`.

### 13. Selectors and commands (memorize)
| Command | Meaning |
|---|---|
| `dbt debug` | Test the connection |
| `dbt deps` | Install packages |
| `dbt compile` | Render Jinja to SQL in `target/compiled` without running it |
| `dbt run` | Build models |
| `dbt test` | Run tests |
| `dbt build` | seed + run + snapshot + test in DAG order. **A failed test skips downstream models.** |
| `dbt run -s fct_orders` | One model |
| `-s fct_orders+` / `+fct_orders` / `+fct_orders+` | Downstream / upstream / both |
| `-s 2+fct_orders` | 2 levels upstream |
| `-s tag:daily` / `path:models/marts` / `config.materialized:incremental` | By tag, path, or config |
| `--exclude stg_x` | Exclude a model |
| `--full-refresh` | Rebuild incremental models and seeds |
| `dbt retry` | Re-run from the point of failure |
| `dbt source freshness` | Check source loaded times |
| `dbt show -s model --limit 10` | Preview rows |
| `dbt ls -s +fct_orders` | List the selected nodes |

---

## Part C: Hands-on lab (do this tonight, ~60–90 min)

### Option 1: dbt Projects on Snowflake (fastest, no install)
In Snowsight: **Projects → Workspaces → + Add new → dbt Project**. Pick a role, warehouse, database, and schema, then paste in the files below. Use the **Run / Build** dropdown in the workspace to run them.

### Option 2: local dbt Core
```bash
python -m venv dbtenv && source dbtenv/bin/activate   # Windows: dbtenv\Scripts\activate
pip install dbt-snowflake
dbt init dbt_lab          # answer the prompts → creates profiles.yml in ~/.dbt/
cd dbt_lab && dbt debug
```

### Step 1: Create raw data in Snowflake (run in a worksheet)
```sql
CREATE DATABASE IF NOT EXISTS DBT_LAB;
CREATE SCHEMA IF NOT EXISTS DBT_LAB.RAW;
CREATE SCHEMA IF NOT EXISTS DBT_LAB.DEV;

CREATE OR REPLACE TABLE DBT_LAB.RAW.CUSTOMERS (customer_id INT, name STRING, region STRING, tier STRING, updated_at TIMESTAMP_NTZ);
INSERT INTO DBT_LAB.RAW.CUSTOMERS VALUES
 (1,'Asha','APAC','GOLD',  '2026-10-01'),
 (2,'Ben', 'EMEA','SILVER','2026-10-01'),
 (3,'Chen','AMER','BRONZE','2026-10-01');

CREATE OR REPLACE TABLE DBT_LAB.RAW.ORDERS (order_id INT, customer_id INT, status STRING, amount_cents INT, updated_at TIMESTAMP_NTZ, _loaded_at TIMESTAMP_NTZ);
INSERT INTO DBT_LAB.RAW.ORDERS VALUES
 (101,1,'placed', 12000,'2026-10-20','2026-10-20'),
 (102,1,'shipped', 5000,'2026-10-21','2026-10-21'),
 (103,2,'placed',  7500,'2026-10-22','2026-10-22'),
 (104,3,'returned',3000,'2026-10-23','2026-10-23');
```

### Step 2: Project files
`dbt_project.yml`
```yaml
name: dbt_lab
version: '1.0'
profile: dbt_lab
models:
  dbt_lab:
    staging: { +materialized: view }
    marts:   { +materialized: table }
```

`models/staging/_sources.yml`
```yaml
version: 2
sources:
  - name: raw
    database: DBT_LAB
    schema: RAW
    loaded_at_field: _loaded_at
    freshness: { warn_after: {count: 12, period: hour}, error_after: {count: 30, period: day} }
    tables:
      - name: orders
      - name: customers
```

`macros/cents_to_dollars.sql`
```sql
{% macro cents_to_dollars(col, scale=2) %} round({{ col }} / 100, {{ scale }}) {% endmacro %}
```

`models/staging/stg_orders.sql`
```sql
select order_id, customer_id, upper(status) as status,
       {{ cents_to_dollars('amount_cents') }} as amount, updated_at
from {{ source('raw','orders') }}
```

`models/staging/stg_customers.sql`
```sql
select customer_id, initcap(name) as customer_name, region, tier, updated_at
from {{ source('raw','customers') }}
```

`models/marts/dim_customers.sql`
```sql
select c.customer_id, c.customer_name, c.region, c.tier,
       count(o.order_id) as total_orders, coalesce(sum(o.amount),0) as lifetime_value
from {{ ref('stg_customers') }} c
left join {{ ref('stg_orders') }} o using (customer_id)
group by all
```

`models/marts/fct_orders.sql` (incremental)
```sql
{{ config(materialized='incremental', unique_key='order_id', incremental_strategy='merge') }}
select o.order_id, o.customer_id, c.region, o.status, o.amount, o.updated_at
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c using (customer_id)
{% if is_incremental() %}
  where o.updated_at > (select dateadd('day', -3, max(updated_at)) from {{ this }})
{% endif %}
```

`models/marts/_schema.yml`
```yaml
version: 2
models:
  - name: fct_orders
    description: "One row per order"
    columns:
      - name: order_id
        data_tests: [unique, not_null]
      - name: status
        data_tests:
          - accepted_values: { values: ['PLACED','SHIPPED','RETURNED'] }
      - name: customer_id
        data_tests:
          - relationships: { to: ref('dim_customers'), field: customer_id }
```

`tests/assert_no_negative_amount.sql`
```sql
select * from {{ ref('fct_orders') }} where amount < 0
```

`snapshots/customers_snapshot.sql`
```sql
{% snapshot customers_snapshot %}
{{ config(target_schema='DEV', unique_key='customer_id', strategy='timestamp', updated_at='updated_at') }}
select * from {{ source('raw','customers') }}
{% endsnapshot %}
```

### Step 3: Run and observe (this is the "practical" part)
| # | Do | What to notice |
|---|---|---|
| 1 | `dbt compile` then open `target/compiled/...` | Jinja is rendered into plain Snowflake SQL |
| 2 | `dbt build` | Views, then tables, snapshot, and tests run in DAG order. Check Snowsight to see the views and tables in DEV. |
| 3 | `dbt source freshness` | Gives a warn or pass based on `_loaded_at` |
| 4 | **Incremental test:** `INSERT INTO DBT_LAB.RAW.ORDERS VALUES (105,2,'shipped',9900,current_timestamp(),current_timestamp());` and `UPDATE DBT_LAB.RAW.ORDERS SET status='shipped', updated_at=current_timestamp() WHERE order_id=103;` then `dbt run -s fct_orders` | Look at Query History: there's a **MERGE**. Row 103 was updated and row 105 was inserted, with no duplicates. |
| 5 | `dbt run -s fct_orders --full-refresh` | It's a CREATE OR REPLACE this time, not a MERGE |
| 6 | **Snapshot test:** `UPDATE DBT_LAB.RAW.CUSTOMERS SET tier='PLATINUM', updated_at=current_timestamp() WHERE customer_id=2;` then `dbt snapshot` and query `DBT_LAB.DEV.CUSTOMERS_SNAPSHOT` | Customer 2 now has 2 rows. The old row has `dbt_valid_to` set (SCD2). |
| 7 | **Break a test:** `INSERT INTO DBT_LAB.RAW.ORDERS VALUES (106,1,'cancelled',100,current_timestamp(),current_timestamp());` then `dbt build` | `accepted_values` fails. Add `config: {severity: warn}` and see how that changes the result. |
| 8 | `dbt run -s +fct_orders` / `dbt ls -s stg_orders+` | Graph selectors |
| 9 | `dbt docs generate` (+ `serve` locally) | Lineage graph |
| 10 | Cleanup: `DROP DATABASE DBT_LAB;` | |

---

## Part D: Interview Q&A (short answers)

1. **What is dbt and why use it over stored procedures?** It gives you modular SQL, automatic dependency ordering, built-in tests and docs, Git and CI/CD, and environments. Stored procedures are monolithic, hard to test, and have no lineage.
2. **`ref` vs `source`?** `source` points to raw tables that dbt doesn't build. `ref` points to dbt models. Both create lineage, and `ref` is environment-aware.
3. **What are the materializations?** view, table, incremental, ephemeral, plus materialized view, dynamic table, and snapshot. Pick based on size, freshness, and cost.
4. **How does an incremental model work on Snowflake?** On the first run it creates the table. After that it filters with `is_incremental()` and does a MERGE on `unique_key`. Use `--full-refresh` to rebuild.
5. **How do you handle late-arriving data?** A lookback window plus merge on `unique_key`, or microbatch with `lookback`.
6. **How do you handle hard deletes?** Soft-delete flags from CDC, periodic full refreshes, or snapshot `hard_deletes='invalidate'`.
7. **What's the difference between `dbt run` and `dbt build`?** `build` also runs seeds, snapshots, and tests in DAG order, and it skips downstream models when a test fails.
8. **What kinds of tests are there?** Generic tests (the 4 built-in ones plus custom), singular tests, unit tests, and package tests. Options include severity, `store_failures`, and thresholds.
9. **What is a snapshot?** SCD Type 2 with either the timestamp or check strategy. It adds `dbt_valid_from` / `dbt_valid_to`.
10. **What's ephemeral, and when should you avoid it?** Ephemeral models are inlined as CTEs. Avoid them when they're reused by many models or need debugging, because you can't query them.
11. **How does dbt know the run order?** It parses `ref`/`source` to build a DAG (`manifest.json`). `threads` controls how many models run in parallel.
12. **How do custom schemas work?** By default they're named `target_schema_custom`. Override `generate_schema_name` to get clean prod names.
13. **How do you manage dev/prod?** Targets in `profiles.yml`, separate databases or schemas, separate roles and warehouses, and zero-copy clones for dev data.
14. **What's Slim CI?** `state:modified+` with `--defer --state` builds only the changed models. It saves time and credits.
15. **How do you orchestrate dbt with Airflow?** Cosmos `DbtTaskGroup` (one Airflow task per model, so you get retries and visibility), `BashOperator("dbt build")`, or a dbt Cloud job operator. On Snowflake you can also use `EXECUTE DBT PROJECT` in a Snowflake Task.
16. **dbt vs Snowflake Streams/Tasks/Dynamic Tables?** Streams/Tasks are for low-latency native CDC. dbt is for tested, documented, modular batch work. dbt can even build Dynamic Tables.
17. **How do you optimize a slow model?** Check the Query Profile. Make it incremental, add clustering or pruning, use a bigger warehouse for that model only (`snowflake_warehouse`), avoid `select *` chains, and materialize heavy intermediate models.
18. **What's the purpose of a macro?** Reusable Jinja/SQL that keeps code DRY (Don't Repeat Yourself). Examples: grants, surrogate keys, schema naming.
19. **What's `{{ this }}`?** The relation of the current model.
20. **What are model contracts?** Enforced column names and types, so downstream consumers don't break. Used in dbt Mesh.

---

## Part E: Scenario answers
| Scenario | Answer |
|---|---|
| A test fails in prod at 3 AM | `dbt build` skips downstream models, so bad data doesn't spread. Airflow sends an alert. Check `store_failures` rows, fix or quarantine, then `dbt retry` or `dbt build -s failed_model+`. |
| A 2B-row table takes hours | Make it incremental with merge, cluster on the filter or merge column, use a dedicated warehouse, and consider `delete+insert` by date. |
| Track customer tier history | Snapshot (SCD2) |
| Migrate a 1000-line stored procedure | Break it into staging, intermediate, and mart models. Add tests at each layer. Run old and new side by side and compare with `dbt_utils.equality` or `EXCEPT`. |
| A source schema adds a column | `on_schema_change='append_new_columns'` for incremental models, a contract if strictness is needed, and source freshness and tests. |
| PII columns | Masking policies in Snowflake applied via post_hook or governance tags, and `secure` views. |

---

## Final 30-minute review before the interview
1. Say the one-line pitch and the layer story (S0/S1/ADL/MDW → staging/intermediate/marts).
2. Write an incremental model from memory.
3. List the 4 generic tests and explain `build` vs `run`.
4. Explain the snapshot columns.
5. Know your selectors: `+model+`, `state:modified+`.
6. Know 3 Snowflake configs: `transient`, `cluster_by`, `snowflake_warehouse` (plus `query_tag`).
