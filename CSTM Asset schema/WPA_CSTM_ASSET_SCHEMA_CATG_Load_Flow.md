# WPA_CSTM_ASSET_SCHEMA_CATG – Load Flow Guide

> Source files: `Streams.sql`, `Procedures DDL.sql` (folder `CSTM Asset schema`)
>
> **Target:** `UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG`
> **Exception:** `NPF_DECODE` lives in `UAT2_WPA_COMMON_UTIL_DB.CORE`. All other source tables, the streams, the procedures and the task are in `UAT2_WPA_ASSET_DB.CORE`.

---

## 1. What the target table holds

One row per **(SCHEMA_ID, INSTR_ID, RPTG_TYPE)** – i.e. for every customer custom schema × every instrument (asset), the asset's **standard** category (super/sub category code + description) and its **custom** category for that schema.

| Column group | Columns |
|---|---|
| Key (MERGE key) | `SCHEMA_ID`, `INSTR_ID`, `RPTG_TYPE` (always `'WLT'`) |
| Schema info | `CUST_SK`, `SCHEMA_DESC` |
| Asset info | `ISS_TYPE` (payload, not part of the key) |
| Standard category | `SUPCATG_CODE`, `SUBCATG_CODE`, `SUPCATG_DESC`, `SUBCATG_DESC` |
| Custom category | `CSTM_SUPCATG_CODE`, `CSTM_SUBCATG_CODE`, `CSTM_SUPCATG_DESC`, `CSTM_SUBCATG_DESC` |
| Audit | `UPDATED_AT` |

The logic is a Snowflake port of the Oracle package `npf_asst_typ_mgr` (5‑arg overload + `RULE_EVALUATION`).

---

## 2. High-level architecture

```
 Source tables (CORE)            Streams (CDC)                       Task  →  Procedures
 ─────────────────────           ─────────────────────────────       ───────────────────────────────────────────
 NPF_ASSET_CATG        ───────▶  WPA_CAS_NPF_ASSET_CATG_STRM    ─┐   WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK
 NPF_DECODE (COMMON_UTIL_DB) ─▶  WPA_CAS_NPF_DECODE_STRM        ─┤     (fires when ANY stream has data)
 NPF_CUST_CSTM_SCHEMA  ───────▶  WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM┤          ▼
 NPF_CSTM_SCHEMA       ───────▶  WPA_CAS_NPF_CSTM_SCHEMA_STRM   ─┼─▶ WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC()
                                                                 │     (controller / dispatcher)
 NPF_CSTM_RULE_MSTR    ───────▶  WPA_CAS_NPF_CSTM_RULE_MSTR_STRM ┤          │  for each stream with data
 NPF_CSTM_RULE_COND    ───────▶  WPA_CAS_NPF_CSTM_RULE_COND_STRM ┤          ▼
 WPA_ASSET             ───────▶  WPA_CAS_ASSET_STRM             ─┘   WPA_CUSTOM_ASSET_SCHEMA_CATG_SP(stream_name)
                                                                       (worker – incremental MERGE)
                                                                            │
                                                                            ▼
                                                     UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
                                                     + audit rows in CORE.WPA_ASSET_PROC_AUDIT
```

---

## 2a. Task – `WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK`

```sql
create or replace task UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK
  target_completion_interval = '60 MINUTES'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 0
  USER_TASK_TIMEOUT_MS = 21600000
when (   SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_ASSET_CATG_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.WPA_CAS_ASSET_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_DECODE_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_SCHEMA_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_CUST_CSTM_SCHEMA_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_RULE_MSTR_STRM')
      OR SYSTEM$STREAM_HAS_DATA('uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_RULE_COND_STRM'))
as
  CALL UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC();
```

| Property | Meaning |
|---|---|
| No `SCHEDULE` + `WHEN` on streams | **Triggered task**: runs when any of the 7 streams has new data. Nothing runs (and no compute is used) when all streams are empty. |
| `TARGET_COMPLETION_INTERVAL = '60 MINUTES'` + `USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'` | **Serverless** task (no `WAREHOUSE`). Snowflake sizes the compute itself, starting at SMALL, and tries to finish each run within 60 minutes. |
| `SUSPEND_TASK_AFTER_NUM_FAILURES = 0` | The task is **never auto-suspended**, however many times it fails. |
| `USER_TASK_TIMEOUT_MS = 21600000` | A run is cancelled after 6 hours. |

