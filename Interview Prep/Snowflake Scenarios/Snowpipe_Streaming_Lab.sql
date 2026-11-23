-- =====================================================================
-- SNOWPIPE STREAMING (HIGH-PERFORMANCE ARCHITECTURE) - BEGINNER LAB SHEET
-- Folder : Interview Prep / Snowflake Scenarios
-- Goal   : Push ROWS from a Python program straight into a Snowflake table
--          in seconds - no files, no stage, no S3, no SQS.
--
-- HOW IT WORKS (big picture)
--   Python app (SDK) --append_row()--> CHANNEL --> PIPE "STREAM_EVENTS-STREAMING"
--                                                   --> TABLE STREAM_EVENTS
--   * CLIENT  = one connection from your app (StreamingIngestClient)
--   * CHANNEL = an ordered lane of rows inside the client (like a Kafka partition)
--   * OFFSET TOKEN = a number YOU attach to each row; Snowflake remembers the last
--                    committed one per channel, so after a crash you resume from there
--   * PIPE    = in the high-performance architecture, channels write through a pipe.
--               The default pipe <TABLE>-STREAMING is created automatically on first use.
--   * Auth    = key pair (private key in the app, public key on the Snowflake user)
--
-- COMPARE WITH THE OTHER SHEET (Snowpipe_S3_AutoIngest_Setup.sql)
--   Snowpipe (auto-ingest) : FILES in S3 -> S3 event -> SQS -> COPY   (~30-60 s)
--   Snowpipe Streaming     : ROWS from code -> channel -> table       (~seconds)
--
-- WHERE EACH STEP HAPPENS
--   [SF]  = run in Snowflake (this worksheet)
--   [PY]  = Python program, run in AWS CloudShell (or your own computer)
--   [OS]  = shell command (openssl) in AWS CloudShell
--
--   WHY CLOUDSHELL: the SDK must reach https://<account>.snowflakecomputing.com.
--   - The Cortex Code sandbox blocks that host (HTTP 403 "egress ... not allowed").
--   - A Snowflake notebook needs an EXTERNAL ACCESS INTEGRATION, and trial accounts get
--     "External access is not supported for trial accounts".
--   - AWS CloudShell (free browser terminal, Python + openssl preinstalled) works.
--
-- MY ENVIRONMENT (actual values used in this lab)
--   Account identifier  : FBIAJMH-QH29041   (URL https://FBIAJMH-QH29041.snowflakecomputing.com)
--   Login user / role   : THAZHAISELVAN / ACCOUNTADMIN   (chosen for the lab - see note in S1)
--   Database.schema     : SF_SCENARIO_BASED_LEARNING.SNOWPIPE   (same as the Snowpipe lab)
--   Target table        : STREAM_EVENTS
--   Pipe (auto-created) : "STREAM_EVENTS-STREAMING"
--   Python SDK          : snowpipe-streaming 1.9.4 (pip install snowpipe-streaming)
--   Private key         : ~/keys/rsa_key.p8 in AWS CloudShell  (NEVER commit to Git)
--   Python program      : ~/stream_events.py in CloudShell (copy of stream_events.py next to this sheet,
--                         with KEY_PATH/PROFILE_PATH set to /home/cloudshell-user/keys/...)
--
-- ORDER AND STATUS
--   S0 [OS] Generate key pair (CloudShell) ............. [DONE]
--   S1 [SF] Register public key on the user ............ [DONE]
--   S2 [SF] Create target table ........................ [DONE]
--   S3 [PY] Install SDK (CloudShell) ................... [DONE]
--   S4 [PY] Stream 10 rows (first run) ................. [DONE]  10 rows, offsets 1-10, ~2 s
--   S5 [SF] Verify rows, pipe, channel ................. [DONE]
--   T1-T5   Experiments (resume, new channel, replay, latency, gaps) [DONE]  see results above T5
--   T2 retry: second channel (--channel channel_2) ...... [DONE]  channel_2 offsets 1-5, own sequence
--   LAB COMPLETE - run CLEANUP at the bottom when finished
--   M  [SF] Monitoring + cost .......................... [TODO]
-- =====================================================================


-- =====================================================================
-- S0 [OS] GENERATE A KEY PAIR                                   [DONE]
-- =====================================================================
--   (in AWS CloudShell)
--   pip3 install --user snowpipe-streaming
--   mkdir -p ~/keys && cd ~/keys
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out keys/rsa_key.p8 -nocrypt
--   openssl rsa -in keys/rsa_key.p8 -pubout -out keys/rsa_key.pub
--   grep -v "^-" keys/rsa_key.pub | tr -d '\n'     # public key on one line, used in S1
--
--   rsa_key.p8  = PRIVATE key (secret, stays with the app)
--   rsa_key.pub = PUBLIC key  (safe to share, goes on the Snowflake user)


-- =====================================================================
-- S1 [SF] REGISTER THE PUBLIC KEY ON THE USER                   [TODO]
-- =====================================================================
-- Note: For the lab we use your own user. In real projects use a dedicated
--       SERVICE user + least-privilege role (INSERT on the table only), e.g.
--       CREATE USER STREAMING_USER TYPE = SERVICE; CREATE ROLE STREAMING_ROLE; ...
--       Adding a key does NOT change your password or Snowsight login.
USE ROLE ACCOUNTADMIN;

-- Paste the one-line public key printed in CloudShell (S0):
ALTER USER THAZHAISELVAN SET RSA_PUBLIC_KEY='<public key from CloudShell>';

-- Check: RSA_PUBLIC_KEY_FP should now show SHA256:xxxx and HAS_KEYPAIR = true
DESC USER THAZHAISELVAN;


-- =====================================================================
-- S2 [SF] CREATE THE TARGET TABLE                               [TODO]
-- =====================================================================
-- No stage, no file format, no COPY. Only a table.
CREATE TABLE IF NOT EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS (
  EVENT_ID      NUMBER,
  DEVICE_ID     VARCHAR,
  EVENT_TYPE    VARCHAR,
  TEMPERATURE   NUMBER(5,2),
  PAYLOAD       VARIANT,        -- JSON object from the app (send a dict, not a string)
  EVENT_TS      TIMESTAMP_NTZ,  -- when the app created the row (UTC)
  CHANNEL_NAME  VARCHAR,        -- which channel sent it (for gap checks)
  STREAM_OFFSET NUMBER          -- offset token as a number (for gap/duplicate checks)
);
-- The pipe "STREAM_EVENTS-STREAMING" is created automatically the first time
-- the SDK opens a channel. (Create your own pipe only for transformations/clustering.)


-- =====================================================================
-- S3 [PY] INSTALL THE SDK                                       [DONE]
-- =====================================================================
--   python3 -m venv ssenv
--   ./ssenv/bin/pip install snowpipe-streaming


-- =====================================================================
-- S4 [PY] STREAM ROWS - FIRST RUN                               [TODO]
-- =====================================================================
--   (in AWS CloudShell)  python3 stream_events.py --rows 10
--   RESULT: 10 rows on channel_1, offsets 1-10, PAYLOAD = OBJECT, all within ~2 seconds.
--
-- What the program does (stream_events.py):
--   1. Builds a profile (account, user, url, private key, role)
--   2. client  = StreamingIngestClient(db, schema, pipe="STREAM_EVENTS-STREAMING")
--   3. channel = client.open_channel("channel_1")
--   4. last    = channel.get_latest_committed_offset_token()   -> resume point
--   5. channel.append_row({...}, offset_token="N") for each row
--   6. channel.wait_for_commit(...)  -> waits until Snowflake confirms the rows
--   7. channel.get_channel_status()  -> status code, row errors, last offset
--   8. channel.close(); client.close()


-- =====================================================================
-- S5 [SF] VERIFY                                                [TODO]
-- =====================================================================
USE WAREHOUSE DEMO_WH;

-- Rows arrived?
SELECT * FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS ORDER BY STREAM_OFFSET;

-- PAYLOAD should be OBJECT (if VARCHAR, the app sent a JSON string instead of a dict)
SELECT PAYLOAD, TYPEOF(PAYLOAD) FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS LIMIT 3;

-- The auto-created pipe
SHOW PIPES IN SCHEMA SF_SCENARIO_BASED_LEARNING.SNOWPIPE;

-- The auto-created pipe shows KIND = STREAMING, is_snowflake_managed = true and the definition
--   COPY INTO STREAM_EVENTS FROM TABLE(DATA_SOURCE(TYPE => 'STREAMING')) MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
--   -> that is why the dict keys only need to match the column names.

-- The channel and its last committed offset
SHOW CHANNELS IN TABLE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS;
--   Observed: returned no rows after the run (the program closes the channel; with the
--   high-performance architecture channels may belong to the pipe). Not confirmed which.
--   The program's printed "last committed offset" is the reliable progress check.


-- =====================================================================
-- EXPERIMENTS (run each, then re-run the S5 queries)
-- =====================================================================
-- T1 RESUME AFTER RESTART (offset tokens)
--    python3 stream_events.py --rows 5
--    The program asks Snowflake for the last committed offset (10) and starts at 11.
--    -> This is how a real app continues after a crash without losing or repeating rows.
--
-- T2 SECOND CHANNEL (parallel lanes)
--    python3 stream_events.py --rows 5 --channel channel_2
--    -> channel_2 has its own offsets (1..5). SHOW CHANNELS now lists 2 channels.
--
-- T3 REPLAY OLD OFFSETS (what if the app ignores the offset token?)
--    python3 stream_events.py --rows 3 --start-offset 1
--    -> Rows with offsets 1-3 are inserted AGAIN = duplicates.
--       Snowflake stores the offset token; it is the APP's job to read it and resume.
--       (Compare: file Snowpipe skips by file name; Streaming relies on the app + offsets.)
--    Find the duplicates:
SELECT CHANNEL_NAME, STREAM_OFFSET, COUNT(*) AS COPIES
FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS
GROUP BY 1, 2 HAVING COUNT(*) > 1 ORDER BY 1, 2;
--
-- T4 LATENCY (seconds, not minutes)
--    python3 stream_events.py --rows 20 --delay 0.5
--    While it runs, re-run this query a few times and watch the count grow:
SELECT COUNT(*) AS ROWS_NOW, MAX(EVENT_TS) AS LATEST_EVENT_UTC
FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS;
--
-- WHAT ACTUALLY HAPPENED IN MY RUN (2026-11-22, 41 rows, all channel_1)
--   Run 1 first run : offsets 1-10   OK
--   Run 2 T1 resume : offsets 11-15  OK (resumed after last committed offset)
--   Run 3 T2        : channel_1 16-20 instead of channel_2 1-5 -> --channel option not used
--   Run 4 T3 replay : only offset 1 saved (3 sent). BUG in the first program version:
--                     it waited for committed >= 3, which was already true (20), and closed
--                     the channel before rows 2-3 were committed. Fixed: wait for the exact
--                     last offset, then wait_for_flush() before close().
--   Run 5 T4        : resumed at 2 (not 21) and re-loaded 2-20 -> 20 duplicate offsets.
--   T2 retry        : channel_2 offsets 1-5, no duplicates, channel_1 untouched (41 rows)
--                     -> each channel keeps its own independent offset sequence.
--   LESSON: the committed offset token is simply the LAST value the app sent, not the
--           highest. Replaying old offsets moves it backwards and every later resume
--           repeats data. Never reuse offsets; dedupe downstream (QUALIFY ROW_NUMBER()).
--
-- T5 GAP CHECK (missing offsets in a channel)
SELECT CHANNEL_NAME, STREAM_OFFSET,
       LAG(STREAM_OFFSET) OVER (PARTITION BY CHANNEL_NAME ORDER BY STREAM_OFFSET) AS PREV_OFFSET
FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS
QUALIFY STREAM_OFFSET > PREV_OFFSET + 1;
--    (No rows = no gaps.)


-- =====================================================================
-- M  [SF] MONITORING AND COST                                   [TODO]
-- =====================================================================
-- Rows per minute
SELECT DATE_TRUNC('minute', EVENT_TS) AS MINUTE_UTC, COUNT(*) AS ROWS_PER_MIN
FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS
GROUP BY 1 ORDER BY 1 DESC;

-- Channel events (ACCOUNT_USAGE has latency of up to a few hours)
SELECT CHANNEL_NAME, EVENT_TYPE, EVENT_TIMESTAMP, ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPIPE_STREAMING_CHANNEL_HISTORY
WHERE PIPE_NAME ILIKE '%STREAM_EVENTS%'
ORDER BY EVENT_TIMESTAMP DESC;

-- Credits used by Snowpipe Streaming (also delayed)
SELECT DATE_TRUNC('day', START_TIME) AS DAY, SUM(CREDITS_USED) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE SERVICE_TYPE = 'SNOWPIPE_STREAMING'
GROUP BY 1 ORDER BY 1 DESC;


-- =====================================================================
-- INTERVIEW QUICK NOTES
-- =====================================================================
--  * Snowpipe Streaming = row-level ingestion through an SDK/REST/Kafka connector.
--    No files or stages. Latency is a few seconds.
--  * High-performance architecture: channels write through a PIPE object
--    (default pipe <TABLE>-STREAMING is auto-created). Classic streaming wrote
--    directly to tables and is being deprecated.
--  * Client -> channels -> pipe -> table. A channel is an ordered lane; ordering is
--    guaranteed only WITHIN a channel. Use several channels for parallelism.
--  * Offset token = app-defined position per channel. After a restart the app calls
--    get_latest_committed_offset_token() and resumes -> exactly-once if the app does
--    this correctly; replaying old offsets creates duplicates.
--  * Auth = key pair (JWT). Use a SERVICE user with a least-privilege role in production.
--  * Send VARIANT data as native dicts/lists, not JSON strings.
--  * Cost: serverless; billed for the ingested data/compute (see METERING_HISTORY),
--    usually cheaper than file Snowpipe for many small, continuous events.
--  * When to pick which:
--      files already land in a bucket          -> Snowpipe (auto-ingest)
--      events from apps, IoT, Kafka, CDC       -> Snowpipe Streaming
--      one-time / scheduled bulk loads         -> COPY INTO on a warehouse
--  * Downstream: STREAM_EVENTS -> Dynamic Table / Stream + Task for curated data.


-- =====================================================================
-- CLEANUP
-- =====================================================================
-- ALTER USER THAZHAISELVAN UNSET RSA_PUBLIC_KEY;       -- remove the lab key
-- DROP PIPE IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE."STREAM_EVENTS-STREAMING";
-- DROP TABLE IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.STREAM_EVENTS;
-- [OS] rm -rf ~/keys ~/stream_events.py   (in CloudShell) -- delete the private key
