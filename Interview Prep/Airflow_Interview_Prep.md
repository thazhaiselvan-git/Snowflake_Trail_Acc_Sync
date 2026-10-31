# Airflow Interview Prep (Snowflake-focused)

Built around the real DAG `DAILY_MASTER_METRIC_NEW` (file: `Interview Prep/Airflow DAG.sql`. It's actually Python code, so in a real repo it would be a `.py` file in the `dags/` folder).

---

## 1. What this DAG does

> "This DAG runs every hour, Monday to Saturday. First it checks that the upstream files exist. Then it calls an external SOAP API with Okta auth and runs the calls in parallel through a multiprocessing pool. The raw XML responses land in a Snowflake table. Next it validates which IDs weren't processed and emails the list. After that it opens a run-control (audit) record and loads data through the layers **S0 → S1 → ADL → MDW** with Snowflake stored procedures, using three task groups that run in parallel. Finally it closes the run-control record and writes marker files so downstream DAGs know it's done."

### Flow
```
CNM_WATCHER ─► FILE_WATCHER ─► DELETE_DATASET ─► CLEANING_RESPONSE (TRUNCATE)
   ─► EXTRACT_XML (API calls → Snowflake) ─► EXTRACT_XML_VALIDATION (email)
   ─► OPEN_BUSINESS_PROCESS
   ─► [ TG0: DAILY_METRIC   S0→S1→ADL
        TG1: DAILY_ANNUAL   S0→S1→ADL
        TG2: IRAS_HIERARCHY ADL→CONFORMITY→MDW ]   (parallel)
   ─► SCRTY_MDW ─► PERF_MDW ─► NONBENCHMARK_MDW ─► RPTNG_DATES_MDW
   ─► LTST_STATE_MDW ─► BRIDGE_MDW ─► CLOSE_BUSINESS_PROCESS
   ─► [ CNM_COMPLETE, COMPLETE ]                    (parallel marker files)
```

### Data layers (Medallion-style)
| Layer | Meaning | Roughly equivalent to |
|---|---|---|
| S0 | Raw landing (API/file data as-is) | Bronze |
| S1 | Cleansed / typed staging | Silver |
| ADL | Integrated data lake layer | Silver/Gold |
| MDW | Dimensional data warehouse (facts, dims, bridges, CDC Type 1) | Gold |

---

## 2. Key terms, mapped to the DAG

### 2.1 DAG and its parameters
```python
dag = DAG(dag_id='DAILY_MASTER_METRIC_NEW', default_args=default_args,
          catchup=False, max_active_runs=1, schedule='0 */1 * * 1-6',
          sla_miss_callback=sla_callback_function, tags=[...])
```
| Term | Meaning |
|---|---|
| **DAG** | Directed Acyclic Graph: a set of tasks plus their dependencies, with no cycles allowed. |
| **dag_id** | Unique name shown in the UI. |
| **schedule** | Cron expression. `0 */1 * * 1-6` means minute 0 of every hour, Mon–Sat. It also accepts presets (`@daily`), `timedelta`, timetables, or **Datasets**. |
| **start_date** | First logical date the DAG is scheduled for. Use a *static* date and never `datetime.now()`. |
| **catchup=False** | Don't backfill the missed intervals between start_date and now. |
| **max_active_runs=1** | Only one DAG run at a time. That matters here because the runs share the same response table and marker files. |
| **tags** | Used to filter DAGs in the UI. |
| **doc_md / .doc** | Documentation shown in the UI. |
| **Timezone** | `pendulum.timezone("America/Chicago")` makes the DAG timezone-aware so it handles DST correctly. Airflow stores times in UTC internally. |

### 2.2 default_args
Dictionary of arguments that **every task inherits**, unless a task overrides them:
- `owner`, `start_date`
- `email_on_failure / email_on_retry`: turned off here because a custom callback handles it
- `do_xcom_push: False`: by default, return values are not stored in XCom
- `sla: timedelta(hours=20)`: each task should finish within 20h of the scheduled time
- `on_failure_callback`: runs `mark_process_as_failed` when any task fails

### 2.3 Operators used
| Operator | Purpose | In this DAG |
|---|---|---|
| **PythonOperator** | Runs a Python callable | API extract, validation |
| **BashOperator** | Runs a shell command | Deletes and creates `.ds` marker files |
| **SQLExecuteQueryOperator** | Runs SQL through a connection (the modern replacement for `SnowflakeOperator`) | TRUNCATE, `CALL` stored procedures |
| **ShortCircuitOperator** | If the callable returns `False`, **all downstream tasks are skipped** | File watchers |
| Imported but unused | `ExternalTaskSensor`, `SFTPSensor`, `SqlSensor`, `SQLCheckOperator`, `SQLValueCheckOperator`, `SQLIntervalCheckOperator`, `SFTPGetMultipleFilesOperator` | Be ready to explain these (see §3) |

**Operator vs Task vs Task Instance**
- *Operator* = the class/template (`PythonOperator`)
- *Task* = an instantiated operator inside a DAG (`DAILY_MASTER_METRIC_EXTRACT_XML`)
- *Task Instance (TI)* = one run of a task for a specific DAG run, with a state such as queued, running, success, failed, skipped, up_for_retry, or upstream_failed

### 2.4 Hooks and Connections
```python
dwh_hook = SnowflakeHook(snowflake_conn_id="wca_elt_conjur_snowflake_dt",
                         session_parameters={"QUERY_TAG": "AIRFLOW-..."})
```
- **Connection**: credentials stored in Airflow's metadata DB or a secrets backend. Here the name `conjur` suggests CyberArk Conjur is the secrets backend. Tasks reference it only by `conn_id`.
- **Hook**: a Python interface to an external system (`SnowflakeHook`, `SSHHook`). Operators use hooks internally.
  - `get_first(sql)` returns the first row, `get_records(sql)` returns all rows, `run(sql)` executes the statement.
- **QUERY_TAG** (Snowflake): tags every query so you can trace it in `QUERY_HISTORY` back to the DAG or task. Good for cost attribution and debugging. **This is an important Snowflake + Airflow talking point.**
- `hook_params` lets you pass these session parameters into `SQLExecuteQueryOperator`.
- `autocommit=True` commits each statement.

### 2.5 Pools
```python
pool='HOLD_IRAS_LOAD_POOL' / 'IRAS_POOL' / 'DEFAULT_POOL' / 'IRAS_MAST_METRIC_D_HIERARCHY_POOL'
```
A **pool** caps how many tasks can run at once against a resource, across *all* DAGs. For example, it can stop 20 DAGs from hammering the same Snowflake warehouse or API. Other related limits: `priority_weight`, `pool_slots`, `max_active_tasks` (DAG level), and `parallelism` (global).

### 2.6 Retries
```python
retries=4, retry_delay=duration(minutes=1)
```
Failed tasks go to `up_for_retry`. Related settings: `retry_exponential_backoff`, `max_retry_delay`. Retries only work well if tasks are **idempotent**, and this DAG is designed for it: the extract only fetches rows `NOT IN` the response table, so a retry resumes where it stopped.

### 2.7 depends_on_past / wait_for_downstream
On `DELETE_DATASET`:
- **depends_on_past=True**: this task runs only if *its own* previous run succeeded (or was skipped).
- **wait_for_downstream=True**: also waits until the previous run's *immediate downstream* tasks finish. That stops overlapping runs from corrupting shared files.

### 2.8 Task Groups
```python
@task_group(group_id='DAILY_METRIC_DATA_PROCESS', dag=dag)
def TG0(): S0 >> S1 >> ADL
```
Task groups visually group tasks in the UI and prefix task_ids (`DAILY_METRIC_DATA_PROCESS.DAILY_MASTER_METRIC_S0`). They replaced **SubDAGs**, which are deprecated and removed in Airflow 3. `[TG0(), TG1(), TG2()]` runs the three groups **in parallel**.

### 2.9 Dependencies
- `a >> b` means b runs after a (`a << b` is the reverse). The same can be written as `a.set_downstream(b)`.
- `a >> [b, c]` fans out, and `[b, c] >> d` fans in.
- **Trigger rules** decide when a task runs based on its upstream states. The default is `all_success`. Others: `all_done`, `one_failed`, `one_success`, `none_failed`, `none_failed_min_one_success`, `all_skipped`.
  - Interview tip: a cleanup or notification task usually uses `trigger_rule='all_done'`.

### 2.10 Callbacks
| Callback | When | In this DAG |
|---|---|---|
| `on_failure_callback` | A task fails | Creates an incident ticket (ServiceNow etc.) and sends a failure email in `finally` |
| `on_success_callback` | A task succeeds | `cleanup_xcom` deletes this DAG's XCom rows |
| `on_retry_callback`, `on_execute_callback` | Retry or start | Not used |
| `sla_miss_callback` | A task misses its SLA | Emails the DL with the blocking tasks and log URL |

The `context` dict holds `task_instance`, `dag`, `exception`, `ds`, `logical_date`, `run_id`, etc.

### 2.11 SLA
`sla=timedelta(hours=20)` is measured from the **scheduled time** of the run, not from when the task started. A miss doesn't stop the task. It only logs and fires the callback. **Note:** classic SLAs were removed in Airflow 3.0. They are being replaced by *Deadline Alerts*.

### 2.12 XCom
- XCom ("cross-communication") is small data passed between tasks and stored in the **metadata DB**.
- `do_xcom_push=True` on SQL operators stores the query result. The DAG cleans these rows up on success through `@provide_session` and a `session.query(XCom).delete()`.
- Interview point: **don't pass large data through XCom**. Pass references instead (a table name or S3 path), or use a custom XCom backend.

### 2.13 Variables
```python
Variable.get("AIRFLOW_ENV", default_var=None)
```
Key/value config stored in the metadata DB (env name, email DLs). Best practice is to call `Variable.get` **inside** tasks or use Jinja `{{ var.value.X }}`. Calling it at the top level hits the DB on every DAG parse.

### 2.14 Dataset-file pattern (file-based cross-DAG dependency)
The DAG checks for and writes `.ds` files in `/opt/p_vol/dataset/`:
- Watchers (`ShortCircuitOperator` + `os.path.isfile`) run the DAG only when the upstream marker exists.
- At the start it deletes the markers. At the end it writes `..._COMPLETE_LOAD.ds` / `..._COMPLETED.ds` for downstream DAGs.

`from airflow import Dataset` is imported but not used. The **native** way to do this is **data-aware scheduling**:
```python
ds = Dataset("snowflake://db/schema/daily_metric")
# producer task:  outlets=[ds]
# consumer DAG:   schedule=[ds]
```
(In Airflow 3 this is called `Asset`.)

### 2.15 Parallelism inside a task
`billiard.Pool(processes=6).map(func, rows)` makes 6 API calls at a time, in batches of 50, until nothing is left unprocessed. `billiard` is Celery's fork of multiprocessing and works inside Celery workers. Airflow-native alternative: **Dynamic Task Mapping** (`.expand()`), which gives one mapped TI per batch with its own retries and logs.

---

## 3. Other must-know concepts (not all in this DAG)

### Architecture
- **Scheduler**: parses DAGs, creates DAG runs, and queues TIs.
- **Executor**: decides *how* tasks run: Sequential, Local, **Celery** (worker queue), **Kubernetes** (a pod per task), CeleryKubernetes.
- **Workers**: execute the tasks.
- **Webserver / API server**: the UI.
- **Metadata DB** (Postgres/MySQL): stores state, XCom, variables, and connections.
- **Triggerer**: runs **deferrable** operators (async waits that don't hold a worker slot).
- **DAG Processor**: parses DAG files (a separate component in Airflow 2.3+ and 3).

### Sensors
Wait for a condition: `FileSensor`, `SFTPSensor`, `SqlSensor`, `ExternalTaskSensor` (waits for a task in another DAG), `S3KeySensor`.
- `mode='poke'` holds a worker slot. `mode='reschedule'` frees the slot between checks. `deferrable=True` is the most efficient.
- `poke_interval`, `timeout`, `soft_fail`.

### Data-quality operators (imported in this DAG)
- `SQLCheckOperator`: fails if the first row contains any falsy value.
- `SQLValueCheckOperator`: compares the result with an expected value, within a tolerance.
- `SQLIntervalCheckOperator`: compares today's metrics against N days ago.
- `SQLColumnCheckOperator` / `SQLTableCheckOperator`: declarative checks.

### Templating (Jinja)
`{{ ds }}`, `{{ ds_nodash }}`, `{{ logical_date }}`, `{{ data_interval_start }}`, `{{ params.x }}`, `{{ var.value.x }}`, `{{ conn.x.host }}`. Templates only work on an operator's `template_fields`, for example the `sql` in SQL operators.

### Logical date / data interval
A run for interval `[start, end)` fires **at the end** of the interval. `execution_date` was renamed to `logical_date`.

### Backfill / catchup / clear
- `airflow dags backfill -s 2024-01-01 -e 2024-01-31 DAG_ID` (in Airflow 3 you can also backfill from the UI)
- **Clear** a task to re-run it and its downstream tasks.

### TaskFlow API
```python
@dag(schedule="@daily", start_date=..., catchup=False)
def my_dag():
    @task
    def extract(): return [1,2,3]
    @task
    def load(x): ...
    load.expand(x=extract())   # dynamic task mapping
my_dag()
```
Return values go through XCom automatically.

### Branching
`BranchPythonOperator` / `@task.branch` returns the task_id(s) to follow and the rest are skipped. Compare with `ShortCircuitOperator`, which is an all-or-nothing skip.

### Other
- `EmptyOperator` (formerly DummyOperator) for start/end markers.
- `TriggerDagRunOperator` triggers another DAG.
- `@task.virtualenv`, `KubernetesPodOperator` for dependency isolation.
- Setup/teardown tasks (Airflow 2.7+).

---

## 4. Snowflake + Airflow (+ dbt) integration

| Topic | Talking point |
|---|---|
| Connection | `snowflake` provider. Account, user, **key-pair auth** (preferred over password), role, warehouse, database, schema. |
| Operators | `SQLExecuteQueryOperator(conn_id=...)`. `SnowflakeOperator` is deprecated. `SnowflakeSqlApiOperator` runs multi-statement SQL async/deferrable through the SQL API. `S3ToSnowflakeOperator` for COPY. |
| Logic location | This DAG keeps transformation logic in **Snowflake stored procedures** (`CALL CODEBASE.WCA_S0_TO_S1_DATA_LOAD(...)`), so Airflow is only the orchestrator. That's a good pattern: compute runs in Snowflake. |
| QUERY_TAG | Traceability and cost attribution in `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`. |
| Run control / audit | `RCC_OPEN_PROC_ROW_SP` / `RCC_CLOSE_PROC_ROW_SP` log the start and end of each business process in an audit table. |
| CDC Type 1 | `WCA_ADL_TO_MDW_CDC_TYPE1` overwrites changed attributes with no history. Type 2 keeps history with effective dates and a current flag. Usually implemented with `MERGE`. |
| Airflow vs Snowflake Tasks | Airflow handles cross-system orchestration (APIs, SFTP, emails, multiple platforms) and gives rich retries and a UI. Snowflake Tasks/Streams/Dynamic Tables are native, serverless, and Snowflake-only. Use both: Airflow orchestrates, and Snowflake objects handle in-database incremental work. |
| dbt | Run with **Astronomer Cosmos** (`DbtTaskGroup`), which turns each dbt model into an Airflow task, or with `BashOperator("dbt build")`, or with `EXECUTE DBT PROJECT` (dbt Projects on Snowflake). The S0/S1/ADL stored procedures could be rewritten as dbt models (staging → intermediate → marts) with tests replacing the validation task. |

---

## 5. Problems in this DAG (worth discussing in interviews)

Being able to critique real code impresses interviewers:

1. **SQL injection / quoting risk**: the `INSERT` is built by string concatenation with API response text. Use bind parameters instead: `dwh_hook.run(sql, parameters=(...))`. Also, inserting one row at a time is slow in Snowflake. Batch inserts (`insert_rows`) or a stage plus `COPY INTO` would be better.
2. **Token logged in plain text**: `print(f"Processing TOKEN: {text}")` leaks the Okta bearer token into the task logs.
3. **Top-level code**: Hooks (`SnowflakeHook`, `SSHHook`) are created at module level, so they're instantiated on every DAG parse. They should be created inside the callables.
4. **Pool not cleaned up**: it calls `pool.close()` but never `pool.join()`. Use `with Pool(6) as p:` instead. The redundant `Total_records` reassignments can also go.
5. **ShortCircuit vs Sensor**: the file watchers check once and skip. A `FileSensor` in `reschedule` or deferrable mode, or native **Datasets**, would be cleaner.
6. **Missing import**: `TaskInstance` is used as a type hint in `sla_callback_function` but never imported. The type hint is evaluated when the function runs, so the callback raises a NameError.
7. **Unused imports**, and logging is configured twice (`logger` is overwritten).
8. **Copy-pasted `.doc` strings**: many tasks say "Open the Business process", which isn't what they do.
9. **Delete script exits 1** if a marker file is missing. That's intentional as a guard, but `set -e` and a clear error message would help.
10. **Hard-coded URL and paths**: move them into Connections or Variables.
11. **Hourly schedule with `sla=20h`**: the SLA is looser than the schedule interval, so a delayed run can overlap the next schedule (`max_active_runs=1` protects against that).
12. **Airflow 3 readiness**: `sla`, `sla_miss_callback`, and direct metadata-DB access (`provide_session` + `XCom` delete) are removed or restricted in Airflow 3.

---

## 6. Likely interview questions with short answers

1. **What is a DAG? Why acyclic?** It's a graph of tasks plus dependencies. Acyclic means there's a guaranteed order and a guaranteed end.
2. **Operator vs Hook vs Sensor?** An operator does the work. A hook is the connection interface the operator uses. A sensor is an operator that waits for a condition.
3. **What does `catchup` do?** With `True`, the scheduler creates runs for all past intervals since start_date. With `False`, it only creates the latest one.
4. **How do you pass data between tasks?** XCom for small data. For large data, write it to Snowflake or S3 and pass the reference.
5. **How do you limit concurrency against Snowflake?** Pools, `max_active_runs`, `max_active_tasks`, and warehouse sizing or multi-cluster on the Snowflake side.
6. **How do you make tasks idempotent?** Use MERGE/upsert, delete+insert by partition or date, and an "only process unprocessed rows" filter, as in this DAG's `NOT IN`.
7. **How do you handle failures?** Retries with a delay, `on_failure_callback` (incident + email), trigger rules for cleanup, and alerting on SLAs or deadlines.
8. **What's the difference between `depends_on_past` and `wait_for_downstream`?** `depends_on_past` checks the same task's previous run. `wait_for_downstream` also waits for that previous run's direct downstream tasks.
9. **How do you create cross-DAG dependencies?** `ExternalTaskSensor`, `TriggerDagRunOperator`, Datasets/Assets (preferred), or marker files (this DAG's legacy approach).
10. **ShortCircuitOperator vs BranchPythonOperator?** ShortCircuit skips all downstream tasks when it returns False. Branch picks which path to follow.
11. **What are the executor types?** Local, Celery, Kubernetes. Celery means persistent workers. Kubernetes gives a pod per task with isolation.
12. **What are deferrable operators?** They release the worker slot while waiting, and the Triggerer handles the async wait.
13. **How do you secure credentials?** Connections plus a secrets backend (Conjur, Vault, AWS Secrets Manager), key-pair auth for Snowflake, and never logging secrets.
14. **How would you orchestrate dbt on Snowflake from Airflow?** Cosmos `DbtTaskGroup` (model-level tasks with retries) or `dbt build` in a task, then run tests, with `QUERY_TAG` or dbt `query_tag` set for traceability.
15. **What would you improve in this DAG?** See §5.

---

## 7. Cheat sheet
```
schedule cron:   min hour dom month dow   → '0 */1 * * 1-6'
states:          none → scheduled → queued → running → success/failed/skipped/up_for_retry/upstream_failed
CLI:             airflow dags list | dags test <id> <date> | tasks test <dag> <task> <date>
                 airflow dags trigger <id> | dags backfill | tasks clear
```
