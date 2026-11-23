# Snowflake Data Quality & Data Metric Functions (DMF) – Beginner Guide

> Interview prep + hands-on reference. Every section has a real-world scenario and runnable SQL.
> Edition note: DMFs require **Enterprise Edition or higher**. DMF runs use serverless compute (billed credits).

---

## 1. What is Data Quality in Snowflake?

Data quality = can the business **trust** the data? The common dimensions:

| Dimension | Question | Example DMF |
| --- | --- | --- |
| Completeness | Are values missing? | `NULL_COUNT`, `NULL_PERCENT`, `BLANK_COUNT` |
| Uniqueness | Are there duplicates? | `DUPLICATE_COUNT`, `UNIQUE_COUNT` |
| Freshness / Timeliness | Is data up to date? | `FRESHNESS`, `DATA_METRIC_SCHEDULE_TIME` |
| Volume | Did the expected number of rows arrive? | `ROW_COUNT` |
| Validity | Are values in the allowed set / range? | `ACCEPTED_VALUES`, custom DMFs |
| Statistics / Distribution | Did values drift? | `AVG`, `MIN`, `MAX`, `STDDEV` |
| Consistency | Do two tables agree? | `ROW_COUNT_DIFFERENCE`, `REFERENTIAL_INTEGRITY_COUNT`, `SOURCE_TARGET_LAG` |

Snowflake's native tool for this is **Data Metric Functions (DMFs)**. They are part of Snowflake Horizon and appear in the **Data Quality** tab in Snowsight.

---

## 2. What is a DMF?

A **Data Metric Function** is a special function that takes a table (and columns) as input and returns **one number**, the metric.

```
Table/Columns ──► DMF ──► number (e.g. 42 nulls) ──► stored in results ──► expectation / alert
```

Two types:
- **System DMFs**: built-in, live in `SNOWFLAKE.CORE`.
- **Custom DMFs**: you write them with `CREATE DATA METRIC FUNCTION`.

Lifecycle:
1. **Set a schedule** on the table (`DATA_METRIC_SCHEDULE`).
2. **Attach** DMFs to the table/columns.
3. Snowflake **runs** them serverlessly on the schedule.
4. **Results** are stored → query them, chart them, add **expectations** and **alerts**.

---

## 3. Setup for the examples

```sql
CREATE DATABASE IF NOT EXISTS DQ_DEMO;
CREATE SCHEMA  IF NOT EXISTS DQ_DEMO.SALES;
USE SCHEMA DQ_DEMO.SALES;

CREATE OR REPLACE TABLE CUSTOMERS (
  customer_id  NUMBER,
  email        STRING,
  country      STRING,
  created_at   TIMESTAMP_LTZ
);

CREATE OR REPLACE TABLE ORDERS (
  order_id     NUMBER,
  customer_id  NUMBER,
  status       STRING,
  amount       NUMBER(10,2),
  updated_at   TIMESTAMP_LTZ
);

INSERT INTO CUSTOMERS VALUES
 (1,'a@x.com','IN',CURRENT_TIMESTAMP()),
 (2,NULL,'US',CURRENT_TIMESTAMP()),          -- missing email
 (3,'a@x.com','IN',CURRENT_TIMESTAMP()),     -- duplicate email
 (4,'bad-email','UK',CURRENT_TIMESTAMP());   -- invalid email

INSERT INTO ORDERS VALUES
 (101,1,'SHIPPED',250,CURRENT_TIMESTAMP()),
 (102,2,'PENDING',-10,DATEADD(day,-3,CURRENT_TIMESTAMP())),  -- negative amount, old
 (103,99,'UNKNOWN',80,CURRENT_TIMESTAMP());                  -- orphan customer, bad status
```

### Privileges needed (run as ACCOUNTADMIN once)
```sql
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE DQ_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE DQ_ENGINEER;      -- use system DMFs
GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE DQ_ENGINEER; -- read results
-- The role also needs OWNERSHIP of the table to attach DMFs.
```

---

## 4. Feature 1 – Ad-hoc (one-off) checks

You can call any system DMF directly, without scheduling. This is good for a quick spot check.

```sql
SELECT SNOWFLAKE.CORE.NULL_COUNT     (SELECT email FROM CUSTOMERS);   -- 1
SELECT SNOWFLAKE.CORE.DUPLICATE_COUNT(SELECT email FROM CUSTOMERS);   -- 1
SELECT SNOWFLAKE.CORE.ROW_COUNT      (SELECT * FROM ORDERS);          -- 3
SELECT SNOWFLAKE.CORE.FRESHNESS      (SELECT updated_at FROM ORDERS); -- seconds since newest row
```

