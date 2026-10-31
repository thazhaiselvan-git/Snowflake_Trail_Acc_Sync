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

---

## 13. Final Checklist

- [ ] Can explain Snowflake architecture in 2 minutes
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
