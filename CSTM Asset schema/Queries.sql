/* =============================================================================
   Data walkthrough for WPA_CSTM_ASSET_SCHEMA_CATG
   Run section by section. Sections follow the load flow:
     1 Sources  ->  2 Asset + std category  ->  3 Custom rows  ->  4 Rules
     ->  5 Trace one schema/instrument end-to-end  ->  6 Target checks
   Set a sample schema / instrument once, reuse everywhere.
   ============================================================================= */

-- Pick a schema that has rules and custom rows (query 4.1 / 3.2 help choose)
SET v_schema_id = (SELECT MIN(schema_id) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR WHERE rule_stat = 'A');
SET v_instr_id  = (SELECT MIN(instr_id)  FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
                   WHERE schema_id = $v_schema_id AND end_dt IS NULL);
SELECT $v_schema_id AS schema_id, $v_instr_id AS instr_id;


/* =============================================================================
   1. SOURCE TABLES - shape and keys
   ============================================================================= */

-- 1.1 Customer schemas (schema header). PK = (CUST_SK, SCHEMA_ID)
SELECT cust_sk, schema_id, schema_desc, sort_nbr, upd_tm
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
ORDER BY schema_id, cust_sk;

-- 1.2 !! Is a SCHEMA_ID shared by more than one CUST_SK?
--     Target MERGE key is (SCHEMA_ID, INSTR_ID, RPTG_TYPE) - no CUST_SK.
--     If this returns rows, the fallback branch produces one row per cust_sk
--     for the same key (explains target 38.6M > 53 x 399K-ish).
SELECT schema_id, COUNT(*) AS cust_cnt, LISTAGG(cust_sk::VARCHAR, ',') AS cust_sks
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
GROUP BY schema_id
HAVING COUNT(*) > 1
ORDER BY cust_cnt DESC;

-- 1.3 Standard category mapping ISS_TYPE -> SUP/SUB category. PK = (ISS_TYPE, RPTG_TYPE)
SELECT rptg_type, COUNT(*) AS iss_types,
       COUNT(DISTINCT supcatg_code) AS sup_codes, COUNT(DISTINCT subcatg_code) AS sub_codes
FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG
GROUP BY rptg_type;

SELECT supcatg_code, supcatg_desc, subcatg_code, subcatg_desc, COUNT(*) AS iss_type_cnt
FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG
WHERE rptg_type = 'WLT'
GROUP BY 1,2,3,4
ORDER BY 1,3;

-- 1.4 Country decode (only CNTRY used by this flow)
SELECT dcde_code, dcde_desc
FROM UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE
WHERE dcde_type = 'CNTRY'
ORDER BY dcde_code
LIMIT 50;


/* =============================================================================
   2. ASSETS + STANDARD CATEGORY  (proc CTEs asset_base / asset_catg / cntry_desc)
   ============================================================================= */

-- 2.1 Asset universe: old (WPA_ASSET) vs new (WPA_ASSET_DYN)
SELECT
  (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET     WHERE iss_type IS NOT NULL) AS old_assets,
  (SELECT COUNT(*) FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN  WHERE iss_type IS NOT NULL) AS dyn_assets;

-- 2.2 How many assets get a real mapping vs the defaults (30 Other Assets / 20 Miscellaneous)
SELECT IFF(ac.iss_type IS NULL, 'DEFAULT 30/20', 'MAPPED') AS catg_source,
       COUNT(*) AS assets
FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
       ON ac.rptg_type = 'WLT' AND ac.iss_type = ab.iss_type
WHERE ab.iss_type IS NOT NULL
GROUP BY 1;

-- 2.3 Unmapped ISS_TYPEs (land in defaults)
SELECT ab.iss_type, COUNT(*) AS assets
FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
       ON ac.rptg_type = 'WLT' AND ac.iss_type = ab.iss_type
WHERE ab.iss_type IS NOT NULL AND ac.iss_type IS NULL
GROUP BY 1 ORDER BY 2 DESC;

-- 2.4 Assets with no country description (NULL cntry_desc never matches a country rule)
SELECT IFF(d.dcde_code IS NULL, 'NO CNTRY DESC', 'HAS CNTRY DESC') AS cntry_status, COUNT(*) AS assets
FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
       ON d.dcde_type = 'CNTRY' AND d.dcde_code = ab.cntry_risk_dcde
