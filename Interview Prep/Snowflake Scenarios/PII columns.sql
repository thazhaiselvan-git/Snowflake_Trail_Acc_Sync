/*==============================================================================
  SCENARIO: How do you find PII columns using Snowflake metadata?
================================================================================
  Snowflake does NOT flag PII on its own in INFORMATION_SCHEMA. PII info comes
  from one of these sources:

    1. Sensitive Data Classification (SYSTEM$CLASSIFY / auto-classification)
       -> writes system tags SNOWFLAKE.CORE.SEMANTIC_CATEGORY and
          SNOWFLAKE.CORE.PRIVACY_CATEGORY on columns
    2. Your own custom tags (e.g. SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII = 'EMAIL')
    3. Masking policies attached to columns (a strong sign of PII)
    4. Heuristic: column-name pattern search in INFORMATION_SCHEMA.COLUMNS

  Metadata views to remember:
    - SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES        (account-wide, ~2h latency)
    - SNOWFLAKE.ACCOUNT_USAGE.DATA_CLASSIFICATION_LATEST (latest classify result)
    - SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES     (masking / row access)
    - SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY        (who read PII columns)
    - <db>.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(table, 'table') (real-time)
    - <db>.INFORMATION_SCHEMA.COLUMNS               (name-based heuristic)

  PRIVACY_CATEGORY values : IDENTIFIER, QUASI_IDENTIFIER, SENSITIVE
  SEMANTIC_CATEGORY e.g.  : EMAIL, NAME, PHONE_NUMBER, US_SSN, DATE_OF_BIRTH,
                            STREET_ADDRESS, CREDIT_CARD, IP_ADDRESS, GENDER,
                            AGE, PASSPORT, BANK_ACCOUNT, NATIONAL_IDENTIFIER ...

  Required privileges:
    - ACCOUNT_USAGE views: IMPORTED PRIVILEGES on SNOWFLAKE db
      (or database roles SNOWFLAKE.GOVERNANCE_VIEWER / OBJECT_VIEWER)
    - Classification: SNOWFLAKE.CORE.CLASSIFICATION_ADMIN database role,
      SELECT on the table, APPLY TAG (to set tags)
==============================================================================*/

USE ROLE ACCOUNTADMIN;          -- or a role with the grants above
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SF_SCENARIO_BASED_LEARNING;

-- Sandbox used in every step below:
--   SF_SCENARIO_BASED_LEARNING.PII_DATA   -> CUSTOMERS, ORDERS, EMPLOYEES, PAYROLL, LEADS, CONTACTS,
--                                     INVOICES, PAYMENTS, TICKETS, SUBSCRIBERS
--   SF_SCENARIO_BASED_LEARNING.GOVERNANCE -> tags, masking policies, classification profile

/*------------------------------------------------------------------------------
  STEP 0 (one-time): grant access for a governance role
------------------------------------------------------------------------------*/
CREATE ROLE IF NOT EXISTS DATA_GOV_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.GOVERNANCE_VIEWER      TO ROLE DATA_GOV_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORE.CLASSIFICATION_ADMIN TO ROLE DATA_GOV_ROLE;
GRANT APPLY TAG ON ACCOUNT TO ROLE DATA_GOV_ROLE;
GRANT USAGE ON DATABASE SF_SCENARIO_BASED_LEARNING TO ROLE DATA_GOV_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE SF_SCENARIO_BASED_LEARNING TO ROLE DATA_GOV_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA SF_SCENARIO_BASED_LEARNING.PII_DATA TO ROLE DATA_GOV_ROLE;


USE ROLE ACCOUNTADMIN;
GRANT APPLY TAG ON ACCOUNT TO ROLE PII_READER;     -- allows setting tags, including SNOWFLAKE.CORE system tags

USE ROLE PII_READER;
CALL SYSTEM$CLASSIFY('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', {'auto_tag': true});
USE ROLE ACCOUNTADMIN;

/*------------------------------------------------------------------------------
  STEP 1: Classify a table to DETECT PII
------------------------------------------------------------------------------*/
-- 1a. Classify only (returns JSON, no tags applied)
CALL SYSTEM$CLASSIFY('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', NULL);

