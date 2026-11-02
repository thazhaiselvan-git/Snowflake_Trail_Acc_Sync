/* =============================================================================
   DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY  -  Dynamic Tables (DEV)
   Built directly from Oracle npf_common_pkg.npf_asst_typ_mgr (11-arg)
   + npf_asst_typ_mgr (6-arg) + NPF_CUST_SCHEMA_RULE_EVALUATION_PKG.RULE_EVALUATION
   Reference: Oracle_Asset_Type_Manager_Logic.md

   Grain : one row per NPF_CUST_CSTM_SCHEMA (CUST_SK, SCHEMA_ID) x asset instrument,
           RPTG_TYPE = 'WLT'    (= one npf_asst_typ_mgr call)
   Graph :
     DEV_WPA_ASSET_DB.CORE.WPA_ASSET_DYN  (existing asset DT: NPF_ASSET filtered to
        │  read ONCE                        held / traded instruments)
        │  + NPF_ASSET_CATG (WLT)  + NPF_DECODE (CNTRY)
        ▼
     DT1 WPA_CAS_ASSET_STD_DYN    (6-arg proc + country)      1 row / instrument
        ├──────────────────────────────┐
        ▼                              │
     DT2 WPA_CAS_RULE_PICK_DYN         │   ◀─ NPF_CSTM_RULE_MSTR / NPF_CSTM_RULE_COND
        (RULE_EVALUATION)              │
        │   DT3 WPA_CAS_CSTM_ROW_DYN   │   ◀─ NPF_CSTM_SCHEMA
        │      (v_rec_cnt + cursor)    │
        ▼      ▼                       ▼
     FINAL WPA_CSTM_ASSET_SCHEMA_CATG_DY = NPF_CUST_CSTM_SCHEMA x DT1
                                        ⟕ DT3 (custom row?) ⟕ DT2 (rule match?)

   Oracle parity rules applied:
     P1  Defaults from package spec: '30' / '20' / 'Other Assets' / 'Miscellaneous'
         (applied in DT1 only when no NPF_ASSET_CATG row exists, as Oracle FETCH).
     P2  Oracle '' = NULL            -> NULLIF(col,'') on every text input.
     P3  Oracle CONCAT(NULL,'x')='x' -> NVL(col,'') || 'x'.
     P4  NULL comparisons never match (EQUAL and NOTEQUAL) - native in Snowflake too.
     P5  Any condition with LOGICAL_OPER='OR' -> rule = OR, else AND.
     P6  Active rule with ZERO conditions MATCHES (0 = 0, has_OR false).
     P7  1 match -> that rule; >1 -> last (highest RULE_SK); COALESCE per column
         (last, first, standard).
     P8  Custom row: standard codes, custom desc as-is (even NULL), -C/-S codes.
     P9  Several active custom rows: Oracle order undefined -> latest START_DT kept.
     P10 p_cust_sk is not used by the proc -> same result for every CUST_SK of a schema.
     P11 Rule result codes and country outputs are not used (as in Oracle).

   Environment : DEV. NPF_* from DEV_WPA_ASSET_DB.CORE, asset DT
                 DEV_WPA_ASSET_DB.CORE.WPA_ASSET_DYN (DEV copy of
                 PROD_WPA_ASSET_DB.CORE.WPA_ASSET_DYN), NPF_DECODE from
                 DEV_WPA_COMMON_UTIL_DB.CORE, warehouse DEV_ADHOC_ANALYSIS.
                 For UAT: replace DEV_ -> UAT_ and the warehouse name.
   NOT compiled here - DEV databases not visible from this session.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   0. Pre-reqs
   ----------------------------------------------------------------------------- */
-- Change tracking on base tables read directly by the DTs
-- (DEV_WPA_ASSET_DB.CORE.WPA_ASSET_DYN is a DT - no change tracking needed)
-- ALTER TABLE DEV_WPA_ASSET_DB.CORE.NPF_ASSET_CATG        SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE DEV_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE      SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE DEV_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA  SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE DEV_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA       SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR    SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND    SET CHANGE_TRACKING = TRUE;

-- Final DT is named WPA_CSTM_ASSET_SCHEMA_CATG_DY, so the existing proc-loaded
-- table WPA_CSTM_ASSET_SCHEMA_CATG is left untouched (parallel run / comparison).