WHERE ab.iss_type IS NOT NULL
GROUP BY 1;

-- 2.5 Distinct (sup_desc, sub_desc, cntry_desc) combos = rows rules really need to evaluate
SELECT COUNT(*) AS distinct_combos FROM (
  SELECT DISTINCT
         COALESCE(ac.supcatg_desc, 'Other Assets')  AS sup_desc,
         COALESCE(ac.subcatg_desc, 'Miscellaneous') AS sub_desc,
         d.dcde_desc                                AS cntry_desc
  FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
  LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
         ON ac.rptg_type = 'WLT' AND ac.iss_type = ab.iss_type
  LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
         ON d.dcde_type = 'CNTRY' AND d.dcde_code = ab.cntry_risk_dcde
  WHERE ab.iss_type IS NOT NULL);


/* =============================================================================
   3. EXPLICIT CUSTOM ROWS  (NPF_CSTM_SCHEMA -> proc CTE cstm_row / custom_out)
   ============================================================================= */

-- 3.1 Active vs end-dated, by reporting type
SELECT rptg_type, IFF(end_dt IS NULL, 'ACTIVE', 'END-DATED') AS status, COUNT(*) AS rows_cnt
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
GROUP BY 1,2 ORDER BY 1,2;

-- 3.2 Active custom rows per schema
SELECT schema_id, COUNT(*) AS active_rows, COUNT(DISTINCT instr_id) AS instrs
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
WHERE rptg_type = 'WLT' AND end_dt IS NULL
GROUP BY 1 ORDER BY 2 DESC;

-- 3.3 More than one active row for same (schema, instr)? (proc keeps 1 via ROW_NUMBER)
SELECT schema_id, instr_id, COUNT(*) AS active_cnt
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
WHERE rptg_type = 'WLT' AND end_dt IS NULL
GROUP BY 1,2 HAVING COUNT(*) > 1
ORDER BY 3 DESC LIMIT 50;

-- 3.4 Which -C / -S code pattern each custom row falls into
SELECT
  CASE
    WHEN cstm_supcatg_code IS NULL     AND cstm_subcatg_code IS NOT NULL THEN 'SUP=npf-S, SUB=cstm-C'
    WHEN cstm_supcatg_code IS NOT NULL AND cstm_subcatg_code IS NULL     THEN 'SUP=cstm-C, SUB=npf-S'
    WHEN cstm_supcatg_code IS NULL     AND cstm_subcatg_code IS NULL     THEN 'SUP=npf-S, SUB=npf-S'
    ELSE 'SUP=cstm-C, SUB=cstm-C'
  END AS code_pattern,
  COUNT(*) AS rows_cnt
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
WHERE rptg_type = 'WLT' AND end_dt IS NULL
GROUP BY 1;

-- 3.5 Custom rows whose instrument is NOT in the new asset universe (will drop out)
SELECT COUNT(*) AS custom_rows_not_in_asset_dyn
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA ncs
WHERE ncs.rptg_type = 'WLT' AND ncs.end_dt IS NULL
  AND NOT EXISTS (SELECT 1 FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN a
                  WHERE a.instr_id = ncs.instr_id AND a.iss_type IS NOT NULL);


/* =============================================================================
   4. RULES  (NPF_CSTM_RULE_MSTR + NPF_CSTM_RULE_COND -> rule_eval / rule_pick)
   ============================================================================= */

-- 4.1 Rules per schema and status
SELECT schema_id, rule_stat, COUNT(*) AS rules
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR
GROUP BY 1,2 ORDER BY 1,2;

-- 4.2 Condition vocabulary (fields / operators / logical operators actually used)
SELECT rule_fld_name, rule_oper, NVL(logical_oper, '<null>') AS logical_oper, COUNT(*) AS conds
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND
GROUP BY 1,2,3 ORDER BY 1,2,3;
-- Proc only understands fld_name CSTM_SUPCATG_DESC / CSTM_SUBCATG_DESC / CSTM_CNTRY_RISK_DESC
-- and oper EQUAL / NOTEQUAL; anything else here counts as "not matched".

