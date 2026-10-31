# WPA_CSTM_ASSET_SCHEMA_CATG – Data Model & Business Definitions

> **Sources:** `Table DDL.sql` (structure, primary keys) and `Procedures DDL.sql` (how columns are used).
> **About the definitions:** keys and data types come straight from the DDL. Business meanings marked *(inferred)* are worked out from column names and how the procedure uses them. Please confirm those with the business or data owners.
> There are **no foreign keys** in the DDL. All relationships below are logical joins taken from the procedure code.

---

## 1. Business context (short)

Every instrument (asset) has a **standard** asset category: a super-category with a sub-category beneath it, for example *Equity → US Large Cap*. The standard category comes from its issue type (`ISS_TYPE`).

A customer can define one or more **custom schemas**, i.e. their own way of grouping assets for reporting. Inside a schema, an instrument's category can be set in two ways:
1. **Explicit override:** a row in `NPF_CSTM_SCHEMA` for that specific instrument.
2. **Rules:** a rule (`NPF_CSTM_RULE_MSTR`) with conditions (`NPF_CSTM_RULE_COND`), such as "if standard sub-category = X and country = Y, then custom description = Z".

If neither applies, the standard category is used.

`WPA_CSTM_ASSET_SCHEMA_CATG` stores the final answer for every **schema × instrument**.

---

## 2. Entity relationship diagram

```
                         ┌──────────────────────────┐
                         │   NPF_CUST_CSTM_SCHEMA   │  PK (CUST_SK, SCHEMA_ID)
                         │  customer ↔ schema header│
                         └────────────┬─────────────┘
                                      │ SCHEMA_ID (1 schema : N customers possible)
             ┌────────────────────────┼─────────────────────────────┐
             │                        │                             │
             ▼                        ▼                             │
┌──────────────────────────┐ ┌──────────────────────────┐           │
│     NPF_CSTM_SCHEMA      │ │    NPF_CSTM_RULE_MSTR    │ PK RULE_SK│
│ explicit override per    │ │ rule header per schema   │           │
│ (schema, instrument)     │ └────────────┬─────────────┘           │
│ PK (SCHEMA_ID, INSTR_ID, │              │ RULE_SK (1 : N)         │
│     START_DT, END_DT)    │              ▼                         │
└────────────┬─────────────┘ ┌──────────────────────────┐           │
             │ INSTR_ID      │    NPF_CSTM_RULE_COND    │ PK (COND_SK, RULE_SK)
             │               │ conditions of a rule     │           │
             │               └────────────┬─────────────┘           │
             │                            │ compares RULE_FLD_VALUE │
             │                            │ to asset descriptions   │
             ▼                            ▼                         │
┌──────────────────────────┐    ┌──────────────────────────┐        │
│ WPA_ASSET / WPA_ASSET_DYN│───▶│      NPF_ASSET_CATG      │ PK (ISS_TYPE, RPTG_TYPE)
│ instrument master        │    │ ISS_TYPE → std category  │        │
│ INSTR_ID, ISS_TYPE,      │    └──────────────────────────┘        │
│ CNTRY_RISK_DCDE          │                                        │
└────────────┬─────────────┘    ┌──────────────────────────┐        │
             └─────────────────▶│ NPF_DECODE (COMMON_UTIL) │ PK (DCDE_TYPE, DCDE_CODE)
               CNTRY_RISK_DCDE  │ code → description       │        │
               = DCDE_CODE      │ DCDE_TYPE='CNTRY'        │        │
                                └──────────────────────────┘        │
                                                                    ▼
                         ┌───────────────────────────────────────────────┐
                         │          WPA_CSTM_ASSET_SCHEMA_CATG           │
                         │  1 row per (SCHEMA_ID, INSTR_ID, RPTG_TYPE)   │
                         │  (no PK in DDL; MERGE key in proc)            │
                         └───────────────────────────────────────────────┘
```

### Join keys

