# Python Prep – Index & Study Plan

| File | What's inside |
|---|---|
| `01_Python_Core_Interview_QA.md` | 40+ core Python questions: data types, mutability, comprehensions, generators, decorators, OOP, exceptions, context managers, GIL/concurrency, logging, quick-fire table |
| `02_Python_for_Data_Engineering_QA.md` | pandas (joins, windows, dedupe, JSON flatten), file formats, REST APIs, boto3/S3, ETL/ELT patterns, incremental & idempotent loads, DQ checks, Airflow, pytest/mocking |
| `03_Python_with_Snowflake_QA.md` | Python connector, `write_pandas`, PUT/COPY, async queries, Snowpark DataFrames, MERGE, UDF/UDTF/vectorized UDF/stored procs, external access, Streamlit, CI/CD, scenario questions |
| `04_Python_Coding_Problems.py` | 45+ runnable coding-round solutions (strings, arrays, dicts, DE-style grouping/dedupe/joins, log parsing, LRU cache, DAG topological sort) with self-tests |

## Suggested order
1. **Day 1** – File 01, sections 1–4. Practise writing decorators & generators from memory.
2. **Day 2** – File 01, sections 5–9 + run/rewrite 10 problems from file 04.
3. **Day 3** – File 02 (pandas + ETL patterns). Translate each pandas answer to Snowflake SQL.
4. **Day 4** – File 03 (Snowflake + Python). Create one UDF, one UDTF and one Python proc in your trial account.
5. **Day 5** – Remaining problems in file 04 without looking; mock-answer the scenario questions aloud.

## Most-asked (if short on time)
Mutable vs immutable · list vs tuple · `is` vs `==` · generators · decorators · `*args/**kwargs` · GIL ·
shallow vs deep copy · pandas dedupe/merge/groupby · Snowpark lazy evaluation · UDF vs stored proc ·
`write_pandas` · bind variables (SQL injection) · two-sum / anagram / word-count / flatten JSON.
