/* =============================================================================
   VALIDATION  -  DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
   Checks every (SCHEMA_ID, INSTR_ID, ISS_TYPE, CUST_SK) row against an INDEPENDENT
   re-implementation of Oracle npf_asst_typ_mgr (11-arg) + RULE_EVALUATION,
   built straight from base tables (not from the WPA_CAS_* DTs):
     - standard category from the POSITION / TRANSACTION issue type + NPF_ASSET_CATG + defaults
     - country from NPF_ASSET.cntry_risk_dcde + NPF_DECODE('CNTRY')
     - rules evaluated PER INSTRUMENT (DT evaluates per desc combo)
   Grain (same as the DT) = each NPF_CUST_CSTM_SCHEMA (cust_sk, schema) x the
   (instrument, issue type) pairs that cust_sk ever held (WPA_AC_POSITION, any date) or transacted (WPA_TRANSACTION)
   (instrument attributes read straight from NPF_ASSET, as the Oracle proc does;
   held/transacted instruments = the same set WPA_ASSET_DYN keeps).

   Sections
     0  Parameters
     1  Build expected result (temp table) with Oracle SCENARIO tag
     2  Structural checks (grain, duplicates, NULLs, code formats)
     3  Full comparison DT vs expected  (per column, per scenario)
     4  Scenario coverage + sample rows per scenario
     5  CUST_SK consistency (same schema -> same values for every customer)
     6  Optional: compare with old proc-loaded table WPA_CSTM_ASSET_SCHEMA_CATG

   Scenarios (Oracle branch that produced the row)
     P1-CC  custom row, cstm sup code + cstm sub code       -> sup -C, sub -C
     P1-SC  custom row, cstm sup NULL, cstm sub present     -> sup -S, sub -C
     P1-CS  custom row, cstm sup present, cstm sub NULL     -> sup -C, sub -S
     P1-SS  custom row, both cstm codes NULL                -> sup -S, sub -S
     P2-R1  no custom row, exactly 1 rule matched           -> rule desc
     P2-RN  no custom row, >1 rule matched                  -> last rule desc (per column fallback)
     P2-STD no custom row, no rule matched                  -> standard desc
   Extra flags: DEFAULT_CATG (no NPF_ASSET_CATG mapping -> 30/20),
                NO_CNTRY (country desc NULL), NULL_ISS_TYPE.
   ============================================================================= */


/* =============================================================================
   0. Parameters
   Set V_SCHEMA_ID to one schema for a fast run, or NULL for all schemas.
   ============================================================================= */
SET V_SCHEMA_ID = NULL;          -- e.g. SET V_SCHEMA_ID = 101;


/* =============================================================================
   1. Expected result (independent Oracle re-implementation)
   ============================================================================= */