Who checks what:
- **Task `WHEN`:** is there *any* stream with data? If so, start a run.
- **Controller:** checks each stream again and calls the worker for each one that has data.
- **Worker:** processes one stream.

Monitor runs with:
```sql
SELECT name, state, scheduled_time, completed_time, error_code, error_message
FROM TABLE(UAT2_WPA_ASSET_DB.INFORMATION_SCHEMA.TASK_HISTORY(
       TASK_NAME => 'WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK'))
ORDER BY scheduled_time DESC LIMIT 20;
```

---

## 3. Streams (`Streams.sql`)

| Stream | Base table | Role |
|---|---|---|
| `WPA_CAS_NPF_ASSET_CATG_STRM` | `NPF_ASSET_CATG` | ISS_TYPE → std super/sub category mapping |
| `WPA_CAS_NPF_DECODE_STRM` | `UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE` | Decode values; only `DCDE_TYPE='CNTRY'` rows matter |
| `WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM` | `NPF_CUST_CSTM_SCHEMA` | Customer custom schemas (schema header) |
| `WPA_CAS_NPF_CSTM_SCHEMA_STRM` | `NPF_CSTM_SCHEMA` | Explicit per-instrument custom category overrides |
| `WPA_CAS_NPF_CSTM_RULE_MSTR_STRM` | `NPF_CSTM_RULE_MSTR` | Rule header per schema |
| `WPA_CAS_NPF_CSTM_RULE_COND_STRM` | `NPF_CSTM_RULE_COND` | Rule conditions |
| `WPA_CAS_ASSET_STRM` | `WPA_ASSET` | Instruments/assets |

---

## 4. Procedure 1 – `WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC()` (controller)

1. Gets one `PROC_AUDIT_ID` from `WPA_ASSET_PROC_AUDIT_SEQ`.
2. Checks each of the 7 streams with `SYSTEM$STREAM_HAS_DATA(...)` in this fixed order:
   `NPF_ASSET_CATG → NPF_DECODE → NPF_CUST_CSTM_SCHEMA → NPF_CSTM_SCHEMA → NPF_CSTM_RULE_MSTR → NPF_CSTM_RULE_COND → ASSET`
3. For every stream with data → `CALL WPA_CUSTOM_ASSET_SCHEMA_CATG_SP('<STREAM_NAME>')`.
   - Each call is in its own `BEGIN … EXCEPTION` block → one stream failing **does not stop** the others.
   - Per-step JSON (query_id, duration, status, error) is accumulated in `v_additional_detail`.
4. Final status: `NO_DATA` (no stream had data), `SUCCESS`, or `PARTIAL_FAILURE`.
5. Inserts one controller row into `WPA_ASSET_PROC_AUDIT`.
6. If any child failed → `RAISE STATEMENT_ERROR` so the task run is marked failed. Because the task has `SUSPEND_TASK_AFTER_NUM_FAILURES = 0`, it is **not** suspended. Failures show only in `TASK_HISTORY` and `WPA_ASSET_PROC_AUDIT`.

---

## 5. Procedure 2 – `WPA_CUSTOM_ASSET_SCHEMA_CATG_SP(STREAM_NAME)` (worker)

Processes **one stream** incrementally. `v_loc` (0–34) marks the step and is written to the audit on failure – use it to locate errors.

### Step 1 – Capture the stream (v_loc 2–4)
| Temp table | Content |
|---|---|
| `TMP_STREAM` | `SELECT * FROM <stream>` (reading in a DML **consumes** the stream offset when the transaction commits) |
| `TMP_STREAM_UPSERT` | `METADATA$ACTION <> 'DELETE'` (inserts + new image of updates) |
| `TMP_STREAM_DELETE` | `METADATA$ACTION='DELETE' AND METADATA$ISUPDATE='FALSE'` (true deletes only) |

