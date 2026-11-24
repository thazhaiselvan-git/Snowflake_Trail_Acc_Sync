# Python + Snowflake – Interview Q&A

Focus: Snowflake Python Connector, Snowpark, UDFs/UDTFs, stored procedures, and where Python fits in Snowflake.

---

## Section 1: Snowflake Python Connector

### Q1. How do you connect to Snowflake from Python?
```python
import snowflake.connector
conn = snowflake.connector.connect(
    account="myorg-myacct", user="ETL_USER",
    private_key_file="rsa_key.p8",            # key-pair auth (recommended for service users)
    authenticator="SNOWFLAKE_JWT",
    warehouse="ETL_WH", database="RAW", schema="SALES", role="ETL_ROLE",
)
# or: snowflake.connector.connect(connection_name="prod")  -> reads ~/.snowflake/connections.toml
```
Auth options: password (+MFA), key-pair (JWT), OAuth, external browser (SSO), PAT, workload identity federation. Passwords alone are being phased out for service users – use key-pair/OAuth.

### Q2. Execute queries and fetch results
```python
with conn.cursor() as cur:
    cur.execute("select id, amount from orders where region = %s", ("US",))  # bind params
    for row in cur: print(row)
    cur.fetchone(); cur.fetchmany(1000); cur.fetchall()
    df = cur.execute("select * from orders").fetch_pandas_all()      # Arrow -> pandas
    for batch in cur.fetch_pandas_batches(): process(batch)          # big results
    print(cur.sfqid)                                                  # query id
```

### Q3. How do you prevent SQL injection?
Use bind variables (`%s`, `%(name)s`, or `?` with `paramstyle='qmark'`), never f-strings with user input. For identifiers use `IDENTIFIER(%s)` or validate against an allow-list.

### Q4. Bulk-load a pandas DataFrame
```python
from snowflake.connector.pandas_tools import write_pandas
success, nchunks, nrows, _ = write_pandas(conn, df, "ORDERS_STG",
                                          auto_create_table=True, overwrite=True,
                                          quote_identifiers=False)
```
Internally: writes Parquet → `PUT` to temp stage → `COPY INTO`. Much faster than `executemany` INSERTs.

### Q5. PUT / GET files from Python
```python
cur.execute("PUT file:///data/orders_*.csv @my_int_stage AUTO_COMPRESS=TRUE PARALLEL=8")
cur.execute("COPY INTO orders FROM @my_int_stage FILE_FORMAT=(TYPE=CSV SKIP_HEADER=1) ON_ERROR='CONTINUE'")
cur.execute("GET @my_int_stage/exports/ file:///tmp/out/")
```

### Q6. Async queries
```python
cur.execute_async("call long_running_proc()")
qid = cur.sfqid
while conn.is_still_running(conn.get_query_status(qid)):
    time.sleep(5)
cur.get_results_from_sfqid(qid)
```

### Q7. Transactions
Autocommit is on by default. For multi-statement atomicity:
```python
conn.autocommit(False)
try:
    cur.execute("delete from tgt where dt = %s", (d,))
    cur.execute("insert into tgt select * from stg where dt = %s", (d,))
    conn.commit()
except Exception:
    conn.rollback(); raise
```

### Q8. Handling connector errors
```python
from snowflake.connector.errors import ProgrammingError, DatabaseError, OperationalError
try: cur.execute(sql)
except ProgrammingError as e:
    print(e.errno, e.sqlstate, e.sfqid, e.msg)
```

---

## Section 2: Snowpark for Python

### Q9. What is Snowpark?
A DataFrame API (Python/Java/Scala) whose operations are **lazily** translated to SQL and executed **inside Snowflake** compute. Data doesn't leave Snowflake → secure, scalable, no separate Spark cluster.

### Q10. Connector vs Snowpark?
| | Connector | Snowpark |
|---|---|---|
| Style | Send SQL strings | DataFrame API (pushdown) |
| Execution | Results come to client | Runs in warehouse |
| UDF/Proc creation | Via SQL DDL | Native Python `@udf`, `@sproc` |
| Best for | Simple scripts, loading, admin | Transformations, ML, pipelines |

### Q11. Create a session & basic DataFrame ops
```python
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, sum as sum_, when, lit, current_timestamp

session = Session.builder.configs({"connection_name": "prod"}).create()
# inside a Snowflake notebook / proc: from snowflake.snowpark.context import get_active_session

orders = session.table("RAW.SALES.ORDERS")
result = (orders.filter(col("STATUS") == "COMPLETE")
                .with_column("TIER", when(col("AMOUNT") > 1000, lit("HIGH")).otherwise(lit("LOW")))
                .group_by("REGION", "TIER")
                .agg(sum_("AMOUNT").alias("TOTAL")))
result.show()                                    # action -> executes
result.write.mode("overwrite").save_as_table("ANALYTICS.SALES.REGION_SUMMARY")
```

### Q12. What is lazy evaluation in Snowpark? Transformations vs actions?
Transformations (`filter`, `select`, `join`, `group_by`) build a query plan only. **Actions** (`collect`, `show`, `count`, `to_pandas`, `save_as_table`) generate SQL and run it. Check SQL with `df.queries` / `df.explain()`.

