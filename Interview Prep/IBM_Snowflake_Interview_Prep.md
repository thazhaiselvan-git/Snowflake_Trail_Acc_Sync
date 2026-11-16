# IBM – Data Engineer (Snowflake Data Platforms) – Interview Prep Guide

> Role level: 10–12 yrs | Consulting / client-facing | Focus: Snowflake + Data Engineering + Cloud + Data & AI

---

## 0. How to Use This Guide

| Day | Focus | Sections |
|-----|-------|----------|
| 1 | Architecture, performance, cost | 1, 2 |
| 2 | Pipelines + SQL practice | 3, 7 |
| 3 | Security, governance, sharing | 4, 5 |
| 4 | Cortex AI / ML (build a mini demo) | 6 |
| 5 | Data modeling, migration, cloud, DevOps | 8, 9 |
| 6 | Architecture whiteboard + STAR stories | 10, 11 |
| 7 | Mock interview using Q&A bank | 12 |

---

## 1. Snowflake Architecture

**Three layers**
1. **Storage** – columnar, compressed, immutable **micro-partitions** (50–500 MB uncompressed) on cloud object storage.
2. **Compute** – **virtual warehouses** (independent MPP clusters). Scale up (size) for complex queries; scale out (multi-cluster) for concurrency.
3. **Cloud Services** – auth, metadata, optimizer, transactions, security, result cache.

**Why it matters:** storage & compute scale independently → workload isolation (ETL vs BI vs DS warehouses), pay-per-second, no contention.

**Table types**
| Type | Time Travel | Fail-safe | Use |
|------|-------------|-----------|-----|
| Permanent | 0–90 days (Enterprise) | 7 days | Prod data |
| Transient | 0–1 day | None | Staging / reproducible data |
| Temporary | 0–1 day | None | Session-only |

**Key features to explain**
- **Zero-copy cloning** – metadata-only copy; great for dev/test environments.
- **Time Travel** – `AT(OFFSET => -3600)`, `BEFORE(STATEMENT => '<qid>')`, `UNDROP TABLE`.
- **Fail-safe** – 7 days, Snowflake-support recovery only.

```sql
CREATE DATABASE dev_db CLONE prod_db;
SELECT * FROM orders AT(OFFSET => -60*60);
UNDROP TABLE orders;
```

### 1a. Micro-partitions – deep dive

**Columnar** – values stored column by column, not row by row.
```
Row store : [1,Asha,Exec,300000] [2,Ravi,Eng,180000] ...
Columnar  : emp_id [1,2,3] | name [Asha,Ravi,Meena] | dept [Exec,Eng,Eng] | salary [...]
```
→ `SELECT AVG(salary)` reads only the salary column. 100 columns, 2 used ≈ 2% of the data read.

**Compressed** – same-type, repetitive column values shrink well; Snowflake picks the encoding per column automatically.
| Technique | Example |
|-----------|---------|
| Dictionary | `[Exec, Eng, Eng]` → `{0=Exec,1=Eng}` + `[0,1,1]` |
| Run-length | `[Eng, Eng, Eng, Eng]` → `Eng × 4` |
| Delta | dates `[10-01, 10-02, 10-03]` → start + `[+1,+1]` |

→ Lower storage bill (billed on compressed size) + less I/O.

**Immutable** – never edited in place. `UPDATE`/`DELETE` write **new** micro-partitions and retire the old ones → enables Time Travel, cloning, consistent reads.

**Metadata per micro-partition** (kept in Cloud Services): min/max per column, distinct count, NULL count, row count.
- **Pruning**: `WHERE sale_date = '2026-10-03'` skips every partition whose min/max range excludes that date.
- **Metadata-only answers**: `COUNT(*)`, `MIN`, `MAX` often need no warehouse.

**Clustering**
- Data is naturally clustered in **load order** (e.g. by date when loaded daily).
- Over time DML scatters values → overlapping min/max ranges → poor pruning.
- **Clustering key** + **Automatic Clustering** (serverless, billed) reorganizes partitions.
- Health metrics: **clustering depth** (lower = better), overlaps.

```sql
ALTER TABLE sales.fact_orders CLUSTER BY (order_date, region);
SELECT SYSTEM$CLUSTERING_INFORMATION('sales.fact_orders', '(order_date)');
SELECT SYSTEM$CLUSTERING_DEPTH('sales.fact_orders', '(order_date)');
ALTER TABLE sales.fact_orders SUSPEND RECLUSTER;   -- pause cost
```

**Good clustering key:** frequently filtered/joined column, enough distinct values to prune but not unique (e.g. `DATE`, not `TIMESTAMP` or ID – use `TO_DATE(ts)`), max 3–4 columns, low → high cardinality order.

**Check pruning in Query Profile:** *Partitions scanned* vs *Partitions total* on the TableScan operator.

**How rows and columns are laid out (hybrid columnar / PAX)** – rows are grouped horizontally into micro-partitions (load order), and **inside** each one every column is a separate compressed block with its own min/max. Both happen at write time, not in two steps.
```
              col_1  col_2  col_3 ... col_100
            ┌──────┬──────┬──────┬───┬───────┐
MP1 rows    │ ███  │ ███  │ ███  │...│  ███  │   ← each █ = one compressed column block
1–200K      ├──────┼──────┼──────┼───┼───────┤
MP2 rows    │ ███  │ ███  │ ███  │...│  ███  │
200K–400K   └──────┴──────┴──────┴───┴───────┘
```
Rows → **pruning** (skip micro-partitions). Columns → **projection** (read only needed columns).