**Real-time scenario:** A business user says "the dashboard looks wrong". Run these checks before you go any deeper.

---

## 5. Feature 2 – System DMFs catalog

| Category | DMF | Returns |
| --- | --- | --- |
| Accuracy / completeness | `NULL_COUNT`, `NULL_PERCENT` | nulls in a column |
| | `BLANK_COUNT`, `BLANK_PERCENT` | empty / whitespace strings |
| Uniqueness | `DUPLICATE_COUNT` | duplicated non-null values |
| | `UNIQUE_COUNT` | distinct non-null values |
| Volume | `ROW_COUNT` | rows in the table |
| Freshness | `FRESHNESS` | seconds since the newest timestamp (or last DML with `ON ()`) |
| | `DATA_METRIC_SCHEDULE_TIME` | used for custom freshness logic |
| Statistics | `AVG`, `MIN`, `MAX`, `STDDEV` | numeric distribution |
| Validity | `ACCEPTED_VALUES` | rows NOT in the allowed list |
| Two-table | `ROW_COUNT_DIFFERENCE`, `REFERENTIAL_INTEGRITY_COUNT`, `SOURCE_TARGET_LAG` | parity, orphans, lag between tables |

Newer system DMFs are added regularly. To list what your account has:
```sql
SHOW DATA METRIC FUNCTIONS IN SCHEMA SNOWFLAKE.CORE;
```

---

## 6. Feature 3 – Scheduling (`DATA_METRIC_SCHEDULE`)

The schedule is set **per table** and applies to **all** DMFs attached to that table.

```sql
ALTER TABLE ORDERS SET DATA_METRIC_SCHEDULE = '5 MINUTE';              -- interval (5,15,30,60,720,1440 min)
ALTER TABLE ORDERS SET DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC'; -- daily 6 AM UTC
ALTER TABLE ORDERS SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';    -- run when DML changes the table

SHOW PARAMETERS LIKE 'DATA_METRIC_SCHEDULE' IN TABLE ORDERS;
```

**Scenario:** Your ETL loads at 5 AM, so you schedule the checks with CRON at 6 AM. A table that streams data in all day suits `TRIGGER_ON_CHANGES`.

---

## 7. Feature 4 – Attaching / detaching DMFs

```sql
ALTER TABLE CUSTOMERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT      ON (email),
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT ON (email);

ALTER TABLE ORDERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (updated_at),
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();

-- See what is attached
SELECT * FROM TABLE(INFORMATION_SCHEMA.DATA_METRIC_FUNCTION_REFERENCES(
  REF_ENTITY_NAME => 'DQ_DEMO.SALES.ORDERS', REF_ENTITY_DOMAIN => 'TABLE'));

-- Pause / resume / remove
ALTER TABLE ORDERS MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON () SUSPEND;
ALTER TABLE ORDERS MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON () RESUME;
ALTER TABLE ORDERS DROP   DATA METRIC FUNCTION SNOWFLAKE.CORE.ROW_COUNT ON ();
```

DMFs can be attached to tables, views, materialized views, dynamic tables, external and Iceberg tables.

---

## 8. Feature 5 – Data freshness (deep dive)

```sql
-- Column based: age of the newest updated_at
ALTER TABLE ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (updated_at);

-- Table based: time since the last DML (no timestamp column needed)
ALTER TABLE CUSTOMERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON ();
```

Quick freshness without DMFs (metadata):
```sql
SELECT table_name, last_altered, DATEDIFF('hour', last_altered, CURRENT_TIMESTAMP()) AS hours_old
FROM DQ_DEMO.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SALES';
```
`LAST_ALTERED` also changes on DDL, so the DMF is more reliable.

**Scenario:** The finance report SLA says the orders table must be less than 1 hour old. Attach `FRESHNESS` and add an expectation `VALUE < 3600` (see section 11).

---

## 9. Feature 6 – Custom DMFs

Write your own business rules. A custom DMF must return a NUMBER.

```sql
-- Invalid email count
CREATE OR REPLACE DATA METRIC FUNCTION DQ_DEMO.SALES.INVALID_EMAIL_COUNT(
  t TABLE(email STRING))
RETURNS NUMBER AS
$$
  SELECT COUNT_IF(NOT REGEXP_LIKE(email, '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')) FROM t
$$;

-- Negative amount count
CREATE OR REPLACE DATA METRIC FUNCTION DQ_DEMO.SALES.NEGATIVE_AMOUNT_COUNT(
  t TABLE(amount NUMBER))
RETURNS NUMBER AS
$$ SELECT COUNT_IF(amount < 0) FROM t $$;

ALTER TABLE CUSTOMERS ADD DATA METRIC FUNCTION DQ_DEMO.SALES.INVALID_EMAIL_COUNT ON (email);
ALTER TABLE ORDERS    ADD DATA METRIC FUNCTION DQ_DEMO.SALES.NEGATIVE_AMOUNT_COUNT ON (amount);
```

