/* =============================================================================
   UAT2 VALIDATION  -  UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
   Covers every DT in the pipeline, customer-level counts, the full Oracle
   re-implementation compare (by Oracle branch / scenario), and Oracle edge cases.

   Objects (UAT2)
     DT1   UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN    <- WPA_ASSET_DYN + NPF_ASSET_CATG + NPF_DECODE
     DT2   UAT2_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN    <- DT1 + NPF_CSTM_RULE_MSTR / _COND
     DT3   UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN     <- NPF_CSTM_SCHEMA
     DT4   UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN   <- WPA_AC_POSITION + WPA_TRANSACTION
     FINAL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
   Sources
     UAT2_WPA_ASSET_DB.CORE.{NPF_ASSET, NPF_ASSET_CATG, NPF_CUST_CSTM_SCHEMA, NPF_CSTM_SCHEMA,
                             NPF_CSTM_RULE_MSTR, NPF_CSTM_RULE_COND, WPA_ASSET_DYN}
     UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE
     UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION
     UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION
   If WPA_ASSET_DYN lives elsewhere (e.g. UAT_WPA_ASSET_DB.CORE), find/replace it.

   Sections                                                         Expect
     0  Parameters
     1  DT refresh health                                           all ACTIVE, no failures
     2  Pipeline row counts                                         info
     3  DT1 asset standard category                                 0 in each check
     4  DT3 custom row                                              0 in each check
     5  DT4 customer-instrument                                     0 in each check
     6  CUSTOMER validations                                        0 rows / 0 counts
     7  Expected result (independent Oracle re-implementation)      builds temp table
     8  Full compare DT vs expected                                 only 'BOTH', 0 diffs
     9  Scenario coverage + samples (Oracle branches)               every scenario > 0
    10  DT2 rule evaluation detail (AND / OR / zero-cond / multi)   0 diffs
    11  Oracle edge cases (source-data profile + DT behaviour)      see each query
    12  Structural / format checks on FINAL                         0 in each check
    13  Optional: compare with old proc-loaded table                explain diffs

   Scenarios (Oracle npf_asst_typ_mgr 11-arg branch)
     P1-CC  custom row, cstm sup code + cstm sub code       -> sup <c>-C , sub <c>-C
     P1-SC  custom row, cstm sup NULL,  cstm sub present    -> sup <npf>-S, sub <c>-C
     P1-CS  custom row, cstm sup present, cstm sub NULL     -> sup <c>-C , sub <npf>-S
     P1-SS  custom row, both cstm codes NULL                -> sup <npf>-S, sub <npf>-S
     P2-R1  no custom row, exactly 1 rule matched           -> rule desc
     P2-RN  no custom row, >1 rule matched                  -> last rule desc, per column
                                                               fallback last -> first -> std
     P2-STD no custom row, no rule matched                  -> standard desc
     Path 2 codes always: sup '<sup>-S', sub '<sup>-<sub>-S'
   ============================================================================= */


/* =============================================================================
   0. Parameters
   ============================================================================= */
SET V_SCHEMA_ID = NULL;          -- one schema for a fast run, e.g. SET V_SCHEMA_ID = 686;
SET V_CUST_SK   = 104265;        -- customer used in the customer spot checks (section 6.6)


/* =============================================================================
   1. DT refresh health
   ============================================================================= */
-- 1.1 State / refresh mode of all 5 DTs (expect scheduling_state = ACTIVE, refresh_mode as designed:
--     DT1 ADAPTIVE, DT2 INCREMENTAL, DT3 INCREMENTAL, DT4 ADAPTIVE, FINAL ADAPTIVE)
SHOW DYNAMIC TABLES LIKE 'WPA_C%' IN SCHEMA UAT2_WPA_ASSET_DB.CORE;

SELECT "name", "refresh_mode", "refresh_mode_reason", "scheduling_state", "target_lag",
       "data_timestamp", "rows", "warehouse"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "name" IN ('WPA_CAS_ASSET_STD_DYN','WPA_CAS_RULE_PICK_DYN','WPA_CAS_CSTM_ROW_DYN',
                 'WPA_CAS_CUST_INSTR_DYN','WPA_CSTM_ASSET_SCHEMA_CATG_DY')
ORDER BY "name";

-- 1.2 Last 50 refreshes: failures, refresh action (INCREMENTAL / FULL / REINITIALIZE), duration
SELECT name, state, refresh_action, refresh_trigger,
       refresh_start_time, refresh_end_time,
       DATEDIFF('second', refresh_start_time, refresh_end_time) AS secs,
       state_message
FROM TABLE(UAT2_WPA_ASSET_DB.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE name IN ('WPA_CAS_ASSET_STD_DYN','WPA_CAS_RULE_PICK_DYN','WPA_CAS_CSTM_ROW_DYN',
               'WPA_CAS_CUST_INSTR_DYN','WPA_CSTM_ASSET_SCHEMA_CATG_DY')
ORDER BY refresh_start_time DESC
LIMIT 50;

-- 1.3 Any failed refresh (expect 0 rows)
SELECT name, state, state_code, state_message, refresh_start_time
FROM TABLE(UAT2_WPA_ASSET_DB.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(ERROR_ONLY => TRUE))
WHERE name LIKE 'WPA_C%'
ORDER BY refresh_start_time DESC;


/* =============================================================================
   2. Pipeline row counts (info - compare against expectations below)
   ============================================================================= */
SELECT 'SRC  WPA_ASSET_DYN'          AS obj, COUNT(*) AS rows_cnt, COUNT(DISTINCT instr_id) AS instruments FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET_DYN
UNION ALL SELECT 'SRC  NPF_ASSET',              COUNT(*), COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET
UNION ALL SELECT 'DT1  WPA_CAS_ASSET_STD_DYN',  COUNT(*), COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN
UNION ALL SELECT 'DT2  WPA_CAS_RULE_PICK_DYN',  COUNT(*), NULL                     FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_RULE_PICK_DYN
UNION ALL SELECT 'DT3  WPA_CAS_CSTM_ROW_DYN',   COUNT(*), COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN
UNION ALL SELECT 'DT4  WPA_CAS_CUST_INSTR_DYN', COUNT(*), COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN
UNION ALL SELECT 'FINAL WPA_CSTM_..._DY',       COUNT(*), COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
UNION ALL SELECT 'SRC  NPF_CUST_CSTM_SCHEMA',   COUNT(*), NULL                     FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA;

-- 2.1 FINAL distinct customers / schemas vs NPF_CUST_CSTM_SCHEMA
SELECT
  (SELECT COUNT(DISTINCT cust_sk)   FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA)            AS src_customers,
  (SELECT COUNT(DISTINCT cust_sk)   FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY)   AS dt_customers,
  (SELECT COUNT(DISTINCT schema_id) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA)            AS src_schemas,
  (SELECT COUNT(DISTINCT schema_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY)   AS dt_schemas,
  (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA)                             AS src_cust_schema_pairs,
  (SELECT COUNT(*) FROM (SELECT DISTINCT cust_sk, schema_id
                         FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY))             AS dt_cust_schema_pairs;


/* =============================================================================
   3. DT1  WPA_CAS_ASSET_STD_DYN  (6-arg npf_asst_typ_mgr + country)
   ============================================================================= */
-- 3.1 One row per instrument, same instruments as WPA_ASSET_DYN (all 0)
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT instr_id) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN) AS dup_instr,
  (SELECT COUNT(*) FROM (SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET_DYN
                         EXCEPT SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN)) AS missing_in_dt1,
  (SELECT COUNT(*) FROM (SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN
                         EXCEPT SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_ASSET_DYN))        AS extra_in_dt1;

