-- =====================================================================
-- SNOWPIPE (AUTO-INGEST) FROM AWS S3 - BEGINNER STEP-BY-STEP SHEET
-- Folder : Interview Prep / Snowflake Scenarios
-- Goal   : A file dropped into S3 is loaded into a Snowflake table
--          automatically within about a minute, without a warehouse or a scheduler.
--
-- HOW IT WORKS (big picture)
--   S3 bucket --(event: new file)--> SQS queue (owned by Snowflake)
--             --> PIPE runs its COPY INTO --> TARGET TABLE
--   Access to the bucket = STORAGE INTEGRATION + AWS IAM ROLE (no keys stored)
--
-- WHERE EACH STEP HAPPENS
--   [SF]  = run in Snowflake (this worksheet)
--   [AWS] = do in the AWS Console (free tier is enough)
--
-- PROGRESS LEGEND
--   [DONE] = already completed      [TODO] = still to do
--
-- MY ENVIRONMENT (actual values used in this lab)
--   Snowflake account / region : OB04393 / AWS_EU_CENTRAL_1 (Frankfurt)
--   S3 bucket                  : my-snowpipe-demo-thazhaiselvan   (folder: orders/, region eu-north-1)
--   Snowpipe SQS queue ARN     : arn:aws:sqs:eu-north-1:241227970269:sf-snowpipe-AIDATQKSOW3O6X4EHGDF4-ZDQpSYrf6VeL_uM1yI4Lzg
--   AWS account                : 717279725946
--   IAM policy / role          : snowflake_s3_read_policy / snowflake_s3_role
--   IAM role ARN               : arn:aws:iam::717279725946:role/snowflake_s3_role
--   Snowflake database.schema  : SF_SCENARIO_BASED_LEARNING.SNOWPIPE
--   Storage integration        : S3_DEMO_INT   (account-level object, not inside a schema)
--   Warehouse (testing only)   : DEMO_WH (XSMALL, auto-suspend 60s)
--
-- ORDER AND STATUS
--   A1  [AWS] S3 bucket + orders/ folder ............... [DONE]
--   A2  [AWS] IAM policy + role ........................ [DONE]
--   SF0 [SF]  Schema + warehouse ....................... [DONE]
--   SF1 [SF]  Storage integration ...................... [DONE]
--   SF2 [SF]  DESC integration (get ARN + external ID) . [DONE]
--   A3  [AWS] Update the role's trust policy ........... [DONE]
--   SF3 [SF]  File format .............................. [DONE]
--   SF4 [SF]  External stage + LIST test ............... [DONE]
--   SF5 [SF]  Target table ............................. [DONE]
--   SF6 [SF]  Pipe + get the SQS ARN ................... [DONE]
--   A4  [AWS] S3 event notification -> SQS ............. [TODO]  <-- YOU ARE HERE
--   T   Test: upload a CSV and check the table ......... [TODO]
--   M   Monitor / troubleshoot ......................... [TODO]
-- =====================================================================


-- =====================================================================
-- A1 [AWS] CREATE AN S3 BUCKET                                   [DONE]
-- =====================================================================
--   S3 > Create bucket
--     Name   : my-snowpipe-demo-thazhaiselvan
--     Region : eu-north-1 (Snowflake account is eu-central-1; same region is best
--              to avoid data transfer cost - check with SELECT CURRENT_REGION();)
--     "Block all public access" left ON (Snowflake uses the IAM role, not public access)
--   Bucket > Create folder > orders


-- =====================================================================
-- A2 [AWS] CREATE AN IAM POLICY + ROLE                           [DONE]
-- =====================================================================
--   IAM > Policies > Create policy > JSON tab:
--   {
--     "Version": "2012-10-17",
--     "Statement": [
--       { "Effect": "Allow",
--         "Action": ["s3:GetObject","s3:GetObjectVersion"],
--         "Resource": "arn:aws:s3:::my-snowpipe-demo-thazhaiselvan/orders/*" },
--       { "Effect": "Allow",
--         "Action": ["s3:ListBucket","s3:GetBucketLocation"],
--         "Resource": "arn:aws:s3:::my-snowpipe-demo-thazhaiselvan",
--         "Condition": { "StringLike": { "s3:prefix": ["orders/*"] } } }
--     ]
--   }
--   Name: snowflake_s3_read_policy
--
--   IAM > Roles > Create role
--     Trusted entity : AWS account > "This account"   (placeholder, replaced in A3)
--     "Require external ID" = 0000                     (placeholder, replaced in A3)
--     Policy         : snowflake_s3_read_policy
--     Name           : snowflake_s3_role
--   Role ARN: arn:aws:iam::717279725946:role/snowflake_s3_role


