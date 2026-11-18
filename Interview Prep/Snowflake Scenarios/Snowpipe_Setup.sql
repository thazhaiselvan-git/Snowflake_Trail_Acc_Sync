/*=====================================================================================
  SNOWPIPE END-TO-END SETUP (AWS S3 -> SNOWFLAKE)  |  Beginner-friendly walkthrough
=======================================================================================

WHAT IS SNOWPIPE?
  - Serverless, continuous ingestion service. When a new file lands in a stage (S3),
    Snowpipe automatically runs a COPY INTO statement to load it into a table.
  - Near real-time: files are typically loaded within about a minute of arriving.
  - No warehouse needed: Snowflake-managed compute, billed per second of compute
    plus a small per-file overhead charge.

HOW AUTO-INGEST WORKS
  File uploaded to S3  ->  S3 Event Notification  ->  SQS queue (owned by Snowflake)
        ->  Snowpipe picks up the event  ->  runs COPY INTO  ->  rows appear in table

OVERALL STEPS
  AWS  1. Create S3 bucket + folder (prefix)
  AWS  2. Create IAM policy (S3 read access)
  AWS  3. Create IAM role (temporary trust, fixed in step 6)
  SF   4. Create STORAGE INTEGRATION (Snowflake <-> IAM role link)
  SF   5. DESC INTEGRATION -> copy STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID
  AWS  6. Update IAM role trust policy with those 2 values
  SF   7. Create database/schema, target table, file format
  SF   8. Create EXTERNAL STAGE and test with LIST
  SF   9. Test a manual COPY INTO (validate before automating)
  SF  10. Create PIPE with AUTO_INGEST = TRUE
  SF  11. SHOW PIPES -> copy notification_channel (SQS ARN)
  AWS 12. Add S3 Event Notification -> SQS ARN
  BOTH 13. Upload a file and verify / monitor
=====================================================================================*/


/*-------------------------------------------------------------------------------------
  STEP 1 (AWS) - Create S3 bucket
---------------------------------------------------------------------------------------
  AWS Console -> S3 -> Create bucket
    Bucket name : my-snowpipe-demo-bucket   (globally unique)
    Region      : ideally the SAME region as your Snowflake account (avoids egress cost)
  Create a folder (prefix):  orders/
  Sample file orders_001.csv:
      order_id,customer_id,amount,order_date
      1,C001,250.50,2026-11-01
      2,C002,99.99,2026-11-02
-------------------------------------------------------------------------------------*/


/*-------------------------------------------------------------------------------------
  STEP 2 (AWS) - Create IAM policy
---------------------------------------------------------------------------------------
  IAM -> Policies -> Create policy -> JSON. Name it: snowflake_s3_read_policy
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:GetObjectVersion"],
        "Resource": "arn:aws:s3:::my-snowpipe-demo-bucket/orders/*"
      },
      {
        "Effect": "Allow",
        "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
        "Resource": "arn:aws:s3:::my-snowpipe-demo-bucket",
        "Condition": { "StringLike": { "s3:prefix": ["orders/*"] } }
      }
    ]
  }
  (Add s3:PutObject / s3:DeleteObject only if you plan to unload or PURGE files.)
-------------------------------------------------------------------------------------*/


/*-------------------------------------------------------------------------------------
  STEP 3 (AWS) - Create IAM role
---------------------------------------------------------------------------------------
  IAM -> Roles -> Create role -> "AWS account" -> "This account" (temporary)
    Tick "Require external ID" and enter 0000 (temporary placeholder)
    Attach policy: snowflake_s3_read_policy
    Role name   : snowflake_s3_role
  Copy the Role ARN, e.g.  arn:aws:iam::123456789012:role/snowflake_s3_role
-------------------------------------------------------------------------------------*/


/*-------------------------------------------------------------------------------------
  STEP 4 (SNOWFLAKE) - Create storage integration
  Needs ACCOUNTADMIN (or a role with CREATE INTEGRATION privilege)
-------------------------------------------------------------------------------------*/
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE STORAGE INTEGRATION S3_SNOWPIPE_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake_s3_role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://my-snowpipe-demo-bucket/orders/');


/*-------------------------------------------------------------------------------------
  STEP 5 (SNOWFLAKE) - Get the values AWS needs
  Copy: STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID
-------------------------------------------------------------------------------------*/
DESC INTEGRATION S3_SNOWPIPE_INT;


