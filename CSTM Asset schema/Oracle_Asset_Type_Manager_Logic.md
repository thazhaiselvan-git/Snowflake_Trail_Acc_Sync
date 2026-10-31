# Oracle Logic Guide – `npf_asst_typ_mgr` + `RULE_EVALUATION`

> **Sources:** `Asset Type Manager - Oracle.sql`, `Rule Evaluation Oracle.sql`
> **Goal:** understand the original Oracle logic so that `UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG` can be built as Snowflake Dynamic Tables straight from it.

---

## 1. The three program units

| # | Unit | Package | Role |
|---|---|---|---|
| A | `npf_asst_typ_mgr` (**6 args**) | `npf_common_pkg` | Standard category lookup: `ISS_TYPE` + `RPTG_TYPE` → standard super/sub category code and description. |
| B | `npf_asst_typ_mgr` (**11 args**) | `npf_common_pkg` | Main entry point. Returns the **standard or customised** category for one (schema, instrument). Calls A, and calls C when no custom row exists. |
| C | `RULE_EVALUATION` | `NPF_CUST_SCHEMA_RULE_EVALUATION_PKG` | Evaluates a schema's rules against the asset's descriptions and returns custom descriptions. |

The call you were given:
```sql
npf_common_pkg.npf_asst_typ_mgr(
    v_iss_type_a, v_rptg_type_a, v_instr_id_a, p_schema_fltr, p_cust_sk_a,   -- IN
    v_ast_supcatg_code_a, v_ast_subcatg_code_a,                              -- OUT  → SUPCATG_CODE / SUBCATG_CODE
    v_ast_supcatg_desc_a, v_ast_subcatg_desc_a,                              -- OUT  → SUPCATG_DESC / SUBCATG_DESC
    v_cstm_supcatg_code_a, v_cstm_subcatg_code_a);                           -- OUT  → CSTM_SUPCATG_CODE / CSTM_SUBCATG_CODE
```
It returns the category for **one** (schema, instrument) per call. The caller loops over schemas, customers and instruments; that caller code isn't in the files provided (see §7).

```
caller loop (not provided)
   └─▶ B  npf_asst_typ_mgr(iss_type, 'WLT', instr_id, schema_id, cust_sk, ...)
           ├─ count active NPF_CSTM_SCHEMA rows for (schema, instr, rptg)
           ├─ > 0 → Path 1 (custom override)
           │        └─▶ A  standard codes
           └─ = 0 → Path 2 (rules / standard)
                    ├─▶ A  standard codes + descriptions
                    ├─  country code (NPF_ASSET) → country desc (NPF_DECODE 'CNTRY')
                    └─▶ C  RULE_EVALUATION(schema, sup_desc, sub_desc, cntry_desc)
```

---

## 2. Unit A – standard category lookup (6 args)

```sql
SELECT supcatg_code, subcatg_code, supcatg_desc, subcatg_desc
FROM   NPF_ASSET_CATG
WHERE  rptg_type = :p_rptg_type_a
AND    iss_type  = :p_iss_type_a;
```

**Logic:**
1. **Defaults first:** the OUT parameters are set to package constants `pg_supcatg_asset_code_c`, `pg_subcatg_asset_code_c`, `pg_supcatg_asset_desc_c` and `pg_subcatg_asset_desc_c`.
2. **Lookup:** `OPEN / FETCH / CLOSE` reads **one row**. If it finds a row, that row overwrites the defaults. If it finds none, the defaults stay. A single FETCH doesn't raise NO_DATA_FOUND.
3. **Uniqueness:** PK `(ISS_TYPE, RPTG_TYPE)` guarantees at most one row.

| Output | Value |
|---|---|
| `po_supcatg_code_a` / `po_subcatg_code_a` | Mapping codes, or the package defaults |
| `po_supcatg_desc_a` / `po_subcatg_desc_a` | Mapping descriptions, or the package defaults |

> ✅ **Package constants confirmed** (`NPF COMMON PKG.sql`, lines 236–241):
> `pg_supcatg_asset_code_c = '30'`, `pg_subcatg_asset_code_c = '20'`,
> `pg_supcatg_asset_desc_c = 'Other Assets'`, `pg_subcatg_asset_desc_c = 'Miscellaneous'`,
> `pg_cntry_risk_code_c` / `pg_cntry_risk_desc_c` = **NULL** (declared without a value).