-- 1b. Classify AND auto-apply SEMANTIC_CATEGORY / PRIVACY_CATEGORY tags
CALL SYSTEM$CLASSIFY('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', {'auto_tag': true});

-- 1c. Classify with a bigger sample
CALL SYSTEM$CLASSIFY('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS',
                     {'sample_count': 10000, 'auto_tag': true});

-- 1d. Classify every table in a schema
CALL SYSTEM$CLASSIFY_SCHEMA('SF_SCENARIO_BASED_LEARNING.PII_DATA', {'auto_tag': true});

-- 1e. Read back the last classification result of a table
SELECT SYSTEM$GET_CLASSIFICATION_RESULT('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS');

-- 1f. Parse the JSON result into rows (column, category, confidence)
WITH r AS (
    SELECT PARSE_JSON(SYSTEM$GET_CLASSIFICATION_RESULT('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS')) AS j
)
SELECT f.key                                        AS column_name,
       f.value:recommendation:semantic_category::STRING AS semantic_category,
       f.value:recommendation:privacy_category::STRING  AS privacy_category,
       f.value:recommendation:confidence::STRING        AS confidence
FROM r, LATERAL FLATTEN(input => r.j:classification_result) f;


/*------------------------------------------------------------------------------
  STEP 1 (alternative): AUTOMATIC classification via Classification Profile
  -> Snowflake keeps classifying new/changed tables in the schema/database
------------------------------------------------------------------------------*/
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII_PROFILE(
    {
      'minimum_object_age_for_classification_days': 0,
      'maximum_classification_validity_days': 30,
      'auto_tag': true
    });

ALTER SCHEMA SF_SCENARIO_BASED_LEARNING.PII_DATA
    SET CLASSIFICATION_PROFILE = 'SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII_PROFILE';
-- (or ALTER DATABASE SF_SCENARIO_BASED_LEARNING SET CLASSIFICATION_PROFILE = ...)


/*------------------------------------------------------------------------------
  STEP 2: List ALL PII columns in the account (system classification tags)
------------------------------------------------------------------------------*/
SELECT object_database   AS database_name,
       object_schema     AS schema_name,
       object_name       AS table_name,
       column_name,
       tag_name,                 -- SEMANTIC_CATEGORY / PRIVACY_CATEGORY
       tag_value                 -- e.g. EMAIL / IDENTIFIER
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'SNOWFLAKE'
  AND tag_schema   = 'CORE'
  AND tag_name IN ('SEMANTIC_CATEGORY', 'PRIVACY_CATEGORY')
  AND domain       = 'COLUMN'
  AND object_deleted IS NULL
  AND object_database = 'SF_SCENARIO_BASED_LEARNING'      -- remove to see whole account
ORDER BY 1, 2, 3, 4;

-- 2b. One row per column: semantic + privacy category side by side
SELECT object_database, object_schema, object_name, column_name,
       MAX(IFF(tag_name = 'SEMANTIC_CATEGORY', tag_value, NULL)) AS semantic_category,
       MAX(IFF(tag_name = 'PRIVACY_CATEGORY',  tag_value, NULL)) AS privacy_category
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'SNOWFLAKE' AND tag_schema = 'CORE'
  AND tag_name IN ('SEMANTIC_CATEGORY', 'PRIVACY_CATEGORY')
  AND domain = 'COLUMN' AND object_deleted IS NULL
  AND object_database = 'SF_SCENARIO_BASED_LEARNING'
GROUP BY 1, 2, 3, 4
ORDER BY privacy_category, 1, 2, 3;

-- 2c. Only direct identifiers (highest risk)
SELECT object_database, object_schema, object_name, column_name
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_name = 'PRIVACY_CATEGORY' AND tag_value = 'IDENTIFIER'
  AND domain = 'COLUMN' AND object_deleted IS NULL
  AND object_database = 'SF_SCENARIO_BASED_LEARNING';

-- 2d. PII count per table / schema (summary for reporting)
SELECT object_database, object_schema, object_name,
       COUNT(DISTINCT column_name) AS pii_column_count,
       LISTAGG(DISTINCT column_name, ', ') AS pii_columns
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_name = 'PRIVACY_CATEGORY'
  AND domain = 'COLUMN' AND object_deleted IS NULL
  AND object_database = 'SF_SCENARIO_BASED_LEARNING'
