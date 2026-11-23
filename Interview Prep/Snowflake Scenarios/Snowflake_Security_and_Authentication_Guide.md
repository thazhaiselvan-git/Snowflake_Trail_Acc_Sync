# Snowflake Security & Authentication – Interview Prep Guide

Reference: https://docs.snowflake.com/en/guides-overview-secure

Snowflake security is layered. Think of it as five layers:

| Layer | Features |
|---|---|
| **Network** | Network policies, network rules, PrivateLink / private connectivity, ingress policies |
| **Authentication (who are you?)** | Passwords + MFA, key-pair, SSO/SAML, OAuth, PATs, workload identity federation, authentication policies, password policies, session policies |
| **Authorization (what can you do?)** | RBAC, DAC, system roles, database roles, secondary roles, future grants, managed access schemas |
| **Data protection** | Masking policies, row access policies, projection/aggregation/join policies, tags, classification, secure views/UDFs, encryption, Tri-Secret Secure |
| **Monitoring & governance** | ACCESS_HISTORY, LOGIN_HISTORY, Trust Center, audit queries, replication/failover of security objects |

---

## 1. Network Policies (Inbound Network Control)

### What it is
A network policy controls **inbound** access to the Snowflake service and internal stages based on where the request comes from (IP address, VPC endpoint ID, Azure LinkID, compute pool). By default Snowflake allows connections from **any** address.

> Outbound traffic from Snowflake (UDFs or procedures calling external APIs) is **not** covered by network policies. It is handled by **External Access Integrations** with `MODE = EGRESS` network rules.

### Building blocks
1. **Network rules**: schema-level objects that group identifiers.
   - `MODE = INGRESS` (for network policies), `EGRESS` (for external access), or `INTERNAL_STAGE`
   - `TYPE = IPV4 | IPV6 | AWSVPCEID | AZURELINKID | HOST_PORT | PRIVATE_HOST_PORT | COMPUTE_POOL`
2. **Network policy**: an account-level object with
   - `ALLOWED_NETWORK_RULE_LIST`
   - `BLOCKED_NETWORK_RULE_LIST`
   - The legacy `ALLOWED_IP_LIST` and `BLOCKED_IP_LIST` still work, but don't mix them with rules.
3. **Activation**: a policy has no effect until it is attached.

### Evaluation logic (frequently asked)
- Once anything is allowed, every other identifier **of that type** is implicitly blocked.
- **Blocked list wins** if the same identifier appears in both lists.
- If a request uses private connectivity and the policy allows an `AWSVPCEID` or `AZURELINKID` rule, the IPv4 and IPv6 rules are ignored for that request.
- A private-endpoint rule has **no effect on public traffic**. To allow only private endpoints, also block `0.0.0.0/0`.
- **Precedence:** user-level policy > account-level policy. Security-integration-level policies apply to that integration's traffic, such as OAuth or SCIM.

### Setup
```sql
USE ROLE SECURITYADMIN;   -- or a role with CREATE NETWORK POLICY / CREATE NETWORK RULE

CREATE NETWORK RULE security_db.net.corp_ips
  MODE = INGRESS TYPE = IPV4
  VALUE_LIST = ('203.0.113.0/24', '198.51.100.10');

CREATE NETWORK RULE security_db.net.block_one_ip
  MODE = INGRESS TYPE = IPV4
  VALUE_LIST = ('203.0.113.99');

CREATE NETWORK POLICY corp_policy
  ALLOWED_NETWORK_RULE_LIST = ('security_db.net.corp_ips')
  BLOCKED_NETWORK_RULE_LIST = ('security_db.net.block_one_ip')
  COMMENT = 'Corporate VPN only';

-- Activate
ALTER ACCOUNT SET NETWORK_POLICY = corp_policy;
ALTER USER svc_etl SET NETWORK_POLICY = etl_policy;
ALTER SECURITY INTEGRATION my_oauth SET NETWORK_POLICY = corp_policy;

-- Inspect
SHOW NETWORK POLICIES;
DESCRIBE NETWORK POLICY corp_policy;
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN ACCOUNT;
SHOW PARAMETERS LIKE 'NETWORK_POLICY' IN USER svc_etl;
```