-- =====================================================================
-- SF0 [SF] SCHEMA + WAREHOUSE                                    [DONE]
-- =====================================================================
USE ROLE ACCOUNTADMIN;   -- CREATE INTEGRATION needs ACCOUNTADMIN (or that privilege)

CREATE SCHEMA IF NOT EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE;

-- Only for running test queries; the pipe itself is serverless
CREATE WAREHOUSE IF NOT EXISTS DEMO_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE DEMO_WH;
USE SCHEMA SF_SCENARIO_BASED_LEARNING.SNOWPIPE;


-- =====================================================================
-- SF1 [SF] STORAGE INTEGRATION (Snowflake <-> your IAM role)     [DONE]
-- =====================================================================
-- WARNING: do NOT run CREATE OR REPLACE on this again. Recreating it
--          generates a NEW external ID, and then A3 has to be redone.
CREATE STORAGE INTEGRATION IF NOT EXISTS S3_DEMO_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::717279725946:role/snowflake_s3_role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://my-snowpipe-demo-thazhaiselvan/orders/');


-- =====================================================================
-- SF2 [SF] GET SNOWFLAKE'S IDENTITY FOR THE TRUST POLICY         [DONE]
-- =====================================================================
DESC STORAGE INTEGRATION S3_DEMO_INT;
-- Values returned:
--   STORAGE_AWS_IAM_USER_ARN : arn:aws:iam::241227970269:user/e28c2000-s
--   STORAGE_AWS_EXTERNAL_ID  : OB04393_SFCRole=4_S55Qsq545puQqGba6iCkrwPsvz8=
--   (The ARN is the AWS user Snowflake uses for this account. The external ID
--    makes sure only THIS Snowflake account can use the role.)


-- =====================================================================
-- A3 [AWS] UPDATE THE ROLE'S TRUST POLICY                        [DONE]
-- =====================================================================
--   IAM > Roles > snowflake_s3_role > Trust relationships > Edit trust policy
--   Replace everything with:
--   {
--     "Version": "2012-10-17",
--     "Statement": [{
--       "Effect": "Allow",
--       "Principal": { "AWS": "arn:aws:iam::241227970269:user/e28c2000-s" },
--       "Action": "sts:AssumeRole",
--       "Condition": { "StringEquals": {
--         "sts:ExternalId": "OB04393_SFCRole=4_S55Qsq545puQqGba6iCkrwPsvz8=" } }
--     }]
--   }
--   Click "Update policy".


-- =====================================================================
-- SF3 [SF] FILE FORMAT                                           [DONE]
-- =====================================================================
CREATE OR REPLACE FILE FORMAT SF_SCENARIO_BASED_LEARNING.SNOWPIPE.CSV_FMT
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE;
-- Note: MULTI_LINE defaults to FALSE, which lets Snowflake split large files and
-- load them in parallel. If a field contains a line break, that file fails to load
-- (Load failed in COPY_HISTORY). If your fields can contain line breaks, set MULTI_LINE = TRUE.


-- =====================================================================
-- SF4 [SF] EXTERNAL STAGE (pointer to the S3 folder)             [DONE]
-- =====================================================================
CREATE OR REPLACE STAGE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.S3_ORDERS_STAGE
  URL = 's3://my-snowpipe-demo-thazhaiselvan/orders/'
  STORAGE_INTEGRATION = S3_DEMO_INT
  FILE_FORMAT = SF_SCENARIO_BASED_LEARNING.SNOWPIPE.CSV_FMT;

-- Test the connection: an empty result is fine, an error means A2/A3 is wrong
LIST @SF_SCENARIO_BASED_LEARNING.SNOWPIPE.S3_ORDERS_STAGE;