### Q13. Joins, window functions, MERGE in Snowpark
```python
from snowflake.snowpark import Window
from snowflake.snowpark.functions import row_number

w = Window.partition_by("CUSTOMER_ID").order_by(col("UPDATED_AT").desc())
latest = src.with_column("RN", row_number().over(w)).filter(col("RN") == 1).drop("RN")

joined = orders.join(customers, orders["CUSTOMER_ID"] == customers["ID"], "left")

from snowflake.snowpark.functions import when_matched, when_not_matched
tgt = session.table("DIM_CUSTOMER")
tgt.merge(latest, tgt["ID"] == latest["CUSTOMER_ID"],
          [when_matched().update({"NAME": latest["NAME"]}),
           when_not_matched().insert({"ID": latest["CUSTOMER_ID"], "NAME": latest["NAME"]})])
```

### Q14. Working with semi-structured data in Snowpark
```python
from snowflake.snowpark.functions import flatten
events = session.table("RAW_EVENTS")
events.select(col("V")["user"]["id"].cast("string").alias("USER_ID"))
events.join_table_function("flatten", col("V")["items"]).select(col("VALUE")["sku"])
```

### Q15. `collect()` vs `to_pandas()` – pitfalls?
Both pull results to the client. On large tables this is slow and can OOM. Keep processing in Snowpark; only pull aggregates. Use `to_pandas_batches()` if needed.

### Q16. What is the Snowpark pandas API (Modin)?
`import modin.pandas as pd; import snowflake.snowpark.modin.plugin` – pandas syntax, executed in Snowflake. Lets teams migrate pandas code with minimal changes.

---

## Section 3: Python UDFs, UDTFs, UDAFs, Stored Procedures

### Q17. UDF vs UDTF vs UDAF vs Stored Procedure
| Object | Input → Output | Used in | Typical use |
|---|---|---|---|
| UDF (scalar) | 1 row → 1 value | `SELECT` | Clean/mask/parse a value |
| Vectorized UDF | batch (pandas) → batch | `SELECT` | Fast ML scoring |
| UDTF | 1 row → N rows | `FROM TABLE(...)` | Explode, parse, per-partition logic |
| UDAF | N rows → 1 value | `GROUP BY` | Custom aggregation |
| Stored Procedure | args → result, can run SQL/DDL | `CALL` | Orchestration, admin, ETL steps |

### Q18. Python UDF in SQL
```sql
CREATE OR REPLACE FUNCTION mask_email(e STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
HANDLER = 'mask'
AS $$
def mask(e):
    if e is None or "@" not in e:
        return e
    user, dom = e.split("@", 1)
    return user[0] + "***@" + dom
$$;

SELECT mask_email(email) FROM customers;
```

### Q19. Python UDF using Snowpark decorator + packages
```python
from snowflake.snowpark.functions import udf
@udf(name="clean_phone", is_permanent=True, stage_location="@udf_stage",
     replace=True, packages=["phonenumbers"])
def clean_phone(p: str) -> str:
    import phonenumbers
    try:
        return phonenumbers.format_number(phonenumbers.parse(p, "US"),
                                          phonenumbers.PhoneNumberFormat.E164)
    except Exception:
        return None
```
Packages come from the Snowflake Anaconda channel (or artifact repository for PyPI). Custom code via `IMPORTS = ('@stage/mylib.zip')`.

### Q20. Vectorized UDF – why faster?
Receives a pandas Series/DataFrame batch instead of one row → fewer Python calls, uses NumPy vectorization.
```python
from snowflake.snowpark.functions import pandas_udf
from snowflake.snowpark.types import PandasSeriesType, FloatType
@pandas_udf(return_type=PandasSeriesType(FloatType()),
            input_types=[PandasSeriesType(FloatType())])
def to_usd(s): return s * 1.08
```

### Q21. Python UDTF
```sql
CREATE OR REPLACE FUNCTION split_tags(tags STRING)
RETURNS TABLE (tag STRING)
LANGUAGE PYTHON RUNTIME_VERSION='3.11' HANDLER='Splitter'
AS $$
class Splitter:
    def process(self, tags):
        for t in (tags or "").split(","):
            if t.strip():
                yield (t.strip(),)
$$;

SELECT p.id, t.tag FROM products p, TABLE(split_tags(p.tags)) t;
```
`process()` per row, optional `end_partition()` per partition (with `PARTITION BY`).

### Q22. Python stored procedure
```sql
CREATE OR REPLACE PROCEDURE load_orders(load_date STRING)
RETURNS STRING
LANGUAGE PYTHON RUNTIME_VERSION='3.11'
PACKAGES=('snowflake-snowpark-python')
HANDLER='run'
EXECUTE AS OWNER
AS $$
from snowflake.snowpark.functions import col
def run(session, load_date):
    stg = session.table("RAW.ORDERS").filter(col("ORDER_DATE") == load_date)
    n = stg.count()
    if n == 0:
        return f"No rows for {load_date}"
    stg.write.mode("append").save_as_table("CORE.ORDERS")
    session.sql("insert into audit.load_log select %s, current_timestamp()" % n).collect()
    return f"Loaded {n} rows"
$$;

CALL load_orders('2026-11-22');
```
First handler arg is always the `session`. Schedule it with a Snowflake **TASK**.