-- 3.2 Recompute standard category + country from NPF_ASSET (Oracle source) - expect 0
WITH exp AS (
    SELECT a.instr_id, a.iss_type,
           IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
           IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
           IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
           IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
           NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET a
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = a.iss_type
    LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d ON d.dcde_type = 'CNTRY' AND d.dcde_code = a.cntry_risk_dcde
    WHERE a.instr_id IN (SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN)
)
SELECT
  COUNT_IF(NOT EQUAL_NULL(e.iss_type,     t.iss_type))     AS diff_iss_type,
  COUNT_IF(NOT EQUAL_NULL(e.std_sup_code, t.std_sup_code)) AS diff_sup_code,
  COUNT_IF(NOT EQUAL_NULL(e.std_sub_code, t.std_sub_code)) AS diff_sub_code,
  COUNT_IF(NOT EQUAL_NULL(e.std_sup_desc, t.std_sup_desc)) AS diff_sup_desc,
  COUNT_IF(NOT EQUAL_NULL(e.std_sub_desc, t.std_sub_desc)) AS diff_sub_desc,
  COUNT_IF(NOT EQUAL_NULL(e.cntry_desc,   t.cntry_desc))   AS diff_cntry_desc,
  COUNT_IF(e.instr_id IS NULL)                             AS dt1_instr_not_in_npf_asset
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN t
LEFT JOIN exp e ON e.instr_id = t.instr_id;

-- 3.3 Join keys built correctly (all 0)
SELECT
  COUNT_IF(sup_desc_key   IS DISTINCT FROM NVL(std_sup_desc, '#NULL#')) AS bad_sup_key,
  COUNT_IF(sub_desc_key   IS DISTINCT FROM NVL(std_sub_desc, '#NULL#')) AS bad_sub_key,
  COUNT_IF(cntry_desc_key IS DISTINCT FROM NVL(cntry_desc,   '#NULL#')) AS bad_cntry_key,
  COUNT_IF(std_sup_desc = '' OR std_sub_desc = '' OR cntry_desc = '')   AS empty_strings
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN;

-- 3.4 Default category profile (info): unmapped ISS_TYPE -> 30 / 20 / Other Assets / Miscellaneous
SELECT IFF(ac.iss_type IS NULL, 'NO MAPPING -> DEFAULT', 'MAPPED') AS mapping,
       IFF(t.iss_type  IS NULL, 'NULL ISS_TYPE', 'ISS_TYPE SET')   AS iss_type_state,
       t.std_sup_code, t.std_sub_code, t.std_sup_desc, t.std_sub_desc,
       COUNT(*) AS instruments
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN t
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = t.iss_type
WHERE ac.iss_type IS NULL
GROUP BY ALL
ORDER BY instruments DESC;


/* =============================================================================
   4. DT3  WPA_CAS_CSTM_ROW_DYN  (v_rec_cnt + cstm_asset_cursor)
   ============================================================================= */
-- 4.1 DT3 = active WLT custom rows, 1 per (schema, instr) - all 0
SELECT
  (SELECT COUNT(*) FROM (SELECT schema_id, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN
                         GROUP BY 1,2 HAVING COUNT(*) > 1))                                  AS dup_in_dt3,
  (SELECT COUNT(*) FROM (SELECT DISTINCT schema_id, instr_id FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
                          WHERE rptg_type = 'WLT' AND end_dt IS NULL
                         EXCEPT SELECT schema_id, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN)) AS missing_in_dt3,
  (SELECT COUNT(*) FROM (SELECT schema_id, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN
                         EXCEPT SELECT schema_id, instr_id FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
                          WHERE rptg_type = 'WLT' AND end_dt IS NULL))                       AS extra_in_dt3;

-- 4.2 Source: (schema, instr) with >1 active custom row (Oracle order undefined; DT keeps latest START_DT)
--     expect 0 rows; if any, confirm with the business which row Oracle returns
SELECT schema_id, instr_id, COUNT(*) AS active_rows, MIN(start_dt), MAX(start_dt)
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
WHERE rptg_type = 'WLT' AND end_dt IS NULL
GROUP BY 1,2 HAVING COUNT(*) > 1
LIMIT 100;

-- 4.3 Ended rows (END_DT set) and non-WLT rows must NOT drive a custom row in FINAL (expect 0)
SELECT COUNT(*) AS ended_or_non_wlt_used
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
WHERE f.cstm_subcatg_code NOT LIKE '%-%-S'                               -- path 1 rows
  AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA c
                  WHERE c.schema_id = f.schema_id AND c.instr_id = f.instr_id
                    AND c.rptg_type = 'WLT' AND c.end_dt IS NULL);


/* =============================================================================
   5. DT4  WPA_CAS_CUST_INSTR_DYN  (positions any date + transactions)
   ============================================================================= */