### Step 2 – Country decode gate (v_loc 5–6)
Only for `WPA_CAS_NPF_DECODE_STRM`: counts `CNTRY` rows in upsert (`v_cntry_cnt`) and delete (`v_cntry_del_cnt`). Non-country decode changes are ignored.

### Step 3 – Impacted SCHEMAS → `TMP_IMP_SCHEMA` (v_loc 7–15)
### Step 4 – Impacted INSTRUMENTS → `TMP_IMP_INSTR` (v_loc 16–23)
### Step 5 – Hard-delete keys → `TMP_DEL_SCHEMA` / `TMP_DEL_INSTR` (v_loc 24–26)

How each stream drives the key sets:

| Stream | Impacted schemas (re-evaluate) | Impacted instruments (re-evaluate) | Hard delete |
|---|---|---|---|
| `NPF_CSTM_SCHEMA` | schema_ids in upsert **and** delete rows | instr_ids in upsert **and** delete rows (delete → falls back to rule path) | – |
| `NPF_CUST_CSTM_SCHEMA` | schema_ids in upserts | instrs in `NPF_CSTM_SCHEMA` for those schemas | **schema_ids deleted** |
| `NPF_CSTM_RULE_MSTR` | schema_ids in upsert + delete | instrs in `NPF_CSTM_SCHEMA` for those schemas | – |
| `NPF_CSTM_RULE_COND` | schemas via `RULE_SK → NPF_CSTM_RULE_MSTR` (upsert + delete) | instrs in `NPF_CSTM_SCHEMA` for those schemas | – |
| `NPF_ASSET_CATG` | **all** schemas in `NPF_CUST_CSTM_SCHEMA` | `WPA_ASSET` instrs with matching `ISS_TYPE` (upsert + delete) | – |
| `ASSET` (`WPA_ASSET`) | **all** schemas in `NPF_CUST_CSTM_SCHEMA` (upsert) | instr_ids in upsert + delete | **instr_ids deleted** |
| `NPF_DECODE` (CNTRY only) | **all** schemas (on upsert) | `WPA_ASSET` instrs where `CNTRY_RISK_DCDE = DCDE_CODE` (upsert + delete) | – |

> ⚠ For rule streams, instruments are taken from `NPF_CSTM_SCHEMA` only. Instruments that are classified purely by rules (no `NPF_CSTM_SCHEMA` row) may not be re-evaluated by a rule-only change – worth validating with the team.

### Step 6 – Early exit (v_loc 27–28)
If `(schema_cnt = 0 OR instr_cnt = 0) AND del_keys_cnt = 0` → returns `'No impacted keys found for stream: …'`.
(Note: this early exit happens **before** the success audit row, so nothing is audited for that call.)

### Step 7 – Build `TMP_SOURCE` = new desired rows (v_loc 29)

Scope = impacted schemas × impacted instruments. CTE chain:

```
schema_dim   : NPF_CUST_CSTM_SCHEMA ∩ TMP_IMP_SCHEMA         (cust_sk, schema_desc)
asset_base   : WPA_ASSET ∩ TMP_IMP_INSTR, ISS_TYPE not null
asset_catg   : asset_base LEFT JOIN NPF_ASSET_CATG (RPTG_TYPE='WLT')
               defaults if no mapping: sup '30'/'Other Assets', sub '20'/'Miscellaneous'
cntry_desc   : asset_base LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE (CNTRY)
cstm_row     : NPF_CSTM_SCHEMA (WLT, END_DT IS NULL) in impacted keys, ROW_NUMBER → pick 1
```

Then **two mutually exclusive branches** (UNION ALL):

#### Branch A – Custom override (`custom_out`): an active `NPF_CSTM_SCHEMA` row exists
- `SUPCATG_CODE/SUBCATG_CODE` → from `asset_catg` (standard)
- `SUPCATG_DESC/SUBCATG_DESC` and `CSTM_*_DESC` → from `NPF_CSTM_SCHEMA.cstm_*_desc`
- `CSTM_*_CODE` → suffix rule:

| cstm_supcatg_code | cstm_subcatg_code | CSTM_SUPCATG_CODE | CSTM_SUBCATG_CODE |
|---|---|---|---|
| null | not null | `npf_supcatg_code-S` | `cstm_subcatg_code-C` |
| not null | null | `cstm_supcatg_code-C` | `npf_subcatg_code-S` |
| null | null | `npf_supcatg_code-S` | `npf_subcatg_code-S` |
| not null | not null | `cstm_supcatg_code-C` | `cstm_subcatg_code-C` |

(`-C` = custom, `-S` = standard)

#### Branch B – Rule evaluation / fallback (`fallback_out`): no `NPF_CSTM_SCHEMA` row
1. **rule_eval** – every schema × asset against active rules (`RULE_STAT='A'`) and their conditions. A condition matches on:
   - `CSTM_SUPCATG_DESC` vs asset std super desc
   - `CSTM_SUBCATG_DESC` vs asset std sub desc
   - `CSTM_CNTRY_RISK_DESC` vs country description
   - operators `EQUAL` / `NOTEQUAL`
2. **matched_rules** – a rule matches if:
   - any condition is `OR` → at least one condition matches, else
   - all conditions match (AND).
3. **rule_pick** – first matched rule (lowest `RULE_SK`) and last matched rule (highest `RULE_SK`, only when >1 match).
4. Output:
   - `SUP/SUBCATG_CODE` = standard codes
   - `*_DESC` = `COALESCE(last rule, first rule, standard desc)`
   - `CSTM_SUPCATG_CODE` = `sup_code || '-S'`
   - `CSTM_SUBCATG_CODE` = `sup_code || '-' || sub_code || '-S'`

### Step 8 – `TMP_DELETE_TARGET` (v_loc 30)
Existing target rows whose `SCHEMA_ID ∈ TMP_DEL_SCHEMA` or `INSTR_ID ∈ TMP_DEL_INSTR`.

### Step 9 – `TMP_MERGE_SOURCE` (v_loc 31)
`TMP_SOURCE` (`is_delete=0`) UNION ALL `TMP_DELETE_TARGET` (`is_delete=1`).

### Step 10 – MAIN MERGE (v_loc 32)
```sql
MERGE INTO WPA_CSTM_ASSET_SCHEMA_CATG t USING tmp_merge_source s
  ON t.schema_id = s.schema_id AND t.instr_id = s.instr_id AND t.rptg_type = s.rptg_type
WHEN MATCHED AND s.is_delete = 1 THEN DELETE
WHEN MATCHED                     THEN UPDATE (all payload cols + updated_at)
WHEN NOT MATCHED AND s.is_delete = 0 THEN INSERT
```

### Step 11 – Audit (v_loc 33–34) + exception handler
- Success: row in `WPA_ASSET_PROC_AUDIT` with `STATUS=COMPLETED`, counts (`imp_schemas`, `imp_instr`, `hard_del_keys`) and the per-step JSON.
- Failure: `EXCEPTION WHEN OTHER` writes a `FAILED` row with `SQLCODE/SQLSTATE/SQLERRM`, `STEP`, `LOC`, then `RAISE` (bubbles to the controller).

---

## 6. End-to-end example

1. A user adds a rule condition in `NPF_CSTM_RULE_COND`.
2. `WPA_CAS_NPF_CSTM_RULE_COND_STRM` gets a row.
3. Task fires controller → stream has data → calls SP with `'WPA_CAS_NPF_CSTM_RULE_COND_STRM'`.
4. SP: `RULE_SK` → `NPF_CSTM_RULE_MSTR` → schema_id(s) → instruments of those schemas from `NPF_CSTM_SCHEMA`.
5. Rebuilds rows for those keys, MERGE updates descriptions in the target.
6. Audit rows written (one per SP call + one controller row).

---

## 7. Debugging cheatsheet

