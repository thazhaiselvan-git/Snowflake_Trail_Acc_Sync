# CSTM Asset Schema Category: Session Knowledge Base

Consolidated record of the design, logic, decisions, validation approach and open items for
`WPA_CSTM_ASSET_SCHEMA_CATG` (Oracle `npf_common_pkg.npf_asst_typ_mgr` + `NPF_CUST_SCHEMA_RULE_EVALUATION_PKG.RULE_EVALUATION`
rebuilt on Snowflake). Keep this file together with the SQL files listed in §12.

---

## 1. Goal and final decision

- Replace the Oracle procedure logic and the old Snowflake stored procedure + streams load with a simpler, reviewable Snowflake design.
- **Final approach (agreed in review): View + MERGE procedure + 2 serverless tasks.** The dynamic-table approach was built and validated, then dropped (`Drop Dynamic Tables Liquibase.sql`).
- Oracle parity was proven on 25 hand-picked cases across all 7 Oracle branches, plus an independent validation script.

## 2. Objects (`<ENV>_WPA_ASSET_DB.CORE`)

| Object | Type | Purpose |
|---|---|---|
| `WPA_CSTM_ASSET_SCHEMA_CATG_VW` | View | All business logic |
| `WPA_CSTM_ASSET_SCHEMA_CATG_TBL` | Table | Physical result read by consumers (+ `LOAD_TS`) |
| `WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP` | SQL procedure | Consume rule streams → stage view → MERGE → DELETE |
| `WPA_CSTM_ASSET_SCHEMA_CATG_TSK` | Serverless task | `SCHEDULE = '3 MINUTES'` |
| `WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK` | Serverless triggered task | `WHEN SYSTEM$STREAM_HAS_DATA` on the rule streams |
| `NPF_CSTM_RULE_MSTR_CATG_STRM`, `NPF_CSTM_RULE_COND_CATG_STRM` | Streams | Trigger only; data is always re-read from the base tables |

Sources:
- `NPF_CUST_CSTM_SCHEMA`
- `WPA_AC_POSITION` (HOLDINGS_DB)
- `WPA_TRANSACTION` (TRANSACTION_DB)
- `NPF_ASSET`
- `NPF_ASSET_CATG`
- `NPF_DECODE` (COMMON_UTIL_DB)
- `NPF_CSTM_SCHEMA`
- `NPF_CSTM_RULE_MSTR`
- `NPF_CSTM_RULE_COND`

## 3. Grain (which rows exist)

**One row per `SCHEMA_ID × CUST_SK × INSTR_ID × ISS_TYPE`**, with `RPTG_TYPE = 'WLT'`.
- Customer schemas: every (`CUST_SK`, `SCHEMA_ID`) in `NPF_CUST_CSTM_SCHEMA`.
- × the customer's (instrument, issue type) from **positions on any date** and **all transactions**, de-duplicated with `UNION`.
  - The issue type comes from the source row (`AST_ISS_TYPE`), **not** from `NPF_ASSET`.
  - Sean confirmed that different issue types must **not** be combined. The CAS page combining them is a page-side issue.
  - A blank issue type is treated as NULL: the row is kept and gets the default category.
  - A "latest date only" filter was rejected because it misses instruments.
- The instrument must exist in `NPF_ASSET`; otherwise there is no row.
- The scan is limited to customers that have a custom schema (`cust_scope`).

## 4. Column logic: current, Oracle-exact (deployed)

First question per row: **is there an active custom row in `NPF_CSTM_SCHEMA` for (`SCHEMA_ID`, `INSTR_ID`)?** It must have `RPTG_TYPE='WLT'` and `END_DT IS NULL`; if more than one is active, the latest `START_DT` is used.
- YES → **Path 1, custom row.**
- NO → **Path 2, rules or standard.**

"Standard" = `NPF_ASSET_CATG` lookup on the row's issue type (`RPTG_TYPE='WLT'`). If no mapping row exists, the defaults are 30 'Other Assets' / 20 'Miscellaneous'. Defaults apply only when the row is missing, not when it holds NULL values.