-- =====================================================================
-- SF5 [SF] TARGET TABLE                                          [DONE]
-- =====================================================================
CREATE OR REPLACE TABLE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS (
  ORDER_ID     INT,
  CUSTOMER     STRING,
  AMOUNT       NUMBER(10,2),
  ORDER_TS     TIMESTAMP_NTZ,
  FILE_NAME    STRING,                                   -- audit: which file
  LOADED_AT    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP() -- audit: when
);

-- Optional dry run before creating the pipe (needs a file in S3):
-- COPY INTO SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS (ORDER_ID, CUSTOMER, AMOUNT, ORDER_TS)
--   FROM @SF_SCENARIO_BASED_LEARNING.SNOWPIPE.S3_ORDERS_STAGE VALIDATION_MODE = RETURN_ERRORS;


-- =====================================================================
-- SF6 [SF] THE PIPE                                              [DONE]
-- =====================================================================
CREATE OR REPLACE PIPE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE
  AUTO_INGEST = TRUE
  COMMENT = 'Loads CSV files from s3://my-snowpipe-demo-thazhaiselvan/orders/ into ORDERS'
AS
  COPY INTO SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS (ORDER_ID, CUSTOMER, AMOUNT, ORDER_TS, FILE_NAME)
  FROM (
    SELECT $1, $2, $3, $4, METADATA$FILENAME
    FROM @SF_SCENARIO_BASED_LEARNING.SNOWPIPE.S3_ORDERS_STAGE
  )
  FILE_FORMAT = (FORMAT_NAME = 'SF_SCENARIO_BASED_LEARNING.SNOWPIPE.CSV_FMT')
  ON_ERROR = 'SKIP_FILE';

-- Get the SQS queue ARN that S3 must notify
SHOW PIPES LIKE 'ORDERS_PIPE' IN SCHEMA SF_SCENARIO_BASED_LEARNING.SNOWPIPE;
-- Copy the "notification_channel" column (arn:aws:sqs:eu-central-1:...:sf-snowpipe-...)
--   SQS ARN: arn:aws:sqs:eu-north-1:241227970269:sf-snowpipe-AIDATQKSOW3O6X4EHGDF4-ZDQpSYrf6VeL_uM1yI4Lzg
--   (The queue is created in the BUCKET's region - eu-north-1 here - even though
--    the Snowflake account is in eu-central-1. Cross-region is OK but adds transfer cost.)


-- =====================================================================
-- A4 [AWS] S3 EVENT NOTIFICATION -> SNOWFLAKE'S SQS              [TODO]
-- =====================================================================
--   S3 > my-snowpipe-demo-thazhaiselvan > Properties > Event notifications > Create
--     Name        : snowpipe-orders
--     Prefix      : orders/
--     Suffix      : .csv
--     Event types : All object create events
--     Destination : SQS queue > "Enter SQS queue ARN" > paste the notification_channel
--   (You do NOT create the SQS queue - Snowflake owns it.
--    All auto-ingest pipes in one account+region share the same queue ARN.)


-- =====================================================================
-- T  TEST                                                        [TODO]
-- =====================================================================
-- [AWS] Create orders_001.csv on your computer and upload it to the orders/ folder:
--   order_id,customer,amount,order_ts
--   1,Alice,120.50,2026-11-18 10:00:00
--   2,Bob,75.00,2026-11-18 10:05:00
--   3,Carol,310.99,2026-11-18 10:10:00
--
-- Wait about 30-60 seconds, then:
SELECT * FROM SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS ORDER BY LOADED_AT DESC;

-- Load files that were already in S3 BEFORE the notification existed
-- (only files modified in the last 7 days are picked up)
ALTER PIPE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE REFRESH;

-- Extra tests to try:
--   * Upload orders_002.csv with new rows -> loads automatically
--   * Re-upload orders_001.csv unchanged  -> NOT loaded again (14-day load history)
--   * Overwrite orders_001.csv WITH CHANGES (same name) -> ALSO NOT loaded.
--     Tested: the S3 event arrived and was forwarded, but the pipe skipped the file.
--     Snowpipe tracks files by PATH/NAME. (A manual COPY INTO compares a checksum too
--     and would reload a changed file.) Fix: use a new file name, or
--     COPY INTO ... FILES=('orders_001.csv') FORCE=TRUE (reloads ALL rows -> duplicates).
--   * Upload a file with a bad amount ('abc') -> skipped; see COPY_HISTORY below