### Private-only access (PrivateLink)
```sql
CREATE NETWORK RULE allow_vpce MODE = INGRESS TYPE = AWSVPCEID VALUE_LIST = ('vpce-0fa383eb170331202');
CREATE NETWORK RULE block_public MODE = INGRESS TYPE = IPV4 VALUE_LIST = ('0.0.0.0/0');
CREATE NETWORK POLICY private_only
  ALLOWED_NETWORK_RULE_LIST = ('allow_vpce')
  BLOCKED_NETWORK_RULE_LIST = ('block_public');
```

### Snowflake-managed SaaS rules
Snowflake ships managed network rules for common SaaS IP ranges, such as hosted CI runners and BI tools, in the `SNOWFLAKE.NETWORK_SECURITY` schema. You can combine them with your own rules in a hybrid policy. There are also built-in procedures that recommend a policy based on your login history.

### Gotchas / scenarios
- **Lockout protection:** Snowflake won't let you activate an account policy that blocks your current IP.
- If you're locked out anyway, an ACCOUNTADMIN on an allowed IP can unset the policy, or you contact Snowflake Support.
- **Scenario: "Only the ETL tool's IPs for the service user, VPN for humans."** Use an account policy for the VPN and a user-level policy for the ETL IPs on the service user.
- Monitor rejected logins:
  ```sql
  SELECT event_timestamp, user_name, client_ip, error_code, error_message
  FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
  WHERE is_success = 'NO' ORDER BY event_timestamp DESC;
  ```

### Ingress policies (newer)
Ingress policies evaluate a richer **request context** before admitting a request: client IP, authentication method, client application, geolocation, PrivateLink ID and endpoint path. They are written as conditions and actions, and can be attached at the account or user level. Use them when IP-only network policies aren't expressive enough.

---

## 2. Authentication Methods

| Method | Typical users | Notes |
|---|---|---|
| **Password + MFA** | Humans | Snowflake is enforcing MFA for password users and deprecating single-factor password sign-in. MFA options include Duo push, passkeys and authenticator apps. |
| **SSO / SAML 2.0** (federated auth) | Humans | IdP such as Okta, Entra ID or Ping, set up with `CREATE SECURITY INTEGRATION TYPE = SAML2`. |
| **OAuth** | Apps and tools | *Snowflake OAuth* (Tableau, custom apps) or *External OAuth* (Okta, Entra ID, PingFederate tokens). |
| **Key-pair (RSA)** | Service users, ETL, connectors | Supports key rotation with two keys (`RSA_PUBLIC_KEY` and `RSA_PUBLIC_KEY_2`). |
| **Programmatic Access Tokens (PAT)** | Scripts, REST APIs | Time-limited tokens per user. Typically require a network policy for service users. |
| **Workload Identity Federation (WIF)** | Cloud workloads, CI/CD | Authenticates with AWS IAM, Azure managed identity, GCP service account or OIDC (for example GitHub Actions), with no stored secrets. |

### User types
```sql
CREATE USER jdoe TYPE = PERSON ...;           -- human
CREATE USER svc_etl TYPE = SERVICE ...;       -- no password and no MFA; key-pair, OAuth, PAT or WIF only
CREATE USER old_app TYPE = LEGACY_SERVICE;    -- transitional, allows passwords (being phased out)
```
**Interview point:** humans use SSO plus MFA. Machines are `TYPE = SERVICE` with key-pair, OAuth or WIF, plus a user-level network policy.

### Key-pair authentication
```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8   # encrypted private key
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```
```sql
ALTER USER svc_etl SET RSA_PUBLIC_KEY = 'MIIBIjANBgkq...';
DESC USER svc_etl;  -- check RSA_PUBLIC_KEY_FP
-- Rotation: set RSA_PUBLIC_KEY_2, move clients to the new key, then unset the old one
ALTER USER svc_etl UNSET RSA_PUBLIC_KEY;
```