| Column | Path 1: custom row | Path 2: rule matched | Path 2: no rule |
|---|---|---|---|
| `SUPCATG_CODE` / `SUBCATG_CODE` | standard | standard | standard |
| `SUPCATG_DESC` / `SUBCATG_DESC` | custom desc (as-is) | rule desc | standard desc |
| `CSTM_SUPCATG_CODE` | custom sup + `-C`, else NPF sup + `-S` | std sup + `-S` | std sup + `-S` |
| `CSTM_SUBCATG_CODE` | custom sub + `-C`, else NPF sub + `-S` | std sup-sub + `-S` | std sup-sub + `-S` |
| `CSTM_SUPCATG_DESC` / `CSTM_SUBCATG_DESC` | = `SUPCATG_DESC` / `SUBCATG_DESC` | same | same |

The Path 1 code matrix comes from Oracle's 4-branch IF; each code is decided independently:

| Custom SUP / SUB code | CSTM_SUPCATG_CODE | CSTM_SUBCATG_CODE |
|---|---|---|
| present / present | `<cstm sup>-C` | `<cstm sub>-C` |
| NULL / present | `<npf sup>-S` | `<cstm sub>-C` |
| present / NULL | `<cstm sup>-C` | `<npf sub>-S` |
| NULL / NULL | `<npf sup>-S` | `<npf sub>-S` |

`<npf ..>` = the `NPF_SUPCATG_CODE` / `NPF_SUBCATG_CODE` stored on the custom row.

### Oracle source references
- `Asset Type Manager - Oracle.sql`, lines 221–301: the custom path (4-branch IF).
- Lines 341–350: the rule path. `RULE_EVALUATION` is called, **only descriptions are overwritten**, and codes = `std sup-S` / `std sup-std sub-S`.
- `Rule Evaluation Oracle.sql`:
  - lines 8–10: OUT parameters are **descriptions only**;
  - lines 70–76: rule descriptions are captured;
  - lines 96–97: `COALESCE(desc_2, desc_1, standard)`.
  - `RULE_CSTM_SUPCATG_CODE` / `_SUBCATG_CODE` are **never read**.
- Oracle's single description output pair (`po_supcatg_desc_a`) is overwritten with the custom or rule value. That is why `SUPCATG_DESC` = `CSTM_SUPCATG_DESC` today.

## 5. Rule evaluation detail (Path 2)

- Only active rules (`RULE_STAT = 'A'`) of the schema are used, ordered by `RULE_SK`.
- Conditions are in `NPF_CSTM_RULE_COND`:
  - **Field:** `CSTM_SUPCATG_DESC` | `CSTM_SUBCATG_DESC` | `CSTM_CNTRY_RISK_DESC`, compared against the **standard** values.
  - **Operator:** `EQUAL` | `NOTEQUAL` vs `RULE_FLD_VALUE`.
- Per rule (Oracle variables → our columns):
  - `has_OR` → `has_or`: TRUE if **any** condition has `LOGICAL_OPER = 'OR'` (Oracle lines 60–62).
  - `v_cond_cnt` → `n_cond` / `cond_cnt`: number of conditions (line 37 / 64).
  - `v_cnt` → `n_true` / `match_cnt`: number of conditions that are true (lines 43–57).
- **Match** (Oracle line 66): `(has_or AND n_true > 0) OR (NOT has_or AND n_true = n_cond)`.
  - A rule with **zero** conditions matches (0 = 0).
  - A NULL input or value means the condition is false (never counted).
- **Result:** with 1 match, that rule's descriptions are used. With more than 1, the **last** match (highest `RULE_SK`) wins, falling back per column to the first, then standard. With no match, the standard descriptions are used.
- **Snowflake optimisation:** rules are evaluated once per distinct (std sup desc, std sub desc, country desc) combo (`CROSS JOIN combo`), not per instrument. The result is identical because rules can only see those three values.