**Snowflake equivalent:**
```sql
LEFT JOIN NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = a.iss_type
COALESCE(ac.supcatg_code, <pg_supcatg_asset_code_c>) ...
```

---

## 3. Unit B – main entry point (11 args)

### 3.1 Inputs

| Param | Meaning | Used? |
|---|---|---|
| `p_iss_type_a` | Instrument's issue type | Yes, passed to unit A |
| `p_rptg_type_a` | Reporting type (`'WLT'`) | Yes |
| `p_instr_id_a` | Instrument | Yes |
| `p_schema_fltr` | Custom schema ID | Yes |
| `p_cust_sk` | Customer | **No, never referenced.** The result depends only on (schema, instrument, reporting type). |

### 3.2 Step 0 – defaults
The standard outputs are set to the package defaults, plus `po_cntry_code_a` / `po_cntry_desc_a` for country. `po_cstm_supcatg_code_a` and `po_cstm_subcatg_code_a` start as NULL.

### 3.3 Step 1 – does an explicit custom row exist?
```sql
SELECT COUNT(*) INTO v_rec_cnt
FROM NPF_CSTM_SCHEMA
WHERE schema_id = p_schema_fltr AND instr_id = p_instr_id_a
  AND rptg_type = p_rptg_type_a AND end_dt IS NULL;
```
If the count is more than 0, the procedure takes **Path 1**. Otherwise it takes **Path 2**.

### 3.4 Path 1 – custom override (`v_rec_cnt <> 0`)

Cursor `cstm_asset_cursor`:
```sql
SELECT ncs.cstm_supcatg_code, ncs.cstm_supcatg_desc, ncs.npf_supcatg_code,
       ncs.cstm_subcatg_code, ncs.cstm_subcatg_desc, ncs.npf_subcatg_code
FROM   NPF_CSTM_SCHEMA ncs, NPF_ASSET na
WHERE  ncs.schema_id = p_schema_fltr AND ncs.instr_id = p_instr_id_a
AND    na.instr_id   = ncs.instr_id               -- instrument must exist in NPF_ASSET
AND    ncs.rptg_type = p_rptg_type_a AND end_dt IS NULL;
-- NOTE: na.iss_type = p_iss_type_a is commented out
```

For **each** cursor row:
1. **Standard codes:** call unit A, which sets `po_supcatg_code_a` / `po_subcatg_code_a` (and descriptions) to the **standard** values.
2. **Descriptions:** overwrite them with the custom ones: `po_supcatg_desc_a := CSTM_SUPCATG_DESC`, `po_subcatg_desc_a := CSTM_SUBCATG_DESC`.
3. **Custom codes:** build them from this matrix:

| `CSTM_SUPCATG_CODE` | `CSTM_SUBCATG_CODE` | `po_cstm_supcatg_code_a` | `po_cstm_subcatg_code_a` |
|---|---|---|---|
| NULL | NOT NULL | `NPF_SUPCATG_CODE  \|\| '-S'` | `CSTM_SUBCATG_CODE \|\| '-C'` |
| NOT NULL | NULL | `CSTM_SUPCATG_CODE \|\| '-C'` | `NPF_SUBCATG_CODE  \|\| '-S'` |
| NULL | NULL | `NPF_SUPCATG_CODE  \|\| '-S'` | `NPF_SUBCATG_CODE  \|\| '-S'` |
| NOT NULL | NOT NULL | `CSTM_SUPCATG_CODE \|\| '-C'` | `CSTM_SUBCATG_CODE \|\| '-C'` |

`-C` means the code came from the customer. `-S` means it's the standard code stored on the override row (`NPF_*_CODE`).

**Final Path 1 output:**

| OUT | Value |
|---|---|
| `po_supcatg_code_a`, `po_subcatg_code_a` | Standard codes (unit A) |
| `po_supcatg_desc_a`, `po_subcatg_desc_a` | `CSTM_SUPCATG_DESC`, `CSTM_SUBCATG_DESC`, used **as-is even when NULL** |
| `po_cstm_supcatg_code_a`, `po_cstm_subcatg_code_a` | From the matrix |