**Real-world example – online store `orders` table**

Setup: 100 columns, ~1M orders/day loaded nightly, 30 days → 30M rows ≈ **300 micro-partitions** (assume ~10 per day).
```
Day 1  (Nov 1)  → MP1   … MP10    order_date min/max: Nov 1
Day 2  (Nov 2)  → MP11  … MP20    order_date min/max: Nov 2
...
Day 30 (Nov 30) → MP291 … MP300   order_date min/max: Nov 30
```

*Query A – revenue on Nov 15*
```sql
SELECT SUM(amount) FROM orders WHERE order_date = '2026-11-15';
```
1. **Pruning** (metadata only): MP1–140 and MP151–300 skipped → read **10 of 300** micro-partitions.
2. **Columnar**: inside those 10, open only `order_date` + `amount` → **2 of 100** columns.
→ reads ≈ 0.07 % of the table.

*Query B – revenue from Chennai*
```sql
SELECT SUM(amount) FROM orders WHERE city = 'Chennai';
```
Chennai orders arrive every day → every micro-partition's `city` min/max covers "Chennai" → **no pruning (300 of 300)**. Columnar still helps (2 of 100 columns).
Fix *only if* this query is frequent and the table is large: `ALTER TABLE orders CLUSTER BY (city);` → Automatic Clustering groups Chennai rows into few micro-partitions (costs credits).

| Query | Pruning (row groups) | Columnar (column blocks) |
|-------|----------------------|--------------------------|
| Revenue on Nov 15 | 10 / 300 read | 2 / 100 columns |
| Revenue from Chennai | 300 / 300 read | 2 / 100 columns |

> Analogy: a library with one shelf per day's newspapers. "Nov 15" → go to one shelf, read only the sports page. "Every Chennai article" → check every shelf, but still read only that page.

### 1b. Zero-copy cloning – what happens in the backend

```sql
CREATE TABLE emp_clone CLONE emp;
```

**Step 1 – clone = metadata copy.** Cloud Services copies the table's list of micro-partition pointers. No data read or written, no warehouse needed, seconds even for TBs. **Extra storage = 0.**
```
emp        ──►  [MP1] [MP2] [MP3]
emp_clone  ──►  [MP1] [MP2] [MP3]   (same files, new pointer list)
```

**Step 2 – copy-on-write.** Partitions are immutable, so a change on either side writes a new partition for that side only.
```sql
UPDATE emp_clone SET salary = salary * 1.1 WHERE dept = 'Eng';   -- rows in MP2
```
```
emp        ──►  [MP1] [MP2]  [MP3]
emp_clone  ──►  [MP1] [MP2'] [MP3]   ← only MP2' is new storage
```

**Step 3 – billing.** Pay only for partitions new/changed after the clone. Shared partitions billed once. Dropping the source keeps shared partitions alive (and billed) while the clone references them.

**What is / isn't carried over**
| Item | Cloned? |
|------|---------|
| Data, structure, clustering key | Yes (shared partitions) |
| Grants on the cloned table | No – unless `COPY GRANTS` |
| Grants on child objects (database / schema clone) | Yes |
| Source Time Travel history | No – clone history starts at clone time |
| `COPY INTO` load history | No – re-running COPY may reload the same files |
| Streams (table clone) | No; in DB/schema clones yes, but unconsumed changes are lost |
| Tasks (DB/schema clone) | Yes, created **suspended** |
| Stages (DB/schema clone) | External named stages: yes. Internal named stages: only with `INCLUDE INTERNAL STAGES`. Table stages: cloned but empty |
| Pipes (DB/schema clone) | Pipes on external stages: yes (paused). Pipes on internal stages: no |

**Clone + Time Travel (recovery pattern)**
```sql
CREATE TABLE emp_before_bug CLONE emp AT (OFFSET => -3600);              -- 1 hour ago
CREATE TABLE emp_before_bug CLONE emp BEFORE (STATEMENT => '<query_id>'); -- before bad DML
CREATE DATABASE dev_db CLONE prod_db AT (TIMESTAMP => '2026-11-01 00:00'::TIMESTAMP_LTZ);
```

**Clone + swap (fix-and-replace pattern)**
```sql
CREATE TABLE orders_fix CLONE orders;
-- fix data in orders_fix, validate
ALTER TABLE orders SWAP WITH orders_fix;   -- atomic, readers see old or new
```

**Typical uses:** dev/QA from prod in seconds, test a risky change on a clone, point-in-time backup before a release, recovery after bad DML.

**Interview one-liners**
- *Micro-partitions:* "Immutable, columnar, compressed storage units with min/max metadata per column, so queries read only needed columns and skip non-matching partitions."
- *Clone:* "A metadata copy pointing to the same immutable micro-partitions – instant, no extra storage; only partitions changed afterwards in either object are written and billed."

---

## 2. Performance Tuning & Cost Optimization

**Diagnose a slow query (say this sequence):**
1. Open **Query Profile** → find most expensive operator.
2. Check **partitions scanned vs total** → poor pruning?
3. Check **bytes spilled** to local/remote → warehouse too small.
4. Check **exploding joins**, missing filters, `SELECT *`.
5. Check **queuing** → multi-cluster / separate warehouse.

**Levers**
| Problem | Fix |
|---------|-----|
| Poor pruning on large table | Clustering key, filter on clustered cols |
| Point lookups / selective filters | Search Optimization Service |
| Repeated expensive aggregations | Materialized views / Dynamic Tables |
| Spilling | Bigger warehouse, reduce data early |
| Concurrency queuing | Multi-cluster warehouse |
| Unpredictable large scans | Query Acceleration Service |