**Scenario:** An e-commerce company wants zero refunds booked as negative sales, so they add a custom DMF for it.

---

## 10. Feature 7 – Validity, referential integrity & two-table checks

```sql
-- Allowed status values (counts rows NOT in list)
ALTER TABLE ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (status, status -> status IN ('PENDING','SHIPPED','DELIVERED','CANCELLED'));

-- Orphan orders: customer_id not present in CUSTOMERS
ALTER TABLE ORDERS ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.REFERENTIAL_INTEGRITY_COUNT
  ON (customer_id, TABLE(DQ_DEMO.SALES.CUSTOMERS(customer_id)));
```

Custom two-table DMF (works on any account):
```sql
CREATE OR REPLACE DATA METRIC FUNCTION DQ_DEMO.SALES.ORPHAN_COUNT(
  child TABLE(cid NUMBER), parent TABLE(pid NUMBER))
RETURNS NUMBER AS
$$ SELECT COUNT(*) FROM child WHERE cid NOT IN (SELECT pid FROM parent) $$;
```

**Scenario:** After a migration, you need to prove that silver ⇄ bronze row counts match (`ROW_COUNT_DIFFERENCE`), and that silver isn't falling behind (`SOURCE_TARGET_LAG`). Check `SHOW DATA METRIC FUNCTIONS IN SCHEMA SNOWFLAKE.CORE` to confirm these exist in your account.

---

## 11. Feature 8 – Expectations (pass / fail)

An expectation turns a number into a pass or fail result.

```sql
ALTER TABLE ORDERS MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (updated_at)
  ADD EXPECTATION fresh_within_1h (VALUE < 3600);

ALTER TABLE CUSTOMERS MODIFY DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT ON (email)
  ADD EXPECTATION no_null_email (VALUE = 0);

-- Check expectations ad hoc
SELECT * FROM TABLE(SYSTEM$EVALUATE_DATA_QUALITY_EXPECTATIONS(
  REF_ENTITY_NAME => 'DQ_DEMO.SALES.ORDERS'));
```

---

## 12. Feature 9 – Viewing results

```sql
-- Near real-time (local, per table)
SELECT measurement_time, metric_name, argument_names, value
FROM TABLE(SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS(
  REF_ENTITY_NAME => 'DQ_DEMO.SALES.ORDERS', REF_ENTITY_DOMAIN => 'TABLE'))
ORDER BY measurement_time DESC;

-- Account-wide history (latency up to a few hours)
SELECT * FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
WHERE table_name = 'ORDERS' ORDER BY measurement_time DESC;

-- Cost of DMFs
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_QUALITY_MONITORING_USAGE_HISTORY
ORDER BY start_time DESC;
```
In Snowsight: **Catalog → table → Data Quality tab**. This shows charts, expectation status and trends.

---

## 13. Feature 10 – Finding the bad rows (`SYSTEM$DATA_METRIC_SCAN`)

When a metric fails, this function returns the rows that caused it:
```sql
SELECT * FROM TABLE(SYSTEM$DATA_METRIC_SCAN(
  REF_ENTITY_NAME => 'DQ_DEMO.SALES.CUSTOMERS',
  METRIC_NAME     => 'SNOWFLAKE.CORE.NULL_COUNT',
  ARGUMENT_NAME   => 'email'));
```
This works for the row-level system DMFs (NULL, BLANK, DUPLICATE, ACCEPTED_VALUES …).

---

## 14. Feature 11 – Alerts & notifications

**Option A – built-in DQ notifications** (Snowsight, Data Quality tab → notifications). Sends email or webhook (Slack/Teams) when an expectation fails.

**Option B – Snowflake ALERT** (works everywhere):
```sql
CREATE NOTIFICATION INTEGRATION dq_email TYPE = EMAIL ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('me@company.com');

CREATE OR REPLACE ALERT DQ_DEMO.SALES.ORDERS_STALE_ALERT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE  = '60 MINUTE'
  IF (EXISTS (
     SELECT 1 FROM SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS
     WHERE table_name='ORDERS' AND metric_name='FRESHNESS'
       AND value > 3600
       AND measurement_time > DATEADD('hour',-1,CURRENT_TIMESTAMP())))
  THEN CALL SYSTEM$SEND_EMAIL('dq_email','me@company.com',
         'ORDERS is stale','Freshness > 1 hour, check the pipeline.');

ALTER ALERT DQ_DEMO.SALES.ORDERS_STALE_ALERT RESUME;
```