### SAML SSO
```sql
CREATE SECURITY INTEGRATION okta_sso
  TYPE = SAML2
  ENABLED = TRUE
  SAML2_ISSUER = 'http://www.okta.com/exk...'
  SAML2_SSO_URL = 'https://<org>.okta.com/app/.../sso/saml'
  SAML2_PROVIDER = 'OKTA'
  SAML2_X509_CERT = 'MIID...'
  SAML2_SP_INITIATED_LOGIN_PAGE_LABEL = 'Okta SSO'
  SAML2_ENABLE_SP_INITIATED = TRUE;
```

### SCIM (user provisioning)
SCIM syncs users and groups from the IdP and creates or updates Snowflake users and roles automatically.
```sql
CREATE ROLE aad_provisioner;
GRANT CREATE USER, CREATE ROLE ON ACCOUNT TO ROLE aad_provisioner;
GRANT ROLE aad_provisioner TO ROLE ACCOUNTADMIN;
CREATE SECURITY INTEGRATION aad_scim
  TYPE = SCIM SCIM_CLIENT = 'AZURE' RUN_AS_ROLE = 'AAD_PROVISIONER';
SELECT SYSTEM$GENERATE_SCIM_ACCESS_TOKEN('AAD_SCIM');
```

### OAuth
```sql
-- Snowflake OAuth for a custom client
CREATE SECURITY INTEGRATION my_app_oauth
  TYPE = OAUTH OAUTH_CLIENT = CUSTOM
  OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
  OAUTH_REDIRECT_URI = 'https://app.example.com/callback'
  OAUTH_ISSUE_REFRESH_TOKENS = TRUE
  OAUTH_REFRESH_TOKEN_VALIDITY = 86400
  BLOCKED_ROLES_LIST = ('SYSADMIN');   -- ACCOUNTADMIN, SECURITYADMIN and ORGADMIN are blocked by default

-- External OAuth (IdP-issued tokens)
CREATE SECURITY INTEGRATION ext_oauth_okta
  TYPE = EXTERNAL_OAUTH ENABLED = TRUE
  EXTERNAL_OAUTH_TYPE = OKTA
  EXTERNAL_OAUTH_ISSUER = 'https://<org>.okta.com/oauth2/<id>'
  EXTERNAL_OAUTH_JWS_KEYS_URL = 'https://<org>.okta.com/oauth2/<id>/v1/keys'
  EXTERNAL_OAUTH_AUDIENCE_LIST = ('https://<account>.snowflakecomputing.com')
  EXTERNAL_OAUTH_TOKEN_USER_MAPPING_CLAIM = 'sub'
  EXTERNAL_OAUTH_SNOWFLAKE_USER_MAPPING_ATTRIBUTE = 'LOGIN_NAME';
```

### Programmatic Access Tokens
```sql
ALTER USER svc_api ADD PROGRAMMATIC ACCESS TOKEN api_token
  ROLE_RESTRICTION = 'REPORTING_ROLE' DAYS_TO_EXPIRY = 30;
SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER svc_api;
ALTER USER svc_api REMOVE PROGRAMMATIC ACCESS TOKEN api_token;
```

### Workload Identity Federation (example: GitHub Actions OIDC)
```sql
CREATE USER gh_deployer TYPE = SERVICE
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = 'repo:my-org/my-repo:ref:refs/heads/main');
```

---

## 3. Authentication Policies

Authentication policies control **how** users may authenticate. You can attach them to the account or to individual users, and the user-level policy wins.

```sql
CREATE AUTHENTICATION POLICY human_auth_policy
  AUTHENTICATION_METHODS = ('SAML', 'PASSWORD')
  CLIENT_TYPES = ('SNOWFLAKE_UI', 'SNOWSQL', 'DRIVERS')
  SECURITY_INTEGRATIONS = ('OKTA_SSO')
  MFA_ENROLLMENT = REQUIRED
  MFA_POLICY = (ALLOWED_METHODS = ('PASSKEY', 'TOTP'));

CREATE AUTHENTICATION POLICY service_auth_policy
  AUTHENTICATION_METHODS = ('KEYPAIR', 'OAUTH', 'PROGRAMMATIC_ACCESS_TOKEN');

ALTER ACCOUNT SET AUTHENTICATION POLICY human_auth_policy;
ALTER USER svc_etl SET AUTHENTICATION POLICY service_auth_policy;
```
Options include allowed methods, client types, specific security integrations, MFA enrollment and allowed MFA methods, PAT settings (maximum expiry, network policy requirement) and workload identity settings.