**Caches:** Result cache (24h, cloud services) → Local disk/warehouse cache (lost on suspend) → Metadata cache (COUNT/MIN/MAX free).

**Cost control**
- Auto-suspend 60s, auto-resume, right-size warehouses.
- **Resource monitors** (credit quota, notify/suspend) and **Budgets**.
- Separate warehouses per workload; tag objects/queries for chargeback.
- Monitor via `SNOWFLAKE.ACCOUNT_USAGE`.

```sql
CREATE RESOURCE MONITOR rm_etl WITH CREDIT_QUOTA = 500
  TRIGGERS ON 80 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE etl_wh SET RESOURCE_MONITOR = rm_etl;

-- Top credit consumers last 30 days
SELECT warehouse_name, SUM(credits_used) credits
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD(day,-30,CURRENT_TIMESTAMP())
GROUP BY 1 ORDER BY 2 DESC;

-- Clustering health
SELECT SYSTEM$CLUSTERING_INFORMATION('sales.fact_orders','(order_date)');
```

### 2a. Search Optimization Service (SOS) & Query Acceleration Service (QAS)

**SOS – index-like structure for needle-in-a-haystack lookups**

Problem: `customer_id` is spread across every micro-partition → no pruning.
```sql
SELECT * FROM orders WHERE customer_id = 'C123456';   -- 3 rows out of 30M → scans all 300 MPs
```
Backend: SOS builds a **search access path** (which micro-partitions contain which values), maintained by serverless compute as data changes.
```
'C123456' → MP17, MP242   → read 2 of 300 micro-partitions
```
- Works on any column without reordering the table.
- Good for: equality / `IN`, substring / `LIKE '%x%'`, VARIANT fields, geospatial.
- Use case: support app looking up one customer's orders in a multi-TB table → tens of seconds → ~1 s.
- Cost: storage for the access path + serverless maintenance credits (expensive on high-churn tables). Enterprise Edition+.
```sql
ALTER TABLE orders ADD SEARCH OPTIMIZATION ON EQUALITY(customer_id), SUBSTRING(email);
SELECT SYSTEM$ESTIMATE_SEARCH_OPTIMIZATION_COSTS('orders', 'EQUALITY(customer_id)');
```

**QAS – extra serverless compute for heavy scans**

Problem: one huge outlier query (e.g. a full-year scan) hogs the warehouse; resizing for everyone wastes money.
Backend: for eligible queries, the large scan + filter + aggregation work is **offloaded to shared serverless compute** in parallel; the warehouse finishes the rest.
```
Without QAS: XS warehouse scans 10,000 partitions alone            → 20 min
With QAS   : serverless workers scan in parallel, XS finishes join/sort → 3 min
```
- Good for: ad-hoc / analyst queries with large scans and selective filters or aggregations, unpredictable spikes, keeping a small warehouse size.
- Not useful: no large scan, or time dominated by joins / sorts.
- Use case: XS BI warehouse for dashboards; a monthly 40-min finance query is accelerated without upsizing.
- Cost: serverless credits only while accelerating; capped by the scale factor. Enterprise Edition+.
```sql
ALTER WAREHOUSE bi_wh SET ENABLE_QUERY_ACCELERATION = TRUE
                          QUERY_ACCELERATION_MAX_SCALE_FACTOR = 8;
SELECT SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>');
SELECT query_id, eligible_query_acceleration_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ACCELERATION_ELIGIBLE ORDER BY 2 DESC LIMIT 10;
```

**QAS eligibility – enabled per warehouse, decided per query**

QAS is switched on at warehouse level, but Snowflake decides **per query at run time** whether to accelerate it. You can't flag individual queries.
```
Warehouse bi_wh (QAS enabled)
 ├─ Dashboard, small scan              → not eligible → warehouse only (no extra cost)
 ├─ Lookup returning 3 rows             → not eligible → warehouse only (SOS case)
 └─ Year scan + selective filter / agg  → eligible     → scan offloaded to serverless
```

| Eligible | Common reasons ineligible |
|----------|---------------------------|
| Large scan with a **selective filter** | Scan not large enough (`NO_LARGE_ENOUGH_SCAN`) – no fixed cutoff, depends on plan + warehouse size |
| Large scan with an **aggregation** | Filter not selective enough, or `GROUP BY` cardinality too high |
| Part of the plan can run in parallel | Nondeterministic functions (e.g. `SEQ`, `RANDOM`) |
| Snowflake has high confidence it will be faster | Some `LIMIT` queries – QAS now decides automatically which `LIMIT` queries (even without `ORDER BY`) it can accelerate |

Two meanings of "selective":
- Selective filter **on a big scan** (`WHERE region = 'APAC'` over a year) → **QAS**.
- Point lookup returning a few rows (`WHERE customer_id = 'C123'`) → **SOS**, nothing large to offload.

**Targeting specific workloads** – route them to a dedicated warehouse:
```sql
CREATE WAREHOUSE bi_wh    WAREHOUSE_SIZE = 'XSMALL';                    -- dashboards, no QAS
CREATE WAREHOUSE adhoc_wh WAREHOUSE_SIZE = 'XSMALL'
  ENABLE_QUERY_ACCELERATION = TRUE
  QUERY_ACCELERATION_MAX_SCALE_FACTOR = 4;                              -- heavy ad-hoc / finance
USE WAREHOUSE adhoc_wh;                                                 -- in the heavy job's session
```