-- 4.3 Rules in full for the sample schema (rule -> its conditions, in order)
SELECT r.rule_sk, r.rule_name, r.rule_stat,
       r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
       c.cond_sk, c.cond_order, c.logical_oper,
       c.rule_fld_name, c.rule_oper, c.rule_fld_value
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
WHERE r.schema_id = $v_schema_id
ORDER BY r.rule_sk, c.cond_order;

-- 4.4 Data-quality: active rules with no conditions (never match),
--     rules whose schema is not in NPF_CUST_CSTM_SCHEMA, orphan conditions
SELECT 'ACTIVE_RULE_NO_COND' AS issue, COUNT(*) AS cnt
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
WHERE r.rule_stat = 'A'
  AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c WHERE c.rule_sk = r.rule_sk)
UNION ALL
SELECT 'RULE_SCHEMA_NOT_IN_CUST_SCHEMA', COUNT(*)
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s WHERE s.schema_id = r.schema_id)
UNION ALL
SELECT 'ORPHAN_COND', COUNT(*)
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r WHERE r.rule_sk = c.rule_sk);

-- 4.5 Rule evaluation for the sample schema, per distinct desc combo
--     (same logic as proc: OR -> any match, else all match; first/last rule_sk)
WITH combo AS (
  SELECT DISTINCT
         COALESCE(ac.supcatg_desc, 'Other Assets')  AS sup_desc,
         COALESCE(ac.subcatg_desc, 'Miscellaneous') AS sub_desc,
         d.dcde_desc                                AS cntry_desc
  FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
  LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = ab.iss_type
  LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d ON d.dcde_type = 'CNTRY' AND d.dcde_code = ab.cntry_risk_dcde
  WHERE ab.iss_type IS NOT NULL
),
rule_eval AS (
  SELECT cb.sup_desc, cb.sub_desc, cb.cntry_desc,
         r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
         MAX(IFF(c.logical_oper = 'OR', 1, 0)) AS has_or,
         COUNT(c.rule_sk)                      AS cond_cnt,
         SUM(CASE
               WHEN c.rule_fld_name = 'CSTM_SUPCATG_DESC' AND
                    ((c.rule_oper = 'EQUAL' AND cb.sup_desc = c.rule_fld_value) OR
                     (c.rule_oper = 'NOTEQUAL' AND cb.sup_desc != c.rule_fld_value)) THEN 1
               WHEN c.rule_fld_name = 'CSTM_SUBCATG_DESC' AND
                    ((c.rule_oper = 'EQUAL' AND cb.sub_desc = c.rule_fld_value) OR
                     (c.rule_oper = 'NOTEQUAL' AND cb.sub_desc != c.rule_fld_value)) THEN 1
               WHEN c.rule_fld_name = 'CSTM_CNTRY_RISK_DESC' AND
                    ((c.rule_oper = 'EQUAL' AND cb.cntry_desc = c.rule_fld_value) OR
                     (c.rule_oper = 'NOTEQUAL' AND cb.cntry_desc != c.rule_fld_value)) THEN 1
               ELSE 0 END)                     AS match_cnt
  FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
  JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
  CROSS JOIN combo cb
  WHERE r.schema_id = $v_schema_id AND r.rule_stat = 'A'
  GROUP BY 1,2,3,4,5,6
)
SELECT sup_desc, sub_desc, cntry_desc,
       COUNT(*)                                AS matched_rules,
       MIN(rule_sk)                            AS first_rule_sk,
       MAX(rule_sk)                            AS last_rule_sk,
       MIN_BY(rule_cstm_supcatg_desc, rule_sk) AS r1_sup,
       MAX_BY(rule_cstm_supcatg_desc, rule_sk) AS rn_sup,
       MIN_BY(rule_cstm_subcatg_desc, rule_sk) AS r1_sub,
       MAX_BY(rule_cstm_subcatg_desc, rule_sk) AS rn_sub
FROM rule_eval
WHERE cond_cnt > 0
  AND ((has_or = 1 AND match_cnt > 0) OR (has_or = 0 AND match_cnt = cond_cnt))
GROUP BY 1,2,3
ORDER BY matched_rules DESC, 1,2,3;
-- matched_rules > 1 => proc uses the LAST rule (highest rule_sk) description.


/* =============================================================================
   5. TRACE ONE (SCHEMA, INSTRUMENT) END-TO-END
   ============================================================================= */

