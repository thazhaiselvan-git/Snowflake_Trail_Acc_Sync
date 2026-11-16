/* =============================================================================
   UAT2_WPA_ASSET_DB.CORE  -  CSTM ASSET SCHEMA CATG  :  VIEW + TABLE + TASK version
   *** SINGLE ISSUE TYPE variant  -  issue type from NPF_ASSET (asset master) ***

   NOT DEPLOYED - kept ready in case testing raises concerns about the
   multi-issue-type version (CSTM Asset Schema Catg - View + Task.sql).

   Difference vs the multi-issue-type version
     Multi (current) : ISS_TYPE from POSITION / TRANSACTION AST_ISS_TYPE -> one
                       instrument can produce several rows (one per issue type).
     This file       : ISS_TYPE from NPF_ASSET.ISS_TYPE -> exactly ONE issue type
                       per instrument -> ONE row per schema x customer x instrument.
                       POSITION / TRANSACTION only decide WHICH instruments a
                       customer has; their issue-type column is not read.

   Everything else unchanged: Oracle npf_asst_typ_mgr 11-arg + 6-arg +
   RULE_EVALUATION, parity rules P1-P11, MERGE + DELETE load, 2 tasks.

   Objects carry suffix _AI (Asset Issue type) so both versions can exist side by
   side for comparison. To make this the live version, drop the suffix (and the
   multi version's objects) - consumers read the table name only.

     View  WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW        all logic in ONE view
     Table WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL       physical result
     Proc  WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP   MERGE + DELETE table FROM view
     Task  WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK       every 3 minutes -> proc
     Task  WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK  on rule table change -> proc
     Streams: own pair (a stream offset is per consumer - can't share with the
              multi version's tasks)

   Load key : (SCHEMA_ID, CUST_SK, INSTR_ID)  - ISS_TYPE no longer part of the key
              (it's a function of INSTR_ID). Column kept in the table for
              consumers / comparison.

   CTE map (view)                        former DT / Oracle unit
     cust_scope   customers with a schema   (NPF_CUST_CSTM_SCHEMA)
     cust_instr   DT4  caller loop          positions any date + transactions (instr only)
     asset_std    DT1  6-arg proc + country NPF_ASSET.ISS_TYPE + NPF_ASSET_CATG + NPF_DECODE
     combo        DT2  distinct desc combos
     rule_eval    DT2  RULE_EVALUATION per rule
     rule_pick    DT2  first (R1) / last (RN) match
     cstm_row     DT3  v_rec_cnt + cstm_asset_cursor
     calls / out  FINAL 11-arg proc (Path 1 custom / Path 2 rule-std)

   Assumption to confirm: NPF_ASSET has ONE row per INSTR_ID (grain check in
   section 4). If not, asset_std returns duplicates and the MERGE fails on purpose.
   Tasks are serverless (no warehouse); role needs EXECUTE MANAGED TASK.
   NOT compiled here - UAT2 databases not visible from this session.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. VIEW  -  all logic
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW
  COMMENT = 'Oracle npf_asst_typ_mgr (11-arg) + RULE_EVALUATION per customer schema x customer instrument (issue type from NPF_ASSET). Loaded into WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL by WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK.'
AS
WITH
-- customers that have a custom schema: limits the scan of the huge position/txn tables
cust_scope AS (
    SELECT DISTINCT cust_sk
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
    WHERE cust_sk IS NOT NULL
),
-- (DT4) instruments each in-scope customer ever held (any date) or transacted.
-- Instrument only - issue type is taken from NPF_ASSET below.
cust_instr AS (
    SELECT p.cust_sk, p.instr_id
    FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION p
    WHERE p.instr_id IS NOT NULL
      AND p.cust_sk IN (SELECT cust_sk FROM cust_scope)
    UNION                                                   -- de-duplicates
    SELECT t.cust_sk, t.instr_id
    FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION t
    WHERE t.instr_id IS NOT NULL
      AND t.cust_sk IN (SELECT cust_sk FROM cust_scope)
),
-- distinct instruments to categorise
instr AS (
    SELECT DISTINCT instr_id FROM cust_instr
),
-- (DT1) standard category + country per instrument
--       6-arg npf_asst_typ_mgr with the asset master's issue type
asset_std AS (
    SELECT
        instr_id, iss_type,
        std_sup_code, std_sub_code, std_sup_desc, std_sub_desc, cntry_desc,
        NVL(std_sup_desc, '#NULL#') AS sup_desc_key,
        NVL(std_sub_desc, '#NULL#') AS sub_desc_key,
        NVL(cntry_desc,   '#NULL#') AS cntry_desc_key
    FROM (
        SELECT
            a.instr_id,
            NULLIF(a.iss_type, '') AS iss_type,
            -- P1: FETCH overwrites all 4 defaults when a mapping row exists (even NULL values)
            IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
            IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
            IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
            IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
            NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
        FROM instr i
        JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET a                  -- instr must exist in NPF_ASSET
          ON a.instr_id = i.instr_id
        LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
               ON ac.rptg_type = 'WLT'
              AND ac.iss_type  = a.iss_type                      -- asset master issue type
        LEFT JOIN UAT2_WPA_COMMON_UTIL_DB.CORE.NPF_DECODE d
               ON d.dcde_type = 'CNTRY'
              AND d.dcde_code = a.cntry_risk_dcde
    )
),
-- (DT2) distinct desc combinations - rules depend only on these 3 values
combo AS (
    SELECT std_sup_desc, std_sub_desc, cntry_desc,
           sup_desc_key, sub_desc_key, cntry_desc_key
    FROM asset_std
    GROUP BY ALL
),
-- (DT2) RULE_EVALUATION: per active rule x combo, condition / match counts
rule_eval AS (
    SELECT
        r.schema_id,
        cb.sup_desc_key, cb.sub_desc_key, cb.cntry_desc_key,
        r.rule_sk,
        NULLIF(r.rule_cstm_supcatg_desc, '') AS rule_sup_desc,
        NULLIF(r.rule_cstm_subcatg_desc, '') AS rule_sub_desc,
        MAX(IFF(c.logical_oper = 'OR', 1, 0)) AS has_or,          -- P5
        COUNT(c.rule_sk)                      AS cond_cnt,        -- P6: 0 when no conditions
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
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR r
    LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND c         -- LEFT: P6
           ON c.rule_sk = r.rule_sk
    CROSS JOIN combo cb                                           -- every rule tested on every combo
    WHERE r.rule_stat = 'A'
      AND r.schema_id IN (SELECT schema_id FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA)
    GROUP BY r.schema_id, cb.sup_desc_key, cb.sub_desc_key, cb.cntry_desc_key,
             r.rule_sk, r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc
),
-- (DT2) keep matching rules; first (_1) and last (_2, only when >1 match)  - P7
rule_pick AS (
    SELECT
        schema_id, sup_desc_key, sub_desc_key, cntry_desc_key,
        MIN_BY(rule_sup_desc, rule_sk)                          AS r1_sup,
        MIN_BY(rule_sub_desc, rule_sk)                          AS r1_sub,
        IFF(COUNT(*) > 1, MAX_BY(rule_sup_desc, rule_sk), NULL) AS rn_sup,
        IFF(COUNT(*) > 1, MAX_BY(rule_sub_desc, rule_sk), NULL) AS rn_sub
    FROM rule_eval
    WHERE (has_or = 1 AND match_cnt > 0)
       OR (has_or = 0 AND match_cnt = cond_cnt)
    GROUP BY schema_id, sup_desc_key, sub_desc_key, cntry_desc_key
),
-- (DT3) active WLT custom row per schema + instrument  - P8, P9
cstm_row AS (
    SELECT
        ncs.schema_id,
        ncs.instr_id,
        NULLIF(ncs.cstm_supcatg_code, '') AS cstm_supcatg_code,
        NULLIF(ncs.cstm_supcatg_desc, '') AS cstm_supcatg_desc,
        NULLIF(ncs.npf_supcatg_code,  '') AS npf_supcatg_code,
        NULLIF(ncs.cstm_subcatg_code, '') AS cstm_subcatg_code,
        NULLIF(ncs.cstm_subcatg_desc, '') AS cstm_subcatg_desc,
        NULLIF(ncs.npf_subcatg_code,  '') AS npf_subcatg_code
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_SCHEMA ncs
    WHERE ncs.rptg_type = 'WLT'
      AND ncs.end_dt IS NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ncs.schema_id, ncs.instr_id
                               ORDER BY ncs.start_dt DESC) = 1
),
-- (FINAL) one row per npf_asst_typ_mgr call: customer schema x customer instrument
calls AS (
    SELECT
        s.schema_id, s.cust_sk, s.schema_desc,
        a.instr_id, a.iss_type,
        a.std_sup_code, a.std_sub_code, a.std_sup_desc, a.std_sub_desc,
        cr.schema_id AS cstm_hit,                                 -- NOT NULL => Path 1
        cr.cstm_supcatg_code, cr.cstm_supcatg_desc, cr.npf_supcatg_code,
        cr.cstm_subcatg_code, cr.cstm_subcatg_desc, cr.npf_subcatg_code,
        rp.r1_sup, rp.r1_sub, rp.rn_sup, rp.rn_sub
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA s
    JOIN cust_instr ci ON ci.cust_sk  = s.cust_sk
    JOIN asset_std  a  ON a.instr_id  = ci.instr_id               -- 1 row per instrument
    LEFT JOIN cstm_row cr
           ON cr.schema_id = s.schema_id
          AND cr.instr_id  = a.instr_id
    LEFT JOIN rule_pick rp
           ON rp.schema_id      = s.schema_id
          AND rp.sup_desc_key   = a.sup_desc_key
          AND rp.sub_desc_key   = a.sub_desc_key
          AND rp.cntry_desc_key = a.cntry_desc_key
),
out AS (
    SELECT
        schema_id, cust_sk, instr_id, iss_type, schema_desc,
        std_sup_code AS supcatg_code,
        std_sub_code AS subcatg_code,
        CASE WHEN cstm_hit IS NOT NULL THEN cstm_supcatg_desc                   -- P8
             ELSE COALESCE(rn_sup, r1_sup, std_sup_desc) END           AS supcatg_desc,   -- P7
        CASE WHEN cstm_hit IS NOT NULL THEN cstm_subcatg_desc
             ELSE COALESCE(rn_sub, r1_sub, std_sub_desc) END           AS subcatg_desc,
        CASE WHEN cstm_hit IS NOT NULL THEN
                  IFF(cstm_supcatg_code IS NULL, NVL(npf_supcatg_code, '') || '-S',
                                                 cstm_supcatg_code        || '-C')
             ELSE NVL(std_sup_code, '') || '-S' END                    AS cstm_supcatg_code,   -- P3
        CASE WHEN cstm_hit IS NOT NULL THEN
                  IFF(cstm_subcatg_code IS NULL, NVL(npf_subcatg_code, '') || '-S',
                                                 cstm_subcatg_code        || '-C')
             ELSE NVL(std_sup_code, '') || '-' || NVL(std_sub_code, '') || '-S' END AS cstm_subcatg_code
    FROM calls
)
SELECT
    schema_id,
    cust_sk,
    instr_id,
    'WLT'        AS rptg_type,
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


/* -----------------------------------------------------------------------------
   2. TARGET TABLE  (same columns as the multi version + load timestamp)
   CREATE ... IF NOT EXISTS so re-running the script never drops loaded data.
   ----------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL (
    SCHEMA_ID          NUMBER,
    CUST_SK            NUMBER,
    INSTR_ID           VARCHAR,
    RPTG_TYPE          VARCHAR,
    ISS_TYPE           VARCHAR,
    SUPCATG_CODE       VARCHAR,
    SUBCATG_CODE       VARCHAR,
    SUPCATG_DESC       VARCHAR,
    SUBCATG_DESC       VARCHAR,
    CSTM_SUPCATG_CODE  VARCHAR,
    CSTM_SUBCATG_CODE  VARCHAR,
    CSTM_SUPCATG_DESC  VARCHAR,
    CSTM_SUBCATG_DESC  VARCHAR,
    SCHEMA_DESC        VARCHAR,
    LOAD_TS            TIMESTAMP_LTZ
)
COMMENT = 'Loaded by task WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK from view WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW (MERGE + DELETE on SCHEMA_ID, CUST_SK, INSTR_ID). Issue type from NPF_ASSET.';


/* -----------------------------------------------------------------------------
   3. LOAD  -  view -> table  (procedure + 2 streams + 2 serverless tasks)

     WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK       SCHEDULE '3 MINUTES'            (regular)
     WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK  triggered: WHEN rule stream(s)  (immediate)
          │                                      has data - no schedule
          └──────────────┬───────────────────────┘
                         ▼
          WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP()

   Both runs consume the rule streams first, so a rule change already picked up
   by a scheduled run does not trigger a second, redundant run.
   ----------------------------------------------------------------------------- */