**Things to note:**
- **Several active rows:** the loop overwrites the outputs on each row, so the **last row fetched wins**. The cursor has **no ORDER BY**, which makes the choice non-deterministic in Oracle. The Snowflake procedure picked `ROW_NUMBER() ... ORDER BY npf_supcatg_code, npf_subcatg_code = 1` (a deterministic *first*). That's a reasonable choice but not provably what Oracle does. Query 3.3 in `Queries.sql` shows whether duplicates actually exist.
- **Edge case:** if the instrument isn't in `NPF_ASSET`, `v_rec_cnt > 0` but the cursor returns 0 rows. Only the defaults are returned: default codes and descriptions, and **NULL** custom codes.
- **No country check:** country isn't looked up in Path 1.

### 3.5 Path 2 – rule evaluation / standard (`v_rec_cnt = 0`)

1. **Standard category:** call unit A, which gives standard codes and descriptions.
2. **Country code:**
   ```sql
   SELECT cntry_risk_dcde INTO po_cntry_code_a FROM npf_asset WHERE instr_id = p_instr_id_a;
   ```
   NO_DATA_FOUND gives NULL.
3. **Country description:**
   ```sql
   SELECT dcde_desc INTO po_cntry_desc_a FROM npf_decode
   WHERE dcde_type = 'CNTRY' AND dcde_code = po_cntry_code_a;
   ```
   NO_DATA_FOUND or a NULL code gives NULL.
4. **Rules:** call `RULE_EVALUATION(p_schema_fltr, std_sup_desc, std_sub_desc, cntry_desc)` (§4).
5. **Descriptions:** `po_supcatg_desc_a` / `po_subcatg_desc_a` are set to the descriptions returned by the rule evaluation.
6. **Custom codes, always standard:**
   - `po_cstm_supcatg_code_a = std_sup_code || '-S'`
   - `po_cstm_subcatg_code_a = std_sup_code || '-' || std_sub_code || '-S'` ← note the **sup-sub** concatenation.

**Final Path 2 output:**

| OUT | Value |
|---|---|
| `po_supcatg_code_a`, `po_subcatg_code_a` | Standard codes |
| `po_supcatg_desc_a`, `po_subcatg_desc_a` | Rule descriptions, or the standard descriptions if no rule matched |
| `po_cstm_supcatg_code_a` | `<sup>-S` |
| `po_cstm_subcatg_code_a` | `<sup>-<sub>-S` |

Rule result **codes** (`RULE_CSTM_SUPCATG_CODE`, etc.) are never used. Rules only change **descriptions**.

### 3.6 Exceptions
`WHEN OTHERS → npf_err_pkg.rec_stop(...)` logs the error and stops. For example, `TOO_MANY_ROWS` would raise here if `NPF_ASSET` had duplicate `INSTR_ID`s.

---

## 4. Unit C – `RULE_EVALUATION`

**Inputs:** schema ID, standard super description, standard sub description, country description.
**Outputs:** custom super description, custom sub description, custom country description. The country output isn't used by B.

### 4.1 Algorithm

```
v_rule_cnt := 0
FOR each rule IN NPF_CSTM_RULE_MSTR
        WHERE schema_id = :schema AND rule_stat = 'A'
        ORDER BY rule_sk                         ← precedence order
    has_OR := FALSE; v_cnt := 0; v_cond_cnt := 0
    FOR each cond IN NPF_CSTM_RULE_COND WHERE rule_sk = rule.rule_sk ORDER BY cond_order
        v_cond_cnt := total number of conditions in the rule   (COUNT(1) OVER)
        IF condition is TRUE  → v_cnt += 1
        IF cond.logical_oper = 'OR' → has_OR := TRUE
    END
    rule matches IF (has_OR AND v_cnt > 0) OR (NOT has_OR AND v_cnt = v_cond_cnt)
    IF matches:
        IF v_rule_cnt = 0 → desc_1 := rule.RULE_CSTM_SUPCATG_DESC / SUBCATG_DESC   (first match)
        ELSE              → desc_2 := rule.RULE_CSTM_SUPCATG_DESC / SUBCATG_DESC   (overwritten → last match)
        v_rule_cnt += 1
END
out_sup_desc := COALESCE(desc_2_sup, desc_1_sup, in_sup_desc)
out_sub_desc := COALESCE(desc_2_sub, desc_1_sub, in_sub_desc)
```