-- =====================================================================
-- M  MONITOR AND TROUBLESHOOT                                    [TODO]
-- =====================================================================
-- Pipe health: executionState should be RUNNING; check pendingFileCount and lastIngestedTimestamp
SELECT SYSTEM$PIPE_STATUS('SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE');

-- Per-file load result (status, rows loaded, first error)
SELECT FILE_NAME, STATUS, ROW_COUNT, FIRST_ERROR_MESSAGE, LAST_LOAD_TIME
FROM TABLE(SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS',
       START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())))
ORDER BY LAST_LOAD_TIME DESC;

-- Errors for files the pipe rejected
SELECT * FROM TABLE(SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.VALIDATE_PIPE_LOAD(
       PIPE_NAME  => 'SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE',
       START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())));

-- Pause / resume (for example, before changing the table)
-- ALTER PIPE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;
-- ALTER PIPE SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;

-- COMMON PROBLEMS
--  * LIST @stage fails "access denied"   -> trust policy (A3) ARN / external ID wrong,
--                                           or the S3 path is not in STORAGE_ALLOWED_LOCATIONS
--  * File uploaded but nothing loads     -> event notification (A4) missing, wrong prefix/suffix,
--                                           or wrong SQS ARN; check SYSTEM$PIPE_STATUS
--  * Same file re-uploaded is not loaded -> by design: the pipe keeps 14 days of load history
--                                           (rename the file to reload it)
--  * Status LOAD_FAILED in COPY_HISTORY  -> data/format issue; read FIRST_ERROR_MESSAGE
--  * Changed the COPY logic?             -> recreate the pipe (CREATE OR REPLACE PIPE),
--                                           then ALTER PIPE ... REFRESH if needed


-- =====================================================================
-- INTERVIEW QUICK NOTES
-- =====================================================================
--  * Snowpipe = serverless, event-driven micro-batch COPY. Billed per second of compute
--    plus a small per-file overhead. No warehouse needed.
--  * Latency is usually under a minute. Files of about 100-250 MB compressed are most cost-efficient.
--  * Dedup: file-level load metadata kept for 14 days for pipes (64 days for bulk COPY).
--    Snowpipe skips a file whose path/name was already loaded, even if its contents changed
--    -> always write files with unique names (e.g. timestamps).
--  * AUTO_INGEST works only with EXTERNAL stages (S3/GCS/Azure).
--    For internal stages, call the REST API insertFiles endpoint instead.
--  * Snowpipe vs COPY INTO: continuous and serverless vs on-demand on your warehouse.
--  * Snowpipe vs Snowpipe Streaming: files vs row-level streaming via SDK/Kafka (no files).
--  * Loads are not guaranteed to happen in file order.
--  * Typical downstream pattern: PIPE -> RAW table -> STREAM -> TASK / Dynamic Table -> curated.
--  * The pipe owner role needs USAGE on DB/schema/stage/format and INSERT+SELECT on the table.
--  * Storage integration = no AWS keys stored in Snowflake; AWS trusts Snowflake's
--    IAM user through an IAM role + external ID.


-- =====================================================================
-- CLEANUP (stop costs when you are done)
-- =====================================================================
-- [AWS] delete the S3 event notification, the objects in the bucket, the bucket,
--       the role snowflake_s3_role and the policy snowflake_s3_read_policy
-- DROP PIPE IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS_PIPE;
-- DROP STAGE IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.S3_ORDERS_STAGE;
-- DROP TABLE IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.ORDERS;
-- DROP FILE FORMAT IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE.CSV_FMT;
-- DROP STORAGE INTEGRATION IF EXISTS S3_DEMO_INT;
-- DROP SCHEMA IF EXISTS SF_SCENARIO_BASED_LEARNING.SNOWPIPE;
-- DROP WAREHOUSE IF EXISTS DEMO_WH;
