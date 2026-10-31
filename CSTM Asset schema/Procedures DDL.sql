
CREATE OR REPLACE PROCEDURE "WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC"()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    /* ---- identity / timing ---- */
    v_obj_name        VARCHAR       DEFAULT ''UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_LOAD_CONTROL_PROC'';
    v_starttime       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    v_endtime         TIMESTAMP_NTZ;
    v_duration_secs   NUMBER(18,3)  DEFAULT 0;
    v_session_id      VARCHAR       := CURRENT_SESSION();
    v_proc_audit_id   NUMBER        DEFAULT NULL;

    /* ---- dispatch state ---- */
    v_streams_hit     NUMBER        DEFAULT 0;
    v_streams_failed  NUMBER        DEFAULT 0;
    v_stream_picked   VARCHAR       DEFAULT ''NONE'';
    v_result          VARCHAR       DEFAULT ''No streams have data - nothing triggered'';

    /* ---- exception / status ---- */
    v_status          VARCHAR       DEFAULT ''SUCCESS'';
    v_error_cnt       NUMBER        DEFAULT 0;
    v_error_msg       VARCHAR       DEFAULT NULL;
    v_last_err        VARCHAR       DEFAULT NULL;
    v_sqlcode         VARCHAR       DEFAULT NULL;
    v_sqlstate        VARCHAR       DEFAULT NULL;
    v_step_desc       VARCHAR       DEFAULT ''INIT'';
    v_addinfo         VARCHAR       DEFAULT NULL;

    /* ---- step-level instrumentation (mirrors wpa_transaction_load_sp pattern) ---- */
    v_step_name       VARCHAR       DEFAULT NULL;
    v_step_start      TIMESTAMP_NTZ DEFAULT NULL;
    v_query_id        VARCHAR       DEFAULT NULL;
    v_additional_detail VARCHAR     DEFAULT '''';
BEGIN

    /* Pre-fetch a single audit id so success and failure audit rows for
       this controller tick share the same PROC_AUDIT_ID. */
    SELECT uat2_wpa_asset_db.core.wpa_asset_proc_audit_seq.NEXTVAL
      INTO :v_proc_audit_id;

    /* -----------------------------------------------------------------
       DISPATCH: independent IF blocks so *all* ready streams are drained
       on each task run. Each block is wrapped in its own BEGIN/EXCEPTION
       so a failure on one stream does not prevent the others from
       processing; the last error is remembered and re-raised at the end.
       ----------------------------------------------------------------- */
    v_step_desc := ''STREAM-DISPATCH'';

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.core.wpa_cas_npf_asset_catg_strm'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_ASSET_CATG_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_ASSET_CATG_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_ASSET_CATG_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';

        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_ASSET_CATG_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.wpa_cas_NPF_DECODE_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_DECODE_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_DECODE_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_DECODE_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';

        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_DECODE_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.wpa_cas_NPF_CUST_CSTM_SCHEMA_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';
        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_SCHEMA_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_CSTM_SCHEMA_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_CSTM_SCHEMA_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_CSTM_SCHEMA_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';
        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_CSTM_SCHEMA_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_RULE_MSTR_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';
        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.wpa_cas_NPF_CSTM_RULE_COND_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_NPF_CSTM_RULE_COND_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';
        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_NPF_CSTM_RULE_COND_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    IF (SYSTEM$STREAM_HAS_DATA(''uat2_wpa_asset_db.CORE.WPA_CAS_ASSET_STRM'')) THEN
        BEGIN
            v_step_name  := ''CALL_WPA_CAS_ASSET_STRM'';
            v_step_start := CURRENT_TIMESTAMP();

            CALL uat2_wpa_asset_db.core.wpa_custom_asset_schema_catg_sp(
                ''WPA_CAS_ASSET_STRM'');

            v_query_id      := LAST_QUERY_ID();
            v_streams_hit   := :v_streams_hit + 1;
            v_stream_picked := ''WPA_CAS_ASSET_STRM'';

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"SUCCESS","error":null}'';
        EXCEPTION WHEN OTHER THEN
            v_streams_failed := :v_streams_failed + 1;
            v_last_err := ''WPA_CAS_ASSET_STRM: SQLCODE='' || :SQLCODE || '' SQLERRM='' || :SQLERRM;

            v_additional_detail := :v_additional_detail ||
                IFF(:v_additional_detail = '''', '''', '','') ||
                ''{"step":"'' || :v_step_name || ''"'' ||
                '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
                '',"status":"FAILED"'' ||
                '',"sqlcode":"''  || NVL(:SQLCODE::VARCHAR,'''')  || ''"'' ||
                '',"sqlstate":"'' || NVL(:SQLSTATE,'''')          || ''"'' ||
                '',"error":"''    || REPLACE(NVL(:SQLERRM,''''),''"'',''\\\\"'') || ''"}'';
        END;
    END IF;

    /* -----------------------------------------------------------------
       Finalize state
       ----------------------------------------------------------------- */
    v_step_desc     := ''FINALIZE'';
    v_endtime       := CURRENT_TIMESTAMP();
    v_duration_secs := DATEDIFF(''millisecond'', :v_starttime, :v_endtime) / 1000.0;

    IF (v_streams_hit = 0) THEN
        v_result := ''No streams have data - nothing triggered'';
        v_status := ''NO_DATA'';
    ELSEIF (v_streams_failed > 0) THEN
        v_status    := ''PARTIAL_FAILURE'';
        v_error_cnt := :v_streams_failed;
        v_error_msg := :v_last_err;
        v_result    := ''Dispatched '' || :v_streams_hit
                    || '' stream(s); FAILED '' || :v_streams_failed
                    || ''. Last error: '' || COALESCE(:v_last_err,'''');
    ELSE
        v_status := ''SUCCESS'';
        v_result := ''Dispatched '' || :v_streams_hit
                 || '' stream(s); last stream = '' || :v_stream_picked;
    END IF;

    v_addinfo := ''STATUS=''         || :v_status
              || ''; STEP=''         || :v_step_desc
              || ''; streams_hit=''  || :v_streams_hit
              || ''; streams_fail='' || :v_streams_failed
              || ''; result=''       || :v_result
              || IFF(:v_error_msg IS NULL, '''', ''; err='' || :v_error_msg)
              || ''; steps=['' || :v_additional_detail || '']'';

    /* Controller-level audit row (one per task tick) */
    INSERT INTO uat2_wpa_asset_db.core.wpa_asset_proc_audit (
        asset_proc_audit_id, sid, obj_name, input_param, stream_name,
        proc_start_tm, proc_end_tm, duration_secs,
        insert_cnt, update_cnt, delete_cnt, processed_cnt, error_cnt,
        status, sqlcode_val, sqlstate_val,
        additional_comments, upd_by
    )
    VALUES (
        :v_proc_audit_id, :v_session_id, :v_obj_name, :v_stream_picked, :v_stream_picked,
        :v_starttime, :v_endtime, :v_duration_secs,
        0, 0, 0, :v_streams_hit, :v_error_cnt,
        :v_status, NULL, NULL,
        :v_addinfo, :v_obj_name
    );

    /* If any child failed, surface the error so SUSPEND_TASK_AFTER_NUM_FAILURES
       can act. */
    IF (v_streams_failed > 0) THEN
        RAISE STATEMENT_ERROR;
    END IF;

    RETURN v_result;

/* ========================================================================
   Exception handling - capture SQLCODE / SQLERRM / SQLSTATE and write a
   FAILED audit row to wpa_asset_proc_audit, then RAISE so the task fails.
   ======================================================================== */
EXCEPTION
    WHEN OTHER THEN
        v_endtime       := CURRENT_TIMESTAMP();
        v_duration_secs := DATEDIFF(''millisecond'', :v_starttime, :v_endtime) / 1000.0;
        v_status        := ''FAILED'';
        v_error_cnt     := 1;
        v_error_msg     := COALESCE(:v_last_err,'''')
                        || '' | SQLCODE=''  || :SQLCODE
                        || '' | SQLSTATE='' || :SQLSTATE
                        || '' | SQLERRM=''  || :SQLERRM;
        v_sqlcode       := :SQLCODE::VARCHAR;
        v_sqlstate      := :SQLSTATE;
        v_addinfo       := ''STATUS=FAILED''
                        || ''; STEP=''         || :v_step_desc
                        || ''; streams_hit=''  || :v_streams_hit
                        || ''; streams_fail='' || :v_streams_failed
                        || ''; err=''          || :v_error_msg
                        || ''; steps=['' || :v_additional_detail || '']'';

        BEGIN
            INSERT INTO uat2_wpa_asset_db.core.wpa_asset_proc_audit (
                asset_proc_audit_id, sid, obj_name, input_param, stream_name,
                proc_start_tm, proc_end_tm, duration_secs,
                insert_cnt, update_cnt, delete_cnt, processed_cnt, error_cnt,
                status, sqlcode_val, sqlstate_val,
                additional_comments, upd_by
            )
            VALUES (
                :v_proc_audit_id, :v_session_id, :v_obj_name, :v_stream_picked, :v_stream_picked,
                :v_starttime, :v_endtime, :v_duration_secs,
                0, 0, 0, :v_streams_hit, :v_error_cnt,
                :v_status, :v_sqlcode, :v_sqlstate,
                :v_addinfo, :v_obj_name
            );
        EXCEPTION
            WHEN OTHER THEN
                NULL;
        END;

        RAISE;
END;
';

CREATE OR REPLACE PROCEDURE "WPA_CUSTOM_ASSET_SCHEMA_CATG_SP"("STREAM_NAME" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
declare
    v_stream        string;
    v_schema_cnt    number  default 0;
    v_instr_cnt     number  default 0;
    v_del_keys_cnt  number  default 0;
    v_cntry_cnt     number  default 0;
    v_cntry_del_cnt number  default 0;
    v_loc           number  default 0;

    -- ADDED: Audit logging & exception handling variables
    v_obj_name       string        default ''UAT2_WPA_ASSET_DB.CORE.WPA_CUSTOM_ASSET_SCHEMA_CATG_SP'';
    v_starttime      timestamp_ntz default current_timestamp();
    v_endtime        timestamp_ntz;
    v_duration_secs  number(18,3)  default 0;
    v_row_cnt        number        default 0;
    v_addinfo        string        default '''';
    v_err_msg        string        default '''';
    v_step_desc      string        default ''INIT'';

    -- Audit correlation (mirrors File 2 wpa_transaction_load_sp pattern)
    v_session_id     string        := current_session();
    v_proc_audit_id  number        default null;
    v_status         string        default ''SUCCESS'';
    v_error_cnt      number        default 0;
    v_sqlcode        string        default null;
    v_sqlstate       string        default null;

    -- Step-level instrumentation (mirrors File 2 wpa_transaction_load_sp pattern)
    v_step_name      string        default null;
    v_step_start     timestamp_ntz default null;
    v_step_rows      number        default null;
    v_query_id       string        default null;
    v_additional_detail string     default '''';
begin

    v_loc       := 0;
    v_step_desc := ''INIT-START'';

    -- Pre-fetch a single audit id so success and failure audit rows for
    -- this SP invocation share the same ASSET_PROC_AUDIT_ID.
    select uat2_wpa_asset_db.core.wpa_asset_proc_audit_seq.nextval
      into :v_proc_audit_id;

    v_loc := 1 ;
    v_stream    := stream_name;

    /* ----------------------------------------------------------------------
       1. Capture stream once, split into upsert / delete partitions.
       ---------------------------------------------------------------------- */
    v_loc := 2 ;	   
    v_step_name  := ''STREAM_CAPTURE'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_stream as
    select *
    from identifier(:v_stream);

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_stream);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    v_loc := 3 ;	
    v_step_name  := ''STREAM_SPLIT_UPSERT'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_stream_upsert as
    select *
    from tmp_stream
    where METADATA$ACTION <> ''DELETE'';

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_stream_upsert);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    v_loc := 4 ;	
    v_step_name  := ''STREAM_SPLIT_DELETE'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_stream_delete as
    select *
    from tmp_stream
    where METADATA$ACTION = ''DELETE''
      and METADATA$ISUPDATE = ''FALSE'';

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_stream_delete);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    /* ----------------------------------------------------------------------
       2. Country-decode gating (upsert + delete halves).
       ---------------------------------------------------------------------- */
    v_loc := 5 ;
    IF (  v_stream = ''WPA_CAS_NPF_DECODE_STRM'' ) THEN
        v_cntry_cnt := (
          SELECT COUNT(1)
            FROM tmp_stream_upsert ts
          WHERE :v_stream = ''WPA_CAS_NPF_DECODE_STRM''
            AND ts.dcde_type = ''CNTRY''
            AND ts.dcde_code is not null
        );

        v_loc := 6 ;	
        v_cntry_del_cnt := (
          SELECT COUNT(1)
            FROM tmp_stream_delete ts
          WHERE :v_stream = ''WPA_CAS_NPF_DECODE_STRM''
            AND ts.dcde_type = ''CNTRY''
            AND ts.dcde_code is not null
        );
    END IF  ;

    /* ----------------------------------------------------------------------
       3. Impacted-key sets (schemas + instruments to be RE-EVALUATED).
          Everything that should trigger an UPDATE (or INSERT) of a target
          row goes into tmp_imp_schema / tmp_imp_instr.
       ---------------------------------------------------------------------- */
	   
    v_loc := 7 ;	   
    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_imp_schema(schema_id number);
    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_imp_instr (instr_id  VARCHAR(16777216));

    -- 3a. UPSERTS ---------------------------------------------------------
    v_loc := 8 ;
    -- schemas that themselves changed (upsert side)
    IF ( :v_stream IN (''WPA_CAS_NPF_CSTM_SCHEMA_STRM'', ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'', ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'') ) THEN	
      insert into tmp_imp_schema
      select distinct schema_id
      from tmp_stream_upsert
      where :v_stream in (''WPA_CAS_NPF_CSTM_SCHEMA_STRM'',
                ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'',
                ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'')
        and schema_id is not null;
    END IF  ;
	
    v_loc := 9 ;	  
    -- rule-cond upsert -> schema(s) via rule_mstr
    IF (  v_stream = ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'' ) THEN		
      insert into tmp_imp_schema
      select distinct rm.schema_id
      from UAT2_WPA_ASSET_DB.core.NPF_CSTM_RULE_MSTR rm
      join tmp_stream_upsert ts
        on ts.rule_sk = rm.rule_sk
      where :v_stream = ''WPA_CAS_NPF_CSTM_RULE_COND_STRM''
        and rm.schema_id is not null;
    END IF  ;
	
    v_loc := 10 ;	  
    -- asset / asset_catg upsert affects ALL schemas that map to those instr
    IF ( :v_stream in (''WPA_CAS_ASSET_STRM'',''WPA_CAS_NPF_ASSET_CATG_STRM'') ) THEN		
      insert into tmp_imp_schema
      select distinct schema_id
      from UAT2_WPA_ASSET_DB.core.NPF_CUST_CSTM_SCHEMA
      where :v_stream in (''WPA_CAS_ASSET_STRM'',''WPA_CAS_NPF_ASSET_CATG_STRM'')
        and schema_id is not null;
    END IF  ;

    v_loc := 11 ;	  
    -- decode (country) upsert affects all schemas (cntry_desc feeds rule_eval)
    IF (v_cntry_cnt > 0) THEN
        insert into tmp_imp_schema
        select distinct schema_id
        from UAT2_WPA_ASSET_DB.core.NPF_CUST_CSTM_SCHEMA
        where schema_id is not null;
    END IF;

    v_loc := 12 ;	
    -- 3b. DELETES that must re-evaluate (NOT purge)

    -- NPF_CSTM_SCHEMA delete: row goes back to fallback path  (
    IF (  v_stream = ''WPA_CAS_NPF_CSTM_SCHEMA_STRM'' ) THEN		
      insert into tmp_imp_schema
      select distinct schema_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_NPF_CSTM_SCHEMA_STRM''
        and schema_id is not null;
    END IF;
	
    v_loc := 13 ;	  
    -- NPF_CSTM_RULE_MSTR delete: descriptions need re-evaluation  
    IF (  v_stream = ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'' ) THEN		
      insert into tmp_imp_schema
      select distinct schema_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM''
        and schema_id is not null;
    END IF;
	
    v_loc := 14 ;	  
    -- NPF_CSTM_RULE_COND delete: descriptions need re-evaluation 
    IF (  v_stream = ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'' ) THEN		
      insert into tmp_imp_schema
      select distinct rm.schema_id
      from UAT2_WPA_ASSET_DB.core.NPF_CSTM_RULE_MSTR rm
      join tmp_stream_delete ts
        on ts.rule_sk = rm.rule_sk
      where :v_stream = ''WPA_CAS_NPF_CSTM_RULE_COND_STRM''
        and rm.schema_id is not null;
    END IF;
	
    v_loc := 15 ;	  
    -- NPF_ASSET_CATG delete: corresponding instr re-evaluate to defaults
    IF (  v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM'' ) THEN		
      insert into tmp_imp_schema
      select distinct schema_id
      from UAT2_WPA_ASSET_DB.core.NPF_CUST_CSTM_SCHEMA
      where :v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM''
        and schema_id is not null
        and exists (select 1 from tmp_stream_delete);
    END IF;
	
    v_loc := 16 ;	  
    /* ----------------------------------------------------------------------
       4. Impacted instruments (upsert + delete drivers).
       ---------------------------------------------------------------------- */

    -- 4a. UPSERTS

    IF ( :v_stream  in (''WPA_CAS_ASSET_STRM'',''WPA_CAS_NPF_CSTM_SCHEMA_STRM'') ) THEN	
      insert into tmp_imp_instr
      select distinct instr_id
      from tmp_stream_upsert
      where :v_stream in (''WPA_CAS_ASSET_STRM'',''WPA_CAS_NPF_CSTM_SCHEMA_STRM'')
        and instr_id is not null;
    END IF;
	
    v_loc := 17 ;	  
    IF (  v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM'' ) THEN		
      insert into tmp_imp_instr
      select distinct ab.instr_id
      from UAT2_WPA_ASSET_DB.core.WPA_ASSET ab
      join tmp_stream_upsert ts
        on ts.iss_type = ab.iss_type
      where :v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM''
        and ts.iss_type is not null
        and ab.iss_type is not null;
    END IF;
	
    v_loc := 18 ;	  
    IF (v_cntry_cnt > 0) THEN
        insert into tmp_imp_instr
        select distinct na.instr_id
        from UAT2_WPA_ASSET_DB.core.WPA_ASSET na
        join tmp_stream_upsert ts
          on ts.dcde_code = na.cntry_risk_dcde
        where :v_stream = ''WPA_CAS_NPF_DECODE_STRM''
          and ts.dcde_type = ''CNTRY''
          and ts.dcde_code is not null;
    END IF;

    v_loc := 19 ;	
    -- schema/cust-schema/rule upserts: instruments mapped to those schemas
    -- via NPF_CSTM_SCHEMA, narrowed by tmp_imp_schema .
    IF ( :v_stream in (''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'',
                        ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'',
                        ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'') ) THEN		
      insert into tmp_imp_instr
      select distinct ncs.instr_id
      from UAT2_WPA_ASSET_DB.core.NPF_CSTM_SCHEMA ncs
      join tmp_imp_schema s
        on s.schema_id = ncs.schema_id
      where :v_stream in (''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'',
                ''WPA_CAS_NPF_CSTM_RULE_MSTR_STRM'',
                ''WPA_CAS_NPF_CSTM_RULE_COND_STRM'')
        and ncs.instr_id is not null;
    END IF;
	
    v_loc := 20 ;	  
    -- 4b. DELETES that must re-evaluate

    -- NPF_CSTM_SCHEMA delete : same instr but fallback now applies
    IF (  v_stream = ''WPA_CAS_NPF_CSTM_SCHEMA_STRM'' ) THEN		
      insert into tmp_imp_instr
      select distinct instr_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_NPF_CSTM_SCHEMA_STRM''
        and instr_id is not null;
    END IF;
	
    v_loc := 21 ;	  
    -- WPA_ASSET (NPF_ASSET) delete  -> reachable only via stream_delete row
    IF (  v_stream = ''WPA_CAS_ASSET_STRM'' ) THEN		
      insert into tmp_imp_instr
      select distinct instr_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_ASSET_STRM''
        and instr_id is not null;
    END IF;
	
    v_loc := 22 ;	  
    -- NPF_ASSET_CATG delete : all instrs that had this iss_type
    IF (  v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM'' ) THEN		
      insert into tmp_imp_instr
      select distinct ab.instr_id
      from UAT2_WPA_ASSET_DB.core.WPA_ASSET ab
      join tmp_stream_delete ts
        on ts.iss_type = ab.iss_type
      where :v_stream = ''WPA_CAS_NPF_ASSET_CATG_STRM''
        and ts.iss_type is not null
        and ab.iss_type is not null;
    END IF;
	
    v_loc := 23 ;	  
    -- NPF_DECODE (CNTRY) delete  
    IF (v_cntry_del_cnt > 0) THEN
        insert into tmp_imp_instr
        select distinct na.instr_id
        from UAT2_WPA_ASSET_DB.core.WPA_ASSET na
        join tmp_stream_delete ts
          on ts.dcde_code = na.cntry_risk_dcde
        where :v_stream = ''WPA_CAS_NPF_DECODE_STRM''
          and ts.dcde_type = ''CNTRY''
          and ts.dcde_code is not null;
    END IF;

    v_loc := 24 ;	
    /* ----------------------------------------------------------------------
       5. Hard-delete drivers (target rows MUST disappear).
          Only fired when the parent record is genuinely gone with no
          fallback Oracle row.  In practice this is:
            - WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM delete (whole schema is gone)
            - WPA_CAS_ASSET_STRM delete (the instrument itself is gone)
       ---------------------------------------------------------------------- */
    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_del_schema(schema_id number);
    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_del_instr (instr_id VARCHAR(16777216));

    v_loc := 25 ;	
    IF (  v_stream = ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM'' ) THEN	
      insert into tmp_del_schema
      select distinct schema_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_NPF_CUST_CSTM_SCHEMA_STRM''
        and schema_id is not null;
    END IF;
	
    v_loc := 26 ;	  
    IF (  v_stream = ''WPA_CAS_ASSET_STRM'' ) THEN		
      insert into tmp_del_instr
      select distinct instr_id
      from tmp_stream_delete
      where :v_stream = ''WPA_CAS_ASSET_STRM''
        and instr_id is not null;
    END IF;
	
    v_loc := 27 ;	  
    /* ----------------------------------------------------------------------
       6. decide whether anything is left to do.
          A delete-only stream may have empty impact sets but non-empty
          tmp_del_*; do not early-exit in that case.
       ---------------------------------------------------------------------- */
    -- OPT-4 : assign impact counts.
    v_schema_cnt := (select count(*) from tmp_imp_schema);
    v_instr_cnt := (select count(*) from tmp_imp_instr);
    v_del_keys_cnt := (select count(*) from tmp_del_schema) +
                      (select count(*) from tmp_del_instr);

    v_loc := 28 ;					  
    if ( (v_schema_cnt = 0 or v_instr_cnt = 0) and v_del_keys_cnt = 0 ) then
        return ''No impacted keys found for stream: '' || v_stream;
    end if;

    v_loc := 29 ;	
    /* ----------------------------------------------------------------------
       7. (Removed by OPT-1.)
          Previously this step materialized tmp_imp_keys = tmp_imp_schema X
          tmp_imp_instr.  cstm_row now uses two semi-joins below, which is
          logically equivalent (a row is in the cartesian iff its schema_id
          and its instr_id are each in the corresponding projection) but
          avoids building the cross-product temp table.
       ---------------------------------------------------------------------- */

    /* ----------------------------------------------------------------------
       8. Re-evaluation source (UPSERT side of MERGE).
          Mirrors Oracle npf_asst_typ_mgr 5-arg overload + RULE_EVALUATION.
       ---------------------------------------------------------------------- */
    v_step_name  := ''BUILD_TMP_SOURCE'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_source as
    with
    schema_dim as (
        select
            ccs.cust_sk,
            ccs.schema_id,
            ccs.schema_desc
        from UAT2_WPA_ASSET_DB.core.NPF_CUST_CSTM_SCHEMA ccs
        join (select distinct schema_id from tmp_imp_schema) s
          on s.schema_id = ccs.schema_id
    ),
    asset_base as (
        select
            na.instr_id,
            na.iss_type,
            na.cntry_risk_dcde
        from UAT2_WPA_ASSET_DB.core.WPA_ASSET na
        where na.iss_type is not null
          and na.instr_id in (select instr_id from tmp_imp_instr)
    ),
    /* Oracle inner overload result: defaults if no NPF_ASSET_CATG row
       (pg_supcatg_asset_code_c / pg_subcatg_asset_code_c etc.).             */
    asset_catg as (
        select
            ab.instr_id,
            ab.iss_type,
            coalesce(ac.supcatg_code, ''30'')           as sup_code,
            coalesce(ac.subcatg_code, ''20'')           as sub_code,
            coalesce(ac.supcatg_desc, ''Other Assets'') as sup_desc,
            coalesce(ac.subcatg_desc, ''Miscellaneous'') as sub_desc
        from asset_base ab
        left join UAT2_WPA_ASSET_DB.core.NPF_ASSET_CATG ac
          on ac.rptg_type = ''WLT''
         and ac.iss_type  = ab.iss_type
    ),
    cntry_desc as (
        /* OPT-2 : reuse asset_base (already filtered to tmp_imp_instr)
           instead of re-scanning WPA_ASSET.  asset_base''s iss_type IS NOT
           NULL guard cannot drop any row that would have been joined into
           rule_eval, since ac.instr_id (the join key in rule_eval) is
           itself sourced from asset_base. */
        select
            ab.instr_id,
            d.dcde_desc as cntry_desc
        from asset_base ab
        left join UAT2_WPA_COMMON_UTIL_DB.core.NPF_DECODE d
          on d.dcde_type = ''CNTRY''
         and d.dcde_code = ab.cntry_risk_dcde
    ),
    /* IF v_rec_cnt <> 0 branch in Oracle: NPF_CSTM_SCHEMA has at least one
       row for (schema, instr, ''WLT'', end_dt is null).                       */
    cstm_row as (
        select
            ncs.schema_id,
            ncs.instr_id,
            ncs.rptg_type,
            ncs.cstm_supcatg_code,
            ncs.cstm_supcatg_desc,
            ncs.npf_supcatg_code,
            ncs.cstm_subcatg_code,
            ncs.cstm_subcatg_desc,
            ncs.npf_subcatg_code,
            row_number() over (
                partition by ncs.schema_id, ncs.instr_id, ncs.rptg_type
                order by ncs.npf_supcatg_code, ncs.npf_subcatg_code
            ) as rn
        from UAT2_WPA_ASSET_DB.core.NPF_CSTM_SCHEMA ncs
        where ncs.rptg_type = ''WLT''
          and ncs.end_dt is null
          /* OPT-1 : was JOIN tmp_imp_keys; equivalent to membership in
             both impact projections. */
          and ncs.schema_id in (select schema_id from tmp_imp_schema)
          and ncs.instr_id  in (select instr_id  from tmp_imp_instr)
    ),
    cstm_exists as (
        select distinct schema_id, instr_id from cstm_row
    ),
    /* in the custom branch the std supcatg_code/subcatg_code come
       from NPF_ASSET_CATG (asset_catg CTE), not from NPF_CSTM_SCHEMA.       */
    custom_out as (
        select
            cr.schema_id,
            cr.instr_id,
            cr.rptg_type,
            ac.iss_type,
            ac.sup_code as supcatg_code,
            ac.sub_code as subcatg_code,
            cr.cstm_supcatg_desc as supcatg_desc,
            cr.cstm_subcatg_desc as subcatg_desc,
            case
                when cr.cstm_supcatg_code is null and cr.cstm_subcatg_code is not null
                    then cr.npf_supcatg_code  || ''-S''
                when cr.cstm_supcatg_code is not null and cr.cstm_subcatg_code is null
                    then cr.cstm_supcatg_code || ''-C''
                when cr.cstm_supcatg_code is null and cr.cstm_subcatg_code is null
                    then cr.npf_supcatg_code  || ''-S''
                else cr.cstm_supcatg_code     || ''-C''
            end as cstm_supcatg_code,
            case
                when cr.cstm_supcatg_code is null and cr.cstm_subcatg_code is not null
                    then cr.cstm_subcatg_code || ''-C''
                when cr.cstm_supcatg_code is not null and cr.cstm_subcatg_code is null
                    then cr.npf_subcatg_code  || ''-S''
                when cr.cstm_supcatg_code is null and cr.cstm_subcatg_code is null
                    then cr.npf_subcatg_code  || ''-S''
                else cr.cstm_subcatg_code     || ''-C''
            end as cstm_subcatg_code,
            cr.cstm_supcatg_desc as cstm_supcatg_desc,
            cr.cstm_subcatg_desc as cstm_subcatg_desc
        from cstm_row cr
        join asset_catg ac
          on ac.instr_id = cr.instr_id
        where cr.rn = 1
    ),
    /* ELSE branch in Oracle: rule_evaluation across NPF_CSTM_RULE_MSTR /
       NPF_CSTM_RULE_COND.                                                   */
    rule_eval as (
        select
            sd.schema_id,
            ac.instr_id,
            r.rule_sk,
            r.rule_cstm_supcatg_desc,
            r.rule_cstm_subcatg_desc,
            cast(max(case when c.logical_oper = ''OR'' then 1 else 0 end) as number(38,0)) as has_or,
            cast(sum(case when c.rule_sk is not null then 1 else 0 end) as number(38,0)) as cond_cnt,
            cast(sum(case
                when c.rule_fld_name = ''CSTM_SUPCATG_DESC'' and
                     ((c.rule_oper = ''EQUAL''    and ac.sup_desc =  c.rule_fld_value) or
                      (c.rule_oper = ''NOTEQUAL'' and ac.sup_desc != c.rule_fld_value))
                then 1
                when c.rule_fld_name = ''CSTM_SUBCATG_DESC'' and
                     ((c.rule_oper = ''EQUAL''    and ac.sub_desc =  c.rule_fld_value) or
                      (c.rule_oper = ''NOTEQUAL'' and ac.sub_desc != c.rule_fld_value))
                then 1
                when c.rule_fld_name = ''CSTM_CNTRY_RISK_DESC'' and
                     ((c.rule_oper = ''EQUAL''    and cd.cntry_desc =  c.rule_fld_value) or
                      (c.rule_oper = ''NOTEQUAL'' and cd.cntry_desc != c.rule_fld_value))
                then 1
                else 0
            end) as number(38,0)) as match_cnt
        from schema_dim sd
        cross join asset_catg ac
        left join UAT2_WPA_ASSET_DB.core.NPF_CSTM_RULE_MSTR r
          on r.schema_id = sd.schema_id
         and r.rule_stat = ''A''
        left join UAT2_WPA_ASSET_DB.core.NPF_CSTM_RULE_COND c
          on c.rule_sk = r.rule_sk
        left join cntry_desc cd
          on cd.instr_id = ac.instr_id
        group by sd.schema_id, ac.instr_id, r.rule_sk,
                 r.rule_cstm_supcatg_desc, r.rule_cstm_subcatg_desc
    ),
    /*  Oracle keeps FIRST matched rule in _1 and LAST matched rule
       in _2 (every subsequent match overwrites _2).  rn_first = ascending,
       rn_last = descending so a single SELECT pivots both ends.             */
    matched_rules as (
        select
            re.schema_id,
            re.instr_id,
            re.rule_cstm_supcatg_desc,
            re.rule_cstm_subcatg_desc,
            row_number() over (partition by re.schema_id, re.instr_id
                               order by re.rule_sk asc)  as rn_first,
            row_number() over (partition by re.schema_id, re.instr_id
                               order by re.rule_sk desc) as rn_last,
            count(*)   over (partition by re.schema_id, re.instr_id) as match_total
        from rule_eval re
        where re.cond_cnt > 0
          and (
                (re.has_or = 1 and re.match_cnt > 0)
             or (re.has_or = 0 and re.match_cnt = re.cond_cnt)
          )
    ),
    rule_pick as (
        select
            mr.schema_id,
            mr.instr_id,
            max(case when mr.rn_first = 1 then mr.rule_cstm_supcatg_desc end) as r1_sup,
            max(case when mr.rn_first = 1 then mr.rule_cstm_subcatg_desc end) as r1_sub,
            -- last match only when there is more than one match
            max(case when mr.rn_last  = 1 and mr.match_total > 1
                     then mr.rule_cstm_supcatg_desc end) as rN_sup,
            max(case when mr.rn_last  = 1 and mr.match_total > 1
                     then mr.rule_cstm_subcatg_desc end) as rN_sub
        from matched_rules mr
        group by mr.schema_id, mr.instr_id
    ),
    /* Oracle ELSE branch:
         po_supcatg_code/sub - from inner overload
         po_supcatg_desc/sub - COALESCE(_2 last, _1 first, p_ast_*_desc)
         cstm_supcatg_code   - sup_code || ''-S''
         cstm_subcatg_code   - sup_code || ''-'' || sub_code || ''-S''        */
    fallback_out as (
        select
            sd.schema_id,
            sd.cust_sk,
            sd.schema_desc,
            ac.instr_id,
            ''WLT'' as rptg_type,
            ac.iss_type,
            ac.sup_code as supcatg_code,
            ac.sub_code as subcatg_code,
            coalesce(rp.rN_sup, rp.r1_sup, ac.sup_desc) as supcatg_desc,
            coalesce(rp.rN_sub, rp.r1_sub, ac.sub_desc) as subcatg_desc,
            ac.sup_code || ''-S''                       as cstm_supcatg_code,
            ac.sup_code || ''-'' || ac.sub_code || ''-S'' as cstm_subcatg_code,
            coalesce(rp.rN_sup, rp.r1_sup, ac.sup_desc) as cstm_supcatg_desc,
            coalesce(rp.rN_sub, rp.r1_sub, ac.sub_desc) as cstm_subcatg_desc
        from schema_dim sd
        cross join asset_catg ac
        left join rule_pick rp
          on rp.schema_id = sd.schema_id
         and rp.instr_id  = ac.instr_id
        left join cstm_exists ce
          on ce.schema_id = sd.schema_id
         and ce.instr_id  = ac.instr_id
        where ce.schema_id is null
    )
    select
        co.schema_id,
        sd.cust_sk,
        co.instr_id,
        co.rptg_type,
        co.iss_type,
        co.supcatg_code,
        co.subcatg_code,
        co.supcatg_desc,
        co.subcatg_desc,
        co.cstm_supcatg_code,
        co.cstm_subcatg_code,
        co.cstm_supcatg_desc,
        co.cstm_subcatg_desc,
        sd.schema_desc,
        current_timestamp() as updated_at
    from custom_out co
    join schema_dim sd
      on sd.schema_id = co.schema_id

    union all

    select
        fo.schema_id,
        fo.cust_sk,
        fo.instr_id,
        fo.rptg_type,
        fo.iss_type,
        fo.supcatg_code,
        fo.subcatg_code,
        fo.supcatg_desc,
        fo.subcatg_desc,
        fo.cstm_supcatg_code,
        fo.cstm_subcatg_code,
        fo.cstm_supcatg_desc,
        fo.cstm_subcatg_desc,
        fo.schema_desc,
        current_timestamp() as updated_at
    from fallback_out fo;

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_source);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    v_loc := 30 ;
    /* ----------------------------------------------------------------------
       9. Hard-delete payload (only for tmp_del_* drivers).
          Target rows for these (schema/instr) values are removed outright.
       ---------------------------------------------------------------------- */
    /* OPT-3 : single scan with OR predicate.  Outer DISTINCT preserves
       the UNION-DISTINCT semantics of the prior two-leg version (a target
       row that matched both legs would otherwise be emitted twice). */

    v_step_name  := ''BUILD_TMP_DELETE_TARGET'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_delete_target as
    select distinct
        t.schema_id,
        t.cust_sk,
        t.instr_id,
        t.rptg_type,
        t.iss_type,
        t.supcatg_code,
        t.subcatg_code,
        t.supcatg_desc,
        t.subcatg_desc,
        t.cstm_supcatg_code,
        t.cstm_subcatg_code,
        t.cstm_supcatg_desc,
        t.cstm_subcatg_desc,
        t.schema_desc,
        t.updated_at
    from UAT2_WPA_ASSET_DB.core.wpa_cstm_asset_schema_catg t
    where t.schema_id in (select schema_id from tmp_del_schema)
       or t.instr_id  in (select instr_id  from tmp_del_instr);

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_delete_target);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    v_loc := 31 ;
    /* ----------------------------------------------------------------------
       10. Build merge source (re-evaluation rows + hard-delete rows).
       ---------------------------------------------------------------------- */
    v_step_name  := ''BUILD_TMP_MERGE_SOURCE'';
    v_step_start := current_timestamp();

    create or replace temporary table UAT2_WPA_ASSET_DB.CORE.tmp_merge_source as
    select
        s.schema_id, s.cust_sk, s.instr_id, s.rptg_type, s.iss_type,
        s.supcatg_code, s.subcatg_code, s.supcatg_desc, s.subcatg_desc,
        s.cstm_supcatg_code, s.cstm_subcatg_code,
        s.cstm_supcatg_desc, s.cstm_subcatg_desc,
        s.schema_desc, s.updated_at,
        0 as is_delete
    from tmp_source s

    union all

    select
        d.schema_id, d.cust_sk, d.instr_id, d.rptg_type, d.iss_type,
        d.supcatg_code, d.subcatg_code, d.supcatg_desc, d.subcatg_desc,
        d.cstm_supcatg_code, d.cstm_subcatg_code,
        d.cstm_supcatg_desc, d.cstm_subcatg_desc,
        d.schema_desc, d.updated_at,
        1 as is_delete
    from tmp_delete_target d;

    v_query_id  := last_query_id();
    v_step_rows := (select count(*) from UAT2_WPA_ASSET_DB.CORE.tmp_merge_source);

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":'' || NVL(:v_step_rows::VARCHAR,''null'') ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    v_loc := 32 ;
    /* ----------------------------------------------------------------------
       11. : MERGE on (schema_id, instr_id, rptg_type).
            iss_type is payload, not identity.
       ---------------------------------------------------------------------- */
    v_step_name  := ''MAIN_MERGE'';
    v_step_start := current_timestamp();

    merge into UAT2_WPA_ASSET_DB.core.wpa_cstm_asset_schema_catg t
    using tmp_merge_source s
      on t.schema_id = s.schema_id
     and t.instr_id  = s.instr_id
     and t.rptg_type = s.rptg_type
    when matched and s.is_delete = 1 then delete
    when matched then update set
        t.cust_sk            = s.cust_sk,
        t.iss_type           = s.iss_type,
        t.supcatg_code       = s.supcatg_code,
        t.subcatg_code       = s.subcatg_code,
        t.supcatg_desc       = s.supcatg_desc,
        t.subcatg_desc       = s.subcatg_desc,
        t.cstm_supcatg_code  = s.cstm_supcatg_code,
        t.cstm_subcatg_code  = s.cstm_subcatg_code,
        t.cstm_supcatg_desc  = s.cstm_supcatg_desc,
        t.cstm_subcatg_desc  = s.cstm_subcatg_desc,
        t.schema_desc        = s.schema_desc,
        t.updated_at         = s.updated_at
    when not matched and s.is_delete = 0 then insert (
        schema_id, cust_sk, instr_id, rptg_type, iss_type,
        supcatg_code, subcatg_code, supcatg_desc, subcatg_desc,
        cstm_supcatg_code, cstm_subcatg_code,
        cstm_supcatg_desc, cstm_subcatg_desc,
        schema_desc, updated_at
    ) values (
        s.schema_id, s.cust_sk, s.instr_id, s.rptg_type, s.iss_type,
        s.supcatg_code, s.subcatg_code, s.supcatg_desc, s.subcatg_desc,
        s.cstm_supcatg_code, s.cstm_subcatg_code,
        s.cstm_supcatg_desc, s.cstm_subcatg_desc,
        s.schema_desc, s.updated_at
    );

    v_query_id  := last_query_id();

    v_additional_detail := :v_additional_detail ||
        IFF(:v_additional_detail = '''', '''', '','') ||
        ''{"v_loc":'' || :v_loc ||
        '',"step":"'' || :v_step_name || ''"'' ||
        '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
        '',"rows":null'' ||
        '',"duration_secs":'' || (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR ||
        '',"status":"SUCCESS","error":null}'';

    /* ====================================================================
       STEP 33 : Build run summary text + record-counts for audit.
       ==================================================================== */
    v_loc       := 33 ;
    v_step_desc := ''BUILD-RUN-SUMMARY'';
    v_row_cnt   := coalesce(v_schema_cnt,0) + coalesce(v_instr_cnt,0) + coalesce(v_del_keys_cnt,0);
    
    v_addinfo   := ''STATUS=COMPLETED''
        || ''; stream=''        || v_stream
        || ''; imp_schemas=''   || v_schema_cnt
        || ''; imp_instr=''     || v_instr_cnt
        || ''; hard_del_keys='' || v_del_keys_cnt
        || ''; steps=['' || :v_additional_detail || '']'';

    /* ====================================================================
       STEP 34 : COMPLETED - log successful completion.
       ADDED: Audit logging (COMPLETED) - writes to wpa_asset_proc_audit
       ==================================================================== */
    v_loc         := 34 ;
    v_step_desc   := ''COMPLETED'';
    v_endtime     := current_timestamp();
    v_duration_secs := datediff(''millisecond'', :v_starttime, :v_endtime) / 1000.0;
    v_status      := ''SUCCESS'';

    INSERT INTO UAT2_wpa_asset_db.core.wpa_asset_proc_audit
          (
           asset_proc_audit_id,
           sid,
           obj_name,
           input_param,
           stream_name,
           proc_start_tm,
           proc_end_tm,
           duration_secs,
           insert_cnt,
           update_cnt,
           delete_cnt,
           processed_cnt,
           error_cnt,
           status,
           sqlcode_val,
           sqlstate_val,
           additional_comments,
           upd_by
          )
    VALUES (
           :v_proc_audit_id,
           :v_session_id,
           :v_obj_name,
           :v_stream,
           :v_stream,
           :v_starttime,
           :v_endtime,
           :v_duration_secs,
           0,
           0,
           :v_del_keys_cnt,
           :v_row_cnt,
           0,
           :v_status,
           NULL,
           NULL,
           :v_addinfo,
           :v_obj_name
          );

    return ''Processed stream: '' || v_stream
        || '', impacted schemas: '' || v_schema_cnt
        || '', impacted instr: ''   || v_instr_cnt
        || '', hard-delete keys: '' || v_del_keys_cnt;


/* ========================================================================
   ADDED: Exception handling - capture SQLCODE / SQLERRM / SQLSTATE /
          logical step (v_loc + v_step_desc) and write a FAILED audit row
          to wpa_asset_proc_audit, then RAISE so the caller fails too.
   ======================================================================== */
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        -- ADDED: Exception handling - capture error details
        v_endtime       := current_timestamp();
        v_duration_secs := datediff(''millisecond'', :v_starttime, :v_endtime) / 1000.0;
        v_status        := ''FAILED'';
        v_error_cnt     := 1;
        v_sqlcode       := sqlcode::varchar;
        v_sqlstate      := sqlstate;
        v_err_msg       := ''sqlcode=''    || sqlcode
                        || ''; sqlstate='' || sqlstate
                        || ''; sqlerrm=''  || sqlerrm
                        || ''; loc=''      || :v_loc
                        || ''; step=''     || :v_step_desc;

        -- Append failed step JSON entry to step trace
        BEGIN
            v_query_id := last_query_id();
        EXCEPTION
            WHEN OTHER THEN v_query_id := NULL;
        END;
        v_additional_detail := NVL(:v_additional_detail,'''') ||
            IFF(NVL(:v_additional_detail,'''') = '''', '''', '','') ||
            ''{"v_loc":'' || :v_loc ||
            '',"step":"'' || NVL(:v_step_name,:v_step_desc) || ''"'' ||
            '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
            '',"rows":null'' ||
            '',"duration_secs":'' ||
              IFF(:v_step_start IS NULL, ''null'',
                  (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR) ||
            '',"status":"FAILED"'' ||
            '',"sqlcode":"''  || NVL(:v_sqlcode,'''')  || ''"'' ||
            '',"sqlstate":"'' || NVL(:v_sqlstate,'''') || ''"'' ||
            '',"error":"''    || REPLACE(NVL(:v_err_msg,''''),''"'',''\\\\"'') || ''"}'';

        -- ADDED: Audit logging (FAILED)
        INSERT INTO UAT2_wpa_asset_db.core.wpa_asset_proc_audit
              (
               asset_proc_audit_id,
               sid,
               obj_name,
               input_param,
               stream_name,
               proc_start_tm,
               proc_end_tm,
               duration_secs,
               insert_cnt,
               update_cnt,
               delete_cnt,
               processed_cnt,
               error_cnt,
               status,
               sqlcode_val,
               sqlstate_val,
               additional_comments,
               upd_by
              )
        VALUES (
               :v_proc_audit_id,
               :v_session_id,
               :v_obj_name,
               :v_stream,
               :v_stream,
               :v_starttime,
               :v_endtime,
               :v_duration_secs,
               0,
               0,
               :v_del_keys_cnt,
               :v_row_cnt,
               :v_error_cnt,
               :v_status,
               :v_sqlcode,
               :v_sqlstate,
               ''STATUS=FAILED; STEP='' || :v_step_desc || ''; LOC='' || :v_loc || ''; err='' || :v_err_msg || ''; steps=['' || :v_additional_detail || '']'',
               :v_obj_name
              );

        RAISE;

    WHEN OTHER THEN
        -- ADDED: Exception handling - catch-all for non-statement errors
        v_endtime       := current_timestamp();
        v_duration_secs := datediff(''millisecond'', :v_starttime, :v_endtime) / 1000.0;
        v_status        := ''FAILED'';
        v_error_cnt     := 1;
        v_sqlcode       := sqlcode::varchar;
        v_sqlstate      := sqlstate;
        v_err_msg       := ''sqlcode=''    || sqlcode
                        || ''; sqlstate='' || sqlstate
                        || ''; sqlerrm=''  || sqlerrm
                        || ''; loc=''      || :v_loc
                        || ''; step=''     || :v_step_desc;

        -- Append failed step JSON entry to step trace
        BEGIN
            v_query_id := last_query_id();
        EXCEPTION
            WHEN OTHER THEN v_query_id := NULL;
        END;
        v_additional_detail := NVL(:v_additional_detail,'''') ||
            IFF(NVL(:v_additional_detail,'''') = '''', '''', '','') ||
            ''{"v_loc":'' || :v_loc ||
            '',"step":"'' || NVL(:v_step_name,:v_step_desc) || ''"'' ||
            '',"query_id":"'' || NVL(:v_query_id,'''') || ''"'' ||
            '',"rows":null'' ||
            '',"duration_secs":'' ||
              IFF(:v_step_start IS NULL, ''null'',
                  (DATEDIFF(''millisecond'', :v_step_start, CURRENT_TIMESTAMP())/1000.0)::VARCHAR) ||
            '',"status":"FAILED"'' ||
            '',"sqlcode":"''  || NVL(:v_sqlcode,'''')  || ''"'' ||
            '',"sqlstate":"'' || NVL(:v_sqlstate,'''') || ''"'' ||
            '',"error":"''    || REPLACE(NVL(:v_err_msg,''''),''"'',''\\\\"'') || ''"}'';

        -- ADDED: Audit logging (FAILED)
        INSERT INTO UAT2_wpa_asset_db.core.wpa_asset_proc_audit
              (
               asset_proc_audit_id,
               sid,
               obj_name,
               input_param,
               stream_name,
               proc_start_tm,
               proc_end_tm,
               duration_secs,
               insert_cnt,
               update_cnt,
               delete_cnt,
               processed_cnt,
               error_cnt,
               status,
               sqlcode_val,
               sqlstate_val,
               additional_comments,
               upd_by
              )
        VALUES (
               :v_proc_audit_id,
               :v_session_id,
               :v_obj_name,
               :v_stream,
               :v_stream,
               :v_starttime,
               :v_endtime,
               :v_duration_secs,
               0,
               0,
               :v_del_keys_cnt,
               :v_row_cnt,
               :v_error_cnt,
               :v_status,
               :v_sqlcode,
               :v_sqlstate,
               ''STATUS=FAILED; STEP='' || :v_step_desc || ''; LOC='' || :v_loc || ''; err='' || :v_err_msg || ''; steps=['' || :v_additional_detail || '']'',
               :v_obj_name
              );

        RAISE;
end;
';