/*-------------------------------------------------------------------------------------
  STEP 6 (AWS) - Update IAM role trust relationship
---------------------------------------------------------------------------------------
  IAM -> Roles -> snowflake_s3_role -> Trust relationships -> Edit
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": { "AWS": "<STORAGE_AWS_IAM_USER_ARN>" },
        "Action": "sts:AssumeRole",
        "Condition": { "StringEquals": { "sts:ExternalId": "<STORAGE_AWS_EXTERNAL_ID>" } }
      }
    ]
  }
  NOTE: CREATE OR REPLACE on the integration generates a NEW external ID, and you
  then have to update this trust policy again.
-------------------------------------------------------------------------------------*/


/*-------------------------------------------------------------------------------------
  STEP 7 (SNOWFLAKE) - Database, schema, table, file format
-------------------------------------------------------------------------------------*/
CREATE DATABASE IF NOT EXISTS SNOWPIPE_DEMO;
CREATE SCHEMA IF NOT EXISTS SNOWPIPE_DEMO.RAW;

CREATE OR REPLACE TABLE SNOWPIPE_DEMO.RAW.ORDERS (
    ORDER_ID      NUMBER,
    CUSTOMER_ID   VARCHAR,
    AMOUNT        NUMBER(10,2),
    ORDER_DATE    DATE,
    FILE_NAME     VARCHAR,                                   -- audit: source file
    LOAD_TS       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()  -- audit: load time
);

CREATE OR REPLACE FILE FORMAT SNOWPIPE_DEMO.RAW.CSV_FF
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE;


/*-------------------------------------------------------------------------------------
  STEP 8 (SNOWFLAKE) - External stage + connectivity test
-------------------------------------------------------------------------------------*/
CREATE OR REPLACE STAGE SNOWPIPE_DEMO.RAW.ORDERS_STAGE
  URL = 's3://my-snowpipe-demo-bucket/orders/'
  STORAGE_INTEGRATION = S3_SNOWPIPE_INT
  FILE_FORMAT = SNOWPIPE_DEMO.RAW.CSV_FF;

LIST @SNOWPIPE_DEMO.RAW.ORDERS_STAGE;      -- should list orders_001.csv
-- Error "not authorized to perform sts:AssumeRole" => re-check the step 6 trust policy

-- Preview the file contents before loading
SELECT $1, $2, $3, $4, METADATA$FILENAME
FROM @SNOWPIPE_DEMO.RAW.ORDERS_STAGE (FILE_FORMAT => 'SNOWPIPE_DEMO.RAW.CSV_FF');


/*-------------------------------------------------------------------------------------
  STEP 9 (SNOWFLAKE) - Manual COPY test (always validate before automating)
-------------------------------------------------------------------------------------*/
COPY INTO SNOWPIPE_DEMO.RAW.ORDERS (ORDER_ID, CUSTOMER_ID, AMOUNT, ORDER_DATE, FILE_NAME)
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME FROM @SNOWPIPE_DEMO.RAW.ORDERS_STAGE)
VALIDATION_MODE = RETURN_ERRORS;           -- dry run: returns errors only, loads nothing

-- Optional: clear test data so the pipe can be tested from a clean table
-- TRUNCATE TABLE SNOWPIPE_DEMO.RAW.ORDERS;


/*-------------------------------------------------------------------------------------
  STEP 10 (SNOWFLAKE) - Create the pipe
-------------------------------------------------------------------------------------*/
CREATE OR REPLACE PIPE SNOWPIPE_DEMO.RAW.ORDERS_PIPE
  AUTO_INGEST = TRUE
  COMMENT = 'Auto-load order CSVs from S3'
AS
COPY INTO SNOWPIPE_DEMO.RAW.ORDERS (ORDER_ID, CUSTOMER_ID, AMOUNT, ORDER_DATE, FILE_NAME)
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME FROM @SNOWPIPE_DEMO.RAW.ORDERS_STAGE)
FILE_FORMAT = (FORMAT_NAME = 'SNOWPIPE_DEMO.RAW.CSV_FF')
ON_ERROR = CONTINUE;                       -- skip bad rows instead of failing the file


/*-------------------------------------------------------------------------------------
  STEP 11 (SNOWFLAKE) - Get the SQS ARN
  Copy the "notification_channel" column, e.g. arn:aws:sqs:us-east-1:xxxx:sf-snowpipe-...
-------------------------------------------------------------------------------------*/
SHOW PIPES LIKE 'ORDERS_PIPE' IN SCHEMA SNOWPIPE_DEMO.RAW;


/*-------------------------------------------------------------------------------------
  STEP 12 (AWS) - S3 event notification
---------------------------------------------------------------------------------------
  S3 -> my-snowpipe-demo-bucket -> Properties -> Event notifications -> Create
    Name         : snowpipe-orders-event
    Prefix       : orders/
    Suffix       : .csv                    (optional)
    Event types  : All object create events (s3:ObjectCreated:*)
    Destination  : SQS queue -> "Enter SQS queue ARN" -> paste notification_channel
  NOTE: Every pipe in the same account and region shares ONE SQS queue, so a single
  notification can serve many pipes (each pipe filters on its own stage path).
  ALTERNATIVE: SNS topic -> SQS, used when the bucket already has an event for the same prefix.
-------------------------------------------------------------------------------------*/


