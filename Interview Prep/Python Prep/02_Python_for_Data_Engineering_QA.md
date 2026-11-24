# Python for Data Engineering – Interview Q&A

Focus: pandas, file formats, APIs, ETL patterns, testing – what Data Engineer JDs mean by "strong Python".

---

## Section 1: pandas

### Q1. Series vs DataFrame?
Series = 1-D labeled array (one column). DataFrame = 2-D table of Series sharing an index.

### Q2. Reading / writing common formats
```python
import pandas as pd
df = pd.read_csv("orders.csv", dtype={"id": "int64"}, parse_dates=["order_date"])
df = pd.read_json("events.json", lines=True)      # NDJSON
df = pd.read_parquet("data.parquet")
df.to_parquet("out.parquet", index=False)
for chunk in pd.read_csv("big.csv", chunksize=100_000):   # large files
    process(chunk)
```

### Q3. Inspect data
```python
df.head(); df.info(); df.describe(); df.shape; df.dtypes
df.isna().sum(); df["status"].value_counts(); df.nunique()
```

### Q4. Selecting: `loc` vs `iloc`
```python
df.loc[df["amount"] > 100, ["id", "amount"]]   # label-based
df.iloc[0:5, 0:2]                             # position-based
df.query("amount > 100 and region == 'US'")
```

### Q5. Handling nulls
```python
df.dropna(subset=["email"])
df["amount"] = df["amount"].fillna(0)
df["city"] = df["city"].fillna("UNKNOWN")
df.ffill()                       # forward fill
```

### Q6. Remove duplicates / keep latest record per key
```python
df.drop_duplicates()
latest = (df.sort_values("updated_at")
            .drop_duplicates(subset=["customer_id"], keep="last"))
```
SQL equivalent: `QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY updated_at DESC) = 1`.

### Q7. GroupBy / aggregation
```python
df.groupby("region").agg(total=("amount", "sum"),
                         orders=("id", "count"),
                         avg_amt=("amount", "mean")).reset_index()
```

### Q8. Merge / join types
```python
pd.merge(orders, customers, on="customer_id", how="left")   # inner/left/right/outer
pd.merge(a, b, left_on="cid", right_on="id", indicator=True)  # _merge col shows source
pd.concat([df1, df2], ignore_index=True)                      # UNION ALL
```

### Q9. Window functions in pandas
```python
df["rank"] = df.groupby("dept")["salary"].rank(ascending=False, method="dense")
df["running_total"] = df.sort_values("dt").groupby("cust")["amt"].cumsum()
df["prev_amt"] = df.groupby("cust")["amt"].shift(1)          # LAG
df["rolling_7d"] = df["amt"].rolling(7).mean()
```

### Q10. Pivot / unpivot
```python
df.pivot_table(index="region", columns="month", values="amount", aggfunc="sum", fill_value=0)
df.melt(id_vars=["id"], var_name="metric", value_name="value")   # unpivot
```

### Q11. `apply` vs vectorization – why is apply slow?
`apply` runs a Python function row by row. Vectorized ops run in C on whole arrays.
```python
df["total"] = df["qty"] * df["price"]            # fast
df["flag"] = np.where(df["amt"] > 100, "HIGH", "LOW")
# avoid: df.apply(lambda r: r.qty * r.price, axis=1)
```

### Q12. Reduce pandas memory
- `pd.read_csv(usecols=[...], dtype={...})`
- Convert low-cardinality strings to `category`
- Downcast: `pd.to_numeric(s, downcast="integer")`
- Process in chunks, or use Polars / push work to Snowflake.

### Q13. `SettingWithCopyWarning`?
You modified a slice that may be a view. Fix: `df = df[cond].copy()` or use `df.loc[cond, "col"] = val`.

### Q14. Flatten nested JSON
```python
data = [{"id": 1, "cust": {"name": "A", "addr": {"city": "NY"}}, "items": [{"sku": "x"}]}]
pd.json_normalize(data, sep="_")                       # cust_name, cust_addr_city
pd.json_normalize(data, record_path="items", meta=["id"])  # explode array
```
Snowflake equivalent: `VARIANT` + `LATERAL FLATTEN`.

---

## Section 2: File Formats

### Q15. CSV vs JSON vs Parquet vs Avro vs ORC
| Format | Type | Schema | Best for |
|---|---|---|---|
| CSV | Row, text | None | Simple exchange |
| JSON | Row, semi-structured | Self-describing | APIs, events |
| Parquet | **Columnar**, binary, compressed | Embedded | Analytics, data lakes, Snowflake/Iceberg |
| Avro | Row, binary | Embedded, evolution | Kafka/streaming |
| ORC | Columnar | Embedded | Hive ecosystem |

Parquet is preferred for analytics: column pruning, predicate pushdown, great compression.

### Q16. Read a huge file without loading into memory
```python
with open("huge.log") as f:
    for line in f:              # file object is a lazy iterator
        if "ERROR" in line: ...
```
pandas: `chunksize`; Parquet: `pyarrow.parquet.ParquetFile(path).iter_batches()`.

### Q17. Read / write JSON safely
```python
import json
with open("cfg.json") as f: cfg = json.load(f)
json.dumps(obj, indent=2, default=str)   # default=str handles datetime/Decimal
```

---

## Section 3: APIs & Cloud