**Scale factor (cost control)**
- Upper bound on serverless compute as a multiple of warehouse size. **Default 8; `0` = no upper bound.**
- Example: Medium (4 credits/hr) × scale factor 5 → up to 20 extra credits/hr.
- QAS is enabled by default on **Gen2 standard** and **multi-cluster** warehouses.

**Check eligibility / usage**
```sql
-- Before: would this past query benefit? (status, ineligibleReason, estimated times per scale factor)
SELECT PARSE_JSON(SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>'));

-- After: which queries actually used QAS
SELECT query_id, query_acceleration_bytes_scanned,
       query_acceleration_partitions_scanned, query_acceleration_upper_limit_scale_factor
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_acceleration_partitions_scanned > 0
ORDER BY start_time DESC LIMIT 20;
```

**Interview line:** *"QAS is enabled on a warehouse, but Snowflake decides per query at run time – only large scans with selective filters or aggregations get offloaded. To target specific workloads, route them to a dedicated QAS-enabled warehouse and cap spend with the scale factor (default 8)."*

**Which one?**
| | Clustering key | SOS | QAS |
|---|---|---|---|
| Query shape | Range filters (date ranges) | Selective point lookups | Large scans / aggregations |
| How it helps | Reorders micro-partitions | Lookup structure for pruning | Extra parallel compute |
| Set on | Table | Table / column | Warehouse |
| Cost | Reclustering credits | Storage + maintenance | Credits while accelerating |

**Interview line:** *"Clustering for range filters on a few columns, SOS for selective point lookups on any column, QAS when large scans make a few queries far slower than the rest – they can be combined."*

---

## 3. Data Pipelines

### Ingestion options
| Pattern | Tool | Latency |
|---------|------|---------|
| Batch files | `COPY INTO` from stage | Minutes/hours |
| Continuous files | **Snowpipe** (auto-ingest via S3 SQS / Event Grid / Pub/Sub) | ~1 min |
| Streaming rows | **Snowpipe Streaming**, Kafka connector | Seconds |
| SaaS / DB CDC | **Openflow**, Fivetran, partner tools | Varies |

```sql
CREATE STORAGE INTEGRATION s3_int TYPE=EXTERNAL_STAGE STORAGE_PROVIDER='S3'
  ENABLED=TRUE STORAGE_AWS_ROLE_ARN='arn:aws:iam::123:role/sf'
  STORAGE_ALLOWED_LOCATIONS=('s3://my-bucket/raw/');

CREATE STAGE raw_stage URL='s3://my-bucket/raw/' STORAGE_INTEGRATION=s3_int
  FILE_FORMAT=(TYPE=JSON);

CREATE PIPE raw_pipe AUTO_INGEST=TRUE AS
  COPY INTO raw.events FROM @raw_stage;
```

### Transformation / CDC
**Streams + Tasks** – fine-grained control, procedural logic, custom scheduling.
```sql
CREATE STREAM orders_strm ON TABLE raw.orders;

CREATE TASK merge_orders WAREHOUSE=etl_wh SCHEDULE='5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('orders_strm') AS
MERGE INTO silver.orders t USING orders_strm s ON t.id = s.id
WHEN MATCHED AND s.METADATA$ACTION='DELETE' AND s.METADATA$ISUPDATE=FALSE THEN DELETE
WHEN MATCHED AND s.METADATA$ACTION='INSERT' THEN UPDATE SET t.amount=s.amount
WHEN NOT MATCHED AND s.METADATA$ACTION='INSERT' THEN INSERT (id,amount) VALUES (s.id,s.amount);

ALTER TASK merge_orders RESUME;
```

**Dynamic Tables** – declarative; define the SELECT + `TARGET_LAG`, Snowflake handles incremental refresh & dependency DAG.
```sql
CREATE DYNAMIC TABLE gold.daily_sales TARGET_LAG='15 minutes' WAREHOUSE=etl_wh AS
SELECT order_date, region, SUM(amount) revenue FROM silver.orders GROUP BY 1,2;
```

**When which?**
- Dynamic Tables → SQL-expressible transforms, declarative pipelines, less code.
- Streams+Tasks → procedural logic, calling procs/external functions, exact scheduling, side effects.
- dbt → team SDLC, testing, docs, lineage (can materialize as dynamic tables; dbt Projects on Snowflake runs natively).

### 3a. Streams & Dynamic Tables – how change tracking works in the backend

**Foundation: every DML creates a new table version.** Micro-partitions are immutable, so each DML writes new partitions and produces a new version (a new partition list). Old versions are kept for the Time Travel retention period.
```
v1 (10:00)  orders → [MP1] [MP2]  [MP3]
   UPDATE a row in MP2  → written as MP2'
v2 (10:05)  orders → [MP1] [MP2'] [MP3]
   INSERT new rows      → written as MP4
v3 (10:10)  orders → [MP1] [MP2'] [MP3] [MP4]
```
**Change tracking** (`CHANGE_TRACKING = TRUE`, switched on automatically when a stream is created) adds hidden row-ID/version columns, so Snowflake can match a row in MP2 to the same row in MP2′ and know exactly what changed.

**Streams – a bookmark, not a copy**
```sql
CREATE STREAM orders_strm ON TABLE orders;
```
- Stores only an **offset** (a pointer to one table version, e.g. v1). **No data.**
- Querying the stream compares offset version vs current version:
```
offset = v1           current = v3
[MP1][MP2][MP3]   →   [MP1][MP2'][MP3][MP4]
                       MP1, MP3 unchanged → ignored
                       MP2 → MP2'         → UPDATE
                       MP4 new            → INSERTs
```
- Returns the **net change** (each changed row once, latest values) plus metadata columns:

| METADATA$ACTION | METADATA$ISUPDATE | Meaning |
|-----------------|-------------------|---------|
| INSERT | FALSE | New row |
| DELETE | FALSE | Deleted row |
| DELETE + INSERT | TRUE | Update (old image + new image) |

`METADATA$ROW_ID` identifies the row across versions.

- **Offset moves only when a DML that reads the stream commits** (`INSERT`, `MERGE`, ...). A plain `SELECT` does not move it. Trick to consume without loading: `INSERT INTO sink SELECT ... FROM strm WHERE 1 = 0;`
- **Staleness:** the stream needs the old versions. If not consumed within retention, Snowflake extends retention up to `MAX_DATA_EXTENSION_TIME_IN_DAYS` (default 14); after that the stream becomes **stale** and must be recreated.
- **Types:** Standard (insert/update/delete, net-change compare) · Append-only (inserts only, cheaper – just lists new partitions) · Insert-only (external / Iceberg tables).

**Dynamic Tables – stream + MERGE + scheduler, managed for you**
```sql
CREATE DYNAMIC TABLE daily_sales TARGET_LAG = '15 minutes' WAREHOUSE = etl_wh AS
SELECT order_date, SUM(amount) AS revenue FROM orders GROUP BY order_date;
```
On each refresh:
1. **Scheduler** picks the refresh time so data is never older than `TARGET_LAG`; chained DTs refresh in dependency order, reading the same point in time.
2. **Reads changes since the last refresh** – the DT remembers the source versions it last read (like a stream offset) and uses change tracking to get only inserted/updated/deleted rows.
3. **Incremental refresh** – runs the query on the changes only and merges the result in (only Nov 15 changed → only the Nov 15 row of `daily_sales` is recomputed).
4. **Full refresh** – when the query can't be computed incrementally, the whole result is recomputed.
5. **Commits and records the new versions read**, ready for the next refresh.
```
orders v5 ──(changes v5..v8)──► incremental query ──MERGE──► daily_sales
          remembers "last read = v8"
```
Check behaviour: `SHOW DYNAMIC TABLES` (`refresh_mode`), `DYNAMIC_TABLE_REFRESH_HISTORY`.

**Side by side**
| | Stream | Dynamic Table |
|---|--------|---------------|
| Stores | Offset only (no data) | Full result table |
| Change detection | Offset version vs current version | Same change tracking, internal |
| Who applies changes | You (Task + MERGE) | Snowflake (incremental / full refresh) |
| Position moves | When a DML reading it commits | After each successful refresh |
| Scheduling | You (Task schedule / `WHEN SYSTEM$STREAM_HAS_DATA`) | Automatic, from `TARGET_LAG` |
| Best for | Procedural logic, calling procs, exact control | SQL-expressible transforms, no orchestration code |

**Interview one-liner:** *"A stream is a bookmark on a table version. Querying it compares that version with the current micro-partitions using change-tracking row IDs and returns net changes; the bookmark moves only when a DML reading it commits. A dynamic table uses the same change tracking internally: it remembers the source versions it last read, applies only the changes (or recomputes fully when it must), and Snowflake schedules it to meet the target lag."*

### Semi-structured
```sql
SELECT v:customer.id::STRING cust_id, f.value:sku::STRING sku
FROM raw.events, LATERAL FLATTEN(input => v:items) f;
```

### Snowpark (Python)
- DataFrame API pushed down to Snowflake (lazy execution), UDFs/UDTFs/stored procs, vectorized UDFs, Snowpark-optimized warehouses for memory-heavy ML.

### Open formats
- **Iceberg tables** (Snowflake-managed or external catalog: Glue, Polaris/Open Catalog, Unity) – interoperability with Spark etc.

---

## 4. Security & Governance

**RBAC best practice (explain this pattern):**
- **Access roles** (privileges on objects, e.g. `SALES_RO`, `SALES_RW`) → granted to **functional roles** (e.g. `ANALYST`, `DATA_ENGINEER`) → granted to users.
- Roll all custom roles up to `SYSADMIN`. Use `SECURITYADMIN`/`USERADMIN` for grants/users. Minimize `ACCOUNTADMIN`.
- Use **future grants** and **managed access schemas**; database roles for shareable privilege bundles.

```sql
CREATE ROLE sales_ro;
GRANT USAGE ON DATABASE sales TO ROLE sales_ro;
GRANT USAGE ON ALL SCHEMAS IN DATABASE sales TO ROLE sales_ro;
GRANT SELECT ON FUTURE TABLES IN DATABASE sales TO ROLE sales_ro;
GRANT ROLE sales_ro TO ROLE analyst;
GRANT ROLE analyst TO ROLE sysadmin;
```

**Column / row protection**
```sql
-- Dynamic masking
CREATE MASKING POLICY pii_email AS (val STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('PII_ADMIN') THEN val
       ELSE REGEXP_REPLACE(val,'.+@','*****@') END;
ALTER TABLE customers MODIFY COLUMN email SET MASKING POLICY pii_email;

-- Row access
CREATE ROW ACCESS POLICY region_rap AS (region STRING) RETURNS BOOLEAN ->
  EXISTS (SELECT 1 FROM sec.region_map m
          WHERE m.role = CURRENT_ROLE() AND m.region = region);
ALTER TABLE sales ADD ROW ACCESS POLICY region_rap ON (region);
```
- **Tag-based masking**: attach masking policy to a tag (e.g. `PII=EMAIL`) → auto-protect every tagged column.
- **Auto classification** to detect sensitive data.
- **Auditing**: `ACCESS_HISTORY`, `LOGIN_HISTORY`, lineage in Horizon.
- **Data quality**: Data Metric Functions (NULL_COUNT, FRESHNESS, custom DMFs).