/*-------------------------------------------------------------------------------------
  STEP 13 (BOTH) - Test and monitor
  Upload orders_002.csv to s3://my-snowpipe-demo-bucket/orders/ , wait ~1 min
-------------------------------------------------------------------------------------*/
-- Pipe health: executionState should be RUNNING; pendingFileCount should be 0
SELECT SYSTEM$PIPE_STATUS('SNOWPIPE_DEMO.RAW.ORDERS_PIPE');

-- Data arrived?
SELECT * FROM SNOWPIPE_DEMO.RAW.ORDERS ORDER BY LOAD_TS DESC;

-- File-level load history (last 24 hours)
SELECT FILE_NAME, STATUS, ROW_COUNT, ROW_PARSED, FIRST_ERROR_MESSAGE, LAST_LOAD_TIME
FROM TABLE(SNOWPIPE_DEMO.INFORMATION_SCHEMA.COPY_HISTORY(
       TABLE_NAME => 'SNOWPIPE_DEMO.RAW.ORDERS',
       START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())));

-- Errors for files the pipe has processed
SELECT * FROM TABLE(VALIDATE_PIPE_LOAD(
       PIPE_NAME  => 'SNOWPIPE_DEMO.RAW.ORDERS_PIPE',
       START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())));

-- Cost / credits (ACCOUNT_USAGE has up to ~3 hours of latency)
SELECT PIPE_NAME, START_TIME, CREDITS_USED, FILES_INSERTED, BYTES_INSERTED
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE PIPE_NAME = 'ORDERS_PIPE'
ORDER BY START_TIME DESC;


/*-------------------------------------------------------------------------------------
  USEFUL OPERATIONS
-------------------------------------------------------------------------------------*/
-- Load files that were already in S3 BEFORE the pipe/event existed (last 7 days only)
ALTER PIPE SNOWPIPE_DEMO.RAW.ORDERS_PIPE REFRESH;

-- Pause / resume the pipe
ALTER PIPE SNOWPIPE_DEMO.RAW.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = TRUE;
ALTER PIPE SNOWPIPE_DEMO.RAW.ORDERS_PIPE SET PIPE_EXECUTION_PAUSED = FALSE;

-- Grants for a non-admin role that owns/operates pipes
-- GRANT USAGE ON INTEGRATION S3_SNOWPIPE_INT TO ROLE DATA_ENG;
-- GRANT CREATE STAGE, CREATE PIPE ON SCHEMA SNOWPIPE_DEMO.RAW TO ROLE DATA_ENG;
-- GRANT INSERT, SELECT ON TABLE SNOWPIPE_DEMO.RAW.ORDERS TO ROLE DATA_ENG;


/*-------------------------------------------------------------------------------------
  TROUBLESHOOTING CHECKLIST
---------------------------------------------------------------------------------------
  LIST @stage fails           -> trust policy ARN or external ID mismatch (step 6),
                                 or the IAM policy is missing s3:ListBucket
  LIST works, pipe loads none -> S3 event missing or wrong prefix, or wrong SQS ARN;
                                 check that SYSTEM$PIPE_STATUS lastReceivedMessageTimestamp updates
  Same file not reloading     -> Snowpipe keeps 14 days of load metadata, so an identical
                                 file name is skipped (rename the file, or use COPY ... FORCE = TRUE manually)
  Pipe changed (CREATE OR     -> load history is reset, so the same files may load twice.
  REPLACE)                       Pause, wait until pendingFileCount = 0, then recreate
  Rows missing                -> ON_ERROR = CONTINUE skipped them; check COPY_HISTORY
                                 and VALIDATE_PIPE_LOAD

  BEST PRACTICES / INTERVIEW POINTS
  - Aim for files of ~100-250 MB compressed; many tiny files raise the per-file overhead cost
  - Snowpipe vs COPY INTO: Snowpipe = continuous, serverless, event-driven;
    COPY INTO = batch, runs on your own warehouse, scheduled by a task or orchestrator
  - Snowpipe vs Snowpipe Streaming: Streaming loads rows (SDK/Kafka) with no files
    and lower latency
  - Pair with STREAM + TASK, or a DYNAMIC TABLE, to transform raw data downstream
  - Same pattern on Azure (Event Grid + notification integration) and GCS (Pub/Sub)
-------------------------------------------------------------------------------------*/
