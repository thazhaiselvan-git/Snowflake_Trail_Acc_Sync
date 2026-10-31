/* =============================================================================
   WPA_CSTM_ASSET_SCHEMA_CATG  -  Dynamic Table version
   Replaces: 7 streams + WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK
             + WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC
             + WPA_CUSTOM_ASSET_SCHEMA_CATG_SP

   DT graph (all in UAT_WPA_ASSET_DB.CORE, warehouse UAT_WPA_DYNAMICTABLE_VWH):

     WPA_ASSET_DYN ─┐
     NPF_ASSET_CATG ┼─▶ WPA_CAS_ASSET_CATG_DYN ──┬─────────────────────────┐
     NPF_DECODE    ─┘   (1 row / instrument)     │                         │
                                                 ▼                         │
     NPF_CUST_CSTM_SCHEMA ─┐            WPA_CAS_RULE_PICK_DYN              │
     NPF_CSTM_RULE_MSTR   ─┼──────────▶ (schema × distinct desc combo)     │
     NPF_CSTM_RULE_COND   ─┘                     │                         │
                                                 ▼                         ▼
     NPF_CSTM_SCHEMA ──▶ WPA_CAS_CSTM_ROW_DYN ──▶ WPA_CSTM_ASSET_SCHEMA_CATG_DYN  (final)

   Source DBs follow your count query: NPF_* from UAT2_WPA_ASSET_DB, NPF_DECODE
   from UAT2_WPA_COMMON_UTIL_DB, assets from UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN.
   UPDATED_AT is intentionally left out for now (see notes at the bottom).
   ============================================================================= */


/* -----------------------------------------------------------------------------
   0. Pre-req: change tracking on base tables (DTs need it; streams already
      enabled it where they exist). Check with SHOW TABLES ... change_tracking.
   ----------------------------------------------------------------------------- */
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG        SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA  SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA       SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR    SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND    SET CHANGE_TRACKING = TRUE;
-- ALTER TABLE UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE      SET CHANGE_TRACKING = TRUE;


/* -----------------------------------------------------------------------------
   1. WPA_CAS_ASSET_CATG_DYN
      = proc CTEs asset_base + asset_catg + cntry_desc.
      Standard category per instrument, Oracle defaults when no NPF_ASSET_CATG
      mapping, plus country-risk description used by rule conditions.
      *_KEY columns are null-safe join keys for the rule lookup.
   ----------------------------------------------------------------------------- */
create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN(
  INSTR_ID,
  ISS_TYPE,
  SUP_CODE,
  SUB_CODE,
  SUP_DESC,
  SUB_DESC,
  CNTRY_DESC,
  SUP_DESC_KEY,
  SUB_DESC_KEY,
  CNTRY_DESC_KEY
) target_lag = DOWNSTREAM refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
SELECT
    ab.instr_id,
    ab.iss_type,
    COALESCE(ac.supcatg_code, '30')            AS sup_code,
    COALESCE(ac.subcatg_code, '20')            AS sub_code,
    COALESCE(ac.supcatg_desc, 'Other Assets')  AS sup_desc,
    COALESCE(ac.subcatg_desc, 'Miscellaneous') AS sub_desc,
    d.dcde_desc                                AS cntry_desc,
    NVL(COALESCE(ac.supcatg_desc, 'Other Assets'),  '#NULL#') AS sup_desc_key,
    NVL(COALESCE(ac.subcatg_desc, 'Miscellaneous'), '#NULL#') AS sub_desc_key,
    NVL(d.dcde_desc, '#NULL#')                                AS cntry_desc_key
FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
       ON ac.rptg_type = 'WLT'
      AND ac.iss_type  = ab.iss_type
LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
       ON d.dcde_type = 'CNTRY'
      AND d.dcde_code = ab.cntry_risk_dcde
WHERE ab.iss_type IS NOT NULL;


/* -----------------------------------------------------------------------------
   2. WPA_CAS_RULE_PICK_DYN
      = proc CTEs rule_eval + matched_rules + rule_pick.
      Rule conditions only test SUP_DESC / SUB_DESC / CNTRY_DESC, so rules are
      evaluated once per distinct (schema, sup_desc, sub_desc, cntry_desc)
      instead of once per (schema, instrument).
      Match semantics (unchanged):
        - rule has >=1 condition AND
        - any OR condition  -> at least one condition matches
          else              -> all conditions match
        - NULL cntry_desc never matches (EQUAL or NOTEQUAL), as in Oracle.
      Pick: R1 = lowest RULE_SK matched, RN = highest RULE_SK when >1 match.
   ----------------------------------------------------------------------------- */