### Q23. Owner's rights vs caller's rights procedures
`EXECUTE AS OWNER` (default): runs with owner's privileges, restricted (can't change session state) – good for controlled admin actions. `EXECUTE AS CALLER`: runs with caller's privileges and session context.

### Q24. How can a Python UDF call an external API?
Create a **network rule** (egress hosts) + **secret** + **external access integration**, then reference it:
```sql
CREATE FUNCTION get_fx(...) ...
EXTERNAL_ACCESS_INTEGRATIONS = (fx_api_int)
SECRETS = ('api_key' = fx_api_secret)
...
-- inside Python: import _snowflake; key = _snowflake.get_generic_secret_string('api_key')
```
By default Python UDFs/procs have no internet access (sandboxed).

### Q25. Limitations of Python UDFs?
Sandboxed (no network unless EAI, limited filesystem `/tmp`), only approved packages (or uploaded), memory limits per warehouse node (use Snowpark-optimized warehouses for large memory/ML), cold-start overhead – prefer built-in SQL functions when possible.

---

## Section 4: Python in the wider Snowflake platform

### Q26. Where else does Python run in Snowflake?
- **Snowflake Notebooks** (warehouse or container runtime)
- **Streamlit in Snowflake** – data apps in Python
- **Snowpark ML / Snowflake ML** – feature store, model registry, training & inference
- **Snowpark Container Services** – any containerized Python app
- **dbt Python models** (run as Snowpark)
- **Snowpipe Streaming SDK** (Python) for low-latency ingestion
- **Snowflake CLI (`snow`)** and the Python API (`snowflake.core`) for managing objects

### Q27. Snowflake Python API (`snowflake.core`) example
```python
from snowflake.core import Root
from snowflake.core.warehouse import Warehouse
root = Root(session)
root.warehouses.create(Warehouse(name="DEMO_WH", warehouse_size="XSMALL",
                                 auto_suspend=60), mode="or_replace")
```
Manage objects as Python resources instead of SQL strings – useful for IaC-style automation.

### Q28. Minimal Streamlit in Snowflake app
```python
import streamlit as st
from snowflake.snowpark.context import get_active_session
session = get_active_session()
region = st.selectbox("Region", ["US", "EU", "APAC"])
df = session.table("ANALYTICS.SALES.REGION_SUMMARY").filter(f"REGION = '{region}'").to_pandas()
st.bar_chart(df, x="TIER", y="TOTAL")
```
(Use `col("REGION") == region` instead of string filters for anything user-typed.)

### Q29. How do you deploy Python code to Snowflake in CI/CD?
Package code (zip/wheel) → upload to stage via `snow stage copy` / `PUT` → create/replace UDFs/procs via `snow snowpark deploy` or SQL scripts → GitHub Actions with key-pair or OIDC auth → separate DEV/QA/PROD databases, parameterized by env. Also: Snowflake Git repository integration + `EXECUTE IMMEDIATE FROM @repo/...`.

### Q30. Python performance best practices with Snowflake
1. Push down: filter/aggregate in Snowflake, not in pandas.
2. Use `write_pandas` / COPY for loads, not row-by-row INSERT.
3. Use `fetch_pandas_batches` for large reads.
4. Prefer vectorized UDFs; prefer SQL built-ins over UDFs.
5. Reuse a single connection/session; close cursors.
6. Use Snowpark-optimized warehouses for memory-heavy Python.
7. Set `QUERY_TAG` for cost attribution: `session.query_tag = "etl:orders"`.

---

## Section 5: Scenario Questions

**S1. A pandas script that pulls 200M rows from Snowflake, transforms and writes back is crashing. What do you do?**
Rewrite the transform in Snowpark/SQL so it runs in the warehouse; if Python logic is unavoidable, use a vectorized UDF or UDTF partitioned by key; avoid `to_pandas()` on full data.

**S2. You need to call a third-party REST API for each customer and store results daily.**
Option A: Python stored proc with external access integration + secret, scheduled via Task, results `MERGE`d into a table. Option B: external orchestrator (Airflow) with requests + `write_pandas`. Discuss rate-limits, retries, batching, idempotency.

**S3. How do you load files arriving in S3 every few minutes with Python involvement?**
Prefer Snowpipe auto-ingest (no Python needed). Python is used for pre-processing (e.g., converting XML → Parquet in Lambda) or for Snowpipe Streaming SDK when you need row-level low latency.

**S4. How do you mask PII using Python?**
Prefer native **masking policies** (and tag-based masking). Python UDF only for complex logic (e.g., format-preserving masking) – then call it inside the masking policy body.

**S5. How do you test Snowpark code?**
`pytest` with a local testing session: `Session.builder.config("local_testing", True).create()`, compare DataFrames with expected results; integration tests against a DEV database in CI.