```sql
-- Latest runs (controller + worker)
SELECT asset_proc_audit_id, obj_name, stream_name, status, proc_start_tm, duration_secs,
       processed_cnt, error_cnt, sqlcode_val, additional_comments
FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET_PROC_AUDIT
WHERE obj_name ILIKE '%CUSTOM_ASSET_SCHEMA_CATG%'
ORDER BY proc_start_tm DESC
LIMIT 50;

-- Pending changes per stream
SELECT SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STRM');

-- Manual run
CALL UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC();
CALL UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_SP('WPA_CAS_NPF_CSTM_SCHEMA_STRM');
```

On failure, read `LOC=<n>` in `ADDITIONAL_COMMENTS` and map it to the steps above.

---

## 8. Observations to verify with the team

1. **`NPF_DECODE` stream DDL:** `Streams.sql` uses `on table NPF_DECODE`, which is unqualified. Run in `UAT2_WPA_ASSET_DB.CORE`, that resolves to a table in the asset DB, not `UAT2_WPA_COMMON_UTIL_DB`. Qualify it explicitly:
   `create or replace stream UAT2_WPA_ASSET_DB.CORE.WPA_CAS_NPF_DECODE_STRM on table UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE;`
   (Change tracking must be allowed on that table, and the owning role needs SELECT on it.)
2. **ASSET stream (Streams.sql line 13):** deferred for later, per the team.
3. **Unqualified names in Streams.sql:** the other base table names are also unqualified, so run the file with `UAT2_WPA_ASSET_DB.CORE` as the context.
4. **Temp tables:** they are created with fully qualified names but read unqualified (e.g. `tmp_stream`). This only works while the session context is `UAT2_WPA_ASSET_DB.CORE`.
5. **No audit row on early exit:** the early-exit path (Step 6) returns without writing an audit row, even though the stream was read.
6. **No auto-suspend:** with `SUSPEND_TASK_AFTER_NUM_FAILURES = 0` the task never suspends, so repeated failures can go unnoticed. Consider adding an alert on `TASK_HISTORY` or on `WPA_ASSET_PROC_AUDIT` rows with `STATUS IN ('FAILED','PARTIAL_FAILURE')`.
7. **Duplicate stream checks:** the task's `WHEN` and the controller both call `SYSTEM$STREAM_HAS_DATA`. That's harmless: the task check only decides whether to start a run.

---

## 9. Dynamic Table version (`CSTM Asset Schema Catg DT.sql`)

The streams, task and both procedures are replaced by 4 declarative DTs in `UAT_WPA_ASSET_DB.CORE` (warehouse `UAT_WPA_DYNAMICTABLE_VWH`):

| DT | Lag | Replaces proc CTE(s) | Grain |
|---|---|---|---|
| `WPA_CAS_ASSET_CATG_DYN` | DOWNSTREAM | `asset_base`, `asset_catg`, `cntry_desc` | 1 row / instrument (from `WPA_ASSET_DYN`) |
| `WPA_CAS_RULE_PICK_DYN` | DOWNSTREAM | `rule_eval`, `matched_rules`, `rule_pick` | schema × distinct (sup_desc, sub_desc, cntry_desc) with a matched rule |
| `WPA_CAS_CSTM_ROW_DYN` | DOWNSTREAM | `cstm_row` (rn = 1) | 1 active custom row / (schema, instr) |
| `WPA_CSTM_ASSET_SCHEMA_CATG_DYN` | 60 minutes | `custom_out` UNION ALL `fallback_out` | (schema, instr, 'WLT') |

Key points:
- **Incremental handling is automatic:** the stream routing, the impacted-key temp tables and the MERGE/hard-delete logic all go away.
- **Rule evaluation is cheaper:** rules are evaluated once per distinct description combination, not once per asset. The result is the same with far fewer rows.
- **Row counts will differ:** the asset set now comes from `WPA_ASSET_DYN` (instruments in positions/transactions), not the full `WPA_ASSET`.
- **`UPDATED_AT` dropped for now:** use `ROW_TIMESTAMP = TRUE` later if needed.
- **Audit:** the audit table is replaced by `DYNAMIC_TABLE_REFRESH_HISTORY`.