create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN(
  SCHEMA_ID,
  SUP_DESC_KEY,
  SUB_DESC_KEY,
  CNTRY_DESC_KEY,
  R1_SUP,
  R1_SUB,
  RN_SUP,
  RN_SUB
) target_lag = DOWNSTREAM refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
WITH combo AS (
    SELECT sup_desc, sub_desc, cntry_desc,
           sup_desc_key, sub_desc_key, cntry_desc_key
    FROM UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN
    GROUP BY sup_desc, sub_desc, cntry_desc,
             sup_desc_key, sub_desc_key, cntry_desc_key
),
rule_eval AS (
    SELECT
        r.schema_id,
        cb.sup_desc_key,
        cb.sub_desc_key,
        cb.cntry_desc_key,
        r.rule_sk,
        r.rule_cstm_supcatg_desc,
        r.rule_cstm_subcatg_desc,
        MAX(CASE WHEN c.logical_oper = 'OR' THEN 1 ELSE 0 END) AS has_or,
        COUNT(c.rule_sk)                                         AS cond_cnt,
        SUM(CASE
              WHEN c.rule_fld_name = 'CSTM_SUPCATG_DESC' AND
                   ((c.rule_oper = 'EQUAL'    AND cb.sup_desc =  c.rule_fld_value) OR
                    (c.rule_oper = 'NOTEQUAL' AND cb.sup_desc != c.rule_fld_value)) THEN 1
              WHEN c.rule_fld_name = 'CSTM_SUBCATG_DESC' AND
                   ((c.rule_oper = 'EQUAL'    AND cb.sub_desc =  c.rule_fld_value) OR
                    (c.rule_oper = 'NOTEQUAL' AND cb.sub_desc != c.rule_fld_value)) THEN 1
              WHEN c.rule_fld_name = 'CSTM_CNTRY_RISK_DESC' AND
                   ((c.rule_oper = 'EQUAL'    AND cb.cntry_desc =  c.rule_fld_value) OR
                    (c.rule_oper = 'NOTEQUAL' AND cb.cntry_desc != c.rule_fld_value)) THEN 1
              ELSE 0
            END)                                                 AS match_cnt
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA sd
    JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
      ON r.schema_id = sd.schema_id
     AND r.rule_stat = 'A'
    JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c
      ON c.rule_sk = r.rule_sk
    CROSS JOIN combo cb
    GROUP BY r.schema_id, cb.sup_desc_key, cb.sub_desc_key, cb.cntry_desc_key,
             r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc
)
SELECT
    schema_id,
    sup_desc_key,
    sub_desc_key,
    cntry_desc_key,
    MIN_BY(rule_cstm_supcatg_desc, rule_sk)                          AS r1_sup,
    MIN_BY(rule_cstm_subcatg_desc, rule_sk)                          AS r1_sub,
    IFF(COUNT(*) > 1, MAX_BY(rule_cstm_supcatg_desc, rule_sk), NULL) AS rn_sup,
    IFF(COUNT(*) > 1, MAX_BY(rule_cstm_subcatg_desc, rule_sk), NULL) AS rn_sub
FROM rule_eval
WHERE cond_cnt > 0
  AND ((has_or = 1 AND match_cnt > 0)
    OR (has_or = 0 AND match_cnt = cond_cnt))
GROUP BY schema_id, sup_desc_key, sub_desc_key, cntry_desc_key;


/* -----------------------------------------------------------------------------
   3. WPA_CAS_CSTM_ROW_DYN
      = proc CTE cstm_row (rn = 1).
      Active explicit custom category per (schema, instrument).
      Reads NPF_CSTM_SCHEMA directly: WPA_CUSTOM_SCHEMA_DYN lacks RPTG_TYPE and
      NPF_SUPCATG_CODE / NPF_SUBCATG_CODE needed for the -S/-C code logic.
   ----------------------------------------------------------------------------- */