### 4.2 Condition truth table

| `RULE_FLD_NAME` | Compared input | `EQUAL` true when | `NOTEQUAL` true when |
|---|---|---|---|
| `CSTM_SUPCATG_DESC` | standard super description | `input = RULE_FLD_VALUE` | `input != RULE_FLD_VALUE` |
| `CSTM_SUBCATG_DESC` | standard sub description | same | same |
| `CSTM_CNTRY_RISK_DESC` | country description | same | same |
| anything else | – | never | never |

**NULL handling (Oracle 3-valued logic):** if the input **or** `RULE_FLD_VALUE` is NULL, the comparison is UNKNOWN and the condition counts as **not true**. That applies to `NOTEQUAL` too: an asset with no country never satisfies `CSTM_CNTRY_RISK_DESC NOTEQUAL 'X'`.

### 4.3 Match rule

| Rule shape | Matches when |
|---|---|
| **Any** condition has `LOGICAL_OPER = 'OR'` | At least one condition is true. The whole rule becomes OR. |
| No `OR` anywhere | **All** conditions are true (AND). |
| Unknown field name or operator in an AND rule | That condition is never true, so the rule never matches. |
| **Active rule with zero conditions** | The inner loop never runs: `v_cnt = 0 = v_cond_cnt`, `has_OR = FALSE`, so the rule **MATCHES every asset**. |

`LOGICAL_OPER` isn't parsed as an expression. There is no mixed precedence like `(A AND B) OR C`: a single OR anywhere turns the whole rule into "any".

### 4.4 Choosing the result
- **0 matching rules:** standard descriptions.
- **1 matching rule:** that rule's descriptions.
- **2 or more matching rules:** the **last** matching rule (highest `RULE_SK`).
- **Each column falls back separately:** `COALESCE` is applied per column. If the last rule has a NULL `RULE_CSTM_SUBCATG_DESC`, the sub description falls back to the first rule's value, and then to the standard one. Super and sub can therefore come from **different rules**.

### 4.5 Dead code
- **Rule-level ELSE:** the `ELSE` branch when a rule doesn't match assigns the outputs, but the final COALESCE always overwrites them, so it has no effect.
- **NO_DATA_FOUND handler:** the per-rule exception handler never fires, because cursor FOR loops don't raise it.
- **Country output:** `p_cstm_cntry_of_risk_desc` is returned, but unit B ignores it.

---

## 5. Where the existing Snowflake procedure differs from Oracle

| # | Topic | Oracle | Snowflake proc (`WPA_CUSTOM_ASSET_SCHEMA_CATG_SP`) | Impact |
|---|---|---|---|---|
| 1 | **Active rule with no conditions** | **Matches everything** (§4.3) | `WHERE cond_cnt > 0`, so it **never matches** | Different descriptions for those schemas. Check query 4.4 (`ACTIVE_RULE_NO_COND`). Business must confirm which is intended. |
| 2 | Several active custom rows | Last fetched, no ORDER BY (non-deterministic) | First, by `npf_supcatg_code, npf_subcatg_code` | Only matters if duplicates exist (query 3.3). |
| 3 | Custom row but instrument missing from `NPF_ASSET` | Defaults, custom codes NULL | Row dropped (inner join to asset) | Edge case. |
| 4 | `ISS_TYPE IS NULL` assets | Depends on the caller (A just returns defaults) | Excluded (`iss_type IS NOT NULL`) | Confirm with the caller code. |
| 5 | `CUST_SK` | Input, unused | Taken from `NPF_CUST_CSTM_SCHEMA` and written to the target | Same category per schema. Grain question in §7. |
| 6 | Empty string `''` | Oracle treats `''` as NULL | Snowflake `''` is a value | `NULLIF(col,'')` is needed on description/value columns for exact parity. |