/* -----------------------------------------------------------------------------
   DT1  WPA_CAS_ASSET_STD_DYN
   = npf_asst_typ_mgr 6-arg (standard category, defaults when no mapping)
     + country lookup of the 11-arg ELSE branch (country-of-risk description).
   The ONLY reader of the asset DT. DT2 and FINAL both read this table, so the
   asset -> category/country mapping and the *_DESC_KEY join keys are defined
   once.
   Source DT WPA_ASSET_DYN gives the instrument list (held / traded),
   ISS_TYPE and CNTRY_RISK_DCDE only. It has no category columns, and its
   CNTRY_RISK_DCDE_DESC defaults to 'Unknown' (Oracle returns NULL), so:
     - category : LEFT JOIN NPF_ASSET_CATG (RPTG_TYPE='WLT'); defaults only when
                  no mapping row exists (Oracle FETCH semantics)
     - country  : LEFT JOIN NPF_DECODE (DCDE_TYPE='CNTRY'); NULL when not found
   ----------------------------------------------------------------------------- */
create or replace dynamic table DEV_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN(
  INSTR_ID,
  ISS_TYPE,
  STD_SUP_CODE,
  STD_SUB_CODE,
  STD_SUP_DESC,
  STD_SUB_DESC,
  CNTRY_DESC,
  SUP_DESC_KEY,
  SUB_DESC_KEY,
  CNTRY_DESC_KEY
) target_lag = DOWNSTREAM refresh_mode = ADAPTIVE initialize = ON_SCHEDULE warehouse = DEV_ADHOC_ANALYSIS
 as
SELECT
    instr_id,
    iss_type,
    std_sup_code,
    std_sub_code,
    std_sup_desc,
    std_sub_desc,
    cntry_desc,
    NVL(std_sup_desc, '#NULL#') AS sup_desc_key,
    NVL(std_sub_desc, '#NULL#') AS sub_desc_key,
    NVL(cntry_desc,   '#NULL#') AS cntry_desc_key
FROM (
    SELECT
        a.instr_id,
        a.iss_type,
        -- FETCH overwrites all 4 defaults when a mapping row exists (even NULL values)
        IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
        IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
        IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
        IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
        NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
    FROM DEV_WPA_ASSET_DB.CORE.WPA_ASSET_DYN a
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
           ON ac.rptg_type = 'WLT'
          AND ac.iss_type  = a.iss_type
    LEFT JOIN DEV_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
           ON d.dcde_type = 'CNTRY'
          AND d.dcde_code = a.cntry_risk_dcde
);


/* -----------------------------------------------------------------------------
   DT2  WPA_CAS_RULE_PICK_DYN
   = RULE_EVALUATION(schema, std_sup_desc, std_sub_desc, cntry_desc)
   Flow inside this DT:
     combo      : DISTINCT (std_sup_desc, std_sub_desc, cntry_desc) from DT1
     rule_eval  : active rules x combo -> per-rule cond / match counts
     final SELECT: keep matched rules, pick first (R1) and last (RN) per combo
   Evaluated once per (schema, distinct desc combo) - inputs are only these
   three values, so the result is identical to calling it per instrument.
   Only combos with >= 1 matching rule are stored; others fall back to std.
   ----------------------------------------------------------------------------- */
create or replace dynamic table DEV_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN(
  SCHEMA_ID,
  SUP_DESC_KEY,
  SUB_DESC_KEY,
  CNTRY_DESC_KEY,
  MATCHED_RULE_CNT,
  R1_SUP,
  R1_SUB,
  RN_SUP,
  RN_SUB
) target_lag = DOWNSTREAM refresh_mode = INCREMENTAL initialize = ON_SCHEDULE warehouse = DEV_ADHOC_ANALYSIS
 as
WITH combo AS (
    SELECT std_sup_desc, std_sub_desc, cntry_desc,
           sup_desc_key, sub_desc_key, cntry_desc_key
    FROM DEV_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN
    GROUP BY std_sup_desc, std_sub_desc, cntry_desc,
             sup_desc_key, sub_desc_key, cntry_desc_key
),
rule_eval AS (
    SELECT
        r.schema_id,
        cb.sup_desc_key,
        cb.sub_desc_key,
        cb.cntry_desc_key,
        r.rule_sk,
        NULLIF(r.rule_cstm_supcatg_desc, '') AS rule_sup_desc,
        NULLIF(r.rule_cstm_subcatg_desc, '') AS rule_sub_desc,
        MAX(IFF(c.logical_oper = 'OR', 1, 0)) AS has_or,          -- P5
        COUNT(c.rule_sk)                      AS cond_cnt,        -- 0 when no conditions
        COUNT_IF(
             (c.rule_fld_name = 'CSTM_SUPCATG_DESC' AND
               ((c.rule_oper = 'EQUAL'    AND cb.std_sup_desc =  NULLIF(c.rule_fld_value, '')) OR
                (c.rule_oper = 'NOTEQUAL' AND cb.std_sup_desc != NULLIF(c.rule_fld_value, ''))))
          OR (c.rule_fld_name = 'CSTM_SUBCATG_DESC' AND
               ((c.rule_oper = 'EQUAL'    AND cb.std_sub_desc =  NULLIF(c.rule_fld_value, '')) OR
                (c.rule_oper = 'NOTEQUAL' AND cb.std_sub_desc != NULLIF(c.rule_fld_value, ''))))
          OR (c.rule_fld_name = 'CSTM_CNTRY_RISK_DESC' AND
               ((c.rule_oper = 'EQUAL'    AND cb.cntry_desc   =  NULLIF(c.rule_fld_value, '')) OR
                (c.rule_oper = 'NOTEQUAL' AND cb.cntry_desc   != NULLIF(c.rule_fld_value, ''))))
        )                                     AS match_cnt        -- P4: NULL -> not counted
    FROM DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c          -- LEFT: P6
           ON c.rule_sk = r.rule_sk
    CROSS JOIN combo cb
    WHERE r.rule_stat = 'A'
    GROUP BY r.schema_id, cb.sup_desc_key, cb.sub_desc_key, cb.cntry_desc_key,
             r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc
)
SELECT
    schema_id,
    sup_desc_key,
    sub_desc_key,
    cntry_desc_key,
    COUNT(*)                                                AS matched_rule_cnt,
    MIN_BY(rule_sup_desc, rule_sk)                          AS r1_sup,   -- first match (_1)
    MIN_BY(rule_sub_desc, rule_sk)                          AS r1_sub,
    IFF(COUNT(*) > 1, MAX_BY(rule_sup_desc, rule_sk), NULL) AS rn_sup,   -- last match (_2)
    IFF(COUNT(*) > 1, MAX_BY(rule_sub_desc, rule_sk), NULL) AS rn_sub