create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN(
  SCHEMA_ID,
  INSTR_ID,
  RPTG_TYPE,
  CSTM_SUPCATG_CODE,
  CSTM_SUPCATG_DESC,
  NPF_SUPCATG_CODE,
  CSTM_SUBCATG_CODE,
  CSTM_SUBCATG_DESC,
  NPF_SUBCATG_CODE
) target_lag = DOWNSTREAM refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
SELECT
    ncs.schema_id,
    ncs.instr_id,
    ncs.rptg_type,
    ncs.cstm_supcatg_code,
    ncs.cstm_supcatg_desc,
    ncs.npf_supcatg_code,
    ncs.cstm_subcatg_code,
    ncs.cstm_subcatg_desc,
    ncs.npf_subcatg_code
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA ncs
WHERE ncs.rptg_type = 'WLT'
  AND ncs.end_dt IS NULL
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY ncs.schema_id, ncs.instr_id, ncs.rptg_type
            ORDER BY ncs.npf_supcatg_code, ncs.npf_subcatg_code) = 1;


/* -----------------------------------------------------------------------------
   4. WPA_CSTM_ASSET_SCHEMA_CATG_DYN  (final)
      = proc custom_out UNION ALL fallback_out.
      Branch A: explicit custom row exists      -> custom desc, -C/-S codes
      Branch B: no custom row (schema × asset)  -> last/first matched rule desc,
                                                   else standard desc; -S codes
   ----------------------------------------------------------------------------- */
create or replace dynamic table UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN(
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
) target_lag = '60 minutes' refresh_mode = AUTO initialize = ON_SCHEDULE warehouse = UAT_WPA_DYNAMICTABLE_VWH
 as
-- Branch A: custom override
SELECT
    cr.schema_id,
    sd.cust_sk,
    cr.instr_id,
    cr.rptg_type,
    ac.iss_type,
    ac.sup_code                AS supcatg_code,
    ac.sub_code                AS subcatg_code,
    cr.cstm_supcatg_desc       AS supcatg_desc,
    cr.cstm_subcatg_desc       AS subcatg_desc,
    CASE
        WHEN cr.cstm_supcatg_code IS NULL     AND cr.cstm_subcatg_code IS NOT NULL THEN cr.npf_supcatg_code  || '-S'
        WHEN cr.cstm_supcatg_code IS NOT NULL AND cr.cstm_subcatg_code IS NULL     THEN cr.cstm_supcatg_code || '-C'
        WHEN cr.cstm_supcatg_code IS NULL     AND cr.cstm_subcatg_code IS NULL     THEN cr.npf_supcatg_code  || '-S'
        ELSE cr.cstm_supcatg_code || '-C'
    END                        AS cstm_supcatg_code,
    CASE
        WHEN cr.cstm_supcatg_code IS NULL     AND cr.cstm_subcatg_code IS NOT NULL THEN cr.cstm_subcatg_code || '-C'
        WHEN cr.cstm_supcatg_code IS NOT NULL AND cr.cstm_subcatg_code IS NULL     THEN cr.npf_subcatg_code  || '-S'
        WHEN cr.cstm_supcatg_code IS NULL     AND cr.cstm_subcatg_code IS NULL     THEN cr.npf_subcatg_code  || '-S'
        ELSE cr.cstm_subcatg_code || '-C'
    END                        AS cstm_subcatg_code,
    cr.cstm_supcatg_desc,
    cr.cstm_subcatg_desc,
    sd.schema_desc
FROM UAT_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN cr
JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA sd
  ON sd.schema_id = cr.schema_id
JOIN UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN ac
  ON ac.instr_id = cr.instr_id

UNION ALL

-- Branch B: rule evaluation / standard fallback
SELECT
    sd.schema_id,
    sd.cust_sk,
    ac.instr_id,
    'WLT'                                         AS rptg_type,
    ac.iss_type,
    ac.sup_code                                   AS supcatg_code,
    ac.sub_code                                   AS subcatg_code,
    COALESCE(rp.rn_sup, rp.r1_sup, ac.sup_desc)   AS supcatg_desc,
    COALESCE(rp.rn_sub, rp.r1_sub, ac.sub_desc)   AS subcatg_desc,
    ac.sup_code || '-S'                           AS cstm_supcatg_code,
    ac.sup_code || '-' || ac.sub_code || '-S'     AS cstm_subcatg_code,
    COALESCE(rp.rn_sup, rp.r1_sup, ac.sup_desc)   AS cstm_supcatg_desc,
    COALESCE(rp.rn_sub, rp.r1_sub, ac.sub_desc)   AS cstm_subcatg_desc,
    sd.schema_desc
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA sd
CROSS JOIN UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN ac
LEFT JOIN UAT_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN rp
       ON rp.schema_id      = sd.schema_id
      AND rp.sup_desc_key   = ac.sup_desc_key
      AND rp.sub_desc_key   = ac.sub_desc_key
      AND rp.cntry_desc_key = ac.cntry_desc_key