---

## 4. Password Policies

```sql
CREATE PASSWORD POLICY security_db.policies.strong_pw
  PASSWORD_MIN_LENGTH = 14
  PASSWORD_MIN_UPPER_CASE_CHARS = 1
  PASSWORD_MIN_LOWER_CASE_CHARS = 1
  PASSWORD_MIN_NUMERIC_CHARS = 1
  PASSWORD_MIN_SPECIAL_CHARS = 1
  PASSWORD_MAX_AGE_DAYS = 90
  PASSWORD_MAX_RETRIES = 5
  PASSWORD_LOCKOUT_TIME_MINS = 30
  PASSWORD_HISTORY = 5;

ALTER ACCOUNT SET PASSWORD POLICY security_db.policies.strong_pw;
ALTER USER jdoe SET PASSWORD POLICY security_db.policies.strong_pw;
```
Snowflake's default minimum is 14 characters, and leaked passwords are detected and disabled.

## 5. Session Policies

```sql
CREATE SESSION POLICY security_db.policies.idle_timeout
  SESSION_IDLE_TIMEOUT_MINS = 30          -- clients and drivers
  SESSION_UI_IDLE_TIMEOUT_MINS = 15       -- Snowsight
  ALLOWED_SECONDARY_ROLES = ('ALL');
ALTER ACCOUNT SET SESSION POLICY security_db.policies.idle_timeout;
```

---

## 6. Access Control (RBAC and DAC)

### Models
- **RBAC:** privileges are granted to roles, and roles are granted to users.
- **DAC:** every object has an owning role, and the owner can grant access.
- **User-based access control (UBAC):** privileges granted directly to users, possible only with secondary roles set to `ALL`. Use it sparingly.

### System-defined roles
| Role | Purpose |
|---|---|
| `ORGADMIN` / `GLOBALORGADMIN` | Organization-level work: accounts, org usage |
| `ACCOUNTADMIN` | Top of the hierarchy (SYSADMIN + SECURITYADMIN). Limit it to 2–3 people, all with MFA. |
| `SECURITYADMIN` | Manages grants globally (`MANAGE GRANTS`). Inherits USERADMIN. |
| `USERADMIN` | Creates users and roles |
| `SYSADMIN` | Creates warehouses and databases. All custom roles should roll up to it. |
| `PUBLIC` | Granted to every user |

### Best-practice hierarchy
```
ACCOUNTADMIN
 ├── SECURITYADMIN ── USERADMIN
 └── SYSADMIN
      └── functional roles (ANALYST, DATA_ENGINEER)
            └── access roles (SALES_DB_RO, SALES_DB_RW)  ← privileges granted here
```
```sql
USE ROLE USERADMIN;
CREATE ROLE sales_ro;  CREATE ROLE analyst;
GRANT ROLE sales_ro TO ROLE analyst;
GRANT ROLE analyst TO ROLE SYSADMIN;

USE ROLE SECURITYADMIN;
GRANT USAGE ON DATABASE sales TO ROLE sales_ro;
GRANT USAGE ON ALL SCHEMAS IN DATABASE sales TO ROLE sales_ro;
GRANT SELECT ON ALL TABLES IN DATABASE sales TO ROLE sales_ro;
GRANT SELECT ON FUTURE TABLES IN DATABASE sales TO ROLE sales_ro;   -- future grants
GRANT USAGE ON WAREHOUSE analyst_wh TO ROLE analyst;
```

