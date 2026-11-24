-- =====================================================================
-- GitHub -> Snowflake Integration Setup
-- Repo : https://github.com/thazhaiselvan-git/Snowflake_Trail_Acc_Sync
-- Run each statement one at a time, top to bottom.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1: Role, database and schema
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS GIT_DB;

CREATE SCHEMA IF NOT EXISTS GIT_DB.INTEGRATIONS;

USE SCHEMA GIT_DB.INTEGRATIONS;

-- ---------------------------------------------------------------------
-- STEP 2: Secret holding your GitHub Personal Access Token (PAT)
--   * Needed if the repo is PRIVATE, or if you want to push from Snowflake.
--   * Create the PAT in GitHub: Settings > Developer settings >
--     Personal access tokens > Fine-grained tokens
--     (Repository access: Snowflake_Trail_Acc_Sync, Contents: Read and write)
--   * Replace <YOUR_GITHUB_PAT> below. Do NOT commit this file with the token in it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SECRET GIT_DB.INTEGRATIONS.GITHUB_SECRET
  TYPE = PASSWORD
  USERNAME = 'thazhaiselvan-git'
  PASSWORD = <tOKEN>;

-- ---------------------------------------------------------------------
-- STEP 3: API integration (allows Snowflake to talk to your GitHub account)
-- ---------------------------------------------------------------------
CREATE OR REPLACE API INTEGRATION GITHUB_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/thazhaiselvan-git')
  ALLOWED_AUTHENTICATION_SECRETS = (GIT_DB.INTEGRATIONS.GITHUB_SECRET)
  ENABLED = TRUE;

-- ---------------------------------------------------------------------
-- STEP 4: Git repository object (a clone of your repo inside Snowflake)
--   If the repo is PUBLIC and you skipped Step 2, remove the GIT_CREDENTIALS line.
-- ---------------------------------------------------------------------
CREATE OR REPLACE GIT REPOSITORY GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC
  API_INTEGRATION = GITHUB_API_INTEGRATION
  GIT_CREDENTIALS = GIT_DB.INTEGRATIONS.GITHUB_SECRET
  ORIGIN = 'https://github.com/thazhaiselvan-git/Snowflake_Trail_Acc_Sync.git';

-- ---------------------------------------------------------------------
-- STEP 5: Verify
-- ---------------------------------------------------------------------
-- Pull latest changes from GitHub
ALTER GIT REPOSITORY GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC FETCH;

-- List branches and tags
SHOW GIT BRANCHES IN GIT REPOSITORY GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC;
SHOW GIT TAGS IN GIT REPOSITORY GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC;

-- List files on the main branch (change 'main' if your default branch differs)
LS @GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC/branches/main;

-- ---------------------------------------------------------------------
-- STEP 6 (optional): Use files from the repo
-- ---------------------------------------------------------------------
-- Run a SQL file stored in the repo (adjust the path):
-- EXECUTE IMMEDIATE FROM @GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC/branches/main/path/to/script.sql;

-- ---------------------------------------------------------------------
-- STEP 7 (optional): Let other roles use the repo
-- ---------------------------------------------------------------------
-- GRANT USAGE ON DATABASE GIT_DB TO ROLE SYSADMIN;
-- GRANT USAGE ON SCHEMA GIT_DB.INTEGRATIONS TO ROLE SYSADMIN;
-- GRANT USAGE ON INTEGRATION GITHUB_API_INTEGRATION TO ROLE SYSADMIN;
-- GRANT READ ON SECRET GIT_DB.INTEGRATIONS.GITHUB_SECRET TO ROLE SYSADMIN;
-- GRANT READ ON GIT REPOSITORY GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------
-- CLEANUP (only if you want to remove everything)
-- ---------------------------------------------------------------------
-- DROP GIT REPOSITORY IF EXISTS GIT_DB.INTEGRATIONS.SNOWFLAKE_TRAIL_ACC_SYNC;
-- DROP API INTEGRATION IF EXISTS GITHUB_API_INTEGRATION;
-- DROP SECRET IF EXISTS GIT_DB.INTEGRATIONS.GITHUB_SECRET;
-- DROP DATABASE IF EXISTS GIT_DB;