## 6. Oracle → Snowflake semantic rules (P1–P11)

| # | Rule |
|---|---|
| P1 | Defaults only when the `NPF_ASSET_CATG` row is missing: `IFF(ac.iss_type IS NULL, default, col)` |
| P2 | Oracle `''` = NULL → `NULLIF(col,'')` |
| P3 | Oracle `CONCAT(NULL,'x')='x'` → `NVL(col,'') \|\| '-S'` |
| P4 | NULL comparisons never match |
| P5 | Any OR condition → OR rule, else AND |
| P6 | Zero-condition active rule matches → `LEFT JOIN` to conditions |
| P7 | 1 match → that rule; >1 → last (`MAX_BY`), per column last → first (`MIN_BY`) → standard |
| P8 | Custom path uses custom descriptions as-is (even NULL); `-C`/`-S` codes |
| P9 | More than one active custom row → latest `START_DT` (`QUALIFY`, 0 cases today) |
| P10 | `p_cust_sk` is not used by the procedure; the customer only decides which rows exist |
| P11 | Rule result codes are not used (Oracle). **Proposed change, see §7** |

Null-safe join keys: `NVL(desc,'#NULL#')` for rule-combo joins, and `EQUAL_NULL(iss_type, …)` for the issue-type key.

## 7. Proposed changes: pending business confirmation (NOT deployed)

File: `CSTM Asset Schema Catg - View + Task (Rule Codes).sql`. It uses the same object names, so it is a drop-in view replacement.

| Column | Custom row | Rule matched | No custom row or rule |
|---|---|---|---|
| `SUPCATG_CODE` / `SUBCATG_CODE` | standard | standard | standard |
| `SUPCATG_DESC` / `SUBCATG_DESC` | **standard NPF desc** | **standard NPF desc** | standard |
| `CSTM_SUPCATG_CODE` / `CSTM_SUBCATG_CODE` | custom `-C` / NPF `-S` | **rule code `-C`**, else standard `-S` | standard `-S` |
| `CSTM_SUPCATG_DESC` / `CSTM_SUBCATG_DESC` | custom desc | rule desc | standard |

- **Rule codes:**
  - **Request:** the CAS page needs the custom codes for filtering and grouping.
  - **Implementation:** `rule_eval` carries `RULE_CSTM_SUPCATG_CODE` / `_SUBCATG_CODE`; `rule_pick` adds `r1_*_code` / `rn_*_code`.
  - **Output:** a code is taken from **the same rule that supplied the description** (last, else first) + `-C`. A rule without a code falls back to standard.
- **NPF description fix:**
  - **Tester observation:** NPF descriptions should keep the default values.
  - **Implementation:** `SUPCATG_DESC` / `SUBCATG_DESC` = `std_sup_desc` / `std_sub_desc`. The derived value is only in `CSTM_*_DESC`.
  - **SQL detail:** the final SELECT uses `out.supcatg_desc AS cstm_supcatg_desc`, qualified because the output alias has the same name.
- **To confirm:**
  1. the overall column logic;
  2. suffix `-C` vs a separate marker (e.g. `-R`);
  3. sub code `<rule sub>-C` vs `<rule sup>-<rule sub>-C`;
  4. a code applies only together with its description;
  5. consumers switch to `CSTM_*_DESC` for the custom value.

## 8. Load mechanism

Procedure `..._LOAD_SP` (`LANGUAGE SQL`, `COMMENT` placed **before** `EXECUTE AS CALLER`, otherwise it fails to compile):
0. **Consume the rule streams first**, in their own committed transaction: `CREATE OR REPLACE TEMPORARY TABLE ..._STRM_SINK`, then `INSERT … SELECT rule_sk FROM <stream> WHERE 1=0`. No permanent sink table is needed.
1. **Stage** the view once into a temp table.
2. **MERGE** on (`SCHEMA_ID`, `CUST_SK`, `INSTR_ID`, `EQUAL_NULL(ISS_TYPE)`): insert new rows, and update only when a value changed (`IS DISTINCT FROM`). `LOAD_TS` = last change.
3. **DELETE** keys the view no longer returns, because MERGE has no "not matched by source" clause.
4. Steps 2 and 3 run in **one transaction**. On error: `ROLLBACK` + `RAISE`. The procedure returns `merged (ins+upd): n, deleted: n`.