Everything else in the Snowflake procedure matches Oracle: the `-C`/`-S` matrix, `<sup>-<sub>-S`, OR/AND semantics, last/first rule precedence with per-column COALESCE, and NULLs never matching.

---

## 6. Oracle → Snowflake Dynamic Table translation

Each Oracle unit becomes one declarative layer. The final build is **4 dynamic tables** (DEV: `DEV_WPA_ASSET_DB.CORE`, warehouse `DEV_ADHOC_ANALYSIS`). The asset table is read **once**, by DT1.

| Oracle | Snowflake layer |
|---|---|
| Unit A (+ country lookup in B) | **DT1 `WPA_CAS_ASSET_STD_DYN`**: thin DT over the existing `DEV_ANALYTICS_DB.WCA.WPA_ASSET_DYN` (already joins `NPF_ASSET` + WLT category + decode, with the `30`/`20` defaults). Adds `NULLIF` and the 3 `*_DESC_KEY` join keys. One row per instrument. |
| Unit C | **DT2 `WPA_CAS_RULE_PICK_DYN`**: DT1 → distinct (sup_desc, sub_desc, cntry_desc) → rule evaluation → first and last matching rule per schema |
| `v_rec_cnt` + `cstm_asset_cursor` | **DT3 `WPA_CAS_CSTM_ROW_DYN`**: one active `NPF_CSTM_SCHEMA` row per (schema, instr, 'WLT') |
| Unit B IF/ELSE | **Final `WPA_CSTM_ASSET_SCHEMA_CATG_DY`**: `NPF_CUST_CSTM_SCHEMA` × DT1, LEFT JOIN DT3 (Path 1) and DT2 (Path 2) |

```
DEV_ANALYTICS_DB.WCA.WPA_ASSET_DYN
   │  read once
   ▼
DT1 WPA_CAS_ASSET_STD_DYN ───────────────────────┐
   │                                             │
   ▼                                             │
DT2 WPA_CAS_RULE_PICK_DYN ◀─ NPF_CSTM_RULE_MSTR / NPF_CSTM_RULE_COND
   │                                             │
   │    DT3 WPA_CAS_CSTM_ROW_DYN ◀─ NPF_CSTM_SCHEMA
   │       │                                     │
   ▼       ▼                                     ▼
WPA_CSTM_ASSET_SCHEMA_CATG_DY = NPF_CUST_CSTM_SCHEMA × DT1
                               ⟕ DT3 (custom row?)  ⟕ DT2 (rule match?)
```

DT1 is the single place where the asset → category/country mapping and the join keys are defined, and both DT2 and the final DT read it. Full DDL: `CSTM Asset Schema Catg DT - Oracle Parity.sql`.