| From | To | Join condition | Cardinality |
|---|---|---|---|
| `WPA_ASSET` | `NPF_ASSET_CATG` | `ac.ISS_TYPE = a.ISS_TYPE AND ac.RPTG_TYPE = 'WLT'` | N : 1 (left join, defaults if missing) |
| `WPA_ASSET` | `NPF_DECODE` | `d.DCDE_CODE = a.CNTRY_RISK_DCDE AND d.DCDE_TYPE = 'CNTRY'` | N : 1 (left join) |
| `NPF_CUST_CSTM_SCHEMA` | `NPF_CSTM_SCHEMA` | `SCHEMA_ID` | 1 : N |
| `NPF_CSTM_SCHEMA` | `WPA_ASSET` | `INSTR_ID` | N : 1 |
| `NPF_CUST_CSTM_SCHEMA` | `NPF_CSTM_RULE_MSTR` | `SCHEMA_ID` | 1 : N |
| `NPF_CSTM_RULE_MSTR` | `NPF_CSTM_RULE_COND` | `RULE_SK` | 1 : N |
| `NPF_CUST_CSTM_SCHEMA` × `WPA_ASSET` | target | cross join (every schema × every asset) | – |

> ⚠ **Key mismatch:** `NPF_CUST_CSTM_SCHEMA` has PK `(CUST_SK, SCHEMA_ID)`, so one schema can belong to several customers. The target's MERGE key `(SCHEMA_ID, INSTR_ID, RPTG_TYPE)` doesn't include `CUST_SK`. Queries 1.2 and 6.2 in `Queries.sql` check whether this actually happens in the data.

> ℹ **Datatype differences on join keys:** `SCHEMA_ID` is `FLOAT` in the NPF tables but `NUMBER(38,0)` in the target. `INSTR_ID` is `VARCHAR(11)` in `NPF_CSTM_SCHEMA` but unbounded `VARCHAR` in the target.

---

## 3. Table-by-table definitions

### 3.1 `NPF_CUST_CSTM_SCHEMA` – customer custom schema (header)
`UAT2_WPA_ASSET_DB.CORE` · PK `(CUST_SK, SCHEMA_ID)`

| Column | Type | Definition |
|---|---|---|
| `CUST_SK` | FLOAT | Customer surrogate key: the customer that owns or uses the schema. Copied to the target. |
| `SCHEMA_ID` | FLOAT | Custom categorisation schema ID. Main key across the custom tables. |
| `SCHEMA_DESC` | VARCHAR(50) | Schema name or description. Copied to the target. |
| `SORT_NBR` | NUMBER | Display order of the schema *(inferred)*. Not used by the load. |

### 3.2 `NPF_ASSET_CATG` – standard asset category mapping
`UAT2_WPA_ASSET_DB.CORE` · PK `(ISS_TYPE, RPTG_TYPE)`

| Column | Type | Definition |
|---|---|---|
| `ISS_TYPE` | VARCHAR(8) | Issue / security type code of an instrument (e.g. equity, bond, deposit types). |
| `RPTG_TYPE` | VARCHAR(3) | Reporting type. The load only uses `'WLT'` *(inferred: Wealth reporting)*. |
| `SUPCATG_CODE` / `SUPCATG_DESC` | VARCHAR | Standard **super-category** (top level of the asset class). Default when no mapping exists: `'30'` / `'Other Assets'`. |
| `SUBCATG_CODE` / `SUBCATG_DESC` | VARCHAR | Standard **sub-category** under the super-category. Default when no mapping exists: `'20'` / `'Miscellaneous'`. |
| `SORT_NBR`, `COMNT` | – | Display order and comment. Not used by the load. |

### 3.3 `NPF_DECODE` – generic code/description lookup
`UAT2_WPA_COMMON_UTIL_DB.CORE` · PK `(DCDE_TYPE, DCDE_CODE)`

| Column | Type | Definition |
|---|---|---|
| `DCDE_TYPE` | VARCHAR(31) | Lookup domain. This flow uses only `'CNTRY'` (country). |
| `DCDE_CODE` | VARCHAR(20) | Code value, e.g. a country code. Joined to the asset's `CNTRY_RISK_DCDE`. |
| `DCDE_DESC` | VARCHAR(400) | Description, e.g. the country name. Rule conditions compare it via `CSTM_CNTRY_RISK_DESC`. |