**Network & auth**
- Network policies / rules, PrivateLink, SSO (SAML/OAuth), key-pair auth for service users, MFA.
- Encryption at rest/in transit by default; **Tri-Secret Secure** (customer-managed key); periodic rekeying.

---

## 5. Data Sharing, Replication & DR

- **Secure Data Sharing**: provider grants objects to a **share**; consumer creates DB from share – **no data copy**, live data, consumer pays compute.
- **Reader accounts** for consumers without Snowflake.
- **Listings** (private / Marketplace), cross-region via auto-fulfillment.
- Use **secure views** to share filtered data.
- **Replication & failover groups** – replicate DBs, roles, warehouses, integrations to another region/cloud; `ALTER FAILOVER GROUP ... PRIMARY` for DR. **Client redirect** via connection URLs.
- **Data Clean Rooms** – privacy-preserving joins between parties.

```sql
CREATE SHARE sales_share;
GRANT USAGE ON DATABASE sales TO SHARE sales_share;
GRANT USAGE ON SCHEMA sales.public TO SHARE sales_share;
GRANT SELECT ON VIEW sales.public.v_partner_sales TO SHARE sales_share;
ALTER SHARE sales_share ADD ACCOUNTS = partnerorg.partneracct;
```

---

## 6. Data & AI on Snowflake (heavily emphasized in the JD)

| Capability | What it does | Example use case |
|-----------|--------------|------------------|
| **Cortex AI functions** (`AI_COMPLETE`, `AI_CLASSIFY`, `AI_EXTRACT`, `AI_SENTIMENT`, `AI_SUMMARIZE_AGG`, `AI_FILTER`, `AI_TRANSLATE`) | LLMs in SQL | Ticket triage, review sentiment |
| **AI_PARSE_DOCUMENT** | OCR / layout from PDFs | Invoice & contract processing |
| **Cortex Search** | Hybrid vector + keyword search service | RAG chatbot over docs |
| **Cortex Analyst + Semantic Views** | Natural language → SQL | Self-service BI for business users |
| **Cortex Agents / Snowflake Intelligence** | Orchestrate Analyst + Search + tools | Enterprise assistant |
| **Snowflake ML** (Feature Store, Model Registry, ML Jobs, Observability) | End-to-end ML | Churn / demand forecasting |
| **SPCS** (Container Services) | Run containers/GPUs | Custom models, apps |
| **Streamlit in Snowflake** | Apps on data | UI for AI use cases |

```sql
SELECT ticket_id,
       AI_CLASSIFY(body, ['billing','technical','account']):labels[0]::STRING AS category,
       AI_SENTIMENT(body) AS sentiment
FROM support.tickets;

SELECT AI_COMPLETE('claude-3-5-sonnet',
  'Summarize this complaint in 1 line: ' || body) FROM support.tickets LIMIT 5;
```

**Reference RAG architecture (be able to draw):**
`Stage (PDFs)` → `AI_PARSE_DOCUMENT` → chunk (`SPLIT_TEXT_RECURSIVE_CHARACTER`) → chunk table → `CREATE CORTEX SEARCH SERVICE` → Cortex Agent (+ Analyst over semantic view for structured data) → Streamlit / Snowflake Intelligence UI. Governance: RBAC on search service, masking on source tables, AI cost monitoring.

> Tip: Build this mini demo in your trial account before the interview – speaking from hands-on experience is a big differentiator.

---

## 7. SQL Practice (expect live coding)

```sql
-- 1. Dedup: latest record per key
SELECT * FROM customers
QUALIFY ROW_NUMBER() OVER (PARTITION BY cust_id ORDER BY updated_at DESC) = 1;

-- 2. Running total & 7-day moving average
SELECT order_date, revenue,
  SUM(revenue) OVER (ORDER BY order_date) running_total,
  AVG(revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) ma7
FROM daily_sales;

-- 3. Nth highest salary per department
SELECT * FROM emp
QUALIFY DENSE_RANK() OVER (PARTITION BY dept ORDER BY salary DESC) = 2;

-- 4. Gaps & islands: consecutive login days
WITH d AS (
  SELECT user_id, login_date,
         DATEADD(day, -ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_date), login_date) grp
  FROM (SELECT DISTINCT user_id, login_date FROM logins))
SELECT user_id, MIN(login_date) start_dt, MAX(login_date) end_dt, COUNT(*) streak
FROM d GROUP BY user_id, grp;

-- 5. Month-over-month growth
SELECT month, revenue,
  (revenue - LAG(revenue) OVER (ORDER BY month)) / NULLIF(LAG(revenue) OVER (ORDER BY month),0) mom_pct
FROM monthly_sales;

-- 6. Recursive CTE: org hierarchy
WITH RECURSIVE org AS (
  SELECT emp_id, mgr_id, name, 1 lvl FROM emp WHERE mgr_id IS NULL
  UNION ALL
  SELECT e.emp_id, e.mgr_id, e.name, o.lvl+1 FROM emp e JOIN org o ON e.mgr_id = o.emp_id)
SELECT * FROM org;

-- 7. SCD Type 2 with MERGE (two-step: expire changed, insert new versions)
MERGE INTO dim_customer d
USING (
  SELECT s.cust_id AS merge_key, s.* FROM stg_customer s
  UNION ALL
  SELECT NULL, s.* FROM stg_customer s
  JOIN dim_customer d ON s.cust_id = d.cust_id AND d.is_current
  WHERE s.hash_diff <> d.hash_diff
) src
ON d.cust_id = src.merge_key AND d.is_current
WHEN MATCHED AND d.hash_diff <> src.hash_diff THEN
  UPDATE SET d.is_current = FALSE, d.end_date = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
  INSERT (cust_id, name, city, hash_diff, start_date, end_date, is_current)
  VALUES (src.cust_id, src.name, src.city, src.hash_diff, CURRENT_TIMESTAMP(), NULL, TRUE);

-- 8. Pivot
SELECT * FROM (SELECT region, quarter, revenue FROM sales)
PIVOT (SUM(revenue) FOR quarter IN ('Q1','Q2','Q3','Q4'));
```