Tasks:
- **Settings (both tasks):** serverless, `USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE='SMALL'`, `TARGET_COMPLETION_INTERVAL='10 MINUTES'`, `SUSPEND_TASK_AFTER_NUM_FAILURES=3`, `USER_TASK_TIMEOUT_MS=21600000`.
- **Privilege:** the owner role needs `EXECUTE MANAGED TASK`.
- **Why two tasks:** a task has *either* a schedule *or* a stream condition, so the 3-minute refresh plus the immediate rule refresh needs two tasks calling one procedure.
- **Frequency:** it can't be reduced (cost). A single 1-minute-gated task was rejected for credit reasons.

## 9. Scenarios and operational behaviour

| Scenario | Outcome |
|---|---|
| Rule change while idle | Rule task fires within about 1 minute |
| Rule change **during** a scheduled load | The change is after the stream offset (consumed in step 0), so it stays in the stream; the rule task runs right after. Never missed |
| Both tasks at once (rare) | Each stages its own snapshot. **The second MERGE/DELETE waits for the first to commit** (table lock). Readers are never blocked |
| Load fails after step 0 | Rollback, table unchanged; the next 3-minute run recomputes everything (≤ 3 min delay) |
| Persistent error | Task suspends after 3 failures; visible in `TASK_HISTORY` |
| Redeploy (Liquibase) | `CREATE STREAM IF NOT EXISTS` keeps the offsets; `CREATE TABLE IF NOT EXISTS` keeps the data |
| Stream staleness | Streams are read every 3 minutes, so they shouldn't go stale. They can only go stale if both tasks stay suspended for longer than retention plus the extension (14 days by default). Fix: `CREATE OR REPLACE STREAM` ×2, `CALL LOAD_SP()`, resume the tasks. Monitor `SHOW STREAMS` (`stale`, `stale_after`) and confirm `stale_after` moves forward after task runs |