FROM rule_eval
WHERE (has_or = 1 AND match_cnt > 0)
   OR (has_or = 0 AND match_cnt = cond_cnt)
GROUP BY schema_id, sup_desc_key, sub_desc_key, cntry_desc_key;


/* -----------------------------------------------------------------------------
   DT3  WPA_CAS_CSTM_ROW_DYN
   = v_rec_cnt > 0 check + cstm_asset_cursor (active row, END_DT IS NULL).
   Instrument-exists check of the cursor (join NPF_ASSET) is satisfied in the
   final DT because the driver is DT1.
   QUALIFY is a safeguard only: no duplicate active rows exist today.
   ----------------------------------------------------------------------------- */
create or replace dynamic table DEV_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN(
  SCHEMA_ID,
  INSTR_ID,
  RPTG_TYPE,
  CSTM_SUPCATG_CODE,
  CSTM_SUPCATG_DESC,
  NPF_SUPCATG_CODE,
  CSTM_SUBCATG_CODE,
  CSTM_SUBCATG_DESC,
  NPF_SUBCATG_CODE
) target_lag = DOWNSTREAM refresh_mode = INCREMENTAL initialize = ON_SCHEDULE warehouse = DEV_ADHOC_ANALYSIS
 as
SELECT
    ncs.schema_id,
    ncs.instr_id,
    ncs.rptg_type,
    NULLIF(ncs.cstm_supcatg_code, '') AS cstm_supcatg_code,
    NULLIF(ncs.cstm_supcatg_desc, '') AS cstm_supcatg_desc,
    NULLIF(ncs.npf_supcatg_code,  '') AS npf_supcatg_code,
    NULLIF(ncs.cstm_subcatg_code, '') AS cstm_subcatg_code,
    NULLIF(ncs.cstm_subcatg_desc, '') AS cstm_subcatg_desc,
    NULLIF(ncs.npf_subcatg_code,  '') AS npf_subcatg_code
FROM DEV_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA ncs
WHERE ncs.rptg_type = 'WLT'
  AND ncs.end_dt IS NULL
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY ncs.schema_id, ncs.instr_id, ncs.rptg_type
            ORDER BY ncs.start_dt DESC) = 1;                       -- P9


/* -----------------------------------------------------------------------------
   FINAL  WPA_CSTM_ASSET_SCHEMA_CATG_DY
   = npf_asst_typ_mgr 11-arg, for every (cust_sk, schema) x instrument.
     Path 1 (IF v_rec_cnt <> 0): custom row
     Path 2 (ELSE)             : RULE_EVALUATION result / standard
   OUT param mapping:
     v_ast_supcatg_code_a  -> SUPCATG_CODE      v_ast_subcatg_code_a  -> SUBCATG_CODE
     v_ast_supcatg_desc_a  -> SUPCATG_DESC      v_ast_subcatg_desc_a  -> SUBCATG_DESC
     v_cstm_supcatg_code_a -> CSTM_SUPCATG_CODE v_cstm_subcatg_code_a -> CSTM_SUBCATG_CODE
   CSTM_*_DESC repeat SUPCATG_DESC / SUBCATG_DESC (same as existing table).
   ----------------------------------------------------------------------------- */
