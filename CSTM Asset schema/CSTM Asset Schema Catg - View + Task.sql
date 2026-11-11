/* =============================================================================
   UAT2_WPA_ASSET_DB.CORE  -  CSTM ASSET SCHEMA CATG  :  VIEW + TABLE + TASK version
   Alternative to the 5 dynamic tables (CSTM Asset Schema Catg DT - Oracle Parity.sql).
   Same Oracle logic (npf_asst_typ_mgr 11-arg + 6-arg + RULE_EVALUATION), parity
   rules P1-P11 unchanged - only the delivery mechanism differs.

     View  WPA_CSTM_ASSET_SCHEMA_CATG_VW   all logic in ONE view (CTE per former DT)
     Table WPA_CSTM_ASSET_SCHEMA_CATG_TBL  physical result, read by consumers
     Proc  WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP   MERGE + DELETE table FROM view
     Task  WPA_CSTM_ASSET_SCHEMA_CATG_TSK       every 3 minutes -> proc
     Task  WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK  on rule table change (streams) -> proc

   Why this version
     - No dependency on WPA_ASSET_DYN (changes often, long running, being moved to
       a stream-based approach). The view reads NPF_ASSET directly, restricted to
       the instruments our customers hold/traded -> same "relevant assets" set,
       computed only for what this table needs.
     - POSITION / TRANSACTION are huge: they are read once per task run, and only
       for customers that have a custom schema (semi-join on NPF_CUST_CSTM_SCHEMA),
       not continuously by DT refreshes.
     - Load timing is fully controlled (schedule / after upstream load).

   Load : delta MERGE on key (SCHEMA_ID, CUST_SK, INSTR_ID, ISS_TYPE): view staged once,
          MERGE inserts new / updates changed rows only, DELETE removes keys the
          view no longer returns; MERGE + DELETE in one transaction (readers see
          old or new data). LOAD_TS = when that row last changed.

   CTE map (view)                        former DT / Oracle unit
     cust_scope   customers with a schema   (NPF_CUST_CSTM_SCHEMA)
     cust_instr   DT4  caller loop          positions any date + transactions
     asset_std    DT1  6-arg proc + country NPF_ASSET + NPF_ASSET_CATG + NPF_DECODE
     combo        DT2  distinct desc combos
     rule_eval    DT2  RULE_EVALUATION per rule
     rule_pick    DT2  first (R1) / last (RN) match
     cstm_row     DT3  v_rec_cnt + cstm_asset_cursor
     calls / out  FINAL 11-arg proc (Path 1 custom / Path 2 rule-std)

   Tasks are serverless (no warehouse); role needs EXECUTE MANAGED TASK.
   NOT compiled here - UAT2 databases not visible from this session.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   1. VIEW  -  all logic
   ----------------------------------------------------------------------------- */
CREATE OR REPLACE VIEW UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_VW
  COMMENT = 'Oracle npf_asst_typ_mgr (11-arg) + RULE_EVALUATION per customer schema x customer instrument x issue type (issue type from position / transaction AST_ISS_TYPE). Loaded into WPA_CSTM_ASSET_SCHEMA_CATG_TBL by WPA_CSTM_ASSET_SCHEMA_CATG_TSK.'