GROUP BY 1, 2, 3
ORDER BY pii_column_count DESC;


/*------------------------------------------------------------------------------
  STEP 3: Latest classification results (includes un-tagged recommendations)
------------------------------------------------------------------------------*/
SELECT database_name, schema_name, table_name,
       status, trigger_type, last_classified_on,
       result                                    -- VARIANT JSON per column
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_CLASSIFICATION_LATEST
WHERE database_name = 'SF_SCENARIO_BASED_LEARNING'
ORDER BY last_classified_on DESC;

-- Flatten it to column level
SELECT d.database_name, d.schema_name, d.table_name,
       c.key                                             AS column_name,
       c.value:recommendation:semantic_category::STRING  AS semantic_category,
       c.value:recommendation:privacy_category::STRING   AS privacy_category,
       c.value:recommendation:confidence::STRING         AS confidence
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_CLASSIFICATION_LATEST d,
     LATERAL FLATTEN(input => d.result) c
WHERE c.value:recommendation:privacy_category IS NOT NULL
  AND d.database_name = 'SF_SCENARIO_BASED_LEARNING';


/*------------------------------------------------------------------------------
  STEP 4: REAL-TIME check for one table (no ACCOUNT_USAGE latency)
------------------------------------------------------------------------------*/
SELECT *
FROM TABLE(SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
           'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', 'table'));

-- Tag value of a single column
SELECT SYSTEM$GET_TAG('SNOWFLAKE.CORE.SEMANTIC_CATEGORY',
                      'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS.EMAIL', 'column');


/*------------------------------------------------------------------------------
  STEP 5: CUSTOM PII tags (if your team tags manually)
------------------------------------------------------------------------------*/
-- Same tag the 10-table scenario uses. No ALLOWED_VALUES, because the scenario
-- writes classifier values (US_SSN, CREDIT_CARD, ...). To restrict values:
--   ALTER TAG ... ADD ALLOWED_VALUES 'EMAIL', 'PHONE', ...;
CREATE TAG IF NOT EXISTS SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII
    COMMENT = 'Sensitive column - masked';

ALTER TABLE SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS
    MODIFY COLUMN EMAIL SET TAG SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII = 'EMAIL';

SELECT object_database, object_schema, object_name, column_name, tag_value
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'SF_SCENARIO_BASED_LEARNING' AND tag_name = 'PII'
  AND domain = 'COLUMN' AND object_deleted IS NULL;

-- Real-time alternative (no ~2h latency)
SELECT SYSTEM$GET_TAG('SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII', 'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS.EMAIL', 'column');


/*------------------------------------------------------------------------------
  STEP 6: HEURISTIC name-based search (when nothing is classified/tagged yet)
  -> fast but can give false positives/negatives; confirm with SYSTEM$CLASSIFY
------------------------------------------------------------------------------*/
-- Sandbox database (real-time)
SELECT table_catalog, table_schema, table_name, column_name, data_type
FROM SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'PII_DATA'
  AND REGEXP_LIKE(column_name,
      '.*(EMAIL|PHONE|MOBILE|SSN|SOCIAL|PASSPORT|DOB|BIRTH|FIRST_NAME|LAST_NAME|FULL_NAME'
      || '|ADDRESS|STREET|ZIP|POSTAL|CREDIT|CARD|IBAN|ACCOUNT_NO|TAX|PAN|AADHAAR'
      || '|LICENSE|GENDER|IP_ADDR|SALARY).*', 'i');

-- Whole account
SELECT table_catalog, table_schema, table_name, column_name, data_type
FROM SNOWFLAKE.ACCOUNT_USAGE.COLUMNS
WHERE deleted IS NULL
  --AND table_catalog = 'SF_SCENARIO_BASED_LEARNING'          -- remove to scan whole account
  AND REGEXP_LIKE(column_name,
      '.*(EMAIL|PHONE|SSN|PASSPORT|DOB|BIRTH|NAME|ADDRESS|ZIP|CREDIT|CARD|IBAN|TAX|GENDER|IP_ADDR).*', 'i');