-- 3a. Change tracking + streams on the rule tables (own streams for this version)
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR SET CHANGE_TRACKING = TRUE;   -- if not already on
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND SET CHANGE_TRACKING = TRUE;
CREATE STREAM IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_AI_STRM
  ON TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR
  COMMENT = 'Triggers WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK on rule master changes';
CREATE STREAM IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_AI_STRM
  ON TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND
  COMMENT = 'Triggers WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK on rule condition changes';

-- 3b. Load procedure (MERGE load, delta only):
--   0) consume rule streams FIRST (own transaction)
--   a) view evaluated ONCE into a temp stage
--   b) MERGE  : insert new keys, update only changed rows
--   c) DELETE : keys the view no longer returns
--   b + c in one transaction -> readers never see a half-applied load.
-- Key = (SCHEMA_ID, CUST_SK, INSTR_ID). Duplicate keys -> MERGE fails (intended safeguard).
CREATE OR REPLACE PROCEDURE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Delta load (MERGE + DELETE) of WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL from WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW'
  EXECUTE AS CALLER                                         -- must come after COMMENT
AS
$$
DECLARE
    v_ins_upd NUMBER DEFAULT 0;
    v_del     NUMBER DEFAULT 0;
BEGIN
    -- 0) consume rule streams (DDL first: auto-commits)
    CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STRM_SINK (rule_sk NUMBER);
    BEGIN TRANSACTION;
    INSERT INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STRM_SINK (rule_sk)
        SELECT rule_sk FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_AI_STRM WHERE 1 = 0;
    INSERT INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STRM_SINK (rule_sk)
        SELECT rule_sk FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_AI_STRM WHERE 1 = 0;
    COMMIT;

    -- a) stage
    CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STG AS
    SELECT * FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW;

    BEGIN TRANSACTION;

    -- b) upsert  (ISS_TYPE is a normal attribute now: updated if the asset's issue type changes)
    MERGE INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL t
    USING UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STG s
       ON  t.schema_id = s.schema_id
       AND t.cust_sk   = s.cust_sk
       AND t.instr_id  = s.instr_id
    WHEN MATCHED AND (   t.rptg_type         IS DISTINCT FROM s.rptg_type
                      OR t.iss_type          IS DISTINCT FROM s.iss_type
                      OR t.supcatg_code      IS DISTINCT FROM s.supcatg_code
                      OR t.subcatg_code      IS DISTINCT FROM s.subcatg_code
                      OR t.supcatg_desc      IS DISTINCT FROM s.supcatg_desc
                      OR t.subcatg_desc      IS DISTINCT FROM s.subcatg_desc
                      OR t.cstm_supcatg_code IS DISTINCT FROM s.cstm_supcatg_code
                      OR t.cstm_subcatg_code IS DISTINCT FROM s.cstm_subcatg_code
                      OR t.cstm_supcatg_desc IS DISTINCT FROM s.cstm_supcatg_desc
                      OR t.cstm_subcatg_desc IS DISTINCT FROM s.cstm_subcatg_desc
                      OR t.schema_desc       IS DISTINCT FROM s.schema_desc)
    THEN UPDATE SET
         rptg_type         = s.rptg_type,
         iss_type          = s.iss_type,
         supcatg_code      = s.supcatg_code,
         subcatg_code      = s.subcatg_code,
         supcatg_desc      = s.supcatg_desc,
         subcatg_desc      = s.subcatg_desc,
         cstm_supcatg_code = s.cstm_supcatg_code,
         cstm_subcatg_code = s.cstm_subcatg_code,
         cstm_supcatg_desc = s.cstm_supcatg_desc,
         cstm_subcatg_desc = s.cstm_subcatg_desc,
         schema_desc       = s.schema_desc,
         load_ts           = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT
        (schema_id, cust_sk, instr_id, rptg_type, iss_type,
         supcatg_code, subcatg_code, supcatg_desc, subcatg_desc,
         cstm_supcatg_code, cstm_subcatg_code, cstm_supcatg_desc, cstm_subcatg_desc,
         schema_desc, load_ts)
    VALUES
        (s.schema_id, s.cust_sk, s.instr_id, s.rptg_type, s.iss_type,
         s.supcatg_code, s.subcatg_code, s.supcatg_desc, s.subcatg_desc,
         s.cstm_supcatg_code, s.cstm_subcatg_code, s.cstm_supcatg_desc, s.cstm_subcatg_desc,
         s.schema_desc, CURRENT_TIMESTAMP());
    v_ins_upd := SQLROWCOUNT;

    -- c) remove keys the view no longer produces
    DELETE FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL t
    WHERE NOT EXISTS (
        SELECT 1
        FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_STG s
        WHERE s.schema_id = t.schema_id
          AND s.cust_sk   = t.cust_sk
          AND s.instr_id  = t.instr_id);
    v_del := SQLROWCOUNT;

    COMMIT;
    RETURN 'merged (ins+upd): ' || v_ins_upd || ', deleted: ' || v_del;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;                                   -- task run shows FAILED with the error