---

## 15. Feature 12 – Circuit breaker (stop the pipeline on bad data)

Run the DQ check **before** the downstream load. If it fails, raise an error so the task graph stops.

```sql
CREATE OR REPLACE TASK DQ_DEMO.SALES.DQ_GATE
  WAREHOUSE = COMPUTE_WH
  SCHEDULE  = 'USING CRON 0 6 * * * UTC'
AS
EXECUTE IMMEDIATE $$
BEGIN
  LET bad NUMBER := (SELECT SNOWFLAKE.CORE.NULL_COUNT(SELECT customer_id FROM DQ_DEMO.SALES.ORDERS));
  IF (bad > 0) THEN
    RAISE STATEMENT_ERROR;  -- child tasks (gold load) will not run
  END IF;
END;
$$;

CREATE OR REPLACE TASK DQ_DEMO.SALES.LOAD_GOLD
  WAREHOUSE = COMPUTE_WH AFTER DQ_DEMO.SALES.DQ_GATE
AS INSERT INTO ... ;
```

---

## 16. Feature 13 – Schema-level & create-time attachment

```sql
-- Attach while creating the table (monitoring starts from day 1)
CREATE OR REPLACE TABLE PAYMENTS (id NUMBER, paid_at TIMESTAMP_LTZ)
  DATA_METRIC_SCHEDULE = '60 MINUTE'
  WITH DATA METRIC FUNCTION SNOWFLAKE.CORE.FRESHNESS ON (paid_at);

-- Default schedule for every table in a schema
ALTER SCHEMA DQ_DEMO.SALES SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
```
Check the current docs for the exact `WITH DATA METRIC FUNCTION` syntax in your release.

---

## 17. Feature 14 – Anomaly detection

Snowsight can learn the normal pattern for `ROW_COUNT` / `FRESHNESS` and flag unusual values (e.g. 10x fewer rows on a Monday) without you setting fixed thresholds. Enable it from the table's Data Quality tab. Availability depends on your account and release.

---

## 18. Comparing tables (migration validation)

DMFs give you single numbers. To find the actual rows that differ, compare the tables:
```sql
-- rows in source not in target
SELECT * FROM SRC.ORDERS MINUS SELECT * FROM TGT.ORDERS;
-- quick fingerprint
SELECT HASH_AGG(*) FROM SRC.ORDERS;  SELECT HASH_AGG(*) FROM TGT.ORDERS;
```

---

## 19. Best practices

1. Start with **ROW_COUNT + FRESHNESS** on your most-queried tables.
2. Add **NULL_COUNT / DUPLICATE_COUNT** on primary and business keys.
3. Schedule checks **after** loads (CRON) and avoid running every minute on big tables, because each run costs credits.
4. Always pair a metric with an **expectation** and a **notification**. A number nobody looks at doesn't help.
5. Use **circuit breakers** before gold/reporting layers.
6. Keep custom DMFs in a dedicated `GOVERNANCE.DQ` schema and grant usage to them.
7. Monitor DMF cost via `DATA_QUALITY_MONITORING_USAGE_HISTORY`.

---

## 20. Interview Q&A

| Question | Short answer |
| --- | --- |
| What is a DMF? | A function that returns a quality metric (a number) for a table/column. It runs serverlessly on a schedule. |
| System vs custom DMF? | System DMFs are built into `SNOWFLAKE.CORE`. Custom DMFs are created with `CREATE DATA METRIC FUNCTION` for business rules. |
| How is a DMF scheduled? | With the table parameter `DATA_METRIC_SCHEDULE`: an interval, a CRON or `TRIGGER_ON_CHANGES`. It is shared by all DMFs on that table. |
| Where are results stored? | `SNOWFLAKE.LOCAL.DATA_QUALITY_MONITORING_RESULTS` (a view, plus a table function for near real-time). |
| How do you check freshness? | `SNOWFLAKE.CORE.FRESHNESS` on a timestamp column, or `ON ()` for the last DML, with an expectation like `VALUE < 3600`. |
| How do you find the failing rows? | `SYSTEM$DATA_METRIC_SCAN`. |
| How do you alert? | DQ notifications, or `CREATE ALERT` plus `SYSTEM$SEND_EMAIL` / a webhook. |
| Who pays? | Serverless compute, shown in `DATA_QUALITY_MONITORING_USAGE_HISTORY`. |
| Edition? | Enterprise or higher. |
| How do you stop bad data reaching reports? | A circuit breaker task that raises an error, so dependent tasks don't run. |

---

## 21. Cleanup
```sql
DROP DATABASE IF EXISTS DQ_DEMO;
```