/*------------------------------------------------------------------------------
  STEP 7: Is the PII PROTECTED? (PII columns with / without masking policy)
------------------------------------------------------------------------------*/
WITH pii AS (
    SELECT DISTINCT object_database, object_schema, object_name, column_name, tag_value
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
    WHERE tag_name = 'SEMANTIC_CATEGORY' AND domain = 'COLUMN' AND object_deleted IS NULL
      AND object_database = 'SF_SCENARIO_BASED_LEARNING'
),
masked AS (
    SELECT ref_database_name, ref_schema_name, ref_entity_name, ref_column_name,
           policy_name
    FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
    WHERE policy_kind = 'MASKING_POLICY'
      AND ref_database_name = 'SF_SCENARIO_BASED_LEARNING'
)
SELECT p.object_database, p.object_schema, p.object_name, p.column_name,
       p.tag_value AS pii_type,
       m.policy_name,
       IFF(m.policy_name IS NULL, 'UNPROTECTED', 'MASKED') AS protection_status
FROM pii p
LEFT JOIN masked m
  ON  m.ref_database_name = p.object_database
  AND m.ref_schema_name   = p.object_schema
  AND m.ref_entity_name   = p.object_name
  AND m.ref_column_name   = p.column_name
ORDER BY protection_status DESC, 1, 2, 3;

-- Fixing UNPROTECTED columns -> tag-based masking. The full, runnable version
-- is in the 10-table scenario below (S4-S6), which creates
-- SF_SCENARIO_BASED_LEARNING.GOVERNANCE.MASK_PII_STRING / _NUMBER / _DATE and attaches
-- them to SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII. Pattern:
--   CREATE MASKING POLICY ... AS (val STRING) RETURNS STRING ->
--     CASE WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val ELSE '***MASKED***' END;
--   ALTER TAG SF_SCENARIO_BASED_LEARNING.GOVERNANCE.PII SET MASKING POLICY ...;
-- (System tags like SNOWFLAKE.CORE.SEMANTIC_CATEGORY are owned by SNOWFLAKE,
--  so attach policies to your own tag.)

-- Real-time policy check for one table
SELECT policy_name, ref_column_name, tag_name, policy_status
FROM TABLE(SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.POLICY_REFERENCES(
       REF_ENTITY_NAME => 'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', REF_ENTITY_DOMAIN => 'table'));


/*------------------------------------------------------------------------------
  STEP 8: WHO accessed PII columns (audit) - ACCESS_HISTORY (Enterprise+)
------------------------------------------------------------------------------*/
WITH pii AS (
    SELECT DISTINCT object_database || '.' || object_schema || '.' || object_name AS fqn,
           column_name
    FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
    WHERE tag_name = 'PRIVACY_CATEGORY' AND domain = 'COLUMN' AND object_deleted IS NULL
      AND object_database = 'SF_SCENARIO_BASED_LEARNING'
)
SELECT ah.user_name,
       ah.query_start_time,
       obj.value:objectName::STRING AS table_name,
       col.value:columnName::STRING AS column_name,
       ah.query_id
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
     LATERAL FLATTEN(ah.base_objects_accessed) obj,
     LATERAL FLATTEN(obj.value:columns)        col
JOIN pii
  ON  pii.fqn         = obj.value:objectName::STRING
  AND pii.column_name = col.value:columnName::STRING
WHERE ah.query_start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY ah.query_start_time DESC;


/*==============================================================================
  SCENARIO: 10 tables contain sensitive data -> find those columns -> mask them
================================================================================
  NOTE: Tag queries (STEP 2-4) return ALL classified/tagged columns, whether
  masked or not. Masking info lives only in POLICY_REFERENCES (STEP 7).
  Flow: classify -> extract sensitive columns -> tag -> tag-based masking -> verify
==============================================================================*/

-- Sandbox already created:
--   SF_SCENARIO_BASED_LEARNING.PII_DATA   -> 10 tables x 200 rows of fake PII
--     CUSTOMERS, ORDERS, EMPLOYEES, PAYROLL, LEADS, CONTACTS,
--     INVOICES, PAYMENTS, TICKETS, SUBSCRIBERS
--   SF_SCENARIO_BASED_LEARNING.GOVERNANCE -> PII_SCOPE (already loaded), tags, policies
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SF_SCENARIO_BASED_LEARNING;
CREATE ROLE IF NOT EXISTS PII_READER;   -- role allowed to see unmasked values