-- 5.1 Asset + standard category + country
SELECT ab.instr_id, ab.iss_type, ab.cntry_risk_dcde,
       COALESCE(ac.supcatg_code,'30') AS sup_code, COALESCE(ac.supcatg_desc,'Other Assets')  AS sup_desc,
       COALESCE(ac.subcatg_code,'20') AS sub_code, COALESCE(ac.subcatg_desc,'Miscellaneous') AS sub_desc,
       d.dcde_desc AS cntry_desc
FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN ab
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = ab.iss_type
LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d ON d.dcde_type = 'CNTRY' AND d.dcde_code = ab.cntry_risk_dcde
WHERE ab.instr_id = $v_instr_id;

-- 5.2 Custom row(s) for it - if an ACTIVE WLT row exists, Branch A (custom) wins
SELECT schema_id, instr_id, rptg_type, start_dt, end_dt,
       cstm_supcatg_code, cstm_supcatg_desc, npf_supcatg_code,
       cstm_subcatg_code, cstm_subcatg_desc, npf_subcatg_code
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
WHERE schema_id = $v_schema_id AND instr_id = $v_instr_id
ORDER BY start_dt;

-- 5.3 What the target currently holds for it
SELECT *
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
WHERE schema_id = $v_schema_id AND instr_id = $v_instr_id;

-- 5.4 Same, for an instrument WITHOUT a custom row (Branch B: rules / standard)
SET v_instr_id_fb = (
  SELECT MIN(a.instr_id) FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN a
  WHERE a.iss_type IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA c
                    WHERE c.schema_id = $v_schema_id AND c.instr_id = a.instr_id AND c.end_dt IS NULL));
SELECT *
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
WHERE schema_id = $v_schema_id AND instr_id = $v_instr_id_fb;
-- Compare its SUPCATG_DESC/SUBCATG_DESC with 4.5 (rule hit) or 5.1 (standard).


/* =============================================================================
   6. TARGET TABLE CHECKS
   ============================================================================= */

-- 6.1 Rows per schema vs expected (assets x cust_sk count)
SELECT t.schema_id, COUNT(*) AS target_rows, COUNT(DISTINCT t.cust_sk) AS cust_sks,
       COUNT(DISTINCT t.instr_id) AS instrs
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG t
GROUP BY 1 ORDER BY 2 DESC;

-- 6.2 Duplicate business key (schema, instr, rptg)? Expected 0 - non-zero ties to 1.2
SELECT COUNT(*) AS dup_keys FROM (
  SELECT schema_id, instr_id, rptg_type
  FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
  GROUP BY 1,2,3 HAVING COUNT(*) > 1);

-- 6.3 Branch split in target (-C anywhere = custom row; pure -S = rule/standard)
--     Fallback sub code looks like '<sup>-<sub>-S'; custom branch never has two dashes.
SELECT CASE
         WHEN cstm_subcatg_code LIKE '%-%-S'     THEN 'B: RULE/STANDARD (fallback)'
         ELSE                                         'A: CUSTOM ROW (NPF_CSTM_SCHEMA)'
       END AS branch,
       COUNT(*) AS rows_cnt,
       COUNT_IF(supcatg_desc <> cstm_supcatg_desc OR subcatg_desc <> cstm_subcatg_desc) AS desc_mismatch
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
GROUP BY 1;

-- 6.4 Stale rows: target instruments no longer in WPA_ASSET (proc only removes on ASSET delete)
SELECT COUNT(*) AS target_rows_instr_missing
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG t
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET a
                  WHERE a.instr_id = t.instr_id AND a.iss_type IS NOT NULL);

-- 6.5 Target rows that will be out of scope in the DT (instrument not in WPA_ASSET_DYN)
SELECT COUNT(*) AS target_rows_not_in_asset_dyn
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG t
WHERE NOT EXISTS (SELECT 1 FROM UAT_WPA_ASSET_DB.CORE.WPA_ASSET_DYN a WHERE a.instr_id = t.instr_id);

-- 6.6 Freshness of the current load
SELECT MIN(updated_at), MAX(updated_at), COUNT_IF(updated_at >= DATEADD(day,-1,CURRENT_TIMESTAMP())) AS rows_touched_24h
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG;
