# Data Warehousing Refresher (Interview Prep, Senior Level)

---

## 1. Core Concepts

| Term | Definition |
|---|---|
| **OLTP** | Online Transaction Processing. Normalized (3NF), row-oriented, many small reads and writes (e.g., an order-entry app). |
| **OLAP** | Online Analytical Processing. Denormalized, columnar, large scans and aggregations (e.g., a sales dashboard). |
| **Data Warehouse (DW)** | Central, integrated, **subject-oriented, non-volatile, time-variant** store of curated data for analytics (Inmon's definition). |
| **Data Mart** | A subset of the DW for one business area (Sales mart, Finance mart). It can be **dependent** (fed from the DW) or **independent** (fed straight from sources). |
| **Data Lake** | Stores raw data of **any format** (structured, semi-structured, unstructured) at low cost. **Schema-on-read.** |
| **Lakehouse** | Lake storage plus warehouse features: ACID, schema enforcement, time travel. Built on open table formats (Iceberg, Delta, Hudi). |
| **ODS** | Operational Data Store. Near-real-time, integrated, current-state data that is lightly transformed and used for operational reporting. |
| **Staging Area** | Landing zone for raw extracts before transformation. |
| **ETL vs ELT** | ETL transforms data before loading it (classic tools like Informatica). ELT loads raw data first, then transforms it inside the warehouse (Snowflake + dbt). |
| **Schema-on-write vs read** | With schema-on-write (DW), the structure is enforced at load. With schema-on-read (lake), the structure is applied at query time. |
| **Metadata** | Data about data. *Technical* metadata covers schemas and lineage. *Business* metadata covers definitions and owners. *Operational* metadata covers load stats. |
| **Data Lineage** | Traces where data came from and how it was transformed. |
| **Grain** | The level of detail of one fact row (e.g., "one row per order line per day"). **Declare the grain first, always.** |
| **Surrogate Key (SK)** | A system-generated key (integer or hash) in a dimension. It is independent of the source and enables SCD history. |
| **Natural / Business Key** | The source system identifier (customer_id, SKU). |
| **Conformed Dimension** | A dimension shared with identical meaning across multiple facts or marts (Date, Customer). It enables drill-across. |
| **Bus Matrix** | Kimball's grid with business processes (facts) as rows and conformed dimensions as columns. |
| **Drill down / up / across** | Drill down and up move between hierarchy levels (Year → Quarter → Month). Drill across combines facts through conformed dimensions. |
| **Slice / Dice / Pivot** | OLAP cube operations: filter one dimension (slice), filter several (dice), or rotate the axes (pivot). |
| **MOLAP / ROLAP / HOLAP** | Cube storage types: multidimensional, relational, or hybrid. |

### Data Warehouse vs Data Lake vs Lakehouse

| Aspect | Data Warehouse | Data Lake | Lakehouse |
|---|---|---|---|
| Data | Structured, curated | Any (raw) | Any |
| Schema | On write | On read | Both |
| Users | BI analysts | Data scientists, engineers | Both |
| Cost | Higher | Low (object storage) | Low |
| Quality/ACID | Strong | Weak ("data swamp" risk) | Strong (table formats) |
| Examples | Snowflake, Redshift, Teradata | S3/ADLS + Hive | Iceberg/Delta on S3, Snowflake + Iceberg |

---

## 2. Facts

A **fact table** stores measurements of a business process. It holds foreign keys to dimensions plus numeric measures.

### 2.1 Types of Measures (Additivity)
| Type | Meaning | Example |
|---|---|---|
| **Additive** | Can be summed across **all** dimensions | sales_amount, quantity |
| **Semi-additive** | Can be summed across some dimensions but **not time** | account_balance, inventory_on_hand (use AVG or the last value over time) |
| **Non-additive** | Cannot be summed at all | ratios, percentages, unit_price. Store the numerator and denominator instead. |

### 2.2 Types of Fact Tables
| Type | Description | Example |
|---|---|---|
| **Transaction Fact** | One row per event at the atomic grain. This is the most common type. | One row per order line |
| **Periodic Snapshot** | One row per entity per period. Captures state at regular intervals. | Daily account balance, monthly inventory |
| **Accumulating Snapshot** | One row per process instance, **updated** as milestones happen. Has multiple date FKs. | Order lifecycle: order_date, ship_date, deliver_date, lag days |
| **Factless Fact** | No measures, only FKs. It records that an event or coverage happened. | Student attendance; products on promotion (coverage) |
| **Aggregate Fact** | A pre-summarized rollup built for performance | Sales by month by region |
| **Consolidated Fact** | Combines multiple processes at the same grain | Actual vs forecast in one table |
| **Cumulative Fact** | Running totals (sometimes listed separately) | YTD sales |

**Example: accumulating snapshot**
```sql
CREATE TABLE fact_order_fulfillment (
  order_sk        NUMBER,
  customer_sk     NUMBER,
  order_date_sk   NUMBER,
  ship_date_sk    NUMBER,      -- updated when shipped
  deliver_date_sk NUMBER,      -- updated when delivered
  order_amount    NUMBER(12,2),
  days_to_ship    NUMBER,
  days_to_deliver NUMBER
);
```

**Example: factless fact (attendance)**
```sql
CREATE TABLE fact_attendance (date_sk NUMBER, student_sk NUMBER, class_sk NUMBER);
-- COUNT(*) = attendance; anti-join with the enrollment table = absentees
```

### 2.3 Other Fact Terms
- **Degenerate Dimension:** a dimension attribute stored directly in the fact with no dimension table, for example `invoice_number` or `order_number`.
- **Fact grain types:** atomic (lowest level) vs aggregated.
- **Late-arriving fact:** a fact arrives after its dimension version changed. Look up the SK that was valid on the event date.

---

## 3. Dimensions

A **dimension** gives the context of a fact (who, what, where, when, why). It is wide, denormalized, and descriptive.

### 3.1 Types of Dimensions (structural/role)
| Type | Description | Example |
|---|---|---|
| **Conformed** | Shared across facts and marts with identical keys and attributes | dim_date, dim_customer used by Sales and Returns |
| **Role-playing** | One physical dimension used multiple times in different roles | dim_date as order_date, ship_date, due_date (via views or aliases) |
| **Junk** | Combines low-cardinality flags and indicators into one table to avoid many tiny dimensions | is_gift, payment_type, is_online → dim_order_flags |
| **Degenerate** | A dimension key living in the fact with no table | invoice_no |
| **Outrigger** | A dimension referencing another dimension (secondary snowflaking) | dim_customer → dim_geography |
| **Shrunken** | A subset of a dimension's rows or columns, used for aggregate facts | dim_month (from dim_date), dim_brand (from dim_product) |
| **Mini-dimension** | Splits rapidly changing attributes out of a large dimension | dim_customer_demographics (age band, income band) |
| **Static** | Fixed reference data that never changes | Country codes, gender, calendar |
| **Inferred / Placeholder** | Row created when a fact arrives before its dimension (late-arriving dimension). Updated later. | Customer "Unknown – pending" |
| **Slowly Changing (SCD)** | Attributes change slowly over time (see below) | Customer address |
| **Rapidly Changing** | Changes frequently. Handle with a mini-dimension or Type 4. | Credit score, age band |
| **Multi-valued / Bridge** | Many-to-many between a fact and a dimension via a bridge table with a weighting factor | Account ↔ multiple account holders; patient ↔ multiple diagnoses |
| **Hierarchical (ragged/unbalanced)** | Variable-depth hierarchies, handled with a bridge or closure table | Org chart, bill of materials |
| **Swappable** | Alternate versions of a dimension for different audiences | dim_customer_internal vs dim_customer_partner |
| **Audit Dimension** | ETL metadata attached to each fact row | batch_id, load_ts, source_system |
| **Step Dimension** | Position in a sequential process | Step 3 of 5 in a web session |

### 3.2 Slowly Changing Dimensions (SCD) — **the most-asked topic**

Scenario: customer C101 moves from **Chennai** to **Bangalore**.

| Type | Behavior | Result |
|---|---|---|
| **Type 0** | Retain original. Never update. | Stays Chennai (e.g., date_of_birth, original_signup_date) |
| **Type 1** | Overwrite. No history. | Row updated to Bangalore |
| **Type 2** | Add a new row with a new SK, effective dates, and a current flag. **Full history.** | Two rows (see below) |
| **Type 3** | Add a column for the previous value. Limited history. | current_city = Bangalore, previous_city = Chennai |
| **Type 4** | History table / mini-dimension. Current values in the main dimension, history in a separate table. | dim_customer + dim_customer_history |
| **Type 5** | Type 4 mini-dimension + Type 1 outrigger (current mini-dimension key stored in the base dimension) | Rarely implemented |
| **Type 6** | Hybrid of 1+2+3. Type 2 rows plus a current-value column overwritten on all rows. | Report "as was" and "as is" together |
| **Type 7** | Dual keys in the fact: SK (as-was) plus the durable natural key (as-is via a current view) | Flexible reporting |

**Type 2 example**
| customer_sk | customer_id | city | eff_start | eff_end | is_current |
|---|---|---|---|---|---|
| 1 | C101 | Chennai | 2020-01-01 | 2026-03-14 | N |
| 2 | C101 | Bangalore | 2026-03-15 | 9999-12-31 | Y |

**Type 6 example** (adds `current_city`, overwritten on every row)
| customer_sk | customer_id | city (historical) | current_city | is_current |
|---|---|---|---|---|
| 1 | C101 | Chennai | Bangalore | N |
| 2 | C101 | Bangalore | Bangalore | Y |

**SCD2 in Snowflake (MERGE pattern)**
```sql
-- 1. Expire changed rows
MERGE INTO dim_customer d
USING stg_customer s
  ON d.customer_id = s.customer_id AND d.is_current = 'Y'
WHEN MATCHED AND d.city <> s.city THEN
  UPDATE SET d.eff_end = CURRENT_DATE - 1, d.is_current = 'N';

-- 2. Insert new versions and brand-new customers
INSERT INTO dim_customer (customer_id, city, eff_start, eff_end, is_current)
SELECT s.customer_id, s.city, CURRENT_DATE, '9999-12-31', 'Y'
FROM stg_customer s
LEFT JOIN dim_customer d
  ON d.customer_id = s.customer_id AND d.is_current = 'Y'
WHERE d.customer_id IS NULL;      -- new, or just expired in step 1
```
(dbt `snapshots` implement SCD2 out of the box. Snowflake Streams + Tasks can automate this.)

---

## 4. Modeling Architectures / Schemas

### 4.1 Star Schema
A central fact table joined directly to **denormalized** dimensions.
```
            dim_date
               |
dim_product — FACT_SALES — dim_customer
               |
            dim_store
```
- **Pros:** simple, fewest joins, fast queries, BI-friendly.
- **Cons:** redundancy in dimensions (e.g., category repeated per product).

### 4.2 Snowflake Schema
Dimensions are **normalized** into sub-dimensions.
```
dim_category — dim_subcategory — dim_product — FACT_SALES — dim_customer — dim_city — dim_country
```
- **Pros:** less redundancy, easier dimension maintenance, smaller storage.
- **Cons:** more joins, more complex SQL, usually slower.
- *(Not the same thing as the Snowflake database product.)*

### 4.3 Galaxy / Fact Constellation Schema
**Multiple fact tables sharing conformed dimensions** (e.g., fact_sales and fact_shipments both use dim_date and dim_product). This is the shape of most real enterprise DWs.

### 4.4 Star vs Snowflake (quick answer)
| | Star | Snowflake |
|---|---|---|
| Dimension normalization | Denormalized | Normalized (3NF-ish) |
| Joins | Fewer | More |
| Query performance | Faster | Slower |
| Storage | More | Less |
| Maintenance | Harder updates | Easier updates |
| Preferred for | BI/reporting (default choice) | Very large or deep hierarchies |

### 4.5 Medallion Architecture (Bronze / Silver / Gold)
A **layered data-quality pattern** popularized by Databricks and common in lakehouses and Snowflake.

| Layer | Contents | Example |
|---|---|---|
| **Bronze (Raw)** | As-is ingestion, append-only, plus load metadata | Raw JSON orders from Kafka, Snowpipe landing |
| **Silver (Cleansed/Conformed)** | Deduplicated, typed, validated, joined, conformed entities | Clean `orders`, `customers` tables |
| **Gold (Curated/Business)** | Aggregated, business-ready star schemas, KPIs, ML features | `fact_sales`, `dim_customer`, `agg_daily_revenue` |

Key point: **Medallion is a data-flow layering pattern. Star and snowflake are modeling patterns.** They complement each other, and the Gold layer is typically modeled as star schemas.

In Snowflake: Snowpipe → RAW (bronze) → Streams/Tasks, Dynamic Tables, or dbt → STAGING/SILVER → MARTS/GOLD.

### 4.6 Other Architectures / Methodologies
| Approach | Summary |
|---|---|
| **Kimball (bottom-up)** | Build dimensional data marts per business process, integrated through conformed dimensions (bus architecture). Faster delivery. |
| **Inmon (top-down)** | Build an enterprise DW in 3NF first (Corporate Information Factory), then derive dependent marts. Strong integration, slower start. |
| **Data Vault 2.0** | Hubs (business keys), Links (relationships), Satellites (descriptive attributes + history). Insert-only, auditable, agile for many changing sources. Usually the raw/integration layer, with star schemas on top. |
| **One Big Table (OBT)** | A fully flattened wide table. Simple for columnar engines, but costly to maintain. |
| **Lambda** | Batch layer + speed (streaming) layer + serving layer. |
| **Kappa** | Streaming only; reprocess by replaying the log. |
| **Data Mesh** | Organizational paradigm: domain-owned data products, self-serve platform, federated governance. |
| **Data Fabric** | Metadata- and automation-driven integration layer across distributed sources. |

**Kimball vs Inmon**
| | Kimball | Inmon |
|---|---|---|
| Approach | Bottom-up | Top-down |
| Core model | Dimensional (star) | 3NF enterprise model |
| Time to value | Fast | Slow |
| Integration | Conformed dimensions | Central EDW |

**Data Vault mini example**
```
hub_customer(customer_hk, customer_id, load_dts, record_src)
sat_customer_details(customer_hk, load_dts, hash_diff, name, city, ...)
link_customer_order(link_hk, customer_hk, order_hk, load_dts, record_src)
```

---

## 5. Dimensional Modeling Process (Kimball's 4 steps)
1. **Select the business process** (e.g., retail sales).
2. **Declare the grain** (one row per product per POS transaction line).
3. **Identify the dimensions** (date, product, store, customer, promotion).
4. **Identify the facts** (quantity, sales_amount, discount, cost).

---

## 6. Worked Example: Retail Star Schema
```sql
CREATE TABLE dim_date (
  date_sk NUMBER PRIMARY KEY,     -- 20261124
  full_date DATE, day_name STRING, month NUMBER, quarter NUMBER,
  year NUMBER, is_weekend BOOLEAN, fiscal_period STRING
);

CREATE TABLE dim_product (
  product_sk NUMBER PRIMARY KEY, sku STRING, product_name STRING,
  brand STRING, category STRING, subcategory STRING,     -- denormalized = star
  eff_start DATE, eff_end DATE, is_current CHAR(1)       -- SCD2
);

CREATE TABLE dim_customer (... SCD2 columns ...);
CREATE TABLE dim_store (...);

CREATE TABLE fact_sales (
  date_sk NUMBER, product_sk NUMBER, customer_sk NUMBER, store_sk NUMBER,
  invoice_no STRING,               -- degenerate dimension
  quantity NUMBER,                 -- additive
  sales_amount NUMBER(12,2),       -- additive
  unit_price NUMBER(10,2)          -- non-additive
);

-- Typical query
SELECT d.year, p.category, SUM(f.sales_amount) AS revenue
FROM fact_sales f
JOIN dim_date d    ON f.date_sk = d.date_sk
JOIN dim_product p ON f.product_sk = p.product_sk
GROUP BY 1, 2;
```

---

## 7. Other Frequently Asked Terms
- **CDC (Change Data Capture):** captures inserts, updates, and deletes from source systems (log-based with Debezium, or Snowflake Streams).
- **Full vs Incremental load:** reload everything vs only the delta (watermark or CDC).
- **Idempotency:** re-running a load produces the same result. Critical for pipelines.
- **Late-arriving dimension:** a fact comes first, so insert an inferred dimension row and update it later.
- **Unknown member:** SK = -1 row ("Unknown") so fact FKs never go null.
- **Hash keys:** MD5 or SHA of the business key. Used in Data Vault and parallel loads.
- **Hash diff:** hash of attribute columns, used to detect changes cheaply for SCD2.
- **Bitemporal:** tracks both valid time (business) and transaction time (system).
- **Columnar storage / micro-partitions / pruning / clustering:** physical performance concepts (Snowflake).
- **Materialized views / Dynamic Tables / Aggregates:** pre-computation for performance.
- **Semantic layer:** business definitions of metrics on top of models (Snowflake Semantic Views, dbt metrics, LookML).
- **Data quality dimensions:** accuracy, completeness, consistency, timeliness, validity, uniqueness.
- **MDM (Master Data Management):** a single golden record for core entities. Feeds conformed dimensions.
- **Normalization (1NF/2NF/3NF/BCNF)** vs **denormalization**: OLTP vs OLAP trade-off.
- **Open table formats:** Apache Iceberg, Delta Lake, Hudi. Provide ACID on the lake.

---

## 8. Quick Interview Q&A
1. **SCD2 vs SCD3?** SCD2 keeps unlimited history in rows. SCD3 keeps limited history (usually one previous value) in columns.
2. **Why surrogate keys?** They support SCD2 versions, isolate the DW from source key changes, integrate multiple sources, and make joins faster with integers.
3. **Factless fact use case?** Events without measures (attendance, registrations) or coverage (products on promotion that didn't sell).
4. **Semi-additive example and how to aggregate?** Bank balance: SUM across accounts, but take the last value or AVG across time.
5. **What is a junk dimension?** Groups miscellaneous low-cardinality flags into one dimension, reducing fact width and dimension count.
6. **Role-playing dimension?** One date dimension used as order, ship, and delivery date through aliases or views.
7. **Star vs snowflake, which would you choose?** Star by default for BI performance and simplicity. Snowflake only when dimensions are huge or hierarchies are deep and shared.
8. **Medallion vs star?** Medallion is data layering (raw → clean → curated). Star is how you model the Gold layer.
9. **Data Vault vs Kimball?** Data Vault is for an auditable, agile integration layer with many sources. Kimball is for consumption. They are often combined (DV in silver, star in gold).
10. **Accumulating vs periodic snapshot?** Accumulating has one row per process instance that gets updated through milestones. Periodic has one row per entity per period and is insert-only.
11. **Handling a rapidly changing dimension?** Split the volatile attributes into a mini-dimension (Type 4), or use banding.
12. **Grain mismatch?** Never mix grains in one fact. Build separate facts or aggregate to a common grain.
13. **Lake vs warehouse?** A lake holds raw, any-format, schema-on-read data cheaply. A warehouse holds curated, schema-on-write data that is optimized for BI.