### 3.4 `NPF_CSTM_SCHEMA` – explicit per-instrument override
`UAT2_WPA_ASSET_DB.CORE` · PK `(SCHEMA_ID, INSTR_ID, START_DT, END_DT)`

The table keeps history: a row is **active** when `END_DT IS NULL`.

| Column | Type | Definition |
|---|---|---|
| `SCHEMA_ID` | FLOAT | Schema the override belongs to. |
| `INSTR_ID` | VARCHAR(11) | Instrument being overridden. |
| `RPTG_TYPE` | VARCHAR(3) | Reporting type. Only `'WLT'` is used. |
| `CSTM_SUPCATG_CODE` / `_DESC` | VARCHAR | Customer-defined super-category. A NULL code means "keep the standard one". |
| `CSTM_SUBCATG_CODE` / `_DESC` | VARCHAR | Customer-defined sub-category. A NULL code means "keep the standard one". |
| `NPF_SUPCATG_CODE` / `NPF_SUBCATG_CODE` | VARCHAR | The instrument's standard codes, stored on the override. Used to build `-S` codes when the custom code is NULL. |
| `CSTM_CNTRY_RISK_DESC` / `_DCDE`, `NPF_CNTRY_RISK_DCDE` | VARCHAR | Custom and standard country-risk override *(inferred)*. **Not used** by the current load. |
| `START_DT` / `END_DT` | TIMESTAMP | Validity period. `END_DT IS NULL` means the row is current. |

If there are several active rows for the same (schema, instrument), the procedure keeps the one with the lowest `NPF_SUPCATG_CODE`, then the lowest `NPF_SUBCATG_CODE`.

### 3.5 `NPF_CSTM_RULE_MSTR` – rule header
`UAT2_WPA_ASSET_DB.CORE` · PK `RULE_SK`