-- 5.1 DT4 = distinct (cust_sk, instr_id) of positions UNION transactions - all 0
WITH src AS (
    SELECT cust_sk, instr_id FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION
     WHERE cust_sk IS NOT NULL AND instr_id IS NOT NULL
    UNION
    SELECT cust_sk, instr_id FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION
     WHERE cust_sk IS NOT NULL AND instr_id IS NOT NULL
)
SELECT
  (SELECT COUNT(*) FROM src)                                                                    AS src_pairs,
  (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN)                          AS dt4_pairs,
  (SELECT COUNT(*) FROM (SELECT * FROM src EXCEPT
                         SELECT cust_sk, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN)) AS missing_in_dt4,
  (SELECT COUNT(*) FROM (SELECT cust_sk, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN
                         EXCEPT SELECT * FROM src))                                             AS extra_in_dt4,
  (SELECT COUNT(*) FROM (SELECT cust_sk, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN
                         GROUP BY 1,2 HAVING COUNT(*) > 1))                                     AS dup_in_dt4;

-- 5.2 DT4 instruments that are NOT in DT1 (would get no FINAL row)
--     in_npf_asset > 0 means WPA_ASSET_DYN filters differently (e.g. other transaction table) -> investigate
SELECT IFF(n.instr_id IS NULL, 'NOT IN NPF_ASSET (Oracle also has no row)',
                               'IN NPF_ASSET BUT NOT IN WPA_ASSET_DYN (gap!)') AS reason,
       COUNT(*) AS cust_instr_pairs, COUNT(DISTINCT ci.instr_id) AS instruments
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN ci
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET n ON n.instr_id = ci.instr_id
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN a WHERE a.instr_id = ci.instr_id)
GROUP BY 1;


/* =============================================================================
   6. CUSTOMER validations
   ============================================================================= */
-- 6.1 Per customer + schema: FINAL rows = customer's distinct instruments that exist in DT1
--     (expect 0 rows)
WITH exp AS (
    SELECT s.schema_id, s.cust_sk, COUNT(*) AS exp_rows
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
    JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN ci ON ci.cust_sk = s.cust_sk
    JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN  a  ON a.instr_id = ci.instr_id
    WHERE ($V_SCHEMA_ID IS NULL OR s.schema_id = $V_SCHEMA_ID)
    GROUP BY 1,2
),
dt AS (
    SELECT schema_id, cust_sk, COUNT(*) AS dt_rows
    FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
    GROUP BY 1,2
)
SELECT COALESCE(e.schema_id, d.schema_id) AS schema_id,
       COALESCE(e.cust_sk,   d.cust_sk)   AS cust_sk,
       e.exp_rows, d.dt_rows
FROM exp e FULL OUTER JOIN dt d ON d.schema_id = e.schema_id AND d.cust_sk = e.cust_sk
WHERE NOT EQUAL_NULL(e.exp_rows, d.dt_rows)
ORDER BY 1,2
LIMIT 100;

-- 6.2 Customer gets an instrument they never held / transacted (expect 0)
SELECT COUNT(*) AS rows_not_owned_by_customer
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION p
                  WHERE p.cust_sk = f.cust_sk AND p.instr_id = f.instr_id)
  AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION t
                  WHERE t.cust_sk = f.cust_sk AND t.instr_id = f.instr_id);

-- 6.3 (cust_sk, schema_id) in FINAL but not in NPF_CUST_CSTM_SCHEMA (expect 0)
SELECT COUNT(*) AS cust_schema_not_in_source
FROM (SELECT DISTINCT cust_sk, schema_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY) f
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
                  WHERE s.cust_sk = f.cust_sk AND s.schema_id = f.schema_id);

-- 6.4 Customers with a schema but NO rows in FINAL - split by reason (info)
SELECT CASE
         WHEN NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN ci WHERE ci.cust_sk = s.cust_sk)
              THEN 'NO POSITIONS / TRANSACTIONS'
         ELSE 'HAS INSTRUMENTS BUT NONE IN DT1 (check 5.2)'
       END AS reason,
       COUNT(*) AS cust_schema_pairs, COUNT(DISTINCT s.cust_sk) AS customers
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
                  WHERE f.cust_sk = s.cust_sk AND f.schema_id = s.schema_id)
GROUP BY 1;

-- 6.5 Customers on several schemas: same instruments on every schema (expect 0 rows)
SELECT cust_sk, COUNT(DISTINCT schema_id) AS schemas,
       MIN(instr_cnt) AS min_instr, MAX(instr_cnt) AS max_instr
FROM (SELECT cust_sk, schema_id, COUNT(*) AS instr_cnt
      FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY GROUP BY 1,2)
GROUP BY cust_sk
HAVING COUNT(DISTINCT schema_id) > 1 AND MIN(instr_cnt) <> MAX(instr_cnt)
LIMIT 100;

-- 6.6 One customer end to end ($V_CUST_SK): source instruments vs FINAL per schema
SELECT
  (SELECT COUNT(DISTINCT instr_id) FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION   WHERE cust_sk = $V_CUST_SK) AS position_instr,
  (SELECT COUNT(DISTINCT instr_id) FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION WHERE cust_sk = $V_CUST_SK) AS txn_instr,
  (SELECT COUNT(*) FROM (SELECT instr_id FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION   WHERE cust_sk = $V_CUST_SK
                         UNION
                         SELECT instr_id FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION WHERE cust_sk = $V_CUST_SK)) AS union_instr,
  (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN WHERE cust_sk = $V_CUST_SK)                AS dt4_instr,
  (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CUST_INSTR_DYN ci
     JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN a ON a.instr_id = ci.instr_id
    WHERE ci.cust_sk = $V_CUST_SK)                                                                               AS expected_per_schema,
  (SELECT COUNT(DISTINCT schema_id) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA WHERE cust_sk = $V_CUST_SK) AS schemas;

SELECT schema_id, COUNT(*) AS final_rows, COUNT(DISTINCT instr_id) AS final_instr
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE cust_sk = $V_CUST_SK
GROUP BY 1 ORDER BY 1;

-- 6.7 p_cust_sk is unused by Oracle: all customers on a schema get identical values
--     for the same instrument (expect 0 rows)
SELECT schema_id, instr_id, COUNT(DISTINCT cust_sk) AS customers,
       COUNT(DISTINCT HASH(supcatg_code, subcatg_code, supcatg_desc, subcatg_desc,
                           cstm_supcatg_code, cstm_subcatg_code)) AS distinct_results
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
GROUP BY 1,2
HAVING distinct_results > 1
LIMIT 100;

-- 6.8 Top 20 customers by FINAL rows (info - sanity on size)
SELECT cust_sk, COUNT(DISTINCT schema_id) AS schemas, COUNT(*) AS rows_cnt, COUNT(DISTINCT instr_id) AS instruments
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
GROUP BY 1 ORDER BY rows_cnt DESC LIMIT 20;