### Other concepts
- **Database roles:** scoped to one database, and portable through shares and replication. `CREATE DATABASE ROLE sales.reader;`
- **Secondary roles:** `USE SECONDARY ROLES ALL;` combines privileges from all granted roles. Object creation still uses the primary role.
- **Managed access schemas:** `CREATE SCHEMA s WITH MANAGED ACCESS;` means only the schema owner (or MANAGE GRANTS) can grant on the objects, so object owners can't share them freely.
- **Future grants:** schema-level future grants take precedence over database-level ones.
- **Ownership transfer:** `GRANT OWNERSHIP ON TABLE t TO ROLE r COPY CURRENT GRANTS;`
- **Troubleshooting:** `SHOW GRANTS TO ROLE r;`, `SHOW GRANTS OF ROLE r;`, `SHOW GRANTS ON TABLE t;`, `SHOW FUTURE GRANTS IN SCHEMA s;`

---

## 7. Data Protection Policies (Column- and Row-Level Security)

All of these require **Enterprise Edition or higher**.

### Dynamic data masking
```sql
CREATE MASKING POLICY pii.email_mask AS (val STRING) RETURNS STRING ->
  CASE WHEN IS_ROLE_IN_SESSION('PII_READER') THEN val
       ELSE REGEXP_REPLACE(val, '.+@', '*****@') END;
ALTER TABLE customers MODIFY COLUMN email SET MASKING POLICY pii.email_mask;
```
- **Conditional masking:** the policy takes extra columns as arguments, for example `(val STRING, consent BOOLEAN)`.
- **External tokenization:** the masking policy calls an external function to detokenize values.
- Prefer `IS_ROLE_IN_SESSION()` over `CURRENT_ROLE()` because it respects the role hierarchy.

### Tag-based masking (scales best)
```sql
CREATE TAG governance.pii_type ALLOWED_VALUES 'EMAIL','PHONE','SSN';
ALTER TAG governance.pii_type SET MASKING POLICY pii.email_mask;   -- one policy per data type per tag
ALTER TABLE customers MODIFY COLUMN email SET TAG governance.pii_type = 'EMAIL';
```

### Row access policies
```sql
CREATE ROW ACCESS POLICY sec.region_rap AS (region STRING) RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('SALES_ADMIN')
  OR EXISTS (SELECT 1 FROM sec.region_map m
             WHERE m.role_name = CURRENT_ROLE() AND m.region = region);
ALTER TABLE sales ADD ROW ACCESS POLICY sec.region_rap ON (region);
```
Row access policies are evaluated **before** masking policies. A column can't carry both a masking policy and a row access policy.

### Other privacy policies
- **Projection policy:** a column can be filtered on but not shown in `SELECT`.
- **Aggregation policy:** only aggregates over a minimum group size are returned (k-anonymity).
- **Join policy:** joins are required, or restricted to specific columns.
- **Differential privacy:** privacy budgets for clean rooms and shares.

### Sensitive data classification
```sql
CALL SYSTEM$CLASSIFY('db.schema.customers', {'auto_tag': true});
-- Or automatic classification on a schedule, through a classification profile
```
Classification applies system tags such as `SNOWFLAKE.CORE.SEMANTIC_CATEGORY` and `PRIVACY_CATEGORY`, which you can combine with tag-based masking.

### Secure views and secure UDFs
`CREATE SECURE VIEW` hides the view definition and blocks optimizer-based data leakage. Secure views are required for data sharing.

---

## 8. Encryption & Key Management

- All data is **encrypted at rest with AES-256** and **in transit with TLS 1.2+**, always and at no cost.
- **Hierarchical key model:** root key (in an HSM) → account master key → table master key → file keys.
- **Automatic key rotation** happens every 30 days for active keys.
- **Periodic rekeying** (Enterprise+) re-encrypts data whose keys are older than one year: `ALTER ACCOUNT SET PERIODIC_DATA_REKEYING = TRUE;`
- **Tri-Secret Secure** (Business Critical+) combines a Snowflake-managed key with a **customer-managed key** (CMK) in AWS KMS, Azure Key Vault or GCP KMS. Revoking the CMK makes the data unreadable.
- **Client-side encryption** applies to external stages, with `MASTER_KEY` or cloud KMS options.

---

## 9. Private Connectivity