AS
WITH
-- customers that have a custom schema: limits the scan of the huge position/txn tables
cust_scope AS (
    SELECT DISTINCT cust_sk
    FROM UAT2_WPA_ASSET_DB.CORE.NPF_CUST_CSTM_SCHEMA
    WHERE cust_sk IS NOT NULL
),
-- (DT4) instrument + ISSUE TYPE each in-scope customer ever held (any date) or transacted.
-- ISS_TYPE comes from the source row itself (position / transaction AST_ISS_TYPE):
-- one instrument can carry several issue types, each giving its own category ->
-- separate rows.
cust_instr AS (
    SELECT p.cust_sk, p.instr_id, NULLIF(p.ast_iss_type, '') AS iss_type
    FROM UAT2_WPA_HOLDINGS_DB.CORE.WPA_AC_POSITION p
    WHERE p.instr_id IS NOT NULL
      AND p.cust_sk IN (SELECT cust_sk FROM cust_scope)
    UNION                                                   -- de-duplicates
    SELECT t.cust_sk, t.instr_id, NULLIF(t.ast_iss_type, '') AS iss_type   -- confirm column name
    FROM UAT2_WPA_TRANSACTION_DB.CORE.WPA_TRANSACTION t
    WHERE t.instr_id IS NOT NULL
      AND t.cust_sk IN (SELECT cust_sk FROM cust_scope)
),
-- distinct (instrument, issue type) pairs to categorise
instr_iss AS (
    SELECT DISTINCT instr_id, iss_type FROM cust_instr
),
-- (DT1) standard category per (instrument, issue type) + country per instrument
--       6-arg npf_asst_typ_mgr is called with the passed issue type (position's)
asset_std AS (
    SELECT
        instr_id, iss_type,
        std_sup_code, std_sub_code, std_sup_desc, std_sub_desc, cntry_desc,
        NVL(std_sup_desc, '#NULL#') AS sup_desc_key,
        NVL(std_sub_desc, '#NULL#') AS sub_desc_key,
        NVL(cntry_desc,   '#NULL#') AS cntry_desc_key
    FROM (
        SELECT
            ii.instr_id,
            ii.iss_type,
            -- P1: FETCH overwrites all 4 defaults when a mapping row exists (even NULL values)
            IFF(ac.iss_type IS NULL, '30',            NULLIF(ac.supcatg_code, '')) AS std_sup_code,
            IFF(ac.iss_type IS NULL, '20',            NULLIF(ac.subcatg_code, '')) AS std_sub_code,
            IFF(ac.iss_type IS NULL, 'Other Assets',  NULLIF(ac.supcatg_desc, '')) AS std_sup_desc,
            IFF(ac.iss_type IS NULL, 'Miscellaneous', NULLIF(ac.subcatg_desc, '')) AS std_sub_desc,
            NULLIF(d.dcde_desc, '')                                                  AS cntry_desc
        FROM instr_iss ii
        JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET a                  -- instr must exist in NPF_ASSET
          ON a.instr_id = ii.instr_id
        LEFT JOIN UAT2_WPA_ASSET_DB.CORE.NPF_ASSET_CATG ac
               ON ac.rptg_type = 'WLT'
              AND ac.iss_type  = ii.iss_type                     -- position/Tran issue type
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
    JOIN asset_std  a  ON a.instr_id  = ci.instr_id
                      AND EQUAL_NULL(a.iss_type, ci.iss_type)   -- NULL issue type kept (gets defaults)
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
   2. TARGET TABLE  (same columns as the DT + load timestamp)
   CREATE ... IF NOT EXISTS so re-running the script never drops loaded data.
   ----------------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL (
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
COMMENT = 'Loaded by task WPA_CSTM_ASSET_SCHEMA_CATG_TSK from view WPA_CSTM_ASSET_SCHEMA_CATG_VW (MERGE + DELETE on SCHEMA_ID, CUST_SK, INSTR_ID, ISS_TYPE).';
-- If column types must match the existing table exactly, use instead:
-- CREATE TABLE IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL AS
--   SELECT *, CURRENT_TIMESTAMP()::TIMESTAMP_LTZ AS load_ts
--   FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_VW WHERE 1 = 0;


/* -----------------------------------------------------------------------------
   3. LOAD  -  view -> table  (procedure + 2 streams + 2 serverless tasks)

   Requirement (review): normal refresh every 3 minutes; a change to the RULE
   tables (rare, done by users) should flow to the target IMMEDIATELY.
   A Snowflake task has EITHER a fixed schedule OR runs on a stream condition,
   so the two triggers are two tasks calling ONE procedure (logic in one place):

     WPA_CSTM_ASSET_SCHEMA_CATG_TSK       SCHEDULE '3 MINUTES'            (regular)
     WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK  triggered: WHEN rule stream(s)  (immediate)
          │                                   has data - no schedule
          └──────────────┬────────────────────┘
                         ▼
          WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP()

   Both runs consume the rule streams first, so a rule change already picked up
   by a scheduled run does not trigger a second, redundant run.
   The two tasks can't corrupt each other: each run stages its own snapshot in
   a session temp table, and DML on the same target table is serialised by
   Snowflake (the second MERGE waits for the first to commit).
   ----------------------------------------------------------------------------- */

-- 3a. Change tracking + streams on the rule tables
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR SET CHANGE_TRACKING = TRUE;   -- if not already on
-- ALTER TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND SET CHANGE_TRACKING = TRUE;
CREATE STREAM IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_STRM
  ON TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR
  COMMENT = 'Triggers WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK on rule master changes';
CREATE STREAM IF NOT EXISTS UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_STRM
  ON TABLE UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND
  COMMENT = 'Triggers WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK on rule condition changes';
-- (IF NOT EXISTS: re-running the script must not reset the stream offsets.
--  Add NPF_CSTM_SCHEMA / NPF_CUST_CSTM_SCHEMA streams the same way if custom-row or
--  schema-assignment changes should also be immediate.)

-- 3c. Load procedure (MERGE load, delta only):
--   0) consume rule streams FIRST (own transaction): a rule change made while this
--      run is staging stays in the stream and triggers the next run, so no change
--      is missed. If a later step fails, the 3-minute task re-applies it anyway.
--   a) view evaluated ONCE into a temp stage (MERGE + DELETE both read it)
--   b) MERGE  : insert new keys, update only rows whose values changed
--               (LOAD_TS changes only for touched rows -> real "last changed" ts)
--   c) DELETE : keys no longer produced by the view (ended custom row, customer
--               left schema, ...). Snowflake MERGE has no "NOT MATCHED BY SOURCE".
--   b + c in one transaction -> readers never see a half-applied load.
-- Key = (SCHEMA_ID, CUST_SK, INSTR_ID, ISS_TYPE). If the view ever returned duplicate
-- keys, MERGE fails (ERROR_ON_NONDETERMINISTIC_MERGE = TRUE, default) - intended safeguard.
CREATE OR REPLACE PROCEDURE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP()
  RETURNS VARCHAR
  LANGUAGE SQL
  COMMENT = 'Delta load (MERGE + DELETE) of WPA_CSTM_ASSET_SCHEMA_CATG_TBL from WPA_CSTM_ASSET_SCHEMA_CATG_VW'
  EXECUTE AS CALLER                                         -- must come after COMMENT