/* =============================================================================
   7. Expected result - INDEPENDENT Oracle re-implementation from base tables
      (does NOT read any WPA_CAS_* DT; rules evaluated PER INSTRUMENT)
   ============================================================================= */
CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED AS
WITH
hold AS (                                     -- caller loop: positions any date + transactions
    SELECT p.cust_sk, p.instr_id FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION p
     WHERE p.instr_id IS NOT NULL AND p.cust_sk IS NOT NULL
    UNION
    SELECT t.cust_sk, t.instr_id FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION t
     WHERE t.instr_id IS NOT NULL AND t.cust_sk IS NOT NULL
),
ast AS (                                      -- NPF_ASSET as read by the Oracle proc
    SELECT a.instr_id, a.iss_type, a.cntry_risk_dcde
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET a
    WHERE a.instr_id IN (SELECT instr_id FROM hold)
),
std AS (                                      -- 6-arg npf_asst_typ_mgr + get_cstm_cntry_risk_desc
    SELECT ast.instr_id, ast.iss_type,
           IFF(ac.iss_type IS NULL, 'Y', 'N')                                      AS default_catg,
           IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
           IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
           IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
           IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
           NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
    FROM ast
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac ON ac.rptg_type = 'WLT' AND ac.iss_type = ast.iss_type
    LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d ON d.dcde_type = 'CNTRY' AND d.dcde_code = ast.cntry_risk_dcde
),
sch AS (
    SELECT cust_sk, schema_id, schema_desc
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
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
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
    WHERE rptg_type = 'WLT' AND end_dt IS NULL
      AND ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id ORDER BY start_dt DESC) = 1
),
grid AS (                                     -- one row per npf_asst_typ_mgr call
    SELECT s.cust_sk, s.schema_id, s.schema_desc, t.*
    FROM sch s
    JOIN hold h ON h.cust_sk  = s.cust_sk
    JOIN std  t ON t.instr_id = h.instr_id
),
need_rules AS (                               -- (schema, instr) going to RULE_EVALUATION
    SELECT DISTINCT g.schema_id, g.instr_id, g.std_sup_desc, g.std_sub_desc, g.cntry_desc
    FROM grid g
    WHERE NOT EXISTS (SELECT 1 FROM cs WHERE cs.schema_id = g.schema_id AND cs.instr_id = g.instr_id)
),
cond_eval AS (
    SELECT n.schema_id, n.instr_id, r.rule_sk,
           NULLIF(r.rule_cstm_supcatg_desc, '') AS rule_sup_desc,
           NULLIF(r.rule_cstm_subcatg_desc, '') AS rule_sub_desc,
           c.cond_sk, c.logical_oper, c.rule_fld_name, c.rule_oper,
           CASE c.rule_fld_name
                WHEN 'CSTM_SUPCATG_DESC'    THEN n.std_sup_desc
                WHEN 'CSTM_SUBCATG_DESC'    THEN n.std_sub_desc
                WHEN 'CSTM_CNTRY_RISK_DESC' THEN n.cntry_desc
           END                                  AS fld_val,
           NULLIF(c.rule_fld_value, '')         AS rule_fld_value
    FROM need_rules n
    JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r ON r.schema_id = n.schema_id AND r.rule_stat = 'A'
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
),
rule_match AS (
    SELECT schema_id, instr_id, rule_sk, rule_sup_desc, rule_sub_desc,
           BOOLOR_AGG(COALESCE(logical_oper = 'OR', FALSE)) AS has_or,
           COUNT(cond_sk)                                   AS n_cond,
           COUNT_IF(COALESCE(CASE rule_oper
                                  WHEN 'EQUAL'    THEN fld_val =  rule_fld_value
                                  WHEN 'NOTEQUAL' THEN fld_val <> rule_fld_value
                             END, FALSE))                   AS n_true
    FROM cond_eval
    GROUP BY 1,2,3,4,5
),
matched AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id ORDER BY rule_sk ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY schema_id, instr_id ORDER BY rule_sk DESC) AS rn_last,
           COUNT(*)     OVER (PARTITION BY schema_id, instr_id)                       AS n_match
    FROM rule_match
    WHERE (has_or AND n_true > 0) OR (NOT has_or AND n_true = n_cond)
),
rule_out AS (
    SELECT schema_id, instr_id, MAX(n_match) AS n_match,
           MAX(IFF(rn_first = 1, rule_sup_desc, NULL))                 AS d1_sup,
           MAX(IFF(rn_first = 1, rule_sub_desc, NULL))                 AS d1_sub,
           MAX(IFF(rn_last  = 1 AND n_match > 1, rule_sup_desc, NULL)) AS d2_sup,
           MAX(IFF(rn_last  = 1 AND n_match > 1, rule_sub_desc, NULL)) AS d2_sub,
           MAX(IFF(rn_last  = 1 AND n_match > 1 AND rule_sup_desc IS NULL, 1, 0)) AS last_sup_null,
           MAX(IFF(rn_last  = 1 AND n_match > 1 AND rule_sub_desc IS NULL, 1, 0)) AS last_sub_null,
           MAX(IFF(rn_first = 1 AND has_or, 1, 0))                     AS first_is_or,
           MAX(IFF(rn_first = 1 AND n_cond = 0, 1, 0))                 AS first_zero_cond
    FROM matched
    GROUP BY 1,2
)
SELECT
    g.schema_id, g.cust_sk, g.instr_id, 'WLT' AS rptg_type, g.iss_type,
    g.std_sup_code AS supcatg_code,
    g.std_sub_code AS subcatg_code,
    CASE WHEN cs.schema_id IS NOT NULL THEN cs.cstm_supcatg_desc
         ELSE COALESCE(ro.d2_sup, ro.d1_sup, g.std_sup_desc) END AS supcatg_desc,
    CASE WHEN cs.schema_id IS NOT NULL THEN cs.cstm_subcatg_desc
         ELSE COALESCE(ro.d2_sub, ro.d1_sub, g.std_sub_desc) END AS subcatg_desc,
    CASE
      WHEN cs.schema_id IS NULL                                                  THEN NVL(g.std_sup_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL THEN NVL(cs.npf_supcatg_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL     THEN cs.cstm_supcatg_code || '-C'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NULL     THEN NVL(cs.npf_supcatg_code,'') || '-S'
      ELSE                                                                            cs.cstm_supcatg_code || '-C'
    END AS cstm_supcatg_code,
    CASE
      WHEN cs.schema_id IS NULL                                                  THEN NVL(g.std_sup_code,'') || '-' || NVL(g.std_sub_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL THEN cs.cstm_subcatg_code || '-C'
      WHEN cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL     THEN NVL(cs.npf_subcatg_code,'') || '-S'
      WHEN cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NULL     THEN NVL(cs.npf_subcatg_code,'') || '-S'
      ELSE                                                                            cs.cstm_subcatg_code || '-C'
    END AS cstm_subcatg_code,
    g.schema_desc,
    CASE
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NOT NULL THEN 'P1-CC'
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NULL     AND cs.cstm_subcatg_code IS NOT NULL THEN 'P1-SC'
      WHEN cs.schema_id IS NOT NULL AND cs.cstm_supcatg_code IS NOT NULL AND cs.cstm_subcatg_code IS NULL     THEN 'P1-CS'
      WHEN cs.schema_id IS NOT NULL                                                                           THEN 'P1-SS'
      WHEN ro.n_match = 1                                                                                     THEN 'P2-R1'
      WHEN ro.n_match > 1                                                                                     THEN 'P2-RN'
      ELSE                                                                                                         'P2-STD'
    END AS scenario,
    -- edge-case flags
    g.default_catg,
    IFF(g.cntry_desc IS NULL, 'Y', 'N')                                       AS no_cntry,
    IFF(g.iss_type   IS NULL, 'Y', 'N')                                       AS null_iss_type,
    IFF(cs.schema_id IS NOT NULL AND (cs.cstm_supcatg_desc IS NULL OR cs.cstm_subcatg_desc IS NULL), 'Y', 'N') AS cstm_desc_null,
    IFF(NVL(ro.last_sup_null,0) = 1 OR NVL(ro.last_sub_null,0) = 1, 'Y', 'N') AS rn_col_fallback,
    IFF(NVL(ro.first_is_or,0)     = 1, 'Y', 'N')                             AS or_rule,
    IFF(NVL(ro.first_zero_cond,0) = 1, 'Y', 'N')                             AS zero_cond_rule,
    NVL(ro.n_match, 0)                                                        AS n_rules_matched
FROM grid g
LEFT JOIN cs          ON cs.schema_id = g.schema_id AND cs.instr_id = g.instr_id
LEFT JOIN rule_out ro ON ro.schema_id = g.schema_id AND ro.instr_id = g.instr_id;


/* =============================================================================
   8. Full compare  DT vs expected
   ============================================================================= */
CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF AS
SELECT
    COALESCE(e.schema_id, d.schema_id) AS schema_id,
    COALESCE(e.cust_sk,   d.cust_sk)   AS cust_sk,
    COALESCE(e.instr_id,  d.instr_id)  AS instr_id,
    e.scenario, e.default_catg, e.no_cntry, e.null_iss_type, e.cstm_desc_null,
    e.rn_col_fallback, e.or_rule, e.zero_cond_rule, e.n_rules_matched,
    CASE WHEN d.instr_id IS NULL THEN 'MISSING_IN_DT'
         WHEN e.instr_id IS NULL THEN 'EXTRA_IN_DT'
         ELSE 'BOTH' END                                         AS presence,
    NOT EQUAL_NULL(e.iss_type,          d.iss_type)              AS diff_iss_type,
    NOT EQUAL_NULL(e.supcatg_code,      d.supcatg_code)          AS diff_sup_code,
    NOT EQUAL_NULL(e.subcatg_code,      d.subcatg_code)          AS diff_sub_code,
    NOT EQUAL_NULL(e.supcatg_desc,      d.supcatg_desc)          AS diff_sup_desc,
    NOT EQUAL_NULL(e.subcatg_desc,      d.subcatg_desc)          AS diff_sub_desc,
    NOT EQUAL_NULL(e.cstm_supcatg_code, d.cstm_supcatg_code)     AS diff_cstm_sup_code,
    NOT EQUAL_NULL(e.cstm_subcatg_code, d.cstm_subcatg_code)     AS diff_cstm_sub_code,
    NOT EQUAL_NULL(e.supcatg_desc,      d.cstm_supcatg_desc)     AS diff_cstm_sup_desc,
    NOT EQUAL_NULL(e.subcatg_desc,      d.cstm_subcatg_desc)     AS diff_cstm_sub_desc,
    NOT EQUAL_NULL(e.schema_desc,       d.schema_desc)           AS diff_schema_desc,
    e.supcatg_code      AS exp_sup_code,      d.supcatg_code      AS dt_sup_code,
    e.subcatg_code      AS exp_sub_code,      d.subcatg_code      AS dt_sub_code,
    e.supcatg_desc      AS exp_sup_desc,      d.supcatg_desc      AS dt_sup_desc,
    e.subcatg_desc      AS exp_sub_desc,      d.subcatg_desc      AS dt_sub_desc,
    e.cstm_supcatg_code AS exp_cstm_sup_code, d.cstm_supcatg_code AS dt_cstm_sup_code,
    e.cstm_subcatg_code AS exp_cstm_sub_code, d.cstm_subcatg_code AS dt_cstm_sub_code
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED e
FULL OUTER JOIN (SELECT * FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
                 WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)) d
  ON d.schema_id = e.schema_id AND d.cust_sk = e.cust_sk AND d.instr_id = e.instr_id;

-- 8.1 Overall (expect presence only BOTH, every diff column 0)
--     MISSING_IN_DT here usually = check 5.2 'gap' rows (instrument not in WPA_ASSET_DYN)
SELECT presence, COUNT(*) AS rows_cnt,
       COUNT_IF(diff_iss_type)      AS iss_type,
       COUNT_IF(diff_sup_code)      AS sup_code,
       COUNT_IF(diff_sub_code)      AS sub_code,
       COUNT_IF(diff_sup_desc)      AS sup_desc,
       COUNT_IF(diff_sub_desc)      AS sub_desc,
       COUNT_IF(diff_cstm_sup_code) AS cstm_sup_code,
       COUNT_IF(diff_cstm_sub_code) AS cstm_sub_code,
       COUNT_IF(diff_cstm_sup_desc) AS cstm_sup_desc,
       COUNT_IF(diff_cstm_sub_desc) AS cstm_sub_desc,
       COUNT_IF(diff_schema_desc)   AS schema_desc
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
GROUP BY presence;

-- 8.2 Mismatches by scenario + edge flags (expect all *_diff = 0)
SELECT scenario, default_catg, no_cntry, null_iss_type, cstm_desc_null, rn_col_fallback, or_rule, zero_cond_rule,
       COUNT(*) AS rows_cnt,
       COUNT_IF(diff_sup_code OR diff_sub_code)           AS std_code_diff,
       COUNT_IF(diff_sup_desc OR diff_sub_desc)           AS desc_diff,
       COUNT_IF(diff_cstm_sup_code OR diff_cstm_sub_code) AS cstm_code_diff
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence = 'BOTH'
GROUP BY ALL
ORDER BY 1,2,3,4,5,6,7,8;

-- 8.3 Mismatch detail (first 200)
SELECT schema_id, cust_sk, instr_id, scenario, presence, n_rules_matched,
       exp_sup_code, dt_sup_code, exp_sub_code, dt_sub_code,
       exp_sup_desc, dt_sup_desc, exp_sub_desc, dt_sub_desc,
       exp_cstm_sup_code, dt_cstm_sup_code, exp_cstm_sub_code, dt_cstm_sub_code
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence <> 'BOTH'
   OR diff_iss_type OR diff_sup_code OR diff_sub_code OR diff_sup_desc OR diff_sub_desc
   OR diff_cstm_sup_code OR diff_cstm_sub_code OR diff_cstm_sup_desc OR diff_cstm_sub_desc OR diff_schema_desc
ORDER BY scenario, schema_id, instr_id
LIMIT 200;

-- 8.4 Mismatches per customer (which customers are affected; expect 0 rows)
SELECT cust_sk, COUNT(DISTINCT schema_id) AS schemas, COUNT(*) AS bad_rows,
       COUNT_IF(presence = 'MISSING_IN_DT') AS missing, COUNT_IF(presence = 'EXTRA_IN_DT') AS extra
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence <> 'BOTH'
   OR diff_sup_code OR diff_sub_code OR diff_sup_desc OR diff_sub_desc
   OR diff_cstm_sup_code OR diff_cstm_sub_code
GROUP BY 1 ORDER BY bad_rows DESC LIMIT 100;


/* =============================================================================
   9. Scenario coverage + samples
   ============================================================================= */
-- 9.1 Coverage per Oracle branch (0 = path not tested in this data)
WITH s AS (SELECT column1 AS scenario FROM VALUES
           ('P1-CC'),('P1-SC'),('P1-CS'),('P1-SS'),('P2-R1'),('P2-RN'),('P2-STD'))
SELECT s.scenario,
       COUNT(e.instr_id)               AS rows_cnt,
       COUNT(DISTINCT e.schema_id)     AS schemas,
       COUNT(DISTINCT e.cust_sk)       AS customers,
       COUNT(DISTINCT e.instr_id)      AS instruments,
       COUNT_IF(e.default_catg   = 'Y') AS default_catg,
       COUNT_IF(e.no_cntry       = 'Y') AS no_cntry,
       COUNT_IF(e.null_iss_type  = 'Y') AS null_iss_type,
       COUNT_IF(e.cstm_desc_null = 'Y') AS cstm_desc_null,
       COUNT_IF(e.rn_col_fallback= 'Y') AS rn_col_fallback,
       COUNT_IF(e.or_rule        = 'Y') AS or_rule,
       COUNT_IF(e.zero_cond_rule = 'Y') AS zero_cond_rule
FROM s LEFT JOIN UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED e ON e.scenario = s.scenario
GROUP BY s.scenario ORDER BY s.scenario;

-- 9.2 Scenario mix per schema (info)
SELECT schema_id, COUNT(DISTINCT cust_sk) AS customers, COUNT(*) AS rows_cnt,
       COUNT_IF(scenario = 'P1-CC') AS p1_cc, COUNT_IF(scenario = 'P1-SC') AS p1_sc,
       COUNT_IF(scenario = 'P1-CS') AS p1_cs, COUNT_IF(scenario = 'P1-SS') AS p1_ss,
       COUNT_IF(scenario = 'P2-R1') AS p2_r1, COUNT_IF(scenario = 'P2-RN') AS p2_rn,
       COUNT_IF(scenario = 'P2-STD') AS p2_std
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED
GROUP BY 1 ORDER BY rows_cnt DESC LIMIT 100;

-- 9.3 Three samples per scenario, expected vs DT side by side (use these to spot-check in Oracle)
SELECT scenario, schema_id, cust_sk, instr_id, n_rules_matched,
       exp_sup_code, dt_sup_code, exp_sub_code, dt_sub_code,
       exp_sup_desc, dt_sup_desc, exp_sub_desc, dt_sub_desc,
       exp_cstm_sup_code, dt_cstm_sup_code, exp_cstm_sub_code, dt_cstm_sub_code
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence = 'BOTH'
QUALIFY ROW_NUMBER() OVER (PARTITION BY scenario ORDER BY schema_id, instr_id) <= 3
ORDER BY scenario, schema_id, instr_id;

-- 9.4 Same samples as ready-to-paste Oracle calls (11-arg proc, see Oracle test block)
SELECT scenario,
       'SELECT ''' || scenario || ''' scn, ' || schema_id || ' schema_id, ''' || instr_id ||
       ''' instr_id FROM dual UNION ALL' AS oracle_line
FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF
WHERE presence = 'BOTH'
QUALIFY ROW_NUMBER() OVER (PARTITION BY scenario ORDER BY schema_id, instr_id) <= 3
ORDER BY scenario;


/* =============================================================================
   10. DT2  WPA_CAS_RULE_PICK_DYN  (RULE_EVALUATION per desc combo)
   ============================================================================= */
-- 10.1 DT2 vs expected rule output: aggregate expected per (schema, desc combo) - expect 0
--      (all instruments with the same std sup/sub/country desc must get the same rule result)
WITH exp AS (
    SELECT e.schema_id,
           NVL(s.std_sup_desc,'#NULL#') AS sup_k, NVL(s.std_sub_desc,'#NULL#') AS sub_k,
           NVL(s.cntry_desc,'#NULL#')   AS cntry_k,
           COUNT(DISTINCT HASH(e.supcatg_desc, e.subcatg_desc)) AS distinct_outputs
    FROM UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED e
    JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN s ON s.instr_id = e.instr_id
    WHERE e.scenario LIKE 'P2%'
    GROUP BY 1,2,3,4
)
SELECT COUNT_IF(distinct_outputs > 1) AS combos_with_inconsistent_rule_result
FROM exp;

-- 10.2 Rule profile in source (info): rules per schema, AND/OR, zero-condition, inactive
SELECT r.schema_id,
       COUNT(DISTINCT r.rule_sk)                                         AS rules,
       COUNT(DISTINCT IFF(r.rule_stat = 'A', r.rule_sk, NULL))           AS active_rules,
       COUNT(DISTINCT IFF(r.rule_stat <> 'A', r.rule_sk, NULL))          AS inactive_rules,
       COUNT(DISTINCT IFF(c.logical_oper = 'OR', r.rule_sk, NULL))       AS or_rules,
       COUNT(DISTINCT IFF(c.cond_sk IS NULL, r.rule_sk, NULL))           AS zero_cond_rules,
       COUNT(DISTINCT IFF(c.rule_oper = 'NOTEQUAL', r.rule_sk, NULL))    AS notequal_rules,
       COUNT(c.cond_sk)                                                  AS conditions
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
GROUP BY 1 ORDER BY 1;

-- 10.3 Inactive rules never used: no P2 row in FINAL carries a desc that only an inactive rule has
--      (expect 0)
SELECT COUNT(*) AS rows_using_inactive_rule_desc
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN s ON s.instr_id = f.instr_id
WHERE f.cstm_subcatg_code LIKE '%-%-S'
  AND f.supcatg_desc IS DISTINCT FROM s.std_sup_desc
  AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
                  WHERE r.schema_id = f.schema_id AND r.rule_stat = 'A'
                    AND r.rule_cstm_supcatg_desc = f.supcatg_desc);

-- 10.4 Unknown field names / operators in conditions (Oracle never matches them) - info
SELECT rule_fld_name, rule_oper, logical_oper, COUNT(*) AS conditions
FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND
GROUP BY ALL ORDER BY conditions DESC;

-- 10.5 Trace one schema's rules (pick a P2-RN / OR row from 9.3)
-- SET V_TRACE_SCHEMA = <schema_id>;
-- SELECT r.rule_sk, r.rule_name, r.rule_stat, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc,
--        c.cond_order, c.logical_oper, c.rule_fld_name, c.rule_oper, c.rule_fld_value
-- FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
-- LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c ON c.rule_sk = r.rule_sk
-- WHERE r.schema_id = $V_TRACE_SCHEMA
-- ORDER BY r.rule_sk, c.cond_order;


/* =============================================================================
   11. Oracle edge cases - source profile and DT behaviour
   ============================================================================= */
-- 11.1 Source-data edge-case profile (info; tells which edge paths exist in UAT2)
SELECT 'Instrument with NULL ISS_TYPE (-> default 30/20)'           AS edge_case,
       COUNT(*) AS cnt FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN WHERE iss_type IS NULL
UNION ALL SELECT 'ISS_TYPE without WLT mapping (-> default 30/20)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN t
       WHERE t.iss_type IS NOT NULL AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
                                                    WHERE ac.rptg_type = 'WLT' AND ac.iss_type = t.iss_type)
UNION ALL SELECT 'Mapping row with NULL/empty desc (FETCH overwrites default with NULL)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG
       WHERE rptg_type = 'WLT' AND (NULLIF(supcatg_desc,'') IS NULL OR NULLIF(subcatg_desc,'') IS NULL)
UNION ALL SELECT 'Duplicate WLT mapping per ISS_TYPE (Oracle TOO_MANY_ROWS)',
       COUNT(*) FROM (SELECT iss_type FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG WHERE rptg_type = 'WLT'
                      GROUP BY 1 HAVING COUNT(*) > 1)
UNION ALL SELECT 'Instrument with no country desc (rule on country never matches)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN WHERE cntry_desc IS NULL
UNION ALL SELECT 'Duplicate INSTR_ID in NPF_ASSET (Oracle TOO_MANY_ROWS)',
       COUNT(*) FROM (SELECT instr_id FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET GROUP BY 1 HAVING COUNT(*) > 1)
UNION ALL SELECT 'Active custom row whose instrument is not in NPF_ASSET (Oracle: defaults, NULL cstm codes)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA c
       WHERE c.rptg_type = 'WLT' AND c.end_dt IS NULL
         AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET a WHERE a.instr_id = c.instr_id)
UNION ALL SELECT 'Active custom row with NULL custom desc (kept NULL, as Oracle)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
       WHERE rptg_type = 'WLT' AND end_dt IS NULL
         AND (NULLIF(cstm_supcatg_desc,'') IS NULL OR NULLIF(cstm_subcatg_desc,'') IS NULL)
UNION ALL SELECT 'Active custom row with NULL npf code (-> code "-S")',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA
       WHERE rptg_type = 'WLT' AND end_dt IS NULL
         AND (NULLIF(npf_supcatg_code,'') IS NULL OR NULLIF(npf_subcatg_code,'') IS NULL)
UNION ALL SELECT 'Ended custom rows (END_DT set, ignored)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA WHERE rptg_type = 'WLT' AND end_dt IS NOT NULL
UNION ALL SELECT 'Non-WLT custom rows (ignored)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA WHERE rptg_type <> 'WLT'
UNION ALL SELECT 'Active rules with ZERO conditions (Oracle: MATCH)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
       WHERE r.rule_stat = 'A' AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c WHERE c.rule_sk = r.rule_sk)
UNION ALL SELECT 'Rules mixing AND + OR conditions (Oracle: whole rule = OR)',
       COUNT(*) FROM (SELECT rule_sk FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND
                      GROUP BY 1 HAVING COUNT_IF(logical_oper = 'OR') > 0 AND COUNT_IF(NVL(logical_oper,'AND') <> 'OR') > 0)
UNION ALL SELECT 'Active rules with NULL result desc (P2-RN per-column fallback)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR
       WHERE rule_stat = 'A' AND (NULLIF(rule_cstm_supcatg_desc,'') IS NULL OR NULLIF(rule_cstm_subcatg_desc,'') IS NULL)
UNION ALL SELECT 'Conditions with NULL/empty value (never match)',
       COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND WHERE NULLIF(rule_fld_value,'') IS NULL
UNION ALL SELECT 'Schemas with customers but no rules and no custom rows (all P2-STD)',
       COUNT(*) FROM (SELECT DISTINCT schema_id FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
                      WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r WHERE r.schema_id = s.schema_id)
                        AND NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA c WHERE c.schema_id = s.schema_id));

-- 11.2 Default category in FINAL: unmapped ISS_TYPE rows carry 30/20 + defaults (expect 0 wrong)
SELECT COUNT(*) AS default_rows_wrong
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
                  WHERE ac.rptg_type = 'WLT' AND ac.iss_type = f.iss_type)
  AND (f.supcatg_code <> '30' OR f.subcatg_code <> '20'
       OR (f.cstm_subcatg_code LIKE '%-%-S' AND f.cstm_subcatg_code <> '30-20-S'));

-- 11.3 Custom row with NULL custom desc stays NULL in FINAL (not replaced by standard) - expect 0
SELECT COUNT(*) AS cstm_null_desc_replaced
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN c ON c.schema_id = f.schema_id AND c.instr_id = f.instr_id
WHERE (c.cstm_supcatg_desc IS NULL AND f.supcatg_desc IS NOT NULL)
   OR (c.cstm_subcatg_desc IS NULL AND f.subcatg_desc IS NOT NULL);


/* =============================================================================
   12. Structural / format checks on FINAL
   ============================================================================= */
-- 12.1 Duplicate keys (expect 0 rows)
SELECT schema_id, cust_sk, instr_id, COUNT(*) AS cnt
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
GROUP BY 1,2,3 HAVING COUNT(*) > 1
LIMIT 100;

-- 12.2 NULL / format counts (0 unless explained by 11.1)
SELECT
  COUNT(*)                                                                     AS total_rows,
  COUNT_IF(schema_id IS NULL OR cust_sk IS NULL OR instr_id IS NULL)           AS null_keys,
  COUNT_IF(rptg_type IS DISTINCT FROM 'WLT')                                   AS non_wlt,
  COUNT_IF(supcatg_code IS NULL)                                               AS null_sup_code,
  COUNT_IF(subcatg_code IS NULL)                                               AS null_sub_code,
  COUNT_IF(supcatg_desc IS NULL)                                               AS null_sup_desc,
  COUNT_IF(subcatg_desc IS NULL)                                               AS null_sub_desc,
  COUNT_IF(cstm_supcatg_code IS NULL OR cstm_subcatg_code IS NULL)             AS null_cstm_code,
  COUNT_IF(NOT (cstm_supcatg_code LIKE '%-S' OR cstm_supcatg_code LIKE '%-C')) AS bad_sup_suffix,
  COUNT_IF(NOT (cstm_subcatg_code LIKE '%-S' OR cstm_subcatg_code LIKE '%-C')) AS bad_sub_suffix,
  COUNT_IF(cstm_supcatg_desc IS DISTINCT FROM supcatg_desc)                    AS cstm_sup_desc_ne_desc,
  COUNT_IF(cstm_subcatg_desc IS DISTINCT FROM subcatg_desc)                    AS cstm_sub_desc_ne_desc,
  COUNT_IF(schema_desc IS NULL)                                                AS null_schema_desc,
  COUNT_IF(supcatg_desc = '' OR subcatg_desc = '' OR schema_desc = '')         AS empty_strings
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY;

-- 12.3 Path 2 code pattern: '<sup>-S' and '<sup>-<sub>-S' built from standard codes (expect 0)
SELECT COUNT(*) AS bad_path2_codes
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
WHERE NOT EXISTS (SELECT 1 FROM UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN c
                  WHERE c.schema_id = f.schema_id AND c.instr_id = f.instr_id)
  AND (f.cstm_supcatg_code IS DISTINCT FROM NVL(f.supcatg_code,'') || '-S'
       OR f.cstm_subcatg_code IS DISTINCT FROM NVL(f.supcatg_code,'') || '-' || NVL(f.subcatg_code,'') || '-S');

-- 12.4 Path split (info)
SELECT IFF(c.schema_id IS NULL, 'PATH 2 rule / standard', 'PATH 1 custom row') AS path,
       COUNT(*) AS rows_cnt, COUNT(DISTINCT f.cust_sk) AS customers
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
LEFT JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_CSTM_ROW_DYN c ON c.schema_id = f.schema_id AND c.instr_id = f.instr_id
GROUP BY 1;

-- 12.5 Standard codes = DT1 for every row (codes never come from custom/rule) - expect 0
SELECT COUNT(*) AS std_code_not_from_dt1
FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY f
JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CAS_ASSET_STD_DYN s ON s.instr_id = f.instr_id
WHERE NOT EQUAL_NULL(f.supcatg_code, s.std_sup_code)
   OR NOT EQUAL_NULL(f.subcatg_code, s.std_sub_code)
   OR NOT EQUAL_NULL(f.iss_type,     s.iss_type);


/* =============================================================================
   13. Optional: compare with old proc-loaded table WPA_CSTM_ASSET_SCHEMA_CATG
       (old key has no CUST_SK -> compare on schema + instr for common instruments;
        diffs can be old-proc gaps / stale rows - confirm with section 8 first)
   ============================================================================= */
WITH dt AS (
    SELECT DISTINCT schema_id, instr_id, rptg_type, iss_type, supcatg_code, subcatg_code,
           supcatg_desc, subcatg_desc, cstm_supcatg_code, cstm_subcatg_code
    FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
),
old AS (
    SELECT DISTINCT schema_id, instr_id, rptg_type, iss_type, supcatg_code, subcatg_code,
           supcatg_desc, subcatg_desc, cstm_supcatg_code, cstm_subcatg_code
    FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG
    WHERE ($V_SCHEMA_ID IS NULL OR schema_id = $V_SCHEMA_ID)
      AND (schema_id, instr_id) IN (SELECT schema_id, instr_id FROM dt)
)
SELECT 'ONLY_IN_OLD' AS side, * FROM (SELECT * FROM old EXCEPT SELECT * FROM dt)
UNION ALL
SELECT 'ONLY_IN_DT'  AS side, * FROM (
    SELECT * FROM dt WHERE (schema_id, instr_id) IN (SELECT schema_id, instr_id FROM old)
    EXCEPT SELECT * FROM old)
ORDER BY schema_id, instr_id, side
LIMIT 200;

-- Cleanup
-- DROP TABLE IF EXISTS UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_EXPECTED;
-- DROP TABLE IF EXISTS UAT2_WPA_ASSET_DB.CORE.VAL_CSTM_DIFF;