---

## 8. Data Modeling & Warehousing

- **Kimball**: facts (transactional, periodic snapshot, accumulating snapshot) + conformed dimensions; star preferred over snowflake schema in Snowflake (fewer joins, storage cheap).
- **SCD types**: 0 (fixed), 1 (overwrite), 2 (history rows), 3 (prev column), 6 (hybrid).
- **Data Vault 2.0**: Hubs (business keys), Links (relationships), Satellites (history) – good for auditable, many-source enterprise integration; insert-only, parallel loads.
- **Medallion**: Bronze (raw, VARIANT) → Silver (cleansed, conformed) → Gold (business marts / semantic layer).
- **ELT over ETL** in Snowflake – land raw, transform with in-database compute.
- Principles: idempotent loads, handle late-arriving data, surrogate keys/hash keys, audit columns, data quality checks, data contracts.

---

## 9. Cloud, Migration & DevOps

**Migration approach (e.g. Teradata / Oracle / Netezza / Hadoop → Snowflake):**
1. **Assess** – inventory objects, workloads, dependencies, usage; prioritize by value/complexity.
2. **Plan** – target architecture, RBAC, environments, wave plan.
3. **Convert code** – SnowConvert / AI-assisted conversion; refactor procedural code (BTEQ, PL/SQL) to Snowflake SQL / Snowpark / dbt.
4. **Migrate data** – historical bulk load (export to cloud storage → `COPY INTO`), then incremental CDC to sync.
5. **Validate** – row counts, checksums/aggregates, sample record compare, report reconciliation.
6. **Parallel run & cutover** – repoint BI/ETL, decommission legacy.
7. **Optimize** – right-size warehouses, clustering, cost governance.

**Minimal downtime:** bulk historical + CDC catch-up + parallel run + short freeze window for final delta.

**Cloud essentials (pick your strongest – AWS/Azure/GCP):**
- Object storage (S3/ADLS/GCS), IAM roles & trust policies for storage integrations, KMS, VPC/PrivateLink, event notifications for Snowpipe, orchestration (Airflow, ADF, Step Functions).

**DevOps / IaC:**
- Git integration, CI/CD (GitHub Actions / Azure DevOps / Jenkins), Terraform Snowflake provider, schemachange / DCM projects, dbt.
- Env strategy: DEV / QA / PROD via clones; promote via pipelines; automated tests.

---

## 10. Architecture Whiteboard (practice drawing this)

```
 Sources (ERP, CRM, DBs, APIs, Files, Streams)
        │  Openflow / Fivetran / Kafka / Snowpipe(Streaming)
        ▼
 ┌──────────── SNOWFLAKE ─────────────────────────────────┐
 │ BRONZE (raw, VARIANT)                                  │
 │   │ Streams+Tasks / Dynamic Tables / dbt               │
 │ SILVER (cleansed, conformed, SCD2)                     │
 │   │                                                    │
 │ GOLD (star schemas, marts) → Semantic Views            │
 │                                                        │
 │ AI: Cortex AI funcs, Cortex Search, Analyst, Agents,   │
 │     Snowflake ML, SPCS                                 │
 │ Governance: RBAC, masking/RAP, tags, DMFs, lineage     │
 │ Ops: Resource monitors, budgets, replication/failover  │
 └────────────────────────────────────────────────────────┘
        ▼
 Consumers: BI (Power BI/Tableau), Streamlit apps,
 Snowflake Intelligence, Data Sharing / Marketplace
```
Talk through: **scalability** (warehouse isolation, multi-cluster), **security** (network, RBAC, masking), **cost** (auto-suspend, monitors), **reliability** (DR replication, monitoring, alerts), **CI/CD**.

---

## 11. Behavioral / Consulting (STAR stories)

Prepare 5 stories with **numbers**:
| Theme | Prompt |
|-------|--------|
| Migration | "Tell me about a large migration you led." |
| Performance/Cost | "Describe a time you significantly reduced cost or runtime." |
| Stakeholder | "Time you disagreed with a client on design." |
| Leadership | "How do you mentor / lead a distributed team?" |
| Incident | "A production failure and how you handled it." |
| AI | "An AI/GenAI use case you delivered or would propose." |

**STAR template:** Situation (1 line) → Task (your responsibility) → Action (what *you* did, technical detail) → Result (quantified: %, $, hours, SLA).

**IBM-specific:** IBM Consulting values client focus, delivery excellence, growth mindset, and partner ecosystems (IBM is a Snowflake partner; know watsonx at a high level and how it can complement Snowflake).