END;
$$;

-- 3c. Regular task: every 3 minutes, serverless
CREATE OR REPLACE TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK
  SCHEDULE = '3 MINUTES'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'
  TARGET_COMPLETION_INTERVAL = '10 MINUTES'
  USER_TASK_TIMEOUT_MS = 21600000                           -- 6 hours
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  COMMENT = 'Every 3 min: WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP (view -> table delta load)'
AS
  CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP();

-- 3d. Rule-change task: TRIGGERED (no SCHEDULE)
CREATE OR REPLACE TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'
  TARGET_COMPLETION_INTERVAL = '10 MINUTES'
  USER_TASK_TIMEOUT_MS = 21600000
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  COMMENT = 'On rule table change: WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP (immediate refresh)'
  WHEN SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_AI_STRM')
    OR SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_AI_STRM')
AS
  CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP();

-- Tasks are created suspended. For side-by-side testing, a one-off CALL is enough;
-- resume only if this version goes live.
-- ALTER TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK      RESUME;
-- ALTER TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK RESUME;


/* -----------------------------------------------------------------------------
   4. First load + checks
   ----------------------------------------------------------------------------- */
-- CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP();

-- Pre-check: NPF_ASSET must be 1 row per INSTR_ID (expect 0 rows)
-- SELECT instr_id, COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.NPF_ASSET
-- GROUP BY instr_id HAVING COUNT(*) > 1;