| Column | Type | Definition |
|---|---|---|
| `RULE_SK` | FLOAT | Rule surrogate key. Also sets **precedence**: when several rules match, the highest `RULE_SK` wins (the lowest is used only when there's one match). |
| `SCHEMA_ID` | FLOAT | Schema the rule belongs to. |
| `RULE_NAME` | VARCHAR(100) | Rule label. |
| `RULE_STAT` | VARCHAR(1) | Status. Only `'A'` (active) rules are evaluated. |
| `RULE_CSTM_SUPCATG_DESC` / `RULE_CSTM_SUBCATG_DESC` | VARCHAR(254) | **Result** of the rule: the custom descriptions given to matching instruments. |
| `RULE_CSTM_SUPCATG_CODE`, `RULE_CSTM_SUBCATG_CODE`, `RULE_CSTM_CNTRY_RISK_*` | VARCHAR | Result codes and country *(inferred)*. **Not used**: rule-based rows always get `-S` standard codes. |
| `RULE_DEL_OPT`, `RULE_CRT_OPT` | VARCHAR(10) | Rule create/delete options *(meaning unknown)*. Not used. |

### 3.6 `NPF_CSTM_RULE_COND` – rule conditions
`UAT2_WPA_ASSET_DB.CORE` · PK `(COND_SK, RULE_SK)`

| Column | Type | Definition |
|---|---|---|
| `COND_SK` | FLOAT | Condition ID. |
| `RULE_SK` | FLOAT | Rule that owns the condition. |
| `RULE_FLD_NAME` | VARCHAR(100) | Field being tested. The load understands only `CSTM_SUPCATG_DESC` (standard super-category description), `CSTM_SUBCATG_DESC` (standard sub-category description) and `CSTM_CNTRY_RISK_DESC` (country description). |
| `RULE_OPER` | VARCHAR(10) | `EQUAL` or `NOTEQUAL`. Any other value never matches. |
| `RULE_FLD_VALUE` | VARCHAR(254) | Value compared to the field. It is matched on the **description**, not the code. |
| `RULE_FLD_CODE` | VARCHAR(10) | Code form of the value *(inferred)*. Not used. |
| `LOGICAL_OPER` | VARCHAR(10) | If **any** condition of the rule has `'OR'`, the rule matches when at least one condition matches. Otherwise **all** conditions must match. |
| `COND_ORDER` | FLOAT | Order in which conditions are displayed or entered. It doesn't affect evaluation. |

### 3.7 `WPA_ASSET` / `WPA_ASSET_DYN` – instrument master (columns used)

| Column | Definition |
|---|---|
| `INSTR_ID` | Instrument ID. |
| `ISS_TYPE` | Issue type. Rows with NULL `ISS_TYPE` are excluded. |
| `CNTRY_RISK_DCDE` | Country-of-risk code. Joined to `NPF_DECODE` (`CNTRY`). |

`WPA_ASSET_DYN` only contains instruments that appear in positions or transactions, so it is smaller than `WPA_ASSET`.

### 3.8 `WPA_CSTM_ASSET_SCHEMA_CATG` – target
Grain: one row per `(SCHEMA_ID, INSTR_ID, RPTG_TYPE)`. There's no PK in the DDL.

| Column | Definition | Custom-row branch (A) | Rule/standard branch (B) |
|---|---|---|---|
| `SCHEMA_ID`, `CUST_SK`, `SCHEMA_DESC` | Schema identity | `NPF_CUST_CSTM_SCHEMA` | same |
| `INSTR_ID`, `ISS_TYPE` | Instrument | asset | asset |
| `RPTG_TYPE` | Reporting type | `'WLT'` | `'WLT'` |
| `SUPCATG_CODE` / `SUBCATG_CODE` | **Standard** codes | `NPF_ASSET_CATG` (or `30`/`20`) | same |
| `SUPCATG_DESC` / `SUBCATG_DESC` | **Effective** description shown to the customer | custom description | last matched rule → first matched rule → standard description |
| `CSTM_SUPCATG_CODE` | Effective super code, with source suffix | `<code>-C` or `<npf code>-S` | `<sup>-S` |
| `CSTM_SUBCATG_CODE` | Effective sub code, with source suffix | `<code>-C` or `<npf code>-S` | `<sup>-<sub>-S` |
| `CSTM_SUPCATG_DESC` / `CSTM_SUBCATG_DESC` | Same values as `SUPCATG_DESC` / `SUBCATG_DESC` | custom description | rule or standard description |
| `UPDATED_AT` | Last time the procedure touched the row | – | – |

**Code suffixes:** `-C` means the customer supplied the code. `-S` means it's the standard code. You can tell which branch produced a row from `CSTM_SUBCATG_CODE`: branch B always has the form `x-y-S`.

---

## 4. Decision flow for one (schema, instrument)

```
Instrument has ISS_TYPE?
 └─ no  → not in target
 └─ yes → standard category = NPF_ASSET_CATG(ISS_TYPE,'WLT')  else 30 Other Assets / 20 Miscellaneous
          │
          Active NPF_CSTM_SCHEMA row for (schema, instr, 'WLT')?
           ├─ yes → Branch A: custom descriptions, codes with -C / -S
           └─ no  → evaluate active rules of the schema on
                     (std sup desc, std sub desc, country desc)
                     ├─ ≥1 match → Branch B with rule descriptions (highest RULE_SK if >1)
                     └─ none     → Branch B with standard descriptions
```

---

## 5. Open questions for the business

1. Is `RPTG_TYPE = 'WLT'` the only reporting type needed, and what does WLT stand for?
2. Can one `SCHEMA_ID` really belong to several `CUST_SK`s? If so, should `CUST_SK` be part of the target key?
3. Should the rule result codes (`RULE_CSTM_SUPCATG_CODE` / `SUBCATG_CODE`) be used instead of always producing `-S` codes?
4. Should the country-risk override columns in `NPF_CSTM_SCHEMA` be used?
5. Is "highest `RULE_SK` wins" the intended precedence, or should it follow a priority or sort column?
