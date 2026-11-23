# Snowflake Warehouse Types: Reference Guide

_Account region: AWS_EU_CENTRAL_1 (Frankfurt). Gen2 is available here._
_Verify credit rates against the official [Credit Consumption Table](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf) before making budget decisions._

---

## 1. Overview

| Type | `WAREHOUSE_TYPE` / clause | What it's for | You manage |
|---|---|---|---|
| **Standard Gen1** | `STANDARD`, `GENERATION='1'` | General SQL: BI, ELT, ad-hoc | Size, multi-cluster, QAS |
| **Standard Gen2** | `STANDARD`, `GENERATION='2'` | The same work on faster hardware and software | Size, multi-cluster, QAS |
| **Adaptive** | `ADAPTIVE` | General SQL with no sizing to manage | Performance cap and throughput multiplier only |
| **Snowpark-optimized** | `SNOWPARK-OPTIMIZED` | Memory-heavy Python/Java: ML training, large UDFs and procs | Size, memory (`RESOURCE_CONSTRAINT`), CPU architecture |
| **Interactive** | `CREATE INTERACTIVE WAREHOUSE` | Sub-second, high-concurrency serving: dashboards, APIs | Size, added (pre-warmed) tables |

Gen1 and Gen2 are two **generations** of the same `STANDARD` type. Adaptive, Snowpark-optimized and Interactive are separate **types**.

---

## 2. Gen1 vs Gen2

### What Gen2 is
Gen2 is an upgraded version of the Standard warehouse. It is still the `STANDARD` type, but it uses faster hardware (CPU, memory, cache) and adds software optimizations.

