-- =====================================================================
-- PROD SETUP for retail_project  (GitHub Actions -> PROD account)
--
--   DEV  account : XCULCMB-SO42451  (this one)  -> CI builds on pull requests
--   PROD account : EIESWGF-ZX43054  (new trial) -> deploy on merge to main
--
-- Replace before running:
--   Repo: https://github.com/thazhaiselvan-git/dbt_deployment_demo
--   <GITHUB_USERNAME>    thazhaiselvan-git (or your GitHub login)
--   <GITHUB_PAT>         GitHub personal access token (Contents: Read)  -- never commit this
--   <DEV_PUBLIC_KEY>     contents of dev_key.pub  (without BEGIN/END lines)
--   <PROD_PUBLIC_KEY>    contents of prod_key.pub (without BEGIN/END lines)
-- =====================================================================


-- #####################################################################
-- PART A: run in the DEV account (XCULCMB-SO42451) as ACCOUNTADMIN
-- Service user that GitHub CI uses to build PR changes in RETAIL_DBT.CI_PR_<n>
-- #####################################################################
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS SVC_GITHUB_CI
  TYPE = SERVICE
  DEFAULT_ROLE = DBT_ROLE
  DEFAULT_WAREHOUSE = DBT_WH
  RSA_PUBLIC_KEY = '<DEV_PUBLIC_KEY>'
  COMMENT = 'GitHub Actions CI for retail_project';

GRANT ROLE DBT_ROLE TO USER SVC_GITHUB_CI;


-- #####################################################################
-- PART B: run in the PROD account (EIESWGF-ZX43054) as ACCOUNTADMIN
-- #####################################################################
USE ROLE ACCOUNTADMIN;

-- ---------- 1. Role and warehouse (same names as DEV so the profile needs no changes) ----------
CREATE ROLE IF NOT EXISTS DBT_ROLE COMMENT = 'Runs retail_project in PROD';
GRANT ROLE DBT_ROLE TO ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS DBT_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
GRANT USAGE, OPERATE ON WAREHOUSE DBT_WH TO ROLE DBT_ROLE;

-- ---------- 2. Database and schemas ----------
CREATE DATABASE IF NOT EXISTS RETAIL_DBT;
CREATE SCHEMA IF NOT EXISTS RETAIL_DBT.RAW;
CREATE SCHEMA IF NOT EXISTS RETAIL_DBT.PROD;

GRANT USAGE ON DATABASE RETAIL_DBT TO ROLE DBT_ROLE;
GRANT USAGE ON SCHEMA RETAIL_DBT.RAW TO ROLE DBT_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_DBT.RAW TO ROLE DBT_ROLE;
GRANT ALL ON SCHEMA RETAIL_DBT.PROD TO ROLE DBT_ROLE;

-- ---------- 3. RAW data (in real life this comes from your ingestion pipeline) ----------
CREATE OR REPLACE TABLE RETAIL_DBT.RAW.NATIONS AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION;
CREATE OR REPLACE TABLE RETAIL_DBT.RAW.REGIONS AS SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION;
CREATE OR REPLACE TABLE RETAIL_DBT.RAW.CUSTOMERS AS
  SELECT c.*, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS updated_at FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c;
CREATE OR REPLACE TABLE RETAIL_DBT.RAW.ORDERS AS
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS WHERE o_orderkey <= 400000;
CREATE OR REPLACE TABLE RETAIL_DBT.RAW.LINEITEMS AS
  SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM WHERE l_orderkey <= 400000;
GRANT SELECT ON ALL TABLES IN SCHEMA RETAIL_DBT.RAW TO ROLE DBT_ROLE;

-- ---------- 4. GitHub connection (integrations/secrets are per account, so recreate here) ----------
CREATE OR REPLACE SECRET RETAIL_DBT.PROD.GITHUB_PAT
  TYPE = PASSWORD
  USERNAME = '<GITHUB_USERNAME>'
  PASSWORD = '<GITHUB_PAT>';

CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/thazhaiselvan-git')
  ALLOWED_AUTHENTICATION_SECRETS = (RETAIL_DBT.PROD.GITHUB_PAT)
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION GITHUB_API_INTEGRATION TO ROLE DBT_ROLE;
GRANT READ, USAGE ON SECRET RETAIL_DBT.PROD.GITHUB_PAT TO ROLE DBT_ROLE;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE DBT_ROLE;

-- ---------- 5. Deploy service user for GitHub Actions ----------
CREATE USER IF NOT EXISTS SVC_GITHUB_DEPLOY
  TYPE = SERVICE
  DEFAULT_ROLE = DBT_ROLE
  DEFAULT_WAREHOUSE = DBT_WH
  RSA_PUBLIC_KEY = '<PROD_PUBLIC_KEY>'
  COMMENT = 'GitHub Actions deploy for retail_project';
GRANT ROLE DBT_ROLE TO USER SVC_GITHUB_DEPLOY;

-- Let yourself use DBT_ROLE in the PROD account too
GRANT ROLE DBT_ROLE TO USER <YOUR_PROD_LOGIN>;   -- your login name in the PROD account

-- ---------- 6. Objects owned by DBT_ROLE: Git repo, dbt project, schedule ----------
USE ROLE DBT_ROLE;
USE WAREHOUSE DBT_WH;

CREATE OR REPLACE GIT REPOSITORY RETAIL_DBT.PROD.RETAIL_GIT_REPO
  API_INTEGRATION = GITHUB_API_INTEGRATION
  GIT_CREDENTIALS = RETAIL_DBT.PROD.GITHUB_PAT
  ORIGIN = 'https://github.com/thazhaiselvan-git/dbt_deployment_demo.git';

ALTER GIT REPOSITORY RETAIL_DBT.PROD.RETAIL_GIT_REPO FETCH;
LS @RETAIL_DBT.PROD.RETAIL_GIT_REPO/branches/main;   -- should list dbt_project.yml

-- First deploy (later deploys come from GitHub Actions via ALTER ... DEPLOY FROM)
CREATE DBT PROJECT IF NOT EXISTS RETAIL_DBT.PROD.RETAIL_PROJECT
  FROM '@RETAIL_DBT.PROD.RETAIL_GIT_REPO/branches/main'
  DEFAULT_TARGET = 'prod';

EXECUTE DBT PROJECT RETAIL_DBT.PROD.RETAIL_PROJECT ARGS = 'build --target prod';

-- Daily scheduled run (resume when ready)
CREATE OR ALTER TASK RETAIL_DBT.PROD.RUN_RETAIL_DBT_DAILY
  WAREHOUSE = DBT_WH
  SCHEDULE = 'USING CRON 0 6 * * * Asia/Tokyo'
AS
  EXECUTE DBT PROJECT RETAIL_DBT.PROD.RETAIL_PROJECT ARGS = 'build --target prod';
-- ALTER TASK RETAIL_DBT.PROD.RUN_RETAIL_DBT_DAILY RESUME;

-- ---------- 7. Verify ----------
SHOW DBT PROJECTS IN SCHEMA RETAIL_DBT.PROD;
SELECT *
FROM TABLE(RETAIL_DBT.INFORMATION_SCHEMA.DBT_PROJECT_EXECUTION_HISTORY())
WHERE object_name = 'RETAIL_PROJECT' AND schema_name = 'PROD'
ORDER BY query_start_time DESC LIMIT 5;
SHOW TABLES IN SCHEMA RETAIL_DBT.PROD;