Core of DT2, written to be Oracle-exact. It keeps zero-condition rules (difference #1) and uses `LEFT JOIN` on conditions:

```sql
WITH rule_eval AS (
  SELECT r.schema_id, cb.sup_desc_key, cb.sub_desc_key, cb.cntry_desc_key,
         r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
         MAX(IFF(c.logical_oper = 'OR', 1, 0)) AS has_or,
         COUNT(c.rule_sk)                      AS cond_cnt,          -- 0 for rules without conditions
         COUNT_IF(   (c.rule_fld_name = 'CSTM_SUPCATG_DESC'    AND ((c.rule_oper='EQUAL' AND cb.sup_desc   = c.rule_fld_value) OR (c.rule_oper='NOTEQUAL' AND cb.sup_desc   != c.rule_fld_value)))
                  OR (c.rule_fld_name = 'CSTM_SUBCATG_DESC'    AND ((c.rule_oper='EQUAL' AND cb.sub_desc   = c.rule_fld_value) OR (c.rule_oper='NOTEQUAL' AND cb.sub_desc   != c.rule_fld_value)))
                  OR (c.rule_fld_name = 'CSTM_CNTRY_RISK_DESC' AND ((c.rule_oper='EQUAL' AND cb.cntry_desc = c.rule_fld_value) OR (c.rule_oper='NOTEQUAL' AND cb.cntry_desc != c.rule_fld_value)))
                 ) AS match_cnt
  FROM NPF_CSTM_RULE_MSTR r
  LEFT JOIN NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
  CROSS JOIN <distinct desc combos from asset_std> cb
  WHERE r.rule_stat = 'A'
  GROUP BY ALL
)
SELECT schema_id, sup_desc_key, sub_desc_key, cntry_desc_key,
       MIN_BY(rule_cstm_supcatg_desc, rule_sk)                          AS r1_sup,
       MIN_BY(rule_cstm_subcatg_desc, rule_sk)                          AS r1_sub,
       IFF(COUNT(*) > 1, MAX_BY(rule_cstm_supcatg_desc, rule_sk), NULL) AS rn_sup,
       IFF(COUNT(*) > 1, MAX_BY(rule_cstm_subcatg_desc, rule_sk), NULL) AS rn_sub
FROM rule_eval
WHERE (has_or = 1 AND match_cnt > 0)
   OR (has_or = 0 AND match_cnt = cond_cnt)       -- 0 = 0 → zero-condition rule matches (Oracle)
GROUP BY ALL;
-- final desc = COALESCE(rn_sup, r1_sup, std_sup_desc), same for sub
```

This logic is implemented in `CSTM Asset Schema Catg DT - Oracle Parity.sql` with all the parity adjustments from §5, targeting `UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG`.

---

## 7. Open points to confirm before building

1. ~~Package constants~~ **Resolved:** `'30'` / `'20'` / `'Other Assets'` / `'Miscellaneous'`, country defaults NULL. The package's 11-argument procedure is identical to `Asset Type Manager - Oracle.sql`.
   The package also has `get_cstm_cntry_risk_desc` (custom country of risk from `NPF_CSTM_SCHEMA`), but `npf_asst_typ_mgr` doesn't call it, so it isn't part of this output.
2. **Caller procedure:** the Oracle code that calls `npf_asst_typ_mgr` in a loop. It defines the **grain** of the target:
   - Which instruments: all of `NPF_ASSET`, or only those held or traded (`WPA_ASSET_DYN`)?
   - Whether rows are written per `CUST_SK` or per `SCHEMA_ID`.
   - Whether NULL `ISS_TYPE` instruments are included.
3. ~~Zero-condition active rules~~ **Resolved (data check):** no active rule without conditions exists, so Oracle and Snowflake behave the same today. The DT keeps the Oracle behaviour (such a rule matches every asset).
4. ~~Duplicate active custom rows~~ **Resolved (data check):** 0 (schema, instr) pairs with more than one active `WLT` row in `UAT_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA`. The `QUALIFY ... ORDER BY start_dt DESC` in DT3 is kept only as a safeguard, so the output matches Oracle today.
5. ~~Empty strings~~ **Resolved (data check):** 0 `''` values in rule values, rule descriptions and active custom rows. `NULLIF(...,'')` is kept as a guard for future data.

---

## 8. FINAL OUTPUT SPEC – what one call returns

`npf_asst_typ_mgr(iss_type, 'WLT', instr_id, schema_id, cust_sk, → 6 OUT)`

| OUT param | Target column | Path 1: active custom row exists | Path 2: no custom row | Custom row exists but instr missing from `NPF_ASSET` |
|---|---|---|---|---|
| `v_ast_supcatg_code_a` | `SUPCATG_CODE` | `NPF_ASSET_CATG.SUPCATG_CODE`, else `'30'` | same | `'30'` |
| `v_ast_subcatg_code_a` | `SUBCATG_CODE` | `NPF_ASSET_CATG.SUBCATG_CODE`, else `'20'` | same | `'20'` |
| `v_ast_supcatg_desc_a` | `SUPCATG_DESC` | `NPF_CSTM_SCHEMA.CSTM_SUPCATG_DESC` (even if NULL) | `COALESCE(last_rule_sup, first_rule_sup, std_sup_desc)` | `'Other Assets'` |
| `v_ast_subcatg_desc_a` | `SUBCATG_DESC` | `NPF_CSTM_SCHEMA.CSTM_SUBCATG_DESC` (even if NULL) | `COALESCE(last_rule_sub, first_rule_sub, std_sub_desc)` | `'Miscellaneous'` |
| `v_cstm_supcatg_code_a` | `CSTM_SUPCATG_CODE` | `-C`/`-S` matrix (§3.4) | `std_sup || '-S'` | NULL |
| `v_cstm_subcatg_code_a` | `CSTM_SUBCATG_CODE` | `-C`/`-S` matrix (§3.4) | `std_sup || '-' || std_sub || '-S'` | NULL |

`std_*` means the `NPF_ASSET_CATG` value for (`ISS_TYPE`, `'WLT'`), or the defaults `'30'`/`'20'`/`'Other Assets'`/`'Miscellaneous'`.
The other target columns (`SCHEMA_ID`, `CUST_SK`, `INSTR_ID`, `RPTG_TYPE`, `ISS_TYPE`, `SCHEMA_DESC`) come from the caller's inputs. `CSTM_SUPCATG_DESC` / `CSTM_SUBCATG_DESC` in the target are the same values as `SUPCATG_DESC` / `SUBCATG_DESC`.

### 8.1 Oracle-exact Snowflake SELECT (one statement = all calls)

This assumes the caller calls the procedure for **every `NPF_CUST_CSTM_SCHEMA` (cust_sk, schema) × every `NPF_ASSET` instrument**. Change the `inputs` CTE once the caller's real driver is known (e.g. `WPA_ASSET_DYN`, or `ISS_TYPE IS NOT NULL`).

```sql
WITH
inputs AS (                              -- = caller loop (ASSUMPTION)
    SELECT s.cust_sk, s.schema_id, s.schema_desc,
           a.instr_id, a.iss_type, a.cntry_risk_dcde, 'WLT' AS rptg_type
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
    CROSS JOIN UAT_WPA_ASSET_DB.CORE.NPF_ASSET a
),
std AS (                                 -- Unit A (6-arg overload)
    SELECT i.*,
           COALESCE(ac.supcatg_code, '30')            AS std_sup_code,
           COALESCE(ac.subcatg_code, '20')            AS std_sub_code,
           COALESCE(ac.supcatg_desc, 'Other Assets')  AS std_sup_desc,
           COALESCE(ac.subcatg_desc, 'Miscellaneous') AS std_sub_desc,
           d.dcde_desc                                AS cntry_desc
    FROM inputs i
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
           ON ac.rptg_type = i.rptg_type AND ac.iss_type = i.iss_type
    LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
           ON d.dcde_type = 'CNTRY' AND d.dcde_code = i.cntry_risk_dcde
),
cstm AS (                                -- v_rec_cnt + cstm_asset_cursor (one row kept)
    SELECT schema_id, instr_id, rptg_type,
           cstm_supcatg_code, cstm_supcatg_desc, npf_supcatg_code,
           cstm_subcatg_code, cstm_subcatg_desc, npf_subcatg_code
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
    WHERE end_dt IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id, rptg_type
                               ORDER BY start_dt DESC) = 1   -- Oracle: undefined order; pick latest
),
rule_eval AS (                           -- Unit C, per rule
    SELECT s.schema_id, s.std_sup_desc, s.std_sub_desc, s.cntry_desc,
           r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
           MAX(IFF(c.logical_oper = 'OR', 1, 0)) AS has_or,
           COUNT(c.rule_sk)                      AS cond_cnt,
           COUNT_IF(
                (c.rule_fld_name = 'CSTM_SUPCATG_DESC'    AND ((c.rule_oper = 'EQUAL' AND s.std_sup_desc = c.rule_fld_value) OR (c.rule_oper = 'NOTEQUAL' AND s.std_sup_desc != c.rule_fld_value)))
             OR (c.rule_fld_name = 'CSTM_SUBCATG_DESC'    AND ((c.rule_oper = 'EQUAL' AND s.std_sub_desc = c.rule_fld_value) OR (c.rule_oper = 'NOTEQUAL' AND s.std_sub_desc != c.rule_fld_value)))
             OR (c.rule_fld_name = 'CSTM_CNTRY_RISK_DESC' AND ((c.rule_oper = 'EQUAL' AND s.cntry_desc   = c.rule_fld_value) OR (c.rule_oper = 'NOTEQUAL' AND s.cntry_desc   != c.rule_fld_value)))
           )                                     AS match_cnt
    FROM (SELECT DISTINCT schema_id, std_sup_desc, std_sub_desc, cntry_desc FROM std) s
    JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
      ON r.schema_id = s.schema_id AND r.rule_stat = 'A'
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c       -- LEFT: zero-condition rules kept
      ON c.rule_sk = r.rule_sk
    GROUP BY ALL
),
rule_pick AS (                           -- first / last matched rule
    SELECT schema_id, std_sup_desc, std_sub_desc, cntry_desc,
           MIN_BY(rule_cstm_supcatg_desc, rule_sk)                          AS r1_sup,
           MIN_BY(rule_cstm_subcatg_desc, rule_sk)                          AS r1_sub,
           IFF(COUNT(*) > 1, MAX_BY(rule_cstm_supcatg_desc, rule_sk), NULL) AS rn_sup,
           IFF(COUNT(*) > 1, MAX_BY(rule_cstm_subcatg_desc, rule_sk), NULL) AS rn_sub
    FROM rule_eval
    WHERE (has_or = 1 AND match_cnt > 0)
       OR (has_or = 0 AND match_cnt = cond_cnt)          -- 0 = 0 → empty rule matches (Oracle)
    GROUP BY ALL
)
SELECT
    s.schema_id, s.cust_sk, s.instr_id, s.rptg_type, s.iss_type,
    s.std_sup_code AS supcatg_code,                              -- v_ast_supcatg_code_a
    s.std_sub_code AS subcatg_code,                              -- v_ast_subcatg_code_a
    CASE WHEN c.schema_id IS NOT NULL THEN c.cstm_supcatg_desc
         ELSE COALESCE(rp.rn_sup, rp.r1_sup, s.std_sup_desc) END AS supcatg_desc,   -- v_ast_supcatg_desc_a
    CASE WHEN c.schema_id IS NOT NULL THEN c.cstm_subcatg_desc
         ELSE COALESCE(rp.rn_sub, rp.r1_sub, s.std_sub_desc) END AS subcatg_desc,   -- v_ast_subcatg_desc_a
    CASE WHEN c.schema_id IS NOT NULL THEN
              IFF(c.cstm_supcatg_code IS NULL, c.npf_supcatg_code  || '-S',
                                               c.cstm_supcatg_code || '-C')
         ELSE s.std_sup_code || '-S' END                         AS cstm_supcatg_code, -- v_cstm_supcatg_code_a
    CASE WHEN c.schema_id IS NOT NULL THEN
              IFF(c.cstm_subcatg_code IS NULL, c.npf_subcatg_code  || '-S',
                                               c.cstm_subcatg_code || '-C')
         ELSE s.std_sup_code || '-' || s.std_sub_code || '-S' END AS cstm_subcatg_code, -- v_cstm_subcatg_code_a
    s.schema_desc
FROM std s
LEFT JOIN cstm c
       ON c.schema_id = s.schema_id AND c.instr_id = s.instr_id AND c.rptg_type = s.rptg_type
LEFT JOIN rule_pick rp
       ON rp.schema_id = s.schema_id
      AND rp.std_sup_desc = s.std_sup_desc AND rp.std_sub_desc = s.std_sub_desc
      AND EQUAL_NULL(rp.cntry_desc, s.cntry_desc);
```

**Notes on the query:**
- **Simplified -C/-S matrix:** the 4-case matrix in §3.4 reduces to "each code independently: custom code + `-C`, else NPF code + `-S`". The 4 Oracle branches give exactly that result.
- **Edge case not covered:** a custom row whose instrument is missing from `NPF_ASSET`. The driver *is* `NPF_ASSET`, so it can't occur here.
- **Duplicate custom rows:** if several are active, Oracle's order is undefined. I chose `start_dt DESC` (the latest row). Confirm with the business, or check query 3.3 (it may never happen).
- **Next step (done):** this SELECT has been split into the layers in §6: `inputs`/`std` became the `asset_std` CTE (over the existing asset DT), `cstm` became DT3, `rule_eval`/`rule_pick` became DT2, and the final SELECT became `WPA_CSTM_ASSET_SCHEMA_CATG`.