LEFT JOIN UAT_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN ce
       ON ce.schema_id = sd.schema_id
      AND ce.instr_id  = ac.instr_id
WHERE ce.schema_id IS NULL;


/* =============================================================================
   5. Post-create checks
   ============================================================================= */
-- Refresh mode chosen + reason (want INCREMENTAL on 1, 3, 4; 2 may be FULL - it is small)
-- SHOW DYNAMIC TABLES LIKE 'WPA_CAS%' IN SCHEMA UAT_WPA_ASSET_DB.CORE;
-- SHOW DYNAMIC TABLES LIKE 'WPA_CSTM_ASSET_SCHEMA_CATG_DYN' IN SCHEMA UAT_WPA_ASSET_DB.CORE;

-- First refresh (initialize = ON_SCHEDULE)
-- ALTER DYNAMIC TABLE UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN REFRESH;

-- Refresh history
-- SELECT name, state, refresh_action, refresh_trigger, data_timestamp,
--        refresh_start_time, refresh_end_time, state_message
-- FROM TABLE(UAT_WPA_ASSET_DB.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
--        NAME_PREFIX => 'UAT_WPA_ASSET_DB.CORE.'))
-- WHERE name LIKE 'WPA_CAS%' OR name = 'WPA_CSTM_ASSET_SCHEMA_CATG_DYN'
-- ORDER BY refresh_start_time DESC LIMIT 20;


/* =============================================================================
   6. Validation vs existing proc-loaded table
      Compare only on instruments present in WPA_ASSET_DYN, because the old
      table was built from the full WPA_ASSET universe.
   ============================================================================= */
-- Uniqueness of the business key (expect 0 rows)
-- SELECT schema_id, instr_id, rptg_type, COUNT(*)
-- FROM UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN
-- GROUP BY 1,2,3 HAVING COUNT(*) > 1;

-- Row counts in comparable scope
-- SELECT
--   (SELECT COUNT(*) FROM UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN) AS dt_cnt,
--   (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG t
--     WHERE t.instr_id IN (SELECT instr_id FROM UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN)) AS old_cnt_in_scope;

-- Column-level differences, both directions
-- WITH old AS (
--   SELECT schema_id, cust_sk, instr_id, rptg_type, iss_type, supcatg_code, subcatg_code,
--          supcatg_desc, subcatg_desc, cstm_supcatg_code, cstm_subcatg_code,
--          cstm_supcatg_desc, cstm_subcatg_desc, schema_desc
--   FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
--   WHERE instr_id IN (SELECT instr_id FROM UAT_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_CATG_DYN)
-- ), dt AS (
--   SELECT * FROM UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN
-- )
-- SELECT 'ONLY_IN_OLD' AS side, * FROM (SELECT * FROM old EXCEPT SELECT * FROM dt)
-- UNION ALL
-- SELECT 'ONLY_IN_DT'  AS side, * FROM (SELECT * FROM dt  EXCEPT SELECT * FROM old)
-- LIMIT 200;


/* =============================================================================
   7. Cutover (run only after validation sign-off)
   ============================================================================= */
-- ALTER TASK UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK SUSPEND;
-- Point consumers to UAT_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DYN
--   (or rename old table to *_BKP and create a view with the old name on the DT).
-- After 1-2 weeks of parallel run:
-- DROP TASK      UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROLLER_TASK;
-- DROP PROCEDURE UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC();
-- DROP PROCEDURE UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_SP(VARCHAR);
-- DROP STREAM    UAT2_WPA_ASSET_DB.CORE.WPA_CAS_NPF_ASSET_CATG_STRM;      -- and the other 6 WPA_CAS_* streams


/* =============================================================================
   Notes
   - UPDATED_AT: omitted. CURRENT_TIMESTAMP() in a DT would restamp rows on
     refresh. When needed, add ROW_TIMESTAMP = TRUE on the final DT (Snowflake
     maintains a per-row last-changed timestamp) instead of a computed column.
   - Volume: fallback branch = 53 schemas × ~399K assets ≈ 21M rows. An asset
     change touches 53 rows; a schema/rule change touches ~399K rows for that
     schema. If refreshes get heavy, switch the final DT to REFRESH_MODE = ADAPTIVE.
   - Not compiled/executed: the UAT/UAT2 databases are not visible from the
     account used by this session.
   ============================================================================= */