-- S1. Control list of the 10 tables (already populated)
SELECT * FROM GOVERNANCE.PII_SCOPE;

-- S2. Classify all 10 tables (auto_tag puts SEMANTIC/PRIVACY_CATEGORY tags on columns)
EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR SELECT table_fqn FROM GOVERNANCE.PII_SCOPE;
BEGIN
  FOR r IN c DO
    LET t VARCHAR := r.table_fqn;
    CALL SYSTEM$CLASSIFY(:t, OBJECT_CONSTRUCT('auto_tag', true));
  END FOR;
  RETURN 'Classified';
END;
$$;

SELECT 'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS' AS table_fqn,
       f.key                                            AS column_name,
       f.value:recommendation:semantic_category::STRING AS semantic_category,
       f.value:recommendation:privacy_category::STRING  AS privacy_category,
       f.value:recommendation:confidence::STRING        AS confidence
FROM LATERAL FLATTEN(input => PARSE_JSON(
       SYSTEM$GET_CLASSIFICATION_RESULT('SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS')
      --SYSTEM$GET_CLASSIFICATION_RESULT('SF_SCENARIO_BASED_LEARNING.PII_DATA.PAYROLL')
     ):classification_result) f
WHERE f.value:recommendation:privacy_category IS NOT NULL
ORDER BY column_name;

-- S3. Extract sensitive columns into a table (results come straight from
--     classification, so there is no ACCOUNT_USAGE delay)
--     SYSTEM$GET_CLASSIFICATION_RESULT only accepts a constant table name,
--     so loop over the scope table instead of calling it per row.
EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR SELECT table_fqn FROM GOVERNANCE.PII_SCOPE;
BEGIN
  CREATE OR REPLACE TABLE GOVERNANCE.PII_COLUMNS (
    table_fqn STRING, column_name STRING, semantic_category STRING,
    privacy_category STRING, confidence STRING);
  FOR r IN c DO
    LET t VARCHAR := r.table_fqn;
    LET res VARCHAR := SYSTEM$GET_CLASSIFICATION_RESULT(:t);
    INSERT INTO GOVERNANCE.PII_COLUMNS
    SELECT :t,
           f.key,
           f.value:recommendation:semantic_category::STRING,
           f.value:recommendation:privacy_category::STRING,
           f.value:recommendation:confidence::STRING
    FROM LATERAL FLATTEN(input => PARSE_JSON(:res):classification_result) f
    WHERE f.value:recommendation:privacy_category IS NOT NULL;
  END FOR;
  RETURN 'PII_COLUMNS built';
END;
$$;

-- Review / adjust (remove false positives, add missed columns manually)
SELECT * FROM GOVERNANCE.PII_COLUMNS ORDER BY table_fqn, column_name;
-- DELETE FROM GOVERNANCE.PII_COLUMNS WHERE column_name = 'CITY';
-- INSERT INTO GOVERNANCE.PII_COLUMNS VALUES ('SF_SCENARIO_BASED_LEARNING.PII_DATA.PAYROLL','SALARY','SALARY','SENSITIVE','MANUAL');