-- Grain check on the view (expect 0 rows)
-- SELECT schema_id, cust_sk, instr_id, COUNT(*)
-- FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW
-- GROUP BY ALL HAVING COUNT(*) > 1;

-- Table vs view (same count right after a load)
-- SELECT (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL) AS tbl_rows,
--        (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW)  AS vw_rows;

-- Compare with the multi-issue-type version
-- (a) row counts: multi >= single; the difference = extra issue-type rows
-- SELECT (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL)    AS multi_rows,
--        (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL) AS single_rows;

-- (b) instruments where position/txn issue type differs from NPF_ASSET issue type
--     -> these are exactly the rows where the two versions can give different categories
-- SELECT m.schema_id, m.cust_sk, m.instr_id,
--        m.iss_type      AS pos_txn_iss_type,
--        s.iss_type      AS asset_iss_type,
--        m.supcatg_desc  AS multi_sup,  s.supcatg_desc AS single_sup,
--        m.subcatg_desc  AS multi_sub,  s.subcatg_desc AS single_sub
-- FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL m
-- JOIN UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL s
--   ON s.schema_id = m.schema_id AND s.cust_sk = m.cust_sk AND s.instr_id = m.instr_id
-- WHERE NOT EQUAL_NULL(m.iss_type, s.iss_type)
-- ORDER BY m.instr_id;

-- (c) keys present in one version only (expect 0 both ways - same instrument set)
-- SELECT schema_id, cust_sk, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL
-- EXCEPT
-- SELECT schema_id, cust_sk, instr_id FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL;

-- Cleanup if this version is not needed
-- DROP TASK   IF EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_RULE_TSK;
-- DROP TASK   IF EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TSK;
-- DROP PROCEDURE IF EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_LOAD_SP();
-- DROP STREAM IF EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_AI_STRM;
-- DROP STREAM IF EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_AI_STRM;
-- DROP TABLE  IF EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_TBL;
-- DROP VIEW   IF EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_AI_VW;