### Q18. Call a REST API with pagination and retries
```python
import requests, time
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

s = requests.Session()
s.mount("https://", HTTPAdapter(max_retries=Retry(total=5, backoff_factor=1,
                                 status_forcelist=[429, 500, 502, 503, 504])))

def fetch_all(url, token):
    rows, page = [], 1
    while True:
        r = s.get(url, params={"page": page, "per_page": 100},
                  headers={"Authorization": f"Bearer {token}"}, timeout=30)
        r.raise_for_status()
        batch = r.json()["data"]
        if not batch: break
        rows.extend(batch); page += 1
    return rows
```

### Q19. Upload to / list S3 with boto3
```python
import boto3
s3 = boto3.client("s3")
s3.upload_file("orders.parquet", "my-bucket", "raw/orders/2026/11/23/orders.parquet")
for obj in s3.get_paginator("list_objects_v2").paginate(Bucket="my-bucket", Prefix="raw/"):
    for o in obj.get("Contents", []): print(o["Key"])
```
Then Snowflake loads via an external stage + `COPY INTO` or Snowpipe auto-ingest.

---

## Section 4: ETL Design Patterns

### Q20. How would you build an ETL pipeline in Python?
1. **Extract** – API/DB/files (with retries, pagination, incremental watermark).
2. **Validate** – schema, nulls, duplicates, row counts.
3. **Transform** – pandas/Snowpark, or land raw and transform in Snowflake (ELT, preferred).
4. **Load** – `write_pandas` / stage + `COPY INTO` / `MERGE` for upserts.
5. **Orchestrate** – Airflow / Snowflake Tasks / dbt.
6. **Observe** – logging, alerts, audit table (rows in/out, duration, status).

### Q21. ETL vs ELT?
ETL transforms before loading (on external compute). ELT loads raw first and transforms inside the warehouse – standard with Snowflake because compute is elastic and SQL/Snowpark runs close to the data.

### Q22. Incremental load (watermark) pattern
```python
last = cur.execute("select coalesce(max(updated_at),'1900-01-01') from tgt.orders").fetchone()[0]
src = fetch_from_source(updated_after=last)
write_pandas(conn, src, "ORDERS_STG", auto_create_table=True, overwrite=True)
cur.execute("""
MERGE INTO tgt.orders t USING orders_stg s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET t.amount = s.amount, t.updated_at = s.updated_at
WHEN NOT MATCHED THEN INSERT (id, amount, updated_at) VALUES (s.id, s.amount, s.updated_at)
""")
```

### Q23. How do you make a pipeline idempotent?
Re-running gives the same result: use `MERGE` not blind `INSERT`, truncate-reload staging, deterministic keys, track processed files (Snowflake COPY's load metadata does this for 64 days), partition-overwrite by date.

### Q24. SCD Type 2 logic in Python (concept)
Compare incoming vs current active rows by hash of tracked columns → for changed keys, close old row (`end_date = now, is_current = False`) and insert new row (`start_date = now, is_current = True`). In practice implement as a Snowflake `MERGE` or dbt snapshot.

### Q25. How do you handle bad records?
Quarantine (dead-letter table/file) with reason column, don't fail the whole batch unless above a threshold, alert, and reprocess after fix. Snowflake: `ON_ERROR = CONTINUE`, `VALIDATE()`, error tables.

### Q26. Simple data-quality checks in Python
```python
def dq_checks(df, key):
    errors = []
    if df.empty: errors.append("empty dataset")
    if df[key].isna().any(): errors.append(f"null {key}")
    if df[key].duplicated().any(): errors.append(f"duplicate {key}")
    if (df["amount"] < 0).any(): errors.append("negative amount")
    if errors: raise ValueError("; ".join(errors))
```

---

## Section 5: Airflow (often in JDs)

### Q27. What is a DAG?
Directed Acyclic Graph of tasks with dependencies, defined in Python.
```python
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from datetime import datetime

with DAG("orders_pipeline", start_date=datetime(2026, 1, 1),
         schedule="@daily", catchup=False) as dag:
    extract = PythonOperator(task_id="extract", python_callable=extract_fn)
    load = SnowflakeOperator(task_id="merge", snowflake_conn_id="sf",
                             sql="CALL load_orders('{{ ds }}')")
    extract >> load
```
Key terms: operator, sensor, XCom (small data between tasks), `catchup`, backfill, retries, SLA.

---

## Section 6: Testing & Code Quality

### Q28. How do you unit test a transform?
```python
# test_transform.py   ->  run with: pytest -q
import pandas as pd
from transform import dedupe_latest

def test_dedupe_latest():
    df = pd.DataFrame({"id": [1, 1], "updated_at": ["2026-01-01", "2026-02-01"], "v": [1, 2]})
    out = dedupe_latest(df)
    assert len(out) == 1 and out.iloc[0]["v"] == 2
```
Use fixtures, `unittest.mock` to mock Snowflake/API calls, parametrize edge cases.

### Q29. Mocking an external call
```python
from unittest.mock import patch
@patch("pipeline.requests.get")
def test_fetch(mock_get):
    mock_get.return_value.json.return_value = {"data": []}
    mock_get.return_value.raise_for_status.return_value = None
    assert fetch_all("http://x", "t") == []
```

### Q30. Code quality tools
`black`/`ruff` (format/lint), `mypy` (types), `pytest` + coverage, pre-commit hooks, CI via GitHub Actions.