-- S4. Custom tag first: MASK_PII_STRING references it, so it must exist
--     (no ALLOWED_VALUES so any semantic category value is accepted)
CREATE TAG IF NOT EXISTS GOVERNANCE.PII COMMENT = 'Sensitive column - masked';
SHOW TAGS;
-- Masking policies per data type (one tag can hold one policy per data type)
CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_PII_STRING
  AS (val STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val
       WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('GOVERNANCE.PII') = 'EMAIL'
            THEN REGEXP_REPLACE(val, '.+@', '*****@')          -- partial mask
       ELSE '***MASKED***' END;

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_PII_NUMBER
  AS (val NUMBER) RETURNS NUMBER ->
  CASE WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val ELSE NULL END;

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MASK_PII_DATE
  AS (val DATE) RETURNS DATE ->
  CASE WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val ELSE DATE_FROM_PARTS(1900,1,1) END;

ALTER TAG GOVERNANCE.PII SET
  MASKING POLICY GOVERNANCE.MASK_PII_STRING,
  MASKING POLICY GOVERNANCE.MASK_PII_NUMBER,
  MASKING POLICY GOVERNANCE.MASK_PII_DATE;

-- S5. Generate the ALTER statements (review the output before running)
SELECT 'ALTER TABLE ' || table_fqn ||
       ' MODIFY COLUMN "' || column_name || '" SET TAG GOVERNANCE.PII = ''' ||
       COALESCE(semantic_category, privacy_category) || ''';' AS ddl
FROM GOVERNANCE.PII_COLUMNS;

ALTER TABLE SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS MODIFY COLUMN "EMAIL" SET TAG GOVERNANCE.PII = 'EMAIL';

-- S6. Or apply them all in one go
EXECUTE IMMEDIATE $$
DECLARE
  c CURSOR FOR
    SELECT 'ALTER TABLE ' || table_fqn || ' MODIFY COLUMN "' || column_name ||
           '" SET TAG GOVERNANCE.PII = ''' ||
           COALESCE(semantic_category, privacy_category) || '''' AS ddl
    FROM GOVERNANCE.PII_COLUMNS;
  n INTEGER DEFAULT 0;
BEGIN
  FOR r IN c DO
    EXECUTE IMMEDIATE r.ddl;
    n := n + 1;
  END FOR;
  RETURN n || ' columns tagged & masked';
END;
$$;

-- S7. Verify (real-time, per table): policy should show on each PII column
SELECT * FROM TABLE(SF_SCENARIO_BASED_LEARNING.INFORMATION_SCHEMA.POLICY_REFERENCES(
         REF_ENTITY_NAME => 'SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS', REF_ENTITY_DOMAIN => 'table'));

SELECT * FROM SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS;   -- as ACCOUNTADMIN -> masked

-- Grant PII_READER to yourself + the access it needs to query the tables
GRANT ROLE PII_READER TO USER THAZHAISELVAN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PII_READER;
GRANT USAGE ON DATABASE SF_SCENARIO_BASED_LEARNING TO ROLE PII_READER;
GRANT USAGE ON SCHEMA SF_SCENARIO_BASED_LEARNING.PII_DATA TO ROLE PII_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA SF_SCENARIO_BASED_LEARNING.PII_DATA TO ROLE PII_READER;

USE ROLE PII_READER;
USE WAREHOUSE COMPUTE_WH;
USE SECONDARY ROLES NONE;
SELECT * FROM SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS;   -- as PII_READER -> unmasked
USE ROLE ACCOUNTADMIN;
-- Test as a role without PII_READER -> values should come back masked
-- USE ROLE SYSADMIN;  (needs SELECT grant) SELECT * FROM SF_SCENARIO_BASED_LEARNING.PII_DATA.CUSTOMERS LIMIT 5;

-- S8. Ongoing: run STEP 7 query to catch new UNPROTECTED columns, or schedule
--     S2-S6 as a task / use a classification profile for new tables.


/*==============================================================================
  INTERVIEW TALKING POINTS
================================================================================
  * Detection   : SYSTEM$CLASSIFY / SYSTEM$CLASSIFY_SCHEMA or a classification
                  profile on schema/database for automatic, ongoing classification.
  * Storage     : results become system tags SNOWFLAKE.CORE.SEMANTIC_CATEGORY &
                  PRIVACY_CATEGORY on columns (when auto_tag = true).
  * Discovery   : ACCOUNT_USAGE.TAG_REFERENCES (account-wide, up to ~2h latency)
                  vs INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS (real-time,
                  single table).
  * Protection  : tag-based masking policies -> any new column tagged PII is
                  masked automatically. Verify via POLICY_REFERENCES.
  * Auditing    : ACCESS_HISTORY shows column-level reads of PII.
  * Edition     : classification, tags, masking, ACCESS_HISTORY need
                  Enterprise Edition or higher.
  * Heuristics  : column-name regex is only a first pass; data may be in
                  generic columns (e.g. NOTES, ATTR1) - classification samples
                  actual values, so it is more reliable.
  * Custom PII  : CUSTOM_CLASSIFIER (SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER)
                  for org-specific patterns like EMPLOYEE_ID formats.
==============================================================================*/