- **AWS PrivateLink, Azure Private Link and GCP Private Service Connect** require Business Critical edition or higher.
- `SELECT SYSTEM$GET_PRIVATELINK_CONFIG();` returns the endpoints and URLs to configure.
- **Private connectivity to internal stages** is also available, with `MODE = INTERNAL_STAGE` rules on AWS.
- **Outbound private connectivity** lets external access and external functions reach your services over PrivateLink.
- Combine private connectivity with a network policy that blocks public IPs (see section 1).

---

## 10. Storage, External Access & Secrets

- **Storage integrations** delegate cloud access to Snowflake-managed IAM entities, so no keys appear in stage DDL.
  ```sql
  CREATE STORAGE INTEGRATION s3_int TYPE = EXTERNAL_STAGE STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123:role/sf'
    STORAGE_ALLOWED_LOCATIONS = ('s3://bucket/path/');
  ```
- To stop users from creating stages with embedded credentials:
  ```sql
  ALTER ACCOUNT SET REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_CREATION = TRUE;
  ALTER ACCOUNT SET REQUIRE_STORAGE_INTEGRATION_FOR_STAGE_OPERATION = TRUE;
  ALTER ACCOUNT SET PREVENT_UNLOAD_TO_INLINE_URL = TRUE;
  ```
- **External access** (egress from UDFs and procedures):
  ```sql
  CREATE NETWORK RULE api_rule MODE = EGRESS TYPE = HOST_PORT VALUE_LIST = ('api.example.com');
  CREATE SECRET api_key TYPE = GENERIC_STRING SECRET_STRING = '***';
  CREATE EXTERNAL ACCESS INTEGRATION api_eai
    ALLOWED_NETWORK_RULES = (api_rule) ALLOWED_AUTHENTICATION_SECRETS = (api_key) ENABLED = TRUE;
  ```
- **Secrets** come in several types: `PASSWORD`, `GENERIC_STRING`, `OAUTH2` and `CLOUD_PROVIDER_TOKEN`.

---

## 11. Data Sharing Security

- Shares are read-only. Only secure views, secure UDFs and tables can be shared.
- **Reader accounts** are provider-managed accounts for consumers who don't have Snowflake.
- Use `CURRENT_ACCOUNT()` or database roles inside secure views to filter data per consumer.
- Sharing between different editions (for example, Business Critical to Enterprise) needs `SHARE_RESTRICTIONS = FALSE`.

---

## 12. Monitoring, Auditing & Threat Detection

Key views in `SNOWFLAKE.ACCOUNT_USAGE`:

| View | Use |
|---|---|
| `LOGIN_HISTORY` | Failed logins, authentication methods, client IPs |
| `ACCESS_HISTORY` | Column-level read and write lineage (Enterprise+) |
| `QUERY_HISTORY` | Who ran what |
| `GRANTS_TO_ROLES` / `GRANTS_TO_USERS` | Privilege audit |
| `USERS` | MFA status, password age, disabled users |
| `POLICY_REFERENCES` | Where masking and row access policies are attached |
| `TAG_REFERENCES` | Tag coverage |
| `SESSIONS` | Authentication factor per session |

```sql
-- Users still on password-only sign-in
SELECT name, has_password, has_mfa, has_rsa_public_key, type, last_success_login
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE deleted_on IS NULL AND has_password AND NOT has_mfa;

-- Who holds ACCOUNTADMIN
SELECT grantee_name FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
WHERE role = 'ACCOUNTADMIN' AND deleted_on IS NULL;

-- Brute-force signal
SELECT user_name, client_ip, COUNT(*) failures
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE is_success = 'NO' AND event_timestamp > DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY 1, 2 HAVING failures > 10;
```

- **Trust Center:** scanners for the CIS Benchmark and Security Essentials, plus threat intelligence on risky users and logins, with findings and remediation steps.
- **Alerts and notifications:** `CREATE ALERT` on any of the queries above, with email or webhook delivery.

---

## 13. Business Continuity & Data Recovery (Security-Adjacent)

- **Time Travel** (1 day by default, up to 90 days on Enterprise+) and **Fail-safe** (7 days, recoverable only by Snowflake).
- **Replication and failover groups** can include security objects: `OBJECT_TYPES = USERS, ROLES, NETWORK POLICIES, INTEGRATIONS, ...`
- **Backups / snapshots** can be made immutable with a retention lock, for ransomware protection.