create or replace dynamic table DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY(
  SCHEMA_ID,
  CUST_SK,
  INSTR_ID,
  RPTG_TYPE,
  ISS_TYPE,
  SUPCATG_CODE,
  SUBCATG_CODE,
  SUPCATG_DESC,
  SUBCATG_DESC,
  CSTM_SUPCATG_CODE,
  CSTM_SUBCATG_CODE,
  CSTM_SUPCATG_DESC,
  CSTM_SUBCATG_DESC,
  SCHEMA_DESC
) target_lag = '60 minutes' refresh_mode = ADAPTIVE initialize = ON_SCHEDULE warehouse = DEV_ADHOC_ANALYSIS
 as
WITH calls AS (
    SELECT
        s.schema_id,
        s.cust_sk,
        s.schema_desc,
        a.instr_id,
        'WLT' AS rptg_type,
        a.iss_type,
        a.std_sup_code,
        a.std_sub_code,
        a.std_sup_desc,
        a.std_sub_desc,
        cr.schema_id AS cstm_hit,                 -- NOT NULL => Path 1
        cr.cstm_supcatg_code,
        cr.cstm_supcatg_desc,
        cr.npf_supcatg_code,
        cr.cstm_subcatg_code,
        cr.cstm_subcatg_desc,
        cr.npf_subcatg_code,
        rp.r1_sup, rp.r1_sub, rp.rn_sup, rp.rn_sub
    FROM DEV_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
    CROSS JOIN DEV_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN a
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN cr
           ON cr.schema_id = s.schema_id
          AND cr.instr_id  = a.instr_id
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN rp
           ON rp.schema_id      = s.schema_id
          AND rp.sup_desc_key   = a.sup_desc_key
          AND rp.sub_desc_key   = a.sub_desc_key
          AND rp.cntry_desc_key = a.cntry_desc_key
),
out AS (
    SELECT
        schema_id, cust_sk, instr_id, rptg_type, iss_type, schema_desc,
        std_sup_code AS supcatg_code,
        std_sub_code AS subcatg_code,
        CASE WHEN cstm_hit IS NOT NULL THEN cstm_supcatg_desc                        -- P8
             ELSE COALESCE(rn_sup, r1_sup, std_sup_desc) END                AS supcatg_desc,   -- P7
        CASE WHEN cstm_hit IS NOT NULL THEN cstm_subcatg_desc
             ELSE COALESCE(rn_sub, r1_sub, std_sub_desc) END                AS subcatg_desc,
        CASE WHEN cstm_hit IS NOT NULL THEN
                  -- Oracle 4-branch matrix == per-code independent choice
                  IFF(cstm_supcatg_code IS NULL, NVL(npf_supcatg_code,  '') || '-S',
                                                 cstm_supcatg_code         || '-C')
             ELSE NVL(std_sup_code, '') || '-S' END                         AS cstm_supcatg_code,  -- P3
        CASE WHEN cstm_hit IS NOT NULL THEN
                  IFF(cstm_subcatg_code IS NULL, NVL(npf_subcatg_code,  '') || '-S',
                                                 cstm_subcatg_code         || '-C')
             ELSE NVL(std_sup_code, '') || '-' || NVL(std_sub_code, '') || '-S' END AS cstm_subcatg_code
    FROM calls
)
SELECT
    schema_id,
    cust_sk,
    instr_id,
    rptg_type,
    iss_type,
    supcatg_code,
    subcatg_code,
    supcatg_desc,
    subcatg_desc,
    cstm_supcatg_code,
    cstm_subcatg_code,
    supcatg_desc AS cstm_supcatg_desc,
    subcatg_desc AS cstm_subcatg_desc,
    schema_desc
FROM out;


/* =============================================================================
   Post-create checks
   ============================================================================= */
-- SHOW DYNAMIC TABLES LIKE 'WPA_CAS%' IN SCHEMA DEV_WPA_ASSET_DB.CORE;            -- refresh_mode / reason
-- SHOW DYNAMIC TABLES LIKE 'WPA_CSTM_ASSET_SCHEMA_CATG_DY' IN SCHEMA DEV_WPA_ASSET_DB.CORE;
-- ALTER DYNAMIC TABLE DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY REFRESH;   -- first load

-- Expected row count = cust-schema rows x assets
-- SELECT (SELECT COUNT(*) FROM DEV_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA)
--      * (SELECT COUNT(*) FROM DEV_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN)    AS expected,
--        (SELECT COUNT(*) FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY) AS actual;

-- Path split
-- SELECT IFF(cstm_subcatg_code LIKE '%-%-S', 'PATH 2 rule/std', 'PATH 1 custom') AS path, COUNT(*)
-- FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY GROUP BY 1;

-- Spot-check one instrument against Oracle npf_asst_typ_mgr output
-- SELECT * FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
-- WHERE schema_id = <schema> AND instr_id = '<instr>';