CREATE OR REPLACE TEMPORARY TABLE DEV_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED AS
WITH
hold AS (                                     -- customer positions (any date) + transactions
    SELECT p.cust_sk, p.instr_id, NULLIF(p.ast_iss_type, '') AS iss_type   -- issue type from the position
    FROM DEV_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION p
    WHERE p.instr_id IS NOT NULL AND p.cust_sk IS NOT NULL
    UNION
    SELECT t.cust_sk, t.instr_id, NULLIF(t.ast_iss_type, '') AS iss_type   -- ... and from the transaction
    FROM DEV_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION t
    WHERE t.instr_id IS NOT NULL AND t.cust_sk IS NOT NULL
),
ast AS (                                      -- (instr, passed issue type) + NPF_ASSET country code
    SELECT DISTINCT h.instr_id, h.iss_type, a.cntry_risk_dcde
    FROM hold h
    JOIN DEV_WPA_ASSET_DB.CORE.NPF_ASSET a ON a.instr_id = h.instr_id   -- instr must exist in NPF_ASSET
),
std AS (                                      -- 6-arg npf_asst_typ_mgr + country lookup
    SELECT
        ast.instr_id,
        ast.iss_type,
        IFF(ac.iss_type IS NULL, 'Y', 'N')                                      AS default_catg,
        IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
        IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
        IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
        IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
        NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
    FROM ast
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
           ON ac.rptg_type = 'WLT' AND ac.iss_type = ast.iss_type
    LEFT JOIN DEV_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
           ON d.dcde_type = 'CNTRY' AND d.dcde_code = ast.cntry_risk_dcde
),
sch AS (
    SELECT cust_sk, schema_id, schema_desc
    FROM DEV_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
),
cs AS (                                       -- v_rec_cnt + cstm_asset_cursor
    SELECT schema_id, instr_id,
           NULLIF(cstm_supcatg_code, '') AS cstm_supcatg_code,
           NULLIF(cstm_supcatg_desc, '') AS cstm_supcatg_desc,
           NULLIF(npf_supcatg_code,  '') AS npf_supcatg_code,
           NULLIF(cstm_subcatg_code, '') AS cstm_subcatg_code,
           NULLIF(cstm_subcatg_desc, '') AS cstm_subcatg_desc,
           NULLIF(npf_subcatg_code,  '') AS npf_subcatg_code
    FROM DEV_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
    WHERE rptg_type = 'WLT' AND end_dt IS NULL
      AND ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id ORDER BY start_dt DESC) = 1
),
grid AS (                                     -- one row per npf_asst_typ_mgr call
    SELECT s.cust_sk, s.schema_id, s.schema_desc, t.*
    FROM sch s
    JOIN hold h ON h.cust_sk  = s.cust_sk
    JOIN std  t ON t.instr_id = h.instr_id AND EQUAL_NULL(t.iss_type, h.iss_type)
),
need_rules AS (                               -- (schema, instr, iss) that go to RULE_EVALUATION
    SELECT DISTINCT g.schema_id, g.instr_id, NVL(g.iss_type, '#NULL#') AS iss_key, g.std_sup_desc, g.std_sub_desc, g.cntry_desc
    FROM grid g
    WHERE NOT EXISTS (SELECT 1 FROM cs WHERE cs.schema_id = g.schema_id AND cs.instr_id = g.instr_id)
),
cond_eval AS (                                -- one row per (schema, instr, rule, condition)
    SELECT
        n.schema_id, n.instr_id, n.iss_key, r.rule_sk,
        NULLIF(r.rule_cstm_supcatg_desc, '') AS rule_sup_desc,
        NULLIF(r.rule_cstm_subcatg_desc, '') AS rule_sub_desc,
        c.cond_sk,
        c.logical_oper,
        CASE c.rule_fld_name
             WHEN 'CSTM_SUPCATG_DESC'    THEN n.std_sup_desc
             WHEN 'CSTM_SUBCATG_DESC'    THEN n.std_sub_desc
             WHEN 'CSTM_CNTRY_RISK_DESC' THEN n.cntry_desc
        END                                  AS fld_val,
        c.rule_fld_name,
        c.rule_oper,
        NULLIF(c.rule_fld_value, '')         AS rule_fld_value
    FROM need_rules n
    JOIN DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
      ON r.schema_id = n.schema_id AND r.rule_stat = 'A'
    LEFT JOIN DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c
      ON c.rule_sk = r.rule_sk
),
rule_match AS (                               -- Oracle per-rule decision
    SELECT schema_id, instr_id, iss_key, rule_sk, rule_sup_desc, rule_sub_desc,
           BOOLOR_AGG(COALESCE(logical_oper = 'OR', FALSE))                      AS has_or,
           COUNT(cond_sk)                                                        AS n_cond,
           COUNT_IF(COALESCE(
               CASE WHEN rule_fld_name IN ('CSTM_SUPCATG_DESC','CSTM_SUBCATG_DESC','CSTM_CNTRY_RISK_DESC')
                    THEN CASE rule_oper
                              WHEN 'EQUAL'    THEN fld_val =  rule_fld_value
                              WHEN 'NOTEQUAL' THEN fld_val <> rule_fld_value
                         END
               END, FALSE))                                                      AS n_true
    FROM cond_eval
    GROUP BY schema_id, instr_id, iss_key, rule_sk, rule_sup_desc, rule_sub_desc
),
matched AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id, iss_key ORDER BY rule_sk ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id, iss_key ORDER BY rule_sk DESC) AS rn_last,
           COUNT(*)     OVER (PARTITION BY schema_id, instr_id, iss_key)              AS n_match
    FROM rule_match
    WHERE (has_or AND n_true > 0) OR (NOT has_or AND n_true = n_cond)
),
rule_out AS (                                 -- desc_1 = first, desc_2 = last (only if >1)
    SELECT schema_id, instr_id, iss_key, MAX(n_match) AS n_match,
           MAX(IFF(rn_first = 1, rule_sup_desc, NULL))                 AS d1_sup,
           MAX(IFF(rn_first = 1, rule_sub_desc, NULL))                 AS d1_sub,
           MAX(IFF(rn_last  = 1 AND n_match > 1, rule_sup_desc, NULL)) AS d2_sup,
           MAX(IFF(rn_last  = 1 AND n_match > 1, rule_sub_desc, NULL)) AS d2_sub
    FROM matched
    GROUP BY schema_id, instr_id, iss_key
)
SELECT
    s.schema_id,
    s.cust_sk,
    t.instr_id,
    'WLT'                                     AS rptg_type,
    t.iss_type,
    -- OUT: v_ast_supcatg_code_a / v_ast_subcatg_code_a (always standard)
    t.std_sup_code                            AS supcatg_code,
    t.std_sub_code                            AS subcatg_code,
    -- OUT: v_ast_supcatg_desc_a / v_ast_subcatg_desc_a
    CASE WHEN cs.schema_id IS NOT NULL THEN cs.cstm_supcatg_desc
         ELSE COALESCE(ro.d2_sup, ro.d1_sup, t.std_sup_desc) END        AS supcatg_desc,
    CASE WHEN cs.schema_id IS NOT NULL THEN cs.cstm_subcatg_desc
         ELSE COALESCE(ro.d2_sub, ro.d1_sub, t.std_sub_desc) END        AS subcatg_desc,
    -- OUT: v_cstm_supcatg_code_a / v_cstm_subcatg_code_a (Oracle 4-branch matrix, literal)
    CASE
      WHEN cs.schema_id IS NULL                                                    THEN NVL(t.std_sup_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL   THEN NVL(cs.npf_supcatg_code,'')  || '-S'
      WHEN cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL       THEN cs.cstm_supcatg_code         || '-C'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NULL       THEN NVL(cs.npf_supcatg_code,'')  || '-S'
      ELSE                                                                              cs.cstm_supcatg_code         || '-C'
    END                                                                 AS cstm_supcatg_code,
    CASE
      WHEN cs.schema_id IS NULL                                                    THEN NVL(t.std_sup_code,'') || '-' || NVL(t.std_sub_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL   THEN cs.cstm_subcatg_code         || '-C'
      WHEN cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL       THEN NVL(cs.npf_subcatg_code,'')  || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NULL       THEN NVL(cs.npf_subcatg_code,'')  || '-S'
      ELSE                                                                              cs.cstm_subcatg_code         || '-C'
    END                                                                 AS cstm_subcatg_code,
    s.schema_desc,
    -- Scenario tags
    CASE
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NOT NULL THEN 'P1-CC'
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL THEN 'P1-SC'
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL     THEN 'P1-CS'
      WHEN cs.schema_id IS NOT NULL                                                                           THEN 'P1-SS'
      WHEN ro.n_match = 1                                                                                     THEN 'P2-R1'
      WHEN ro.n_match > 1                                                                                     THEN 'P2-RN'
      ELSE                                                                                                         'P2-STD'
    END                                                                 AS scenario,
    t.default_catg,
    IFF(t.cntry_desc IS NULL, 'Y', 'N')                                 AS no_cntry,
    IFF(t.iss_type   IS NULL, 'Y', 'N')                                 AS null_iss_type,
    NVL(ro.n_match, 0)                                                  AS n_rules_matched
FROM grid t
JOIN sch s         ON s.cust_sk = t.cust_sk AND s.schema_id = t.schema_id
LEFT JOIN cs       ON cs.schema_id = s.schema_id AND cs.instr_id = t.instr_id
LEFT JOIN rule_out ro ON ro.schema_id = s.schema_id AND ro.instr_id = t.instr_id
                     AND ro.iss_key = NVL(t.iss_type, '#NULL#');


/* =============================================================================
   2. Structural checks on the DT
   ============================================================================= */

-- 2.1 Row counts: DT vs expected (cust-schema rows x that customer's holdings)
SELECT
  (SELECT COUNT(*) FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID))                     AS dt_rows,
  (SELECT COUNT(*) FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED)                  AS expected_rows;

-- 2.1b Same, per customer (spot the customers whose counts differ; expect 0 rows)
SELECT COALESCE(d.schema_id, e.schema_id) AS schema_id,
       COALESCE(d.cust_sk,   e.cust_sk)   AS cust_sk,
       d.cnt AS dt_rows, e.cnt AS expected_rows
FROM (SELECT schema_id, cust_sk, COUNT(*) cnt
      FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
      WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
      GROUP BY 1,2) d
FULL OUTER JOIN
     (SELECT schema_id, cust_sk, COUNT(*) cnt
      FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED GROUP BY 1,2) e
  ON e.schema_id = d.schema_id AND e.cust_sk = d.cust_sk
WHERE NOT EQUAL_NULL(d.cnt, e.cnt)
ORDER BY 1,2
LIMIT 100;

-- 2.2 Duplicate keys in DT (expect 0)
SELECT schema_id, instr_id, cust_sk, iss_type, COUNT(*) AS cnt
FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
GROUP BY 1,2,3,4 HAVING COUNT(*) > 1
LIMIT 100;

-- 2.3 NULL / format checks (each count should be 0 unless explained by source data)
SELECT
  COUNT_IF(supcatg_code IS NULL)                                   AS null_supcatg_code,
  COUNT_IF(subcatg_code IS NULL)                                   AS null_subcatg_code,
  COUNT_IF(supcatg_desc IS NULL)                                   AS null_supcatg_desc,
  COUNT_IF(subcatg_desc IS NULL)                                   AS null_subcatg_desc,
  COUNT_IF(cstm_supcatg_code IS NULL)                              AS null_cstm_sup_code,
  COUNT_IF(cstm_subcatg_code IS NULL)                              AS null_cstm_sub_code,
  COUNT_IF(NOT (cstm_supcatg_code LIKE '%-S' OR cstm_supcatg_code LIKE '%-C')) AS bad_sup_suffix,
  COUNT_IF(NOT (cstm_subcatg_code LIKE '%-S' OR cstm_subcatg_code LIKE '%-C')) AS bad_sub_suffix,
  COUNT_IF(cstm_supcatg_desc IS DISTINCT FROM supcatg_desc)        AS cstm_sup_desc_ne_desc,
  COUNT_IF(cstm_subcatg_desc IS DISTINCT FROM subcatg_desc)        AS cstm_sub_desc_ne_desc,
  COUNT_IF(rptg_type <> 'WLT')                                     AS non_wlt
FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID);

-- 2.4 Rule/standard rows: sup code must start the sub code ('<sup>-<sub>-S')
SELECT COUNT(*) AS bad_fallback_code_pattern
FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
  AND cstm_subcatg_code LIKE '%-%-S'
  AND (cstm_supcatg_code <> supcatg_code || '-S'
       OR cstm_subcatg_code <> supcatg_code || '-' || subcatg_code || '-S');


/* =============================================================================
   3. Full comparison DT vs expected
   ============================================================================= */
CREATE OR REPLACE TEMPORARY TABLE DEV_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF AS
SELECT
    COALESCE(e.schema_id, d.schema_id) AS schema_id,
    COALESCE(e.cust_sk,   d.cust_sk)   AS cust_sk,
    COALESCE(e.instr_id,  d.instr_id)  AS instr_id,
    COALESCE(e.iss_type,  d.iss_type)  AS iss_type,
    e.scenario, e.default_catg, e.no_cntry, e.null_iss_type, e.n_rules_matched,
    CASE WHEN d.instr_id IS NULL THEN 'MISSING_IN_DT'
         WHEN e.instr_id IS NULL THEN 'EXTRA_IN_DT'
         ELSE 'BOTH' END                                                AS presence,
    NOT EQUAL_NULL(e.iss_type,          d.iss_type)                     AS diff_iss_type,
    NOT EQUAL_NULL(e.supcatg_code,      d.supcatg_code)                 AS diff_sup_code,
    NOT EQUAL_NULL(e.subcatg_code,      d.subcatg_code)                 AS diff_sub_code,
    NOT EQUAL_NULL(e.supcatg_desc,      d.supcatg_desc)                 AS diff_sup_desc,
    NOT EQUAL_NULL(e.subcatg_desc,      d.subcatg_desc)                 AS diff_sub_desc,
    NOT EQUAL_NULL(e.cstm_supcatg_code, d.cstm_supcatg_code)            AS diff_cstm_sup_code,
    NOT EQUAL_NULL(e.cstm_subcatg_code, d.cstm_subcatg_code)            AS diff_cstm_sub_code,
    NOT EQUAL_NULL(e.schema_desc,       d.schema_desc)                  AS diff_schema_desc,
    e.supcatg_code      AS exp_sup_code,      d.supcatg_code      AS dt_sup_code,
    e.subcatg_code      AS exp_sub_code,      d.subcatg_code      AS dt_sub_code,
    e.supcatg_desc      AS exp_sup_desc,      d.supcatg_desc      AS dt_sup_desc,
    e.subcatg_desc      AS exp_sub_desc,      d.subcatg_desc      AS dt_sub_desc,
    e.cstm_supcatg_code AS exp_cstm_sup_code, d.cstm_supcatg_code AS dt_cstm_sup_code,
    e.cstm_subcatg_code AS exp_cstm_sub_code, d.cstm_subcatg_code AS dt_cstm_sub_code
FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED e
FULL OUTER JOIN (
    SELECT * FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
) d
  ON d.schema_id = e.schema_id AND d.cust_sk = e.cust_sk AND d.instr_id = e.instr_id
 AND EQUAL_NULL(d.iss_type, e.iss_type);

-- 3.1 Overall result: all diff columns should be 0, presence only 'BOTH'
SELECT presence,
       COUNT(*)                       AS rows_cnt,
       COUNT_IF(diff_iss_type)        AS iss_type,
       COUNT_IF(diff_sup_code)        AS sup_code,
       COUNT_IF(diff_sub_code)        AS sub_code,
       COUNT_IF(diff_sup_desc)        AS sup_desc,
       COUNT_IF(diff_sub_desc)        AS sub_desc,
       COUNT_IF(diff_cstm_sup_code)   AS cstm_sup_code,
       COUNT_IF(diff_cstm_sub_code)   AS cstm_sub_code,
       COUNT_IF(diff_schema_desc)     AS schema_desc
FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
GROUP BY presence;

-- 3.2 Mismatches by scenario (which Oracle branch is wrong)
SELECT scenario, default_catg, no_cntry, null_iss_type,
       COUNT(*) AS rows_cnt,
       COUNT_IF(diff_sup_code OR diff_sub_code)           AS std_code_diff,
       COUNT_IF(diff_sup_desc OR diff_sub_desc)           AS desc_diff,
       COUNT_IF(diff_cstm_sup_code OR diff_cstm_sub_code) AS cstm_code_diff
FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence = 'BOTH'
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4;

-- 3.3 Mismatch detail (first 200)
SELECT schema_id, cust_sk, instr_id, iss_type, scenario, presence, n_rules_matched,
       exp_sup_code, dt_sup_code, exp_sub_code, dt_sub_code,
       exp_sup_desc, dt_sup_desc, exp_sub_desc, dt_sub_desc,
       exp_cstm_sup_code, dt_cstm_sup_code, exp_cstm_sub_code, dt_cstm_sub_code
FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence <> 'BOTH'
   OR diff_iss_type OR diff_sup_code OR diff_sub_code OR diff_sup_desc OR diff_sub_desc
   OR diff_cstm_sup_code OR diff_cstm_sub_code OR diff_schema_desc
ORDER BY scenario, schema_id, instr_id
LIMIT 200;


/* =============================================================================
   4. Scenario coverage + samples
   ============================================================================= */

-- 4.1 Coverage: every scenario should have rows (a 0 means that path is untested)
WITH s AS (
    SELECT column1 AS scenario FROM VALUES
      ('P1-CC'),('P1-SC'),('P1-CS'),('P1-SS'),('P2-R1'),('P2-RN'),('P2-STD')
)
SELECT s.scenario,
       COUNT(e.instr_id)                       AS rows_cnt,
       COUNT(DISTINCT e.schema_id)             AS schemas,
       COUNT(DISTINCT e.instr_id)              AS instruments,
       COUNT_IF(e.default_catg  = 'Y')         AS with_default_catg,
       COUNT_IF(e.no_cntry      = 'Y')         AS with_no_cntry,
       COUNT_IF(e.null_iss_type = 'Y')         AS with_null_iss_type
FROM s
LEFT JOIN DEV_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED e ON e.scenario = s.scenario
GROUP BY s.scenario
ORDER BY s.scenario;

-- 4.2 Three sample rows per scenario: DT values side by side with expected
SELECT x.scenario, x.schema_id, x.cust_sk, x.instr_id, x.n_rules_matched,
       x.exp_sup_code, x.dt_sup_code, x.exp_sub_code, x.dt_sub_code,
       x.exp_sup_desc, x.dt_sup_desc, x.exp_sub_desc, x.dt_sub_desc,
       x.exp_cstm_sup_code, x.dt_cstm_sup_code, x.exp_cstm_sub_code, x.dt_cstm_sub_code
FROM DEV_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF x
WHERE x.presence = 'BOTH'
QUALIFY ROW_NUMBER() OVER (PARTITION BY x.scenario ORDER BY x.schema_id, x.instr_id) <= 3
ORDER BY x.scenario, x.schema_id, x.instr_id;

-- 4.3 Trace a P2-RN row: which rules matched, in RULE_SK order (pick ids from 4.2)
-- SET V_TRACE_SCHEMA = <schema_id>;  SET V_TRACE_INSTR = '<instr_id>';
-- SELECT r.rule_sk, r.rule_name, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
--        c.cond_order, c.logical_oper, c.rule_fld_name, c.rule_oper, c.rule_fld_value
-- FROM DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
-- LEFT JOIN DEV_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
-- WHERE r.schema_id = $V_TRACE_SCHEMA AND r.rule_stat = 'A'
-- ORDER BY r.rule_sk, c.cond_order;


/* =============================================================================
   5. CUST_SK consistency
   p_cust_sk is unused by the proc -> all customers sharing a schema must get
   identical values for the same instrument (expect 0 rows).
   ============================================================================= */
SELECT schema_id, instr_id, iss_type,
       COUNT(DISTINCT cust_sk) AS customers,
       COUNT(DISTINCT HASH(supcatg_code, subcatg_code, supcatg_desc, subcatg_desc,
                           cstm_supcatg_code, cstm_subcatg_code)) AS distinct_results
FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
GROUP BY schema_id, instr_id, iss_type
HAVING COUNT(DISTINCT HASH(supcatg_code, subcatg_code, supcatg_desc, subcatg_desc,
                           cstm_supcatg_code, cstm_subcatg_code)) > 1
LIMIT 100;


/* =============================================================================
   6. Optional: compare with the old proc-loaded table
   Old table key has no CUST_SK, so compare on (schema, instr, rptg) and only
   for instruments present in both. Differences here can be old-proc gaps
   (stale rows, zero-condition rule handling), not DT errors - confirm with 3.x.
   ============================================================================= */
WITH dt AS (
    SELECT DISTINCT schema_id, instr_id, rptg_type, iss_type, supcatg_code, subcatg_code,
           supcatg_desc, subcatg_desc, cstm_supcatg_code, cstm_subcatg_code
    FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
),
old AS (
    SELECT DISTINCT schema_id, instr_id, rptg_type, iss_type, supcatg_code, subcatg_code,
           supcatg_desc, subcatg_desc, cstm_supcatg_code, cstm_subcatg_code
    FROM DEV_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
      AND instr_id IN (SELECT instr_id FROM dt)
)
SELECT 'ONLY_IN_OLD' AS side, * FROM (SELECT * FROM old EXCEPT SELECT * FROM dt)
UNION ALL
SELECT 'ONLY_IN_DT'  AS side, * FROM (
    SELECT * FROM dt
    WHERE (schema_id, instr_id) IN (SELECT schema_id, instr_id FROM old)
    EXCEPT
    SELECT * FROM old)
LIMIT 200;