---

## 14. Edition Matrix (Common Interview Question)

| Feature | Standard | Enterprise | Business Critical | VPS |
|---|---|---|---|---|
| Network policies, MFA, SSO, OAuth, key-pair | ✓ | ✓ | ✓ | ✓ |
| Masking, row access, tags, ACCESS_HISTORY | | ✓ | ✓ | ✓ |
| Periodic rekeying, 90-day Time Travel | | ✓ | ✓ | ✓ |
| Tri-Secret Secure, PrivateLink, HIPAA/PCI | | | ✓ | ✓ |
| Dedicated isolated environment | | | | ✓ |

---

## 15. Scenario-Based Interview Questions

1. **"Lock the account down to the corporate VPN, but let the Fivetran service user connect from Fivetran's IPs."**
   Create an account-level network policy for the VPN range and a user-level policy for `svc_fivetran` with Fivetran's IPs. The user-level policy overrides the account policy. Make the user `TYPE = SERVICE` with key-pair authentication.

2. **"Analysts should see masked SSNs, and HR should see real values, across 500 tables."**
   Classify the tables, apply a `pii_type` tag, and attach one masking policy to the tag (tag-based masking). Use `IS_ROLE_IN_SESSION('HR')` in the policy.

3. **"Regional managers should only see their own region's rows."**
   Use a row access policy backed by a mapping table. Keep the mapping table in a secured schema.

4. **"A user is locked out after failed logins."**
   `ALTER USER x SET MINS_TO_UNLOCK = 0;` Then check `LOGIN_HISTORY` for the cause.

5. **"A user lost their MFA device."**
   `ALTER USER x SET MINS_TO_BYPASS_MFA = 10;` Or have them re-enroll after an admin unsets MFA. Check the current commands in the docs.

6. **"Stop object owners from granting access to their own tables."**
   Use managed access schemas.

7. **"Meet compliance with customer-controlled encryption keys."**
   Use Business Critical edition with Tri-Secret Secure.

8. **"Keep all traffic off the public internet."**
   Use PrivateLink plus a network policy that allows the VPCE ID and blocks `0.0.0.0/0`. Add private connectivity for internal stages.

9. **"How do you prevent data exfiltration?"**
   Set `PREVENT_UNLOAD_TO_INLINE_URL` and require storage integrations. Restrict external access integrations, monitor `ACCESS_HISTORY` and large `COPY INTO @stage` queries, and restrict sharing and reader accounts.

10. **"Who has access to table X, and who actually queried it?"**
    `SHOW GRANTS ON TABLE X` (plus the role hierarchy) answers the first question. `ACCESS_HISTORY` filtered on `base_objects_accessed` answers the second.

11. **"Difference between `CURRENT_ROLE()` and `IS_ROLE_IN_SESSION()` in policies?"**
    `CURRENT_ROLE()` returns the primary role only. `IS_ROLE_IN_SESSION()` includes inherited and secondary roles.

12. **"Why shouldn't ACCOUNTADMIN be anyone's default role?"**
    Least privilege and accidental changes. Objects created by ACCOUNTADMIN also become orphaned from the SYSADMIN hierarchy.

---

## 16. Security Best-Practice Checklist

- [ ] Enforce MFA for every human user; use SSO wherever possible
- [ ] Create service users as `TYPE = SERVICE` with key-pair, OAuth or WIF, never passwords
- [ ] Set an account-level network policy, plus user-level policies for service accounts
- [ ] Apply authentication, password and session policies
- [ ] Give ACCOUNTADMIN to 2–3 named users with MFA, and never make it a default role
- [ ] Roll every custom role up to SYSADMIN; separate access roles from functional roles
- [ ] Use managed access schemas for sensitive data
- [ ] Combine classification, tag-based masking and row access policies
- [ ] Require storage integrations and block inline credential URLs
- [ ] Use PrivateLink and Tri-Secret Secure where compliance requires them
- [ ] Enable Trust Center scanners and alert on failed logins and privilege changes
- [ ] Review grants and unused users regularly