| | Gen1 | Gen2 |
|---|---|---|
| Hardware | Previous generation | Faster CPUs, memory and cache (varies by cloud) |
| DML (DELETE / UPDATE / MERGE) | Baseline | Significantly faster ([engineering blog](https://www.snowflake.com/en/engineering-blog/dml-performance-snowflake-gen2-warehouses/)) |
| Table scans | Baseline | Faster |
| Concurrency | Baseline | Higher, so less queuing |
| Sizes | XS – 6XL | XS – **4XL** only (no 5XL/6XL) |
| Snowpark-optimized | Yes | **No** |
| Resume | Cold start | Draws from a pool of warmed servers sized to your usage. Resume time can differ from Gen1 |
| Set in Snowsight UI | n/a | **No.** You must use SQL |
| Default for new orgs | Older orgs | AWS Frankfurt orgs created after 27 Jun 2025, and other regions after 15 Jul 2025 |

### Credits per hour (AWS; Gen1 is the same on every cloud)

| Size | Gen1 | Gen2 (AWS) | Gen2 (Azure) |
|---|---|---|---|
| XS | 1 | 1.35 | 1.25 |
| S | 2 | 2.7 | 2.5 |
| M | 4 | 5.4 | 5 |
| L | 8 | 10.8 | 10 |
| XL | 16 | 21.6 | 20 |
| 2XL | 32 | 43.2 | 40 |
| 3XL | 64 | 86.4 | 80 |
| 4XL | 128 | 172.8 | 160 |

### Why move to Gen2
- **Performance.** Queries finish faster, and the gains are largest on MERGE, UPDATE and DELETE pipelines and large scans.
- **Comparable cost.** The hourly rate is higher, but faster runtimes mean fewer billed seconds for the same work. **Gen2 is a performance upgrade, not a way to save money.** Measure the cost for your own workload.
- **Less queuing.** Higher concurrency suits dashboards with many users.
- **Low risk.** It is the same type and switches over live with no downtime. Rolling back takes one statement.
- **Smaller sizes may be enough.** A Gen2 4XL may handle work that needed a Gen1 5XL/6XL, so benchmark it.

**Gen2 may not pay off for:** very light workloads such as point lookups and tiny queries.

### How to move
```sql
-- check the current generation (INFORMATION_SCHEMA does not show it)
SHOW WAREHOUSES LIKE 'MY_WH';              -- see the "generation" column

ALTER WAREHOUSE MY_WH SET GENERATION = '2'; -- live, no downtime
ALTER WAREHOUSE MY_WH SET GENERATION = '1'; -- rollback

CREATE WAREHOUSE NEW_WH GENERATION = '2' WAREHOUSE_SIZE = SMALL
  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
```
- If you convert while the warehouse is running, running queries finish on the old compute and new queries start on Gen2. You pay for both during that brief overlap. To avoid the overlap, suspend the warehouse first.
- **Replication:** failover regions must also support Gen2, or Gen2 warehouses may fail to resume after failover.
- **Benchmark:** run representative queries on Gen1 and Gen2 and compare elapsed time, credits and spilling.

### 2.1 Concurrency and clustering on Standard (Gen1 / Gen2) warehouses

There are two levels of concurrency: **within one cluster** and **across clusters**.

**Within one cluster: `MAX_CONCURRENCY_LEVEL`**
- By default a warehouse is **one cluster**. Its size (XS, S, M…) sets how much compute that cluster has.
- `MAX_CONCURRENCY_LEVEL` **defaults to 8**. It is the most queries one cluster runs at the same time.
- 8 is a **ceiling, not a guarantee**. Light queries: up to about 8 run together. Heavy queries: fewer run, and the rest **queue** until resources free up.
- A larger size gives each query more compute. **It does not raise the limit of 8.**

```sql
ALTER WAREHOUSE MY_WH SET MAX_CONCURRENCY_LEVEL = 4;          -- fewer queries, more resources each
ALTER WAREHOUSE MY_WH SET STATEMENT_QUEUED_TIMEOUT_IN_SECONDS = 600; -- cancel queries that wait too long
```
Lowering the limit can speed up large, complex queries, but more queries will queue.

**Across clusters: multi-cluster warehouses (Enterprise+)**

When one cluster is full and queries queue, Snowflake can start **more clusters of the same size**.

| Setting | Meaning |
|---|---|
| `MIN_CLUSTER_COUNT` | Clusters that stay running |
| `MAX_CLUSTER_COUNT` | The most it can scale out to |
| `SCALING_POLICY` | How quickly clusters are added or removed |

| Mode | Configuration | Use when |
|---|---|---|
| **Maximized** | MIN = MAX (> 1) | Concurrency is steady and heavy, so all clusters run all the time |
| **Auto-scale** | MIN < MAX | Load varies, so clusters start when queries queue and stop when load drops |

| Scaling policy | Behaviour |
|---|---|
| **STANDARD** (default) | Favours performance. Starts a new cluster as soon as queries begin to queue |
| **ECONOMY** | Favours saving credits. Adds a cluster only when there is enough sustained load to keep it busy, so expect more queuing |

**Maximum clusters by size**

| Size | Max clusters |
|---|---|
| XS / S / M | 300 |
| L | 160 |
| XL | 80 |
| 2XL | 40 |
| 3XL | 20 |
| 4XL / 5XL / 6XL | 10 |

Tip: start with auto-scale and small numbers (for example MIN = 1, MAX = 2–3), then raise them as you see how the load changes.

**How many queries can run in parallel?**

Rough ceiling ≈ `MAX_CONCURRENCY_LEVEL` × running clusters

| Setup | Approximate parallel queries |
|---|---|
| Single cluster, default | up to ~8 |
| Multi-cluster, MAX = 3 | up to ~24 |
| Multi-cluster, MAX = 10 | up to ~80 |

These are upper bounds. Heavy queries lower the real number.

**Cost:** every running cluster bills at the warehouse size's rate. For example, a Medium Gen1 warehouse with 3 clusters costs up to 4 × 3 = **12 credits/hour**.

```sql
CREATE WAREHOUSE BI_WH WAREHOUSE_SIZE = MEDIUM GENERATION = '2'
  MIN_CLUSTER_COUNT = 1 MAX_CLUSTER_COUNT = 3 SCALING_POLICY = 'STANDARD'
  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
```

**Standard vs Adaptive concurrency**

| | Gen1 / Gen2 Standard | Adaptive |
|---|---|---|
| Per-cluster limit | `MAX_CONCURRENCY_LEVEL` (default 8) | None for you to set |
| Scaling out | Adds whole clusters (MIN/MAX) | `QUERY_THROUGHPUT_MULTIPLIER` raises capacity in a shared pool |
| Predictability | You can estimate it (≈ 8 × clusters) | No documented query count. Measure it in `WAREHOUSE_LOAD_HISTORY` |

This is why Standard is easier to reason about for strict-SLA workloads. Adaptive trades that control for less tuning.

Sources: [Multi-cluster warehouses](https://docs.snowflake.com/en/user-guide/warehouses-multicluster), [Limiting concurrent queries](https://docs.snowflake.com/en/user-guide/performance-query-warehouse-max-concurrency)

---

## 3. Adaptive warehouses

### What it is
Adaptive is a **new warehouse type** (`ADAPTIVE`). There is no warehouse size, no multi-cluster setup and no QAS to tune. Every adaptive warehouse in the account sends its queries to one **shared compute pool dedicated to your account**. That pool is not shared with other accounts or with your other warehouse types. Snowflake picks the resources for each query, up to a cap you set.

| Parameter | Controls | Values | Default |
|---|---|---|---|
| `MAX_QUERY_PERFORMANCE_LEVEL` | The most resource a single query can get | XSMALL … X4LARGE | XLARGE |
| `QUERY_THROUGHPUT_MULTIPLIER` | Peak concurrent capacity at the max level | Integer ≥ 2, or 0 = unlimited | 2 |

### Gen2 vs Adaptive
| | Gen2 | Adaptive |
|---|---|---|
| Compute model | Fixed size (XS–4XL) | Resources chosen per query, up to the cap |
| Concurrency | Multi-cluster min/max | `QUERY_THROUGHPUT_MULTIPLIER` |
| Sizing | You | Snowflake |
| QAS | Separate setting and charge | Included in compute credits |
| Billing | Per second while running | **Per query.** Billing starts with the first query, not when the warehouse is created |
| Per-query credits | Not directly | `ACCOUNT_USAGE.QUERY_METERING_HISTORY` |
| Migration | Change the generation | Change the type (both Gen1 and Gen2 can convert) |

Gen2 makes the familiar sizing model faster. Adaptive removes sizing altogether.

### Requirements and limits
- **Enterprise edition or higher.**
- Cannot convert: Snowpark-optimized, Interactive, 5XL/6XL.
- Not recommended for **hybrid-table** (HTAP) workloads, or for SLA-sensitive work that needs precise guarantees.
- Adaptive is a performance and operations feature. **It does not guarantee lower spend.** Measure the cost for your workload.
- You can keep several adaptive warehouses to separate workloads. Resource monitors and budgets still apply.

```sql
CREATE ADAPTIVE WAREHOUSE MY_ADAPTIVE_WH;   -- or convert an existing warehouse:
ALTER WAREHOUSE MY_WH SET WAREHOUSE_TYPE = 'ADAPTIVE';
ALTER WAREHOUSE MY_WH SET WAREHOUSE_TYPE = 'STANDARD';  -- revert, online
```
Docs: https://docs.snowflake.com/en/user-guide/warehouses-adaptive

### 3.1 How `QUERY_THROUGHPUT_MULTIPLIER` (QTM) works

- **What it is:** a scaling factor for how much work the warehouse can run at the same time, measured for queries running at the `MAX_QUERY_PERFORMANCE_LEVEL` cap.
- **What it is not:** a count of queries, clusters or parallel statements. `QTM = 4` does **not** mean "4 queries at once". It multiplies the warehouse's concurrent capacity.
- **Values:** an integer **≥ 2**, or **0 = unlimited**. The default is **2**.
- **Related setting:** QTM sets *how much runs in parallel*. `MAX_QUERY_PERFORMANCE_LEVEL` sets *how big a single query can get*. Together they set the peak capacity of the warehouse.
- **Compared with Standard:** QTM takes the place of the multi-cluster `MIN/MAX_CLUSTER_COUNT` and scaling policy. You don't manage clusters, because Snowflake runs the shared account pool.
- **Cost:** QTM is a **performance setting, not a spending limit**. Use resource monitors and budgets to control spend.

**Starting points**

| Workload | `MAX_QUERY_PERFORMANCE_LEVEL` | QTM |
|---|---|---|
| Latency-sensitive / critical | XLARGE or higher | Higher (4–8) |
| Mixed / general purpose | MEDIUM–LARGE | 2–4 |
| Low-complexity / batch | SMALL–MEDIUM | 2–4 |

**When to change it**

| Symptom | Evidence | Action |
|---|---|---|
| Queries are queuing | `AVG_QUEUED_LOAD` in `WAREHOUSE_LOAD_HISTORY` is consistently > 0, or peaks are high | Raise QTM. Conservative: `CEIL(current × 1.2)`. If queuing is severe: `current × 2` |
| The workload is lighter than expected | Little or no queuing, low `AVG_RUNNING` | Lower QTM to match how much actually runs at once (minimum 2) |
| A single query is slow or times out | Long `EXECUTION_TIME` in `QUERY_HISTORY` | QTM won't help. Raise `MAX_QUERY_PERFORMANCE_LEVEL` by one or two levels instead (max X4LARGE) |
| QTM is already 0 and queries still queue | n/a | The cause is something other than QTM. Investigate further |
| Credits went up | No evidence of queuing | Don't change QTM based on cost alone. Analyse the spend first |

```sql
-- diagnose queuing (last 7 days)
SELECT DATE_TRUNC('hour', start_time) AS hour,
       AVG(avg_running)      AS avg_running,
       AVG(avg_queued_load)  AS avg_queued_load,
       MAX(avg_queued_load)  AS peak_queued_load
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE warehouse_name = 'MY_ADAPTIVE_WH'
  AND start_time >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY 1 ORDER BY avg_queued_load DESC LIMIT 48;

-- adjust
ALTER WAREHOUSE MY_ADAPTIVE_WH SET QUERY_THROUGHPUT_MULTIPLIER = 4;
SHOW WAREHOUSES LIKE 'MY_ADAPTIVE_WH';   -- check the current values
```
Change one setting at a time. Compare the same weekdays before and after, and watch for a week before tuning again.

### 3.2 When to recommend Adaptive

**Good fit**
- Mixed workloads where query sizes vary widely. Each query is sized on its own.
- Dashboards and high-concurrency workloads, especially those on multi-cluster today.
- Warehouses that use QAS today (QAS is included in compute credits).
- Analytics and transformation (ELT) pipelines, including steady ones.
- Teams that keep resizing warehouses or can't agree on a size.
- Teams that value low admin effort over fine-grained control.

**Poor fit**
- Hybrid tables and HTAP-style key-value access. Keep these on Standard.
- Strict-SLA workloads that need precise, predictable performance. A fixed-size Standard warehouse gives more control.
- Not supported: Snowpark-optimized, Interactive, and workloads that need 5XL/6XL.
- Standard edition accounts (Enterprise or higher is required).

### 3.3 Pros and cons

| Pros | Cons |
|---|---|
| No warehouse sizing. Resources are picked per query, up to the cap | Lower cost is not guaranteed. Measure it for your workload |
| No multi-cluster or QAS tuning. One setting (QTM) controls concurrency | Less explicit control than a fixed size, which matters for strict SLAs |
| Right-sizing per query: small queries don't run on an oversized warehouse, and big queries aren't starved | No Snowpark-optimized memory, no 5XL/6XL, no Interactive |
| Compute pool used only by your account | Not recommended for hybrid tables |
| Per-query billing, with visibility in `QUERY_METERING_HISTORY` | Requires Enterprise edition or higher |
| You can still keep several Adaptive warehouses to separate workloads | A new cost model: comparing before and after needs per-query views and care |
| Resource monitors and budgets work the same as on Standard | The cap and QTM still need monitoring and tuning after migration |
| Online conversion, and reverting to Standard is quick | n/a |

### 3.4 Rollout approach
1. Pick a pilot warehouse: one with mixed query sizes, or one that is often resized or multi-cluster tuned.
2. Record a baseline: credits, elapsed time and queue time.
3. Convert and start with the defaults (`XLARGE`, QTM `2`).
4. Compare matched weekdays, then tune. If queries queue, raise QTM. If single queries are slow, raise the performance level.
5. Keep hybrid-table, strict-SLA and Snowpark-memory workloads on Standard (Gen2 where available).

---

## 4. Snowpark-optimized warehouses

- Built for **memory-heavy Snowpark work**: ML training in stored procedures, large UDFs/UDTFs, and code that depends on a specific CPU architecture. Ordinary SQL usually gains nothing from it.
- Each node is a single instance with configurable memory. The default is **16x the memory of a standard node**.

| `RESOURCE_CONSTRAINT` | Memory (up to) | Min size |
|---|---|---|
| `MEMORY_1X` / `_x86` | 16 GB | XSMALL |
| `MEMORY_16X` / `_x86` (default) | 256 GB | MEDIUM |
| `MEMORY_64X` / `_x86` (preview, AWS only) | 1 TB | LARGE |

- Creating and resuming take longer than for Standard warehouses.
- **Gen1 only.** Gen2 and Adaptive are not available for this type.
- Converting to Gen2 Standard reduces memory to the `MEMORY_1X` level. Check your memory needs before you switch.

```sql
CREATE WAREHOUSE SO_WH WAREHOUSE_SIZE='MEDIUM'
  WAREHOUSE_TYPE='SNOWPARK-OPTIMIZED' RESOURCE_CONSTRAINT='MEMORY_16X';
```
Docs: https://docs.snowflake.com/en/user-guide/warehouses-snowpark-optimized

---

## 5. Interactive warehouses

- A query engine tuned for **sub-second latency and high concurrency**. Use it for real-time dashboards, data APIs with repeated query shapes, alerting, and selective agent/AI queries.
- Works with standard, dynamic, interactive and Iceberg tables. Hybrid tables are supported only for compatibility and are not recommended.
- Tables you add to the warehouse are **pre-warmed when it resumes**. Queries are slow until warming finishes, which runs at about 300–400 MB/s on XS and faster on larger sizes.
- Cannot be converted to Gen2 or Adaptive.

```sql
CREATE OR REPLACE INTERACTIVE WAREHOUSE INTERACTIVE_DEMO WAREHOUSE_SIZE = 'XSMALL';
ALTER WAREHOUSE INTERACTIVE_DEMO RESUME;
```
Docs: https://docs.snowflake.com/en/user-guide/interactive

---

## 6. Serverless compute (not a warehouse type)

Snowflake has **no "serverless warehouse" type**. "Serverless" means **Snowflake-managed compute**: Snowflake provides and sizes the compute for certain features, and you never create, size or suspend a warehouse for them. They don't run on your virtual warehouses.

### Main serverless features

| Feature | What it does |
|---|---|
| **Serverless tasks** | Scheduled or triggered tasks with no `WAREHOUSE =` clause |
| **Snowpipe / Snowpipe Streaming** | Continuous file and row ingestion |
| **Automatic clustering** | Background reclustering of tables with clustering keys |
| **Materialized view maintenance** | Keeps materialized views up to date |
| **Search optimization service** | Builds and maintains search access paths |
| **Query Acceleration Service** | Offloads parts of large queries. Billed separately on Standard, included in Adaptive |
| **Replication / failover** | Copies data between accounts and regions |
| **Data metric functions** | Data quality checks |
| **Snowflake App Runtime serverless apps** (preview) | Apps that start on request and stop after an idle period (1 hour by default) |

### Serverless tasks

```sql
-- no WAREHOUSE clause = serverless
CREATE TASK nightly_load
  SCHEDULE = 'USING CRON 0 2 * * * UTC'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'   -- size for the first runs only
AS
  CALL load_proc();
```
- Snowflake picks the compute size from the task's run history, and resizes to try to finish each run within the schedule interval. For example, a task that runs every minute is aimed at finishing in about 54 seconds.
- A Community KB article says the initial-size setting only governs the first run. A newer setting, `SERVERLESS_TASK_MIN/MAX_STATEMENT_SIZE`, may cap the size. **It hasn't been checked in the docs yet**, so confirm it in the [CREATE TASK docs](https://docs.snowflake.com/en/sql-reference/sql/create-task) before relying on it.
- If you need fixed, predictable compute, give the task a `WAREHOUSE =` and it uses your own warehouse instead.

### Serverless vs a virtual warehouse

| | Virtual warehouse (Standard / Gen2 / Adaptive) | Serverless |
|---|---|---|
| Who sizes and manages it | You (or Adaptive within caps you set) | Snowflake |
| Idle cost | Billed while running, with a 60-second minimum on each resume | You pay only for the compute used |
| Billing | Warehouse credits by size and runtime | Per-feature serverless credits. Rates are in the [Credit Consumption Table](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf), Serverless Features table |
| Best for | Interactive SQL, BI, ELT you control | Short or frequent tasks, ingestion, background maintenance |
| Control | Full control of size and concurrency | Little or none |

### When to use serverless
- **Good fit:** short tasks that run often, where a warehouse would bill its 60-second minimum or sit idle; continuous ingestion; background maintenance features.
- **Less suitable:** long, heavy jobs (a warehouse you already keep busy is often cheaper), and work that needs exact sizing or a guaranteed SLA.

### Monitoring serverless cost
```sql
SELECT service_type, SUM(credits_billed) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY 1 ORDER BY 2 DESC;
```
Per-feature views:
- `SERVERLESS_TASK_HISTORY`
- `PIPE_USAGE_HISTORY`
- `AUTOMATIC_CLUSTERING_HISTORY`
- `MATERIALIZED_VIEW_REFRESH_HISTORY`
- `SEARCH_OPTIMIZATION_HISTORY`

> **Adaptive vs serverless:** Adaptive is still a warehouse you create, just without sizing. Serverless features don't use a warehouse you own at all.

---

## 7. Features that apply across types

- **Multi-cluster** (Enterprise+): Standard warehouses scale out for concurrency, with min/max clusters and a scaling policy. On Adaptive, `QUERY_THROUGHPUT_MULTIPLIER` does this job.
- **Query Acceleration Service (QAS):** offloads parts of large scans on Standard warehouses. It is included automatically on Adaptive.
- **Auto-suspend / auto-resume, resource monitors, budgets:** available for all types.

---

## 8. Choosing a type

| Workload | Recommendation |
|---|---|
| ETL/ELT with heavy MERGE/UPDATE/DELETE | **Gen2 Standard** |
| BI dashboards with many users and a known size | **Gen2 Standard** (multi-cluster) |
| Mixed or unpredictable SQL, and you don't want to manage sizing | **Adaptive** |
| ML training, memory-heavy Python/Java | **Snowpark-optimized** |
| Sub-second serving for APIs or dashboards at high concurrency | **Interactive** |
| Hybrid tables / HTAP | **Standard** (not Adaptive) |
| Short or frequent scheduled tasks, continuous ingestion | **Serverless** (serverless tasks / Snowpipe) |
| Needs 5XL/6XL | Gen1 today; benchmark a Gen2 4XL first |

**Suggested path:** Gen1 → **Gen2** (low risk, quick to roll back) → trial **Adaptive** on selected warehouses where removing sizing work is valuable. Measure credits and latency before and after each step.
