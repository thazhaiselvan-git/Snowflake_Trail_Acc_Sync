# Review Guide: CSTM Asset Schema Category (Dynamic Table version)

This guide walks through `CSTM Asset Schema Catg DT - Oracle Parity.sql` one block at a time, explaining **why** each join, filter and function is there. The View + Task version (`CSTM Asset Schema Catg - View + Task.sql`) uses exactly the same logic, with each dynamic table as a CTE, so everything below applies to it too.

---

## 0. What we are rebuilding

Oracle calls `npf_common_pkg.npf_asst_typ_mgr` (the 11-argument version) **once per customer schema × instrument × issue type**. For each call it:

1. **Standard category** (the 6-argument proc): looks up `NPF_ASSET_CATG` with the issue type passed in. If no mapping row exists it falls back to the defaults `30 / 20 / Other Assets / Miscellaneous`.
2. **Path 1, custom row:** if `NPF_CSTM_SCHEMA` has an active custom row for (schema, instrument), it uses the custom descriptions and builds `-C` / `-S` codes.
3. **Path 2, no custom row:** it runs `RULE_EVALUATION` (the schema's rules tested against the standard descriptions and the country). A matching rule's descriptions win; otherwise the standard descriptions are used.

**Output key:** `SCHEMA_ID, CUST_SK, INSTR_ID, ISS_TYPE`.

## 1. Object flow

```
WPA_AC_POSITION + WPA_TRANSACTION
        │
        ▼
DT4 WPA_CAS_CUST_INSTR_DYN    (cust, instr, issue type)       ← created FIRST
        │
        ▼  + WPA_ASSET_DYN + NPF_ASSET_CATG + NPF_DECODE
DT1 WPA_CAS_ASSET_STD_DYN     (instr, issue type) → standard category + country
        │
        ▼  + NPF_CSTM_RULE_MSTR / NPF_CSTM_RULE_COND
DT2 WPA_CAS_RULE_PICK_DYN     (schema, desc combo) → first / last matching rule

DT3 WPA_CAS_CSTM_ROW_DYN      (schema, instr) → active custom row   ◀─ NPF_CSTM_SCHEMA

FINAL WPA_CSTM_ASSET_SCHEMA_CATG_DY
  = NPF_CUST_CSTM_SCHEMA ⋈ DT4 ⋈ DT1  ⟕ DT3  ⟕ DT2
```

**Why 5 objects rather than 1?** Each table does one Oracle step, stays incrementally refreshable, and each source is read only once. Expensive work (de-duplication, rule evaluation) is done once and reused, instead of being recomputed on every refresh.

---

## 2. Oracle → Snowflake rules applied everywhere (P1–P11)

| # | Oracle behaviour | Snowflake implementation | Why it matters |
|---|---|---|---|
| P1 | Defaults apply only when the `FETCH` finds no row | `IFF(ac.iss_type IS NULL, '30', ac.supcatg_code)` | If a mapping row exists but its column is NULL, Oracle keeps NULL; it does not use the default. |
| P2 | `''` is the same as NULL | `NULLIF(col, '')` on every text input | Snowflake treats `''` and NULL as different values; this makes them the same, as in Oracle. |
| P3 | `CONCAT(NULL,'x') = 'x'` | `NVL(col,'') \|\| '-S'` | In Snowflake `NULL \|\| 'x'` is NULL, so we replace NULL with `''` first. |
| P4 | A comparison with NULL is never true | Native in Snowflake | A NULL description never matches a rule condition (EQUAL or NOTEQUAL). |
| P5 | Any condition with `LOGICAL_OPER = 'OR'` makes the whole rule OR | `has_or` flag | Otherwise the rule is AND. |
| P6 | An active rule with **zero** conditions matches | `LEFT JOIN` to conditions, `cond_cnt = 0` | An inner join would drop such rules. |
| P7 | 1 match → that rule; more than 1 → the last (highest RULE_SK); per column it falls back last → first → standard | `MIN_BY` / `MAX_BY` + `COALESCE(rn, r1, std)` | Reproduces how the Oracle loop overwrites values. |
| P8 | Custom path uses the custom description as-is (even NULL) | `CASE WHEN cstm_hit THEN cstm_desc` | No COALESCE on this path. |
| P9 | Several active custom rows: Oracle's order is undefined | `QUALIFY ROW_NUMBER() … ORDER BY start_dt DESC = 1` | Safeguard only; there are 0 such cases today. |
| P10 | `p_cust_sk` is not used inside the proc | — | The customer only decides **which** rows exist, not their values. |
| P11 | Rule result codes are not used | — | Only rule descriptions feed the output. |

---

## 3. DT4: `WPA_CAS_CUST_INSTR_DYN` (customer → instrument + issue type)

**Purpose:** decide **which rows** exist. This replaces the Oracle caller loop over customer holdings.

```sql
WITH src AS (
  SELECT cust_sk, instr_id, NULLIF(ast_iss_type,'') AS iss_type FROM WPA_AC_POSITION  ...
  UNION ALL
  SELECT cust_sk, instr_id, NULLIF(ast_iss_type,'') AS iss_type FROM WPA_TRANSACTION ...
)
SELECT cust_sk, instr_id, iss_type FROM src GROUP BY cust_sk, instr_id, iss_type;
```

| Element | Why |
|---|---|
| Positions **+** transactions, **any date** | Agreed rule. A latest-date-only filter misses instruments. |
| `ISS_TYPE` from the source row, not from `NPF_ASSET` | One instrument can appear with several issue types in positions (e.g. `0yujbMNAB.` has 11). Each one gives a different category, so each is its own row. |
| `UNION ALL` + outer `GROUP BY` instead of `UNION` | Gives the same distinct result, but this shape is incrementally refreshable. New positions only add rows, so refreshes stay small. |
| `WHERE instr_id IS NOT NULL AND cust_sk IS NOT NULL` | Rows without keys can't join anywhere. |
| `NULLIF(…,'')` | P2. |
| Separate table rather than inlined in FINAL | Positions have many rows per (customer, instrument). De-duplicating them here once is far cheaper than inside the final join on every refresh. |
| `CUST_SK` kept here, not in DT1 | Otherwise DT1 and DT2 would become per-customer, many times larger, and every daily position change would cascade into rule evaluation. |

---

## 4. DT1: `WPA_CAS_ASSET_STD_DYN` (standard category + country)

**Purpose:** the 6-argument `npf_asst_typ_mgr` plus the country-of-risk lookup. One row per (instrument, issue type).

| Join / function | Type | Why |
|---|---|---|
| `FROM WPA_CAS_CUST_INSTR_DYN ci` | driver | Only the (instrument, issue type) pairs actually in use. Nothing is computed for unused assets. |
| `JOIN WPA_ASSET_DYN a ON instr_id` | **INNER** | The Oracle custom cursor requires the instrument to exist in `NPF_ASSET`. An instrument missing there gets no row, as in Oracle. Only `CNTRY_RISK_DCDE` is used from it. |
| `LEFT JOIN NPF_ASSET_CATG ac ON rptg_type='WLT' AND iss_type = ci.iss_type` | **LEFT** | An issue type may have no mapping. The row must stay, and it gets the defaults (P1). |
| `LEFT JOIN NPF_DECODE d ON dcde_type='CNTRY' AND dcde_code = cntry_risk_dcde` | **LEFT** | The country may be missing. Oracle returns a NULL description and still processes the row. |
| `IFF(ac.iss_type IS NULL, '30', NULLIF(ac.supcatg_code,''))` | | P1: the default applies only when the mapping **row** is missing, not when its column is NULL. |
| `NVL(desc,'#NULL#') AS *_DESC_KEY` | | A **null-safe join key** for DT2 and FINAL. `NULL = NULL` is never true in a join, so NULL descriptions would otherwise never find their rule result. `#NULL#` is a value that can't occur in real data. |
| `GROUP BY ALL` (top level) | | DT4 has one row per customer; this collapses to one row per (instrument, issue type). Being at the top level keeps the table incrementally refreshable. |
| `ac.iss_type = ci.iss_type` (not `a.iss_type`) | | The Oracle proc categorises using the issue type it is **passed**, which is the position's or transaction's, not the asset master's. |

---

## 5. DT2: `WPA_CAS_RULE_PICK_DYN` (`RULE_EVALUATION`)

**Purpose:** for every schema's active rules, find which rules match each combination of standard super description, standard sub description and country description.

### 5.1 `combo` CTE
```sql
SELECT std_sup_desc, std_sub_desc, cntry_desc, <3 keys> FROM DT1 GROUP BY ...
```
**Why:** a rule condition can only test these 3 values. Thousands of instruments share a few hundred distinct combos, so we evaluate rules **once per combo**, not once per instrument. The result is identical to Oracle's, at a fraction of the cost.

### 5.2 `rule_eval` CTE

| Join / function | Type | Why |
|---|---|---|
| `FROM NPF_CSTM_RULE_MSTR r WHERE rule_stat = 'A'` | | Only active rules, as in the Oracle cursor. |
| `LEFT JOIN NPF_CSTM_RULE_COND c ON rule_sk` | **LEFT** | P6: a rule with zero conditions must still exist and match. An inner join would drop it. |
| `CROSS JOIN combo` | **CROSS** | `RULE_EVALUATION` tests **every** active rule of a schema against the instrument's values. There is no key to join rules to combos: whether a rule applies is the *result* of the evaluation, not a join condition. So every rule is paired with every combo and then evaluated. The size is small (rules × combos, not × instruments). |
| `MAX(IFF(logical_oper='OR',1,0)) AS has_or` | | P5: any OR condition makes the rule OR. |
| `COUNT(c.rule_sk) AS cond_cnt` | | Number of conditions. It counts only real condition rows, so a zero-condition rule gives 0. |
| `COUNT_IF(<field = / != value>) AS match_cnt` | | How many conditions are true. NULL comparisons evaluate to NULL, which isn't counted (P4). |
| `NULLIF(rule_fld_value,'')` | | P2. |
| `GROUP BY schema_id, combo keys, rule_sk, rule descs` | | One row per (schema, combo, rule). |

### 5.3 Final SELECT

| Element | Why |
|---|---|
| `WHERE (has_or=1 AND match_cnt>0) OR (has_or=0 AND match_cnt=cond_cnt)` | The Oracle decision: an OR rule needs any condition true; an AND rule needs all. A zero-condition AND rule gives `0 = 0`, so it matches (P6). |
| `MIN_BY(desc, rule_sk) AS r1_*` | The first matching rule (lowest RULE_SK). |
| `IFF(COUNT(*)>1, MAX_BY(desc, rule_sk), NULL) AS rn_*` | The last matching rule, only when there is more than one match. This reproduces Oracle's `desc_1` / `desc_2` (P7). |
| Only combos with at least 1 match are stored | Combos with no match fall back to the standard descriptions in FINAL, via the LEFT JOIN. |

> **DT insight `TOP_LEVEL_AGGREGATE_NOT_TOP_LEVEL`:** this is reported because `rule_eval` aggregates inside a CTE. We left it as is because the table is small (rules × combos). Splitting it would add an object for no real gain.

---

## 6. DT3: `WPA_CAS_CSTM_ROW_DYN` (custom row)

**Purpose:** Oracle's `v_rec_cnt > 0` check plus the custom cursor. It finds the active custom override for each schema and instrument.

| Element | Why |
|---|---|
| `WHERE rptg_type='WLT' AND end_dt IS NULL` | Active WLT custom rows only, as in Oracle. |
| `NULLIF(col,'')` on all 6 columns | P2. |
| `QUALIFY ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id, rptg_type ORDER BY start_dt DESC) = 1` | P9 safeguard. If more than one active row ever exists, keep the latest. It guarantees one row per key, so FINAL can never duplicate. Today it removes 0 rows. |
| Keyed by (schema, instrument) only, **not** issue type | Oracle's custom cursor doesn't use the issue type. So every issue type of the instrument gets the same custom description; only the standard codes differ. |
| Separate table (decision: option A) | It isolates the QUALIFY and keeps FINAL a simple join. |

---

## 7. FINAL: `WPA_CSTM_ASSET_SCHEMA_CATG_DY` (11-argument proc)

### 7.1 `calls` CTE: one row per Oracle call

| Join | Type | Why |
|---|---|---|
| `FROM NPF_CUST_CSTM_SCHEMA s` | driver | Every (customer, schema) assignment. |
| `JOIN DT4 ci ON ci.cust_sk = s.cust_sk` | **INNER** | Only that customer's own instruments and issue types. This fixed the earlier "every customer gets every instrument" problem (399,775 → about 6,104 instruments for customer 104265). |
| `JOIN DT1 a ON instr_id AND EQUAL_NULL(iss_type)` | **INNER** | Gets the standard category for **that** issue type. `EQUAL_NULL` makes NULL match NULL, so positions with no issue type are kept (they get the defaults). A plain `=` would drop them. Inner join means the instrument must exist in NPF_ASSET. |
| `LEFT JOIN DT3 cr ON schema_id AND instr_id` | **LEFT** | Most rows have **no** custom row. LEFT keeps them, and `cr.schema_id IS NULL` then means "Path 2". |
| `LEFT JOIN DT2 rp ON schema_id AND 3 *_DESC_KEYs` | **LEFT** | Most combos match no rule. LEFT keeps them, and they fall back to standard. The `*_DESC_KEY` columns make NULL descriptions join correctly. |
| `cr.schema_id AS cstm_hit` | | A flag: NOT NULL means Path 1 (custom row exists). |

### 7.2 `out` CTE: Oracle's IF / ELSE

| Output column | Logic | Why |
|---|---|---|
| `SUPCATG_CODE`, `SUBCATG_CODE` | always standard | In Oracle these OUT parameters always hold the 6-argument proc result. |
| `SUPCATG_DESC` | `CASE WHEN cstm_hit THEN cstm_desc ELSE COALESCE(rn_sup, r1_sup, std_sup_desc)` | Path 1 uses the custom description as-is (P8). Path 2 uses the last rule, then the first rule, then standard (P7). |
| `CSTM_SUPCATG_CODE` | Path 1: `IFF(cstm code NULL, NVL(npf code,'')\|\|'-S', cstm code\|\|'-C')`; Path 2: `NVL(std_sup,'')\|\|'-S'` | `-C` means a custom code and `-S` a standard code. Oracle's 4-branch IF matrix reduces to an independent choice per code. `NVL` handles P3. |
| `CSTM_SUBCATG_CODE` | Path 2: `sup-sub-S` | The Oracle format for the standard sub code. |
| `CSTM_*_DESC` | = `SUPCATG_DESC` / `SUBCATG_DESC` | Same as the existing table's layout. |
| `RPTG_TYPE` | `'WLT'` literal | Everything is filtered to WLT. |

**Refresh:** `TARGET_LAG = '60 minutes'`, ADAPTIVE. Upstream tables use `DOWNSTREAM`, so they refresh only when FINAL needs them.

---

## 8. Refresh modes and create order

| Object | Mode | Reason |
|---|---|---|
| DT4 cust_instr | ADAPTIVE | Append-mostly; Snowflake picks incremental or full. |
| DT1 asset_std | ADAPTIVE | Reads DT4 and `WPA_ASSET_DYN` (INCREMENTAL). |
| DT2 rule_pick | INCREMENTAL | Small; agreed. |
| DT3 cstm_row | INCREMENTAL | Small; agreed. |
| FINAL | ADAPTIVE | Large joins; Snowflake picks the cheaper mode. |

**Create order:** DT4 → DT1 → DT2 → DT3 → FINAL, because DT1 now reads DT4.

**Rule:** an INCREMENTAL table can't read a table that refreshes FULL. If DT1 ever resolves to FULL, DT2 fails to create; check `SHOW DYNAMIC TABLES` → `refresh_mode`.

**Change tracking** must be on for the base tables (pre-reqs section of the file).

---

## 9. View + Task version: what is different

| Topic | Dynamic tables | View + Task |
|---|---|---|
| Logic | 5 tables | 1 view, each table as a CTE (identical logic) |
| Asset source | `WPA_ASSET_DYN` | `NPF_ASSET` directly, limited to in-use instruments |
| Scope | All customers | `cust_scope` CTE: only customers with a custom schema (a semi-join filter on the huge position and transaction tables) |
| Load | Automatic (lag) | Serverless task: stage → `MERGE` → `DELETE` in one transaction |
| MERGE key | — | `SCHEMA_ID, CUST_SK, INSTR_ID` + `EQUAL_NULL(ISS_TYPE)` |
| Updates | — | Only when a value actually changed (`IS DISTINCT FROM`), so `LOAD_TS` = last change |
| Deletes | Automatic | Explicit `DELETE … WHERE NOT EXISTS`, because MERGE has no "not matched by source" clause |
| Why stage into a temp table | — | The view runs **once**, and both MERGE and DELETE read the same snapshot |

---

## 10. Likely review questions: short answers

- **Why the CROSS JOIN?** Rules have no join key to instruments; Oracle tests every rule against every input. We cross join rules × *distinct combos* (small), not × instruments.
- **Why LEFT JOIN to conditions?** Zero-condition rules match in Oracle (P6).
- **Why LEFT JOIN to custom row and rule pick?** Both are optional. A missing row means "take the next path".
- **Why `#NULL#` keys / `EQUAL_NULL`?** NULL never equals NULL in a join, and Oracle still processes NULL descriptions and NULL issue types.
- **Why `NULLIF(x,'')` everywhere?** Oracle treats `''` as NULL; Snowflake doesn't.
- **Why `NVL(x,'') || '-S'`?** Oracle string concatenation ignores NULL; Snowflake's returns NULL.
- **Why the QUALIFY in custom row?** It guarantees one custom row per key, so the final table can't duplicate (removes 0 rows today).
- **Why issue type from positions?** One instrument has several issue types in positions, each with a different category; Oracle categorises using the issue type passed in.
- **Why not put CUST_SK in the asset table?** It would multiply DT1 and DT2 by customers and make daily position changes cascade into rule evaluation.
- **Why UNION ALL + GROUP BY instead of UNION?** Same result, but it stays incrementally refreshable.
- **Is it Oracle-exact?** Yes. 25 hand-picked cases across all 7 scenarios (P1-CC/SC/CS/SS, P2-R1/RN/STD) matched; the validation script re-implements Oracle independently and compares every row.

## 11. Open points to mention

1. Confirm `WPA_TRANSACTION.AST_ISS_TYPE` is the column name.
2. **Blank issue types:** today a NULL issue type gets the defaults. Should it fall back to `NPF_ASSET.ISS_TYPE` instead?
3. Final schedule / lag (the task uses 15 minutes for testing).
4. The spilling insight on FINAL: use `INITIALIZATION_WAREHOUSE`, or a one-size warehouse upsize.