Snowflake docs ([Transactions](https://docs.snowflake.com/en/sql-reference/transactions): "Resource locking", "Lock timeout parameters", "Deadlocks"):
- UPDATE, DELETE and MERGE hold locks that prevent parallel UPDATE, DELETE and MERGE.
- Locks are released on COMMIT or ROLLBACK.
- `LOCK_TIMEOUT` default is 43200 seconds.
- Deadlocks are detected and a victim is chosen. A deadlock is unlikely here because there is a single table and the same lock order.

Related docs:
- [CREATE TASK](https://docs.snowflake.com/en/sql-reference/sql/create-task): `ALLOW_OVERLAPPING_EXECUTION` default FALSE.
- [Streams](https://docs.snowflake.com/en/user-guide/streams-intro).

## 10. Validation and monitoring (queries are in the SQL files and this session)

- **Validation script:** `Validation - CSTM Asset Schema Catg DY.sql` (independent Oracle re-implementation, per row and scenario).
- **Test pack for one schema** (e.g. 6892), with no table creation:
  - Run the T4 comparison query once, then `SET T4_QID = LAST_QUERY_ID();`.
  - T5–T8 read `TABLE(RESULT_SCAN($T4_QID))`: summary by scenario, mismatches, one instrument, samples.
  - Scenarios: `P1-CUSTOM`, `P2-RULE(1)`, `P2-RULE(N)`, `P2-STANDARD`.
- **Trace queries:** source vs target for one instrument, for descriptions and for codes, showing `source_used` and `exp_*` vs `tgt_*`.
- **Multi-issue-type check:** instruments whose issue types map to different categories (`COUNT(DISTINCT HASH(...)) > 1`).
- **Performance and credits:**
  - `INFORMATION_SCHEMA.TASK_HISTORY` (state, duration, skipped, `return_value`).
  - `INFORMATION_SCHEMA.SERVERLESS_TASK_HISTORY` / `ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY` (`credits_used`).
  - Step breakdown via `ACCOUNT_USAGE.QUERY_HISTORY` joined on the task's `session_id` (elapsed, GB scanned, spill, rows).
  - Overlap check between the two tasks.
- **Excel tip:** import `INSTR_ID` / codes as **Text**. Otherwise `2.53E+10` and `05` → `5` cause false mismatches.

## 11. Validated examples (UAT2, schema 10391, before the rule was inactivated and the schema deleted)

| Instrument | Path | Result |
|---|---|---|
| 29148790000 | Custom row (code 01, Clone) | `01-C`, `25-05-S`, Clone / Partnerships ✓ |
| 59222950000 | Custom row (code 02, Testing) | `02-C`, `25-05-S`, Testing / Partnerships ✓ |
| 74289530000 | Custom row (no custom code, NPF 80) | `80-S`, `25-05-S`, All Other / Partnerships ✓ |
| 25292480001 | No custom row, rule 225 inactive | `90-S`, `90-10-S`, standard ✓ |

- **Rule 225 (code 425):** `RULE_STAT = 'I'`, so it was not applied. Even if active, Oracle would not output 425 (descriptions only).
- **`LOAD_TS`:** unchanged on untouched rows, which confirms the delta MERGE.

## 12. Files (folder `CSTM Asset schema/`): download all before the account expires

| File | Content |
|---|---|
| `CSTM Asset Schema Catg - View + Task.sql` | **Live** version (multi issue type, Oracle-exact) |
| `View Based Approach Liquibase Deployment.sql` | Liquibase changesets for the live version |
| `CSTM Asset Schema Catg - View + Task (Rule Codes).sql` | Pending: rule codes + NPF description fix |
| `CSTM Asset Schema Catg - View + Task (Asset Issue Type).sql` | Not used: single-issue-type `_AI` variant (issue type from NPF_ASSET) |
| `Drop Dynamic Tables Liquibase.sql` | Drops the 5 dynamic tables |
| `CSTM Asset Schema Catg DT - Oracle Parity.sql` | Dynamic-table version (reference, dropped) |
| `Validation - CSTM Asset Schema Catg DY.sql`, `UAT2 Validation - …` | Validation scripts |
| `Proposal - CSTM Asset Schema Catg View Approach.html` | Proposal for leads |
| `CSTM Asset Schema Catg - Logic Flow.html` | Colour flow of the logic (current Oracle behaviour) |
| `Review Guide - CSTM Asset Schema Catg.md` | Why each join and function is used |
| `Oracle_Asset_Type_Manager_Logic.md`, `WPA_CSTM_ASSET_SCHEMA_CATG_Load_Flow.md`, `..._Data_Model.md` | Oracle logic, old load flow, data model |
| `Asset Type Manager - Oracle.sql`, `Rule Evaluation Oracle.sql`, `NPF COMMON PKG.sql`, `Procedures DDL.sql`, `Table DDL.sql` | Source code and DDL references |

## 13. Open items

1. Business confirmation of §7 (rule codes + NPF description fix, 5 points).
2. Confirm that `WPA_TRANSACTION.AST_ISS_TYPE` is the column name.
3. Blank position issue types: keep the defaults, or fall back to `NPF_ASSET.ISS_TYPE`?
4. Re-test the rule path with an active rule and an instrument without a custom row (schema 6892 test pack).
5. After a week in UAT2: review run time, skipped runs and credits; confirm the stream `stale_after` moves forward.
6. If the change is approved: update the Liquibase file (new view changeset ID), the test pack, the Logic Flow HTML and the docs.