AS
$$
DECLARE
    v_ins_upd NUMBER DEFAULT 0;
    v_del     NUMBER DEFAULT 0;
BEGIN
    -- 0) consume rule streams: a stream offset only moves when DML READS it in a
    --    committed transaction. Target = session temp table, never gets rows.
    --    (CREATE is DDL -> must run before BEGIN TRANSACTION, DDL auto-commits)
    CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STRM_SINK (rule_sk NUMBER);
    BEGIN TRANSACTION;
    INSERT INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STRM_SINK (rule_sk)
        SELECT rule_sk FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_STRM WHERE 1 = 0;
    INSERT INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STRM_SINK (rule_sk)
        SELECT rule_sk FROM UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_STRM WHERE 1 = 0;
    COMMIT;

    -- a) stage
    CREATE OR REPLACE TEMPORARY TABLE UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STG AS
    SELECT * FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_VW;

    BEGIN TRANSACTION;

    -- b) upsert
    MERGE INTO UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL t
    USING UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STG s
       ON  t.schema_id = s.schema_id
       AND t.cust_sk   = s.cust_sk
       AND t.instr_id  = s.instr_id
       AND EQUAL_NULL(t.iss_type, s.iss_type)                -- ISS_TYPE is part of the key
    WHEN MATCHED AND (   t.rptg_type         IS DISTINCT FROM s.rptg_type
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
    DELETE FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL t
    WHERE NOT EXISTS (
        SELECT 1
        FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_STG s
        WHERE s.schema_id = t.schema_id
          AND s.cust_sk   = t.cust_sk
          AND s.instr_id  = t.instr_id
          AND EQUAL_NULL(s.iss_type, t.iss_type));
    v_del := SQLROWCOUNT;

    COMMIT;
    RETURN 'merged (ins+upd): ' || v_ins_upd || ', deleted: ' || v_del;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;                                   -- task run shows FAILED with the error
END;
$$;

-- 3d. Regular task: every 3 minutes, serverless
CREATE OR REPLACE TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TSK
  SCHEDULE = '3 MINUTES'
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'
  TARGET_COMPLETION_INTERVAL = '10 MINUTES'                 -- Snowflake sizes compute to finish within this
  USER_TASK_TIMEOUT_MS = 21600000                           -- 6 hours
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  COMMENT = 'Every 3 min: WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP (view -> table delta load)'
AS
  CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP();

-- 3e. Rule-change task: TRIGGERED (no SCHEDULE) - runs as soon as a rule stream has data
CREATE OR REPLACE TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK
  USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'SMALL'
  TARGET_COMPLETION_INTERVAL = '10 MINUTES'                 -- Snowflake sizes compute to finish within this
  USER_TASK_TIMEOUT_MS = 21600000
  SUSPEND_TASK_AFTER_NUM_FAILURES = 3
  COMMENT = 'On rule table change: WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP (immediate refresh)'
  WHEN SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_STRM')
    OR SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_COND_CATG_STRM')
AS
  CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP();

-- Tasks are created suspended
ALTER TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TSK      RESUME;
ALTER TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK RESUME;


/* -----------------------------------------------------------------------------
   4. First load + checks
   ----------------------------------------------------------------------------- */
-- EXECUTE TASK UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TSK;     -- run now
-- CALL UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_LOAD_SP();       -- or call directly

-- Rule-change path test: touch a rule, the RULE task should run within ~1 minute
-- SELECT SYSTEM$STREAM_HAS_DATA('UAT2_WPA_ASSET_DB.CORE.NPF_CSTM_RULE_MSTR_CATG_STRM');  -- TRUE after a change
-- SHOW TASKS LIKE 'WPA_CSTM_ASSET_SCHEMA_CATG%' IN SCHEMA UAT2_WPA_ASSET_DB.CORE;          -- both 'started'

-- Run history (state, duration, errors)
-- SELECT name, state, scheduled_time, completed_time,
--        DATEDIFF('second', query_start_time, completed_time) AS secs, error_message
-- FROM TABLE(UAT2_WPA_ASSET_DB.INFORMATION_SCHEMA.TASK_HISTORY(
--        RESULT_LIMIT => 50))
-- WHERE name IN ('WPA_CSTM_ASSET_SCHEMA_CATG_TSK', 'WPA_CSTM_ASSET_SCHEMA_CATG_RULE_TSK')
-- ORDER BY scheduled_time DESC;

-- Last run's delta: rows touched by the latest load (inserted or updated)
-- SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL
-- WHERE load_ts = (SELECT MAX(load_ts) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL);

-- Grain check: must return 0 rows
-- SELECT schema_id, cust_sk, instr_id, iss_type, COUNT(*)
-- FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_VW
-- GROUP BY ALL HAVING COUNT(*) > 1;

-- Table vs view (expect same count, 0 diff rows right after a load)
-- SELECT (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL) AS tbl_rows,
--        (SELECT COUNT(*) FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_VW)  AS vw_rows;

-- Table vs the validated DT (expect 0 both ways while both exist)
-- SELECT COUNT(*) FROM (
--   SELECT * EXCLUDE load_ts FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL
--   EXCEPT
--   SELECT * FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY);
-- SELECT COUNT(*) FROM (
--   SELECT * FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_DY
--   EXCEPT
--   SELECT * EXCLUDE load_ts FROM UAT2_WPA_ASSET_DB.CORE.WPA_CSTM_ASSET_SCHEMA_CATG_TBL);
-- (If the DT reads WPA_ASSET_DYN and that filters on a different transaction table,
--  small differences come from that, not from the logic.)

-- The UAT2 validation script works against the table too: replace
-- WPA_CSTM_ASSET_SCHEMA_CATG_DY with WPA_CSTM_ASSET_SCHEMA_CATG_TBL in sections 6, 8, 12.