**Questions to ask them:**
- What client industries / use cases will this role support first?
- Is the work greenfield, migration, or modernization-heavy?
- How is the Snowflake practice structured (team size, onshore/offshore)?
- What does success look like in the first 6 months?

---

## 12. Q&A Bank – Short Model Answers

1. **Why Snowflake over a traditional DW?** Separation of storage/compute, elasticity, near-zero maintenance, native semi-structured support, secure sharing, multi-cloud, built-in AI.
2. **Scale up vs scale out?** Up = bigger size for complex/large queries; out = multi-cluster for concurrency.
3. **What is a micro-partition / pruning?** Immutable columnar units with min/max metadata; optimizer skips partitions not matching filters.
4. **When to add a clustering key?** Multi-TB tables, frequent filters on a column, poor pruning, and query patterns justify reclustering cost.
5. **Stream types?** Standard (insert/update/delete), append-only, insert-only (external/Iceberg). Stream offset advances only when consumed in a DML transaction.
6. **Snowpipe vs COPY?** Snowpipe is serverless, event-driven, continuous; COPY is batch using your warehouse.
7. **How to load idempotently?** COPY load metadata (64 days) prevents reload; MERGE on keys; hash diffs.
8. **Secure view vs normal view?** Secure hides definition and prevents optimizer leaks; required for sharing; may be slightly slower.
9. **How to protect PII?** Classification → tags → tag-based masking policies → row access policies → audit via access history.
10. **How to share data without copying?** Secure Data Sharing / listings; reader accounts for non-Snowflake consumers.
11. **DR strategy?** Replication + failover groups to secondary region, client redirect, define RPO/RTO, test failovers.
12. **Control costs?** Right-size, auto-suspend, resource monitors/budgets, workload separation, query optimization, monitor ACCOUNT_USAGE, storage lifecycle (transient tables, shorter Time Travel).
13. **Dynamic Table refresh modes?** Incremental (where supported) vs full; `TARGET_LAG` or `DOWNSTREAM`.
14. **RAG in Snowflake?** Parse docs → chunk → Cortex Search service → Agent/AI_COMPLETE with retrieved context → Streamlit UI.
15. **Text-to-SQL for business users?** Semantic view (dimensions, metrics, relationships, verified queries) + Cortex Analyst.
16. **Handling schema evolution?** `ENABLE_SCHEMA_EVOLUTION` on tables, VARIANT landing, `INFER_SCHEMA`, `MATCH_BY_COLUMN_NAME`.
17. **Time Travel vs Fail-safe?** User-accessible 0–90 days vs 7-day Snowflake-only recovery.
18. **Monitor pipelines?** Task history, `TASK_HISTORY`, alerts, event tables, DMFs, notifications to email/Slack.
19. **What does columnar + compressed buy you?** Read only the columns a query needs; per-column encoding (dictionary, RLE, delta) cuts storage and I/O.
20. **Why are micro-partitions immutable?** Enables Time Travel, zero-copy cloning and consistent reads; DML writes new partitions instead of editing.
21. **Can you control micro-partition size or partition a table manually?** No – Snowflake creates them automatically; you influence layout only with a clustering key / load order.
22. **What happens when you clone a table?** Metadata copy of the micro-partition pointer list; zero storage until either side changes, then copy-on-write.
23. **Does a clone copy grants / Time Travel / load history?** Grants only with `COPY GRANTS` (child-object grants are kept in DB/schema clones); no source Time Travel; no load history (COPY may reload files).
24. **Recover a table after a bad UPDATE?** `CREATE TABLE t_fix CLONE t BEFORE (STATEMENT => '<qid>')`, validate, `ALTER TABLE t SWAP WITH t_fix`.
25. **Cloned DB has tasks – are they running?** No, cloned tasks are suspended; resume explicitly.
26. **Does a stream store data?** No – only an offset (table version). Changes are computed from micro-partition versions + change-tracking columns when queried.
27. **When does a stream's offset advance?** Only when a DML that reads it commits; `SELECT` alone doesn't.
28. **What makes a stream stale?** Not consumed within retention (+ `MAX_DATA_EXTENSION_TIME_IN_DAYS`, default 14) – the old versions it needs are gone; recreate it.
29. **How does a dynamic table refresh incrementally?** It remembers the source versions last read, uses change tracking to get only the changed rows, runs the query on them and merges into the DT; falls back to full refresh when the query isn't incrementalizable.
30. **Stream + Task or Dynamic Table?** DT for declarative SQL transforms with target lag; Stream + Task for procedural logic, side effects, exact scheduling.

---

## 13. Final Checklist

- [ ] Can explain Snowflake architecture in 2 minutes
- [ ] Can explain micro-partitions (columnar, compressed, immutable, pruning) and draw clone copy-on-write
- [ ] Can diagnose a slow query out loud using Query Profile
- [ ] Can write MERGE / SCD2 / QUALIFY / window queries without notes
- [ ] Can design RBAC + masking for a multi-team client
- [ ] Can compare Streams+Tasks vs Dynamic Tables vs dbt
- [ ] Can draw end-to-end Data + AI architecture
- [ ] Built a small Cortex demo (AI functions + Cortex Search)
- [ ] Have a migration methodology with validation & cutover
- [ ] 5 quantified STAR stories ready
- [ ] 3–4 questions prepared for the interviewer
- [ ] (Optional) SnowPro Core / Advanced Data Engineer cert noted on resume

Good luck!
