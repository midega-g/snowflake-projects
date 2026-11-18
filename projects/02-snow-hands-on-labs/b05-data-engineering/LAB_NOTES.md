# b05 - Lab notes

Snowflake lessons from setting up badge 5: commands, results, errors, fixes and reasoning. `README.md` has the short version.

Placeholders stand in for real values: `<user_name>` (from `SELECT CURRENT_USER();`) and `<account_locator>`. Login and key-pair setup are in `../b01-data-warehousing/LAB_NOTES.md`.

## The lab's instructions
1. Have a warehouse `COMPUTE_WH`, sized XS, that auto-suspends. Create it if missing.
2. Have a database `UTIL_DB` to hold the DORA grader function. Create it if missing.
3. SYSADMIN must own `COMPUTE_WH`, `UTIL_DB` and `UTIL_DB.PUBLIC`.
4. Set user defaults: role `SYSADMIN`, warehouse `COMPUTE_WH`, namespace `UTIL_DB.PUBLIC`.

The lab's example uses `alter user KISHOREK ...`. On this account the user name is lowercase, so the plain form fails (section 5).

## Primary and secondary roles
Several later sections depend on these two terms. Source: Snowflake docs, "Overview of Access Control", section "Authorization through primary role and secondary roles".

- **Primary role:** a session's one current role. `USE ROLE x` sets it, and `SELECT CURRENT_ROLE();` shows it. At login it is the role named in the connection, otherwise the user's `DEFAULT_ROLE`.
- **Secondary roles:** any number of extra roles that are also active in the session. Each one must already be granted to the user. `USE SECONDARY ROLES ALL | NONE | <role>, ...` sets them, and `SELECT CURRENT_SECONDARY_ROLES();` shows them. At login they come from the user's `DEFAULT_SECONDARY_ROLES`, which is `('ALL')` on this account.
- **How they combine:** for most actions (`SELECT`, `USAGE`, `SHOW`, `ALTER`, `DROP` on existing objects), the privileges of the primary role and all secondary roles are added together. Each role also brings the roles below it in the hierarchy.
- **The exception is `CREATE <object>`.** Only the primary role can authorise it, and the primary role becomes the new object's owner. Secondary roles can never create objects or decide who owns them.

| Question | Decided by |
|---|---|
| May I create this object? | Primary role only |
| Who owns the new object? | Primary role |
| May I read, use, change or drop an existing object? | Primary plus all secondary roles |

In practice, `USE ROLE SYSADMIN` with the default `ALL` secondary roles behaves like SYSADMIN for creating and owning objects, and like every granted role combined, ACCOUNTADMIN included, for everything else. Sections 3 and 8.6 show the `CREATE` rule, and sections 5 and 8.7 show the rest.

## 1. Check before creating, as ACCOUNTADMIN
```sql
USE ROLE ACCOUNTADMIN;
SHOW WAREHOUSES LIKE 'COMPUTE_WH';      -- empty
SHOW DATABASES LIKE 'UTIL_DB';          -- empty
SHOW RESOURCE MONITORS;                 -- empty
SHOW WAREHOUSES;                        -- SNOWFLAKE_LEARNING_WH, SYSTEM$STREAMLIT_NOTEBOOK_WH (both ACCOUNTADMIN)
```
**Why ACCOUNTADMIN for the check:** `SHOW` lists only objects that the current role has some privilege on, directly or through roles it inherits. Run as SYSADMIN, an empty result could mean "doesn't exist" or "exists but isn't visible to me". Creating in the second case would only report "already exists", and the object would keep the wrong owner. ACCOUNTADMIN sees everything, so its empty result really means the object is missing.

**Noticed: SYSADMIN could already see ACCOUNTADMIN's warehouses.** This held even with secondary roles off (`USE SECONDARY ROLES NONE`). The grants explain it:
```sql
SHOW GRANTS ON WAREHOUSE SNOWFLAKE_LEARNING_WH;         -- USAGE, OPERATE, MONITOR to SNOWFLAKE_LEARNING_ROLE
SHOW GRANTS OF ROLE SNOWFLAKE_LEARNING_ROLE;            -- granted to PUBLIC
SHOW GRANTS ON WAREHOUSE "SYSTEM$STREAMLIT_NOTEBOOK_WH"; -- USAGE to PUBLIC
```
Every role inherits `PUBLIC`, so anything granted to `PUBLIC`, or to a role granted to `PUBLIC`, is visible to every user. Note the double quotes on `"SYSTEM$STREAMLIT_NOTEBOOK_WH"`: an unquoted `$` in an identifier doesn't parse.

**Noticed:** this trial account had no `COMPUTE_WH`. Newer trial accounts come with `SNOWFLAKE_LEARNING_WH` (owned by ACCOUNTADMIN, `AUTO_SUSPEND=300`). We left it alone.

## 2. Create the warehouse and database as SYSADMIN
```sql
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Shared lab warehouse for 02-snow-hands-on-labs';
CREATE DATABASE IF NOT EXISTS UTIL_DB COMMENT = 'Home for the DORA grader function';
-- Warehouse COMPUTE_WH successfully created.
-- Database UTIL_DB successfully created.
```
**Reasoning:**
- **Create with the role that should own it.** The creating role becomes the owner. In b01, `DEMO_DB` was created by ACCOUNTADMIN and needed `GRANT OWNERSHIP` for the database and its `PUBLIC` schema. Here SYSADMIN creates both objects, so it owns them and the auto-created `UTIL_DB.PUBLIC` from the start, and no transfer is needed. This covers lab instruction 3.
- **SYSADMIN can do this.** By default SYSADMIN has `CREATE WAREHOUSE` and `CREATE DATABASE` on the account.
- **`INITIALLY_SUSPENDED = TRUE`.** Without it, a new warehouse starts running and bills a minimum of 60 seconds even if nothing uses it.
- **`AUTO_SUSPEND = 60`** (seconds of idle time before suspending). The SQL default is 600. Lower means fewer idle credits, but each resume clears the warehouse's local cache. For short lab queries, 60 is a good trade-off.
- **`AUTO_RESUME = TRUE`.** A query against a suspended warehouse starts it automatically, so you don't need to run `ALTER WAREHOUSE ... RESUME` yourself.
- **XSMALL** costs 1 credit per running hour, billed per second after the first 60 seconds. Each size up doubles the cost.

The setup script also runs `ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;`. If the warehouse had already existed with other settings, `CREATE ... IF NOT EXISTS` would skip it silently. The `ALTER` enforces the settings either way.

## 3. Resource monitor: SYSADMIN can't create one
```sql
USE ROLE SYSADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS COMPUTE_WH_RM WITH CREDIT_QUOTA = 15;
-- 003001 (42501): SQL access control error:
-- Insufficient privileges to operate on account '<account_locator>'.
```
**Why:** a resource monitor is an **account-level** object, and only ACCOUNTADMIN can create one by default. The error names the account, which shows the missing privilege is at account scope, not on the warehouse. ACCOUNTADMIN could grant `CREATE RESOURCE MONITOR` to another role, but that isn't worth it for a lab.

**Fix:** run the monitor statements as ACCOUNTADMIN, inside the script only:
```sql
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS COMPUTE_WH_RM
  WITH CREDIT_QUOTA = 15 FREQUENCY = WEEKLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = COMPUTE_WH_RM;
```
**How the monitor works:**
| Setting | Meaning |
|---|---|
| `CREDIT_QUOTA = 15` | Credits allowed per period. Raise it if a lab needs more |
| `FREQUENCY = WEEKLY` | The used-credit counter resets every week. Other values: `DAILY`, `MONTHLY`, `YEARLY`, `NEVER` |
| `START_TIMESTAMP = IMMEDIATELY` | The first period starts now, so later weekly resets fall on this weekday and time |
| `NOTIFY` at 75% | Sends an alert only (email for account admins who enabled notifications) |
| `SUSPEND` at 100% | Running queries finish, then the warehouse suspends and new queries are blocked |
| `SUSPEND_IMMEDIATE` at 110% | Cancels running queries and suspends at once. This is the hard stop if long queries keep going past 100% |

- **Warehouse vs account monitor.** `ALTER WAREHOUSE ... SET RESOURCE_MONITOR` makes it a warehouse-level monitor (`level = WAREHOUSE` in `SHOW RESOURCE MONITORS`). It limits only `COMPUTE_WH`. An account-level monitor (`ALTER ACCOUNT SET RESOURCE_MONITOR = ...`) would cover all warehouses.
- **What it doesn't limit:** serverless features (Snowpipe, tasks without a warehouse, search optimisation) and cloud services credits. It controls warehouse credits only.
- **Ownership:** the monitor stays owned by ACCOUNTADMIN. That's expected, and it has no effect on the lab's ownership rule, which covers the warehouse and database.
- **Changing the quota later:** `USE ROLE ACCOUNTADMIN; ALTER RESOURCE MONITOR COMPUTE_WH_RM SET CREDIT_QUOTA = <n>;`

## 4. Verify ownership
```sql
SHOW WAREHOUSES LIKE 'COMPUTE_WH';      -- owner SYSADMIN, size X-Small, auto_suspend 60, resource_monitor COMPUTE_WH_RM, SUSPENDED
SHOW DATABASES LIKE 'UTIL_DB';          -- owner SYSADMIN
SHOW SCHEMAS IN DATABASE UTIL_DB;       -- PUBLIC owner SYSADMIN; INFORMATION_SCHEMA has no owner (system view schema)
```

## 5. User defaults: the lowercase user name again
The lab's form, adapted to our user:
```sql
USE ROLE SYSADMIN;
ALTER USER <user_name> SET DEFAULT_ROLE = 'SYSADMIN';
-- 002003 (02000): SQL compilation error: User '<USER_NAME>' does not exist or not authorized.
```
**Why:** the same identifier rule as in b01. Unquoted identifiers are uppercased, and this user was created in lowercase. The lab's `KISHOREK` works only because that user name is uppercase.

**Fix 1, quote the exact name:**
```sql
ALTER USER "<user_name>" SET DEFAULT_ROLE = 'SYSADMIN';
ALTER USER "<user_name>" SET DEFAULT_WAREHOUSE = 'COMPUTE_WH';
ALTER USER "<user_name>" SET DEFAULT_NAMESPACE = 'UTIL_DB.PUBLIC';
-- Statement executed successfully. (x3)
```

**Fix 2, no hardcoded name.** This form is used in `sql/02_setup.sql` so that no user name is committed. The obvious attempt fails:
```sql
ALTER USER IDENTIFIER(CURRENT_USER()) SET DEFAULT_ROLE = 'SYSADMIN';
-- 001003 (42000): syntax error ... unexpected 'CURRENT_USER'.
```
`IDENTIFIER()` accepts only a string literal or a session variable, not a function call. Put the value in a variable first:
```sql
SET my_user = '"' || CURRENT_USER() || '"';   -- '"<user_name>"' : quotes keep the lowercase
ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'SYSADMIN';
DESC USER IDENTIFIER($my_user);
```
The added double quotes matter. Without them, `IDENTIFIER('<user_name>')` would be uppercased like any unquoted name.

**Lessons:**
- **No SECURITYADMIN needed.** A user can change its own defaults (`DEFAULT_ROLE`, `DEFAULT_WAREHOUSE`, `DEFAULT_NAMESPACE`, and others). Changing another user's defaults needs `OWNERSHIP` on that user, usually through USERADMIN or SECURITYADMIN.
- **Defaults are applied at login. They aren't checked when you set them.** Snowflake accepts a default role you don't hold, or a warehouse that doesn't exist, and the session then starts without it. That's why the warehouse and database were created before the defaults were set.
- **A namespace is `DATABASE.SCHEMA`** (or just a database).
- **Defaults apply to all clients:** Snowsight worksheets, the CLI, and drivers. A value set on the connection (`role`, `warehouse`, `database` in `connections.toml`) overrides them. That's why the shared template sets only `role`.
- **Noticed: `DEFAULT_SECONDARY_ROLES = ["ALL"]`** (see "Primary and secondary roles" above). `SELECT CURRENT_SECONDARY_ROLES();` in a SYSADMIN session returned `ACCOUNTADMIN,ORGADMIN`. That is why the resource monitor failed as SYSADMIN in section 3 even with ACCOUNTADMIN active as a secondary role. It is also why the new objects are owned by SYSADMIN. To see what the primary role alone can do, run `USE SECONDARY ROLES NONE;`. We kept the default.

## 6. Confirm the defaults in a fresh session
User defaults apply only to new sessions, so this was checked with a new CLI connection that sets no warehouse or database:
```sql
SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();
-- SYSADMIN | COMPUTE_WH | UTIL_DB | PUBLIC
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
-- {"project":"snow-hol-b05-data-engineering","env":"dev","tool":"snow","owner":"midega-g"}
```
`CURRENT_WAREHOUSE()` returns `COMPUTE_WH` even while the warehouse is suspended. Setting a session's warehouse doesn't start it. Only a query that needs compute triggers auto-resume.

## 7. Idempotency check
Running `sql/02_setup.sql` a second time:
```
COMPUTE_WH already exists, statement succeeded.
UTIL_DB already exists, statement succeeded.
COMPUTE_WH_RM already exists, statement succeeded.
```
The warehouse stayed `SUSPENDED` and no credits were used. `CREATE`, `ALTER`, `SHOW` and `DESC` are metadata operations run by the cloud services layer, not by the warehouse.

## 8. DORA step 1: the API integration
DORA (Diagnostic Online Results Assessor) is the lab's grader. It runs in Snowflake's own AWS account and records lab progress there. Step 1 lets this account call it. The lab's command:
```sql
use role accountadmin;
create or replace api integration dora_api_integration
api_provider = aws_api_gateway
api_aws_role_arn = 'arn:aws:iam::321463406630:role/snowflakeLearnerAssumedRole'
enabled = true
api_allowed_prefixes = ('https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora');
```
`sql/04_dora_api_integration.sql` runs the same statement with `CREATE ... IF NOT EXISTS`. Subsection 8.5 explains why.

### 8.1 What an API integration is
An **account-level** object with no database or schema, listed by `SHOW INTEGRATIONS`. It stores the settings for reaching an HTTPS service, and it runs no code itself:
- the kind of proxy service (`API_PROVIDER`);
- the identity Snowflake uses at that provider (here an AWS IAM role);
- an allowlist of URL prefixes Snowflake may call;
- an on/off switch.

Nothing happens until an **external function** points at it: `CREATE EXTERNAL FUNCTION ... API_INTEGRATION = dora_api_integration AS '<url>'`. That is DORA step 2. The integration holds the trust settings, and the function holds the URL and the SQL signature.

Snowflake has several integration types. They are easy to mix up:
| Type | Created with | Lets Snowflake... |
|---|---|---|
| API integration | `CREATE API INTEGRATION` | call a proxy service (AWS API Gateway, Azure API Management, Google API Gateway) from an external function. Also used for Git repositories (`git_https_api`) |
| Storage integration | `CREATE STORAGE INTEGRATION` | read and write cloud storage (S3, GCS, Azure) from stages |
| External access integration | `CREATE EXTERNAL ACCESS INTEGRATION` + network rules | let Python/Java UDFs and procedures make their own outbound calls |
| Security integration | `CREATE SECURITY INTEGRATION` | handle sign-in (SSO, OAuth). The two that already existed here (`OIDC_GOOGLE`, `SNOWFLAKE$LOCAL_APPLICATION`) are this type |

### 8.2 How a call travels (AWS API Gateway)
From the docs ("Introduction to external functions"):
1. A query calls the external function, and the warehouse executes it.
2. Snowflake checks the function's URL against `API_ALLOWED_PREFIXES` (and `API_BLOCKED_PREFIXES`). No match means an error, and no request is sent.
3. Snowflake's AWS IAM user for this account (`API_AWS_IAM_USER_ARN`) calls AWS STS `AssumeRole` on `API_AWS_ROLE_ARN`, passing `API_AWS_EXTERNAL_ID`.
4. AWS checks that role's **trust policy**. If the policy trusts this caller, AWS returns temporary credentials.
5. Snowflake signs an HTTPS `POST` with those credentials and sends the rows as JSON batches. Each row is tagged with its row number.
6. API Gateway checks the signature and passes the request to its backend. The backend returns one result row per input row. We can't see what DORA's backend is.

No password or token is stored anywhere. Trust is a two-sided handshake: Snowflake says which role it wants, and the role's trust policy in AWS says who may assume it.

### 8.3 Parameters
| Parameter | Value here | Meaning |
|---|---|---|
| `API_PROVIDER` | `aws_api_gateway` | A regional API Gateway endpoint. Other options: `aws_private_api_gateway` (PrivateLink), the `aws_gov_*` variants, `azure_api_management`, `google_api_gateway`, `git_https_api`. Write it as an unquoted keyword |
| `API_AWS_ROLE_ARN` | `arn:aws:iam::321463406630:role/snowflakeLearnerAssumedRole` | The role to assume. Account `321463406630` belongs to Snowflake's education team, not to us, so we can't see or change its trust policy |
| `API_ALLOWED_PREFIXES` | `https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora` | A plain prefix match: every external function using this integration must have a URL that starts with this string. This is the main way to limit what the integration can reach. `('https://')` would allow anything |
| `API_BLOCKED_PREFIXES` | not set | Exceptions inside the allowed prefixes. Blocked wins |
| `API_KEY` | not set | Optional. Sends an `x-api-key` header for API Gateway usage plans |
| `ENABLED` | `true` | `ALTER API INTEGRATION dora_api_integration SET ENABLED = FALSE;` acts as a kill switch for every function using it |

### 8.4 What Snowflake generates
```sql
DESC INTEGRATION dora_api_integration;
-- ENABLED true | API_PROVIDER AWS_API_GATEWAY | API_AWS_ROLE_ARN arn:aws:iam::321463406630:role/... | API_ALLOWED_PREFIXES https://awy6...
-- API_AWS_IAM_USER_ARN  <generated>   API_AWS_EXTERNAL_ID  <generated>   API_KEY / API_BLOCKED_PREFIXES / COMMENT empty
```
- **`API_AWS_IAM_USER_ARN`:** the AWS identity Snowflake uses for this account.
- **`API_AWS_EXTERNAL_ID`:** a value AWS requires on the `AssumeRole` call. It guards against the "confused deputy" problem: Snowflake serves many customers from the same AWS side, and the external ID proves which customer's integration is asking.

In a normal setup with your own AWS account, you copy both values into the IAM role's trust policy (`Principal` = the IAM user ARN, `sts:ExternalId` condition = the external ID). DORA's role is shared by every learner, so its trust policy has to accept any learner account. Presumably it doesn't check external IDs, but we can't verify that.

Both values are specific to this account, so they stay out of these notes and out of git. They aren't credentials on their own, but publishing them weakens the external-ID check.

### 8.5 Experiment: `OR REPLACE` creates a new external ID
I compared hashes (not the values) of the two generated properties before and after running the lab's exact `CREATE OR REPLACE`:
```
before   IAM_USER_ARN:9c4e866d  EXTERNAL_ID:40e226d5
rerun    DORA_API_INTEGRATION already exists, statement succeeded.   (IF NOT EXISTS: untouched)
replace  Integration DORA_API_INTEGRATION successfully created.
after    IAM_USER_ARN:9c4e866d  EXTERNAL_ID:c43a5afb
```
- **The IAM user ARN belongs to the account.** It stayed the same.
- **The external ID belongs to the integration object.** `OR REPLACE` drops the object and creates a new one, so it gets a new ID.
- **Consequence with your own AWS role:** `CREATE OR REPLACE` breaks the trust policy until you paste in the new ID. Change settings with `ALTER API INTEGRATION ... SET ...` instead, which keeps the object and its ID. `OR REPLACE` also drops all grants on the object.
- **Why the lab uses `OR REPLACE` anyway:** DORA works for any learner, and a rerun overwrites a mistyped first attempt. For repeatable scripts, `IF NOT EXISTS` is the safer default. If a value ever needs fixing, use `ALTER`.

### 8.6 Privileges
```sql
USE ROLE SYSADMIN;
CREATE API INTEGRATION IF NOT EXISTS dora_api_integration ...;
-- 003001 (42501): SQL access control error
```
- **Creating** needs the account-level `CREATE INTEGRATION` privilege. By default only ACCOUNTADMIN has it. It failed even though ACCOUNTADMIN was active as a secondary role, which confirms again that `CREATE` uses only the primary role (section 5).
- **Owner:** `SHOW GRANTS ON INTEGRATION dora_api_integration;` → `OWNERSHIP` to ACCOUNTADMIN, and no other grants.
- **Using it:** whoever creates an external function on it needs `USAGE` on the integration. Callers then need `USAGE` on the function. If DORA step 2 creates the grader as SYSADMIN, run `GRANT USAGE ON INTEGRATION dora_api_integration TO ROLE SYSADMIN;` first. If step 2 uses ACCOUNTADMIN, no grant is needed. Follow the lab's step 2.

### 8.7 Visibility: secondary roles do affect `SHOW`
```sql
USE ROLE SYSADMIN; USE SECONDARY ROLES NONE; SHOW INTEGRATIONS LIKE 'DORA%';   -- 0 rows
USE ROLE SYSADMIN; /* default: secondary ALL */ SHOW INTEGRATIONS LIKE 'DORA%'; -- 1 row
```
Nothing grants the integration to SYSADMIN or PUBLIC, so SYSADMIN alone can't see it. With the default `ALL` secondary roles, ACCOUNTADMIN's privileges also count for `SHOW`, and the integration appears. This adds to section 1: the warehouses there showed up through PUBLIC grants, and secondary roles were not involved. But in a default SYSADMIN session, `SHOW` can list ACCOUNTADMIN-only objects too. For a strict "what can this role alone see" check, run `USE SECONDARY ROLES NONE` first.

### 8.8 Cost and data
- **Cost of creating:** creating or describing the integration is a metadata operation, so `COMPUTE_WH` stayed suspended.
- **Cost of calls:** calls through the external function use the warehouse while the query runs, plus a small data-transfer charge.
- **Data:** every value passed to the function leaves the account and goes to Snowflake's education AWS account. Section 9.2 lists exactly what the grader sends.

## 9. DORA step 2: the grader external function
### 9.1 What an external function is
An external function looks like a normal SQL function, but its body runs outside Snowflake. In this lab the body is DORA's grading code behind AWS API Gateway. When a query calls it:
1. The warehouse groups the input rows into batches.
2. Each batch is sent as one HTTPS POST with a JSON body. Every row is a `[row_number, arg1, arg2, ...]` array inside `{"data": [...]}`.
3. The call goes through the API integration from section 8: Snowflake assumes the IAM role and signs the request.
4. The service must reply with one `[row_number, value]` per input row. Snowflake matches the replies back to the rows.

The function has no data or code of its own in Snowflake. It is a name, an argument list, a return type, an integration and a URL.

### 9.2 The statement
`sql/05_dora_grader.sql`, the lab's SQL with comments added:
```sql
USE ROLE ACCOUNTADMIN;
USE SCHEMA UTIL_DB.PUBLIC;
CREATE OR REPLACE EXTERNAL FUNCTION util_db.public.grader(
      step varchar, passed boolean, actual integer, expected integer, description varchar)
RETURNS VARIANT
API_INTEGRATION = dora_api_integration
CONTEXT_HEADERS = (current_timestamp, current_account, current_statement, current_account_name)
AS 'https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora/grader';
```
- **`RETURNS VARIANT`:** the service returns JSON, and VARIANT holds it as is.
- **`API_INTEGRATION`:** names the integration that authorises the call. Snowflake rejects the URL unless it starts with one of the integration's `API_ALLOWED_PREFIXES`. Here `.../dev/edu_dora/grader` is under `.../dev/edu_dora`.
- **`CONTEXT_HEADERS`:** session values that Snowflake adds to each request as HTTP headers. DORA uses them to know which account ran which check, and when. So every call sends the timestamp, the account locator, the account name and **the full text of the calling statement** to DORA, as well as the five arguments.
- **`integer` becomes `NUMBER`:** `SHOW EXTERNAL FUNCTIONS` lists the signature as `GRADER(VARCHAR, BOOLEAN, NUMBER, NUMBER, VARCHAR) RETURN VARIANT`. `INTEGER` is an alias for `NUMBER(38,0)`. Use the listed types when naming the function in `SHOW GRANTS ON FUNCTION` or `DROP FUNCTION`.

### 9.3 Role and privileges
- **We created it as ACCOUNTADMIN**, the role the lab uses for the test. The creator needs `USAGE` on the integration, and ACCOUNTADMIN owns it, so no grant was needed. `SHOW GRANTS ON INTEGRATION` still lists only ACCOUNTADMIN's ownership.
- **It needs `CREATE FUNCTION` on `UTIL_DB.PUBLIC`.** SYSADMIN owns that schema (section 6). ACCOUNTADMIN gets the privilege through the role hierarchy, because SYSADMIN is granted to ACCOUNTADMIN.
- **Owner:** ACCOUNTADMIN, as the primary role (see "Primary and secondary roles"). The function is owned by ACCOUNTADMIN, inside a schema owned by SYSADMIN. Object ownership and schema ownership are separate.
- **Who can call it:** a caller needs `USAGE` on the function. The integration privilege is checked when the function is created, not when it is called. Today only ACCOUNTADMIN has it. To call the grader as SYSADMIN later: `GRANT USAGE ON FUNCTION util_db.public.grader(VARCHAR, BOOLEAN, NUMBER, NUMBER, VARCHAR) TO ROLE SYSADMIN;`. We didn't add it, because the lab calls the grader as ACCOUNTADMIN.
- **Why `OR REPLACE` is fine here**, unlike section 8.5: a function has no generated values. Replacing it does drop grants on it, so any `USAGE` grant above would have to be reapplied.

## 10. DORA step 3: connection test
`sql/06_dora_test.sql`:
```sql
USE ROLE ACCOUNTADMIN;
USE SCHEMA UTIL_DB.PUBLIC;
SELECT util_db.public.grader(step, (actual = expected), actual, expected, description) AS graded_results
FROM (SELECT 'DORA_IS_WORKING' AS step, (SELECT 123) AS actual, 123 AS expected, 'Dora is working!' AS description);
```
**First attempt, before step 2:** `002141 (42601): SQL compilation error: Unknown user-defined function UTIL_DB.PUBLIC.GRADER.` That's the lab's "GRADER doesn't exist" case. `SHOW USER FUNCTIONS IN SCHEMA UTIL_DB.PUBLIC` returned nothing.

**After step 2**, `GRADED_RESULTS` was:
```json
[{"_": "✅", "actual": 123, "description": "Dora is working!", "expected": 123, "passed": true, "step": "DORA_IS_WORKING"}]
```
- **How the pattern works:** each later DORA check computes `actual` with a query against your objects. The check passes `actual = expected` as `passed` and sends both numbers. DORA records the step for this account. The `passed` flag comes from your own SQL, but DORA also gets the full statement text through `CONTEXT_HEADERS`.
- **Warehouse:** the query ran on `COMPUTE_WH` (from `INFORMATION_SCHEMA.QUERY_HISTORY`). It took 1.7 s total, mostly the round trip to API Gateway. The warehouse auto-resumed for the call, and a check 75 s later showed it `SUSPENDED` again. An external function needs a running warehouse. Creating one doesn't, because creation is metadata only.
- **The 90-day window:** DORA counts from your first check to your last. All checks must fall within 90 days for the badge. Checks older than that must be rerun. The test above starts the clock (2026-11-18).

## 11. Project infrastructure: AGS_GAME_AUDIENCE
`sql/07_ags_game_audience.sql`, run as SYSADMIN. A read-only check beforehand (as SYSADMIN and as ACCOUNTADMIN) found no `AGS%` database.

### 11.1 Database and schemas
```sql
USE ROLE SYSADMIN;
CREATE DATABASE IF NOT EXISTS AGS_GAME_AUDIENCE;
DROP SCHEMA IF EXISTS AGS_GAME_AUDIENCE.PUBLIC;
CREATE SCHEMA IF NOT EXISTS AGS_GAME_AUDIENCE.RAW;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;
```
- **Every new database gets `PUBLIC` and `INFORMATION_SCHEMA`.** You can drop `PUBLIC`, but not `INFORMATION_SCHEMA`, which is a read-only view of the database's metadata. After the drop, `SHOW SCHEMAS IN DATABASE AGS_GAME_AUDIENCE` listed only `INFORMATION_SCHEMA` and `RAW`.
- **Qualify the drop.** `CREATE DATABASE` also makes the new database and its `PUBLIC` schema the session's current context. A bare `DROP SCHEMA PUBLIC` works right after the create, but on a rerun it would hit whichever database is current. `AGS_GAME_AUDIENCE.PUBLIC` can only hit this one.
- **Reset the context.** The dropped schema was the current one, so run `USE SCHEMA ... RAW` before creating anything unqualified.
- **Owner check:** the database, `RAW`, and everything below are owned by SYSADMIN, because SYSADMIN was the primary role (see "Primary and secondary roles"). If something had been created by the wrong role, the lab's fix would be `GRANT OWNERSHIP ON <object> <name> TO ROLE SYSADMIN COPY CURRENT GRANTS;`. A wrong name would be fixed with `ALTER <object> <old> RENAME TO <new>;`.

### 11.2 Table for raw JSON
```sql
CREATE TABLE IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.GAME_LOGS (RAW_LOG VARIANT);
```
- **`VARIANT`** holds any semi-structured value (an object, an array, or a scalar) up to 128 MB per value, uncompressed. Each JSON record lands in one row with no fixed columns. You pull fields out later with `raw_log:field::type`.
- **Code templates:** the lab builds this in Snowsight from a template (in a worksheet, the `+` menu or the database object explorer offers prefilled `CREATE` statements). The CLI has no templates, so we typed the statement. The result is the same.

### 11.3 External stage
```sql
CREATE STAGE IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.UNI_KISHORE
  URL = 's3://uni-kishore'
  DIRECTORY = (ENABLE = TRUE);
```
- **External stage:** a named pointer to a cloud storage location. Snowflake reads the files where they are. Nothing is copied until you load.
- **No credentials or storage integration:** `SHOW STAGES` shows `type EXTERNAL`, `has_credentials N`. The lab bucket allows public reads. A private bucket would need a `STORAGE_INTEGRATION` (see the table in 8.1) or keys.
- **Dash vs underscore:** S3 bucket names allow dashes but not underscores (`uni-kishore`). Snowflake identifiers allow underscores, and dashes only in quotes (`uni_kishore`).
- **Directory table** (`directory_enabled Y`): a file catalogue stored with the stage. Snowsight can browse the files, and `SELECT * FROM DIRECTORY(@uni_kishore)` lists them with metadata. On an external stage it isn't refreshed automatically unless `AUTO_REFRESH` and cloud event notifications are set up. After new files arrive, run `ALTER STAGE uni_kishore REFRESH;`.

### 11.4 Testing the stage
```sql
LIST @uni_kishore/kickoff;
```
One file:

| name | size | last_modified |
|---|---|---|
| `s3://uni-kishore/kickoff/DNGW_Sample_from_Agnies_Game.json` | 52071 | Sun, 4 Dec 2022 15:08:22 GMT |

- **`LIST` returns the full cloud path**, not a path relative to the stage. The text after `@uni_kishore/` is a prefix filter, so `kickoff` matches the `kickoff/` folder.
- **Cost:** `LIST`, `SHOW` and every `CREATE` here ran in cloud services. `COMPUTE_WH` stayed `SUSPENDED`.

### 11.5 File format
```sql
CREATE FILE FORMAT IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.FF_JSON_LOGS
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE;
```
- **A file format** is a named, reusable set of parsing options for `COPY INTO` and for querying staged files.
- **`STRIP_OUTER_ARRAY = TRUE`:** a file shaped `[ {...}, {...} ]` becomes one row per element. Without it, the whole array would be a single VARIANT value in one row, and that row is capped by VARIANT's size limit.
- **Defaults:** `SHOW FILE FORMATS` returned the other JSON options at their defaults: `COMPRESSION AUTO`, `STRIP_NULL_VALUES false`, `ALLOW_DUPLICATE false`, `IGNORE_UTF8_ERRORS false`, `MULTI_LINE true`.

### 11.6 Rerun
A second run of `07` reported "already exists" for each object, and "PUBLIC already dropped" for the drop. `sql/08_ags_verify.sql` repeats the `SHOW` and `LIST` checks.

## 12. Exploring the staged file before loading
`sql/09_explore_kickoff.sql`, as SYSADMIN. Querying a stage reads the file, so `COMPUTE_WH` auto-resumes.

```sql
SELECT $1 FROM @uni_kishore/kickoff LIMIT 3;                                  -- no file format
SELECT $1 FROM @uni_kishore/kickoff (file_format => 'ff_json_logs') LIMIT 5;  -- with it
```
- **Without a file format** the stage falls back to CSV, so each line is cut at the first comma: `[{"user_login":"atamlett0"`. That's useless, but it shows the stage works.
- **With `FF_JSON_LOGS`** each row is one whole JSON object, because `STRIP_OUTER_ARRAY` split the file's outer `[...]`.
- **Shape check before loading:** `COUNT(*)` gave 250 rows. `COUNT(DISTINCT OBJECT_KEYS($1)::string)` gave 1, so every record has the same keys: `agent`, `datetime_iso8601`, `user_event`, `user_login`.

### 12.1 Why `=>` here and `=` in COPY
- **`@stage (file_format => ...)`:** in a `FROM` clause, a stage is read like a table function, and its arguments use named-argument syntax `name => value`. `FLATTEN(input => ...)` uses the same syntax. A bare `=` would be read as a comparison. The value must be the **name** of an existing file format, quoted or not. You can't write options inline here. The only other argument is `pattern => '<regex>'`.
- **`COPY INTO ... FILE_FORMAT = (...)`:** `FILE_FORMAT` is a statement parameter, like `TYPE = JSON` in `CREATE FILE FORMAT`. Statement parameters use `=`. The brackets hold either `FORMAT_NAME = ff_json_logs` or inline options such as `TYPE = JSON STRIP_OUTER_ARRAY = TRUE`.

### 12.2 Checking for bad data before loading
- **`ON_ERROR` is a COPY option**, not a file format option, and a stage `SELECT` doesn't accept it. A `SELECT` from a stage simply fails on a file it can't parse.
- **The file format does hold the parse-level choices:** `IGNORE_UTF8_ERRORS`, `REPLACE_INVALID_CHARACTERS`, and for CSV `ERROR_ON_COLUMN_COUNT_MISMATCH`. These decide what counts as an error. `ON_ERROR` decides what COPY does about one.
- **There are four ways to check before or after a load:**
  1. **`VALIDATION_MODE` on the COPY itself, a dry run that loads nothing:**
     ```sql
     COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS FROM @uni_kishore/kickoff
     FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
     VALIDATION_MODE = RETURN_ERRORS;   -- or RETURN_ALL_ERRORS, or RETURN_10_ROWS
     ```
     It returned no rows, which means no errors. It won't work with a COPY that transforms data (`FROM (SELECT ...)`), nor with `MATCH_BY_COLUMN_NAME`.
  2. **A stage `SELECT` with `TRY_` casts**, for values that parse as JSON but are wrong for their purpose. COPY into a VARIANT column only checks that the JSON is valid. `COUNT_IF(TRY_TO_TIMESTAMP_NTZ($1:datetime_iso8601::text) IS NULL)` checks the dates.
  3. **`ON_ERROR` at load time**, to set what happens on a bad row. **For "load only correct data", keep `ABORT_STATEMENT`:** COPY is one transaction, so one bad row means nothing loads.
  4. **`SELECT * FROM TABLE(VALIDATE(game_logs, job_id => '_last'))` afterwards**, which lists the rows a previous COPY rejected. It's only useful with `CONTINUE` or `SKIP_FILE_*`.

| `ON_ERROR` | On a bad row | Default for |
|---|---|---|
| `ABORT_STATEMENT` | Stop, load nothing | Bulk COPY |
| `CONTINUE` | Skip the row, load the rest | |
| `SKIP_FILE` | Skip the whole file. Slower, because it buffers every file | Snowpipe |
| `SKIP_FILE_10` / `'SKIP_FILE_10%'` | Skip the file once it has 10 bad rows, or more than 10% bad | |

## 13. Loading the file
`sql/10_load_game_logs.sql`:
```sql
COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/kickoff
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
ON_ERROR = ABORT_STATEMENT;
```
Result: `status LOADED, rows_parsed 250, rows_loaded 250, errors_seen 0`, and `GAME_LOGS` has 250 rows. `ON_ERROR` is the default, but writing it out records the intent.

**A rerun returned "Copy executed with 0 files processed."** and the count stayed 250. COPY keeps **load metadata** per table: the files it has loaded and their checksums, kept for 64 days. It skips those files, so a rerun doesn't duplicate rows.

### 13.1 Choosing which files COPY loads
With no file named, COPY loads every file under the `FROM` path that it hasn't loaded yet. Other options:

| Option | What it does | Example |
|---|---|---|
| Path in `FROM` | Prefix filter. Only files under it | `FROM @uni_kishore/kickoff` |
| `FILES = (...)` | Exact names relative to the `FROM` path, up to 1000. A missing file aborts under `ABORT_STATEMENT` | `FILES = ('DNGW_Sample_from_Agnies_Game.json')` |
| `PATTERN = '<regex>'` | Regex. Bulk COPY matches it against the full path, so start it with `.*` | `PATTERN = '.*kickoff/.*[.]json'` |
| `FORCE = TRUE` | Ignores load metadata and reloads everything. **Creates duplicates** | |
| `LOAD_UNCERTAIN_FILES = TRUE` | Also loads files whose status is unknown: staged, and last loaded, more than 64 days ago | |
| `SIZE_LIMIT = <bytes>` | Stops starting new files once this much data is loaded | |
| `PURGE = TRUE` | Deletes files after a successful load. It needs delete rights on the bucket and fails silently without them, so it's no use on this public bucket | |
| `FROM (SELECT ... FROM @stage)` | Transforms during the load: reorders or casts columns, adds `METADATA$FILENAME` | |

Don't use `FILES` and `PATTERN` together, because then only `FILES` applies.

## 14. One column per attribute: the LOGS view
`sql/11_logs_view.sql`, as SYSADMIN:
```sql
CREATE OR REPLACE VIEW AGS_GAME_AUDIENCE.RAW.LOGS AS (
  SELECT
      raw_log:agent::text                       AS agent
    , raw_log:user_event::text                  AS user_event
    , raw_log:user_login::text                  AS user_login
    , raw_log:datetime_iso8601::timestamp_ntz   AS datetime_iso8601
    , raw_log
  FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
);
```
- **Path syntax:** `raw_log:agent` reads the `agent` key from the VARIANT column, giving another VARIANT. Nested keys chain with `.`, as in `col:a.b`, and arrays index with `[0]`. Keys are case-sensitive, column names are not.
- **Casts:** `::text` turns the VARIANT string into VARCHAR. Without the cast, the value stays VARIANT and prints in JSON quotes (`"login"`).
- **Why `TIMESTAMP_NTZ`:** the values look like `2022-10-13T01:24:53Z`. That's ISO 8601, and the trailing `Z` (Zulu) means UTC, offset +00:00. All 250 values end in `Z`, and all parse (`TRY_TO_TIMESTAMP_NTZ` found no NULLs). This session's `TIMEZONE` is `America/Los_Angeles`. The same literal cast three ways gave:

  | Cast | Result |
  |---|---|
  | `::timestamp_ntz` | `2022-10-13 01:24:53.000` |
  | `::timestamp_ltz` | `2022-10-12 18:24:53.000 -0700` |
  | `::timestamp_tz` | `2022-10-13 01:24:53.000 Z` |

  NTZ ("no time zone") keeps the wall-clock time as written and stores no zone. Every source value is UTC, so the stored times are UTC times, and the column's meaning is "UTC" by convention. LTZ would show each time in the session's zone, so the result would depend on who runs the query.
- **Order:** `RAW_LOG` comes last and stays in the view, so every row can be traced back to its original JSON.

**Checks:** `SELECT COUNT(*) FROM LOGS` returned 250. `DESC VIEW` showed `AGENT`, `USER_EVENT` and `USER_LOGIN` as `VARCHAR(16777216)`, `DATETIME_ISO8601` as `TIMESTAMP_NTZ(9)`, and `RAW_LOG` as `VARIANT`. The owner is SYSADMIN. A view stores only the query and no data, so each `SELECT` on it reads `GAME_LOGS` and uses the warehouse.

### 14.1 The local sample is a different file
The downloaded `DNGW_Sample_from_Agnies_Game.json` has the same name as the staged file but different contents: 2.5 MB, 10,000 records, and a fifth key `game_subscription_type`. The staged file is 52,071 bytes with 250 records and 4 keys. Everything above uses the staged file. The local copy sits in `data/`, which is gitignored because it's over the 500 KB large-file hook.

## 15. Time zones
- **UTC** is the reference time. GMT+0, UTC+0 and "Zulu" (`Z`) all mean the same offset. `UTC+5` means the UTC time plus 5 hours.
- **Converting:** at 1:00 AM GMT, a UTC+5 zone reads 6:00 AM. Greenwich isn't always on GMT, though. The UK uses BST (UTC+1) from late March until the last Sunday of October, so 1:00 AM on a BST date in Greenwich is 5:00 AM in UTC+5.
- **Timestamp layout:** in Snowflake format elements, a full timestamp is `YYYY-MM-DD HH24:MI:SS.FF3 TZH:TZM`.
  - `YYYY`, `MM`, `DD`: 4-digit year, then 2-digit month and day.
  - `HH24`: hour on the 24-hour clock, `00` to `23`. The `24` tells it apart from `HH12`, the 12-hour clock (`01` to `12`), which needs `AM`/`PM` to be unambiguous. A plain `HH` means `HH24`.
  - `MI`, `SS`: 2-digit minutes and seconds. `MI` is used because `MM` already means month.
  - `FF3`: fractional seconds to 3 digits, which is milliseconds. `FF9` gives nanoseconds, the most `TIMESTAMP` can hold.
  - `TZH:TZM`: the offset from UTC in hours and minutes, with its sign giving the direction. `-06:00` (or `-0600`) means UTC-6, which is Denver in October (MDT).
- **Trial accounts default to `America/Los_Angeles`.** That's UTC-7 in summer (PDT) and UTC-8 in winter (PST). Time zone names (`Region/City`) come from the [IANA time zone database](https://data.iana.org/time-zones/tzdb-2021a/zone1970.tab). Use those rather than fixed offsets, because they follow daylight saving changes.
- **`ALTER SESSION SET TIMEZONE`** changes only the current session. In Snowsight, each worksheet is its own session. With the CLI, each `snow sql` run is a new session, so `sql/12_time_zones.sql` keeps the whole demo in one run. Results on 2026-11-18:

  | Session `TIMEZONE` | `CURRENT_TIMESTAMP()` |
  |---|---|
  | (default) America/Los_Angeles | `2026-11-18T00:45:11.807-08:00` (PST) |
  | UTC | `2026-11-18T08:45:12.666+00:00` |
  | Africa/Nairobi | `2026-11-18T11:45:13.499+03:00` (no DST) |
  | Pacific/Funafuti | `2026-11-18T20:45:14.642+12:00` |
  | Asia/Shanghai | `2026-11-18T16:45:15.708+08:00` |

  The clock time changed while the moment stayed the same, 08:45 UTC (about a second apart per query).
- **`SHOW PARAMETERS LIKE 'timezone'`** returned value `Asia/Shanghai` at level `SESSION`. The same command with `IN ACCOUNT` still showed `America/Los_Angeles`, with an empty level, meaning the account uses the default. Neither `CURRENT_TIMESTAMP` nor `SHOW` needed the warehouse.
- **NTZ, LTZ and TZ:** see section 14. The session time zone changes how LTZ values display. NTZ values don't change.

## 16. A second file with a different shape
`sql/13_load_updated_feed.sql` and `sql/14_filter_new_rows.sql`, as SYSADMIN.

### 16.1 Finding the file
`LIST @uni_kishore;` with no path lists the whole bucket:

| name | size | last_modified |
|---|---|---|
| `s3://uni-kishore/kickoff/DNGW_Sample_from_Agnies_Game.json` | 52071 | Sun, 4 Dec 2022 |
| `s3://uni-kishore/updated_feed/DNGW_updated_feed_0_0_0.json` | 34910 | Sat, 25 Feb 2023 |

The `_0_0_0` suffix is the naming pattern Snowflake uses when it unloads to files (`COPY INTO @stage`), so this feed was probably exported from another Snowflake account.

### 16.2 Comparing the two files before loading
I queried the new file through the stage with `FF_JSON_LOGS`:
```sql
SELECT OBJECT_KEYS($1)::string AS keys, COUNT(*)
FROM @uni_kishore/updated_feed (file_format => 'ff_json_logs') GROUP BY 1;
```
It has 284 rows, all with the same key set:

| | kickoff (250 rows) | updated_feed (284 rows) |
|---|---|---|
| `agent` | yes | **removed** |
| `ip_address` | no | **added**. VARCHAR, all 284 parse with `PARSE_IP(..., 'INET', 1)` |
| `user_event`, `user_login` | yes | yes. Logins now include non-ASCII names such as `Woźniak31`, which load fine as UTF-8 |
| `datetime_iso8601` | `2022-10-13T01:24:53Z` | `2022-10-14 22:28:58.000` |
| Date range | 10 to 13 Oct 2022 | 14 to 16 Oct 2022 |

**The timestamp format changed too.** The new values have a space instead of `T`, add milliseconds, and **have no `Z`**. They no longer say which time zone they're in. They still parse: `TRY_TO_TIMESTAMP_NTZ` found no failures, because `AUTO` detection handles both layouts. But the `LOGS` column now mixes values known to be UTC with values of unknown zone. The ranges don't overlap and the new file starts right after the old one ends, which fits UTC. That's only consistent with UTC, not proof. Ask the data's owner before relying on it. In real work this belongs in a data contract with the source. Section 18 settles it with known test records: the values are UTC.

### 16.3 Does GAME_LOGS need to change?
**No.** `GAME_LOGS` has one `VARIANT` column, and the JSON keys live inside each value. A new or missing key changes nothing at the table level. This is "schema on read": the structure is applied when you query, not when you load.

A change would be needed if the table had typed columns, for example `AGENT VARCHAR, ...` loaded with `MATCH_BY_COLUMN_NAME`. Then you would need `ALTER TABLE game_logs ADD COLUMN ip_address VARCHAR;`, and the old rows would get NULL there. Table schema evolution (`ENABLE_SCHEMA_EVOLUTION = TRUE`) can add such columns automatically during COPY.

### 16.4 The load
Only the `FROM` path changed from section 13:
```sql
COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/updated_feed
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
ON_ERROR = ABORT_STATEMENT;
```
- **Dry run first:** `VALIDATION_MODE = RETURN_ERRORS` returned no rows.
- **Load:** `status LOADED, rows_parsed 284, rows_loaded 284, errors_seen 0`.
- **Count:** `GAME_LOGS` now has **534** rows (250 + 284). The old rows were never touched, because COPY only appends.
- **Rerun:** "Copy executed with 0 files processed.", still 534.
- **Wider path:** `FROM @uni_kishore` with no folder would also work, because load metadata would skip the kickoff file it already loaded. But that relies on the 64-day metadata window. The explicit folder states what is meant.

### 16.5 How the new rows look
- **In `GAME_LOGS`:** each new `RAW_LOG` has `ip_address` and no `agent`.
- **In the `LOGS` view:** the view still works, because missing keys don't cause errors. But it is now incomplete:
  - The 284 new rows show **`AGENT` as NULL**.
  - **`ip_address` isn't in the view at all**, because the view only extracts the keys it names.
  - `DATETIME_ISO8601` holds both layouts as one `TIMESTAMP_NTZ`. Kickoff rows run from 2022-10-10 00:04:02 to 10-13 23:32:56, and new rows from 10-14 22:10:30 to 10-16 03:38:45.

  The view needs updating before the new field is usable. That isn't done yet.

### 16.6 Filtering to the new rows
```sql
SELECT raw_log:ip_address::text AS ip_address, raw_log:user_event::text AS user_event,
       raw_log:user_login::text AS user_login,
       raw_log:datetime_iso8601::timestamp_ntz AS datetime_iso8601, raw_log
FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
WHERE raw_log:agent IS NULL           -- removed field
  AND raw_log:ip_address IS NOT NULL; -- added field
```
Result: 284 rows. Either condition alone gives the same rows. A cross-tab by key confirms it: `has_agent=true, has_ip=false` is 250 rows and `has_agent=false, has_ip=true` is 284. No row has both keys or neither.

- **`IS NULL` works here** because the key is missing in the new rows, not set to `null`. Section 16.7 explains the difference.
- **Which test is stronger?** `ip_address IS NOT NULL` tests for something the new file has. `agent IS NULL` would also match any future file without `agent`, or a kickoff row with a missing value. Using both makes the filter exact for these two files.
- **Filtering by file instead of by shape** removes the guesswork. Section 16.8 shows how.

### 16.7 Missing key vs JSON `null`
JSON can say "no value" in two ways. The key can be left out (`{"ip_address": "1.2.3.4"}`), or it can be present with the value `null` (`{"agent": null}`). Snowflake keeps the two apart.
- **A missing key** gives a real **SQL NULL**.
- **A JSON `null`** gives a VARIANT that **holds** a null. Snowflake calls this `NULL_VALUE`. The VARIANT itself is not NULL.

`sql/15_missing_key_vs_json_null.sql` tests all three cases on literal JSON, with no table involved:
```sql
WITH samples AS (
  SELECT 'key present, string' AS case_name, PARSE_JSON('{"agent": "Mozilla/5.0"}') AS v UNION ALL
  SELECT 'key present, null',                PARSE_JSON('{"agent": null}')          UNION ALL
  SELECT 'key missing',                      PARSE_JSON('{"ip_address": "1.2.3.4"}')
)
SELECT case_name,
       v:agent                AS agent_variant,
       v:agent IS NULL        AS is_sql_null,
       IS_NULL_VALUE(v:agent) AS is_json_null,
       TYPEOF(v:agent)        AS typeof_agent,
       v:agent::text          AS agent_text,
       ARRAY_CONTAINS('agent'::variant, OBJECT_KEYS(v)) AS has_key
FROM samples;
```
| case_name | agent_variant | is_sql_null | is_json_null | typeof_agent | agent_text | has_key |
|---|---|---|---|---|---|---|
| key present, string | `"Mozilla/5.0"` | false | false | `VARCHAR` | `Mozilla/5.0` | true |
| key present, null | `null` | **false** | **true** | `NULL_VALUE` | NULL | true |
| key missing | NULL | **true** | NULL | NULL | NULL | false |

What the output shows:
- **`IS NULL` is false for a JSON null.** The VARIANT holds something: the JSON `null` itself. So `WHERE v:agent IS NULL` misses those rows.
- **`IS_NULL_VALUE()` only finds JSON nulls.** For a missing key it returns NULL, not false, because there's nothing to test. `NOT IS_NULL_VALUE(...)` therefore drops missing-key rows as well.
- **A cast hides the difference.** `v:agent::text` is SQL NULL in both cases. After casting, as the `LOGS` view does, you can no longer tell which case a row was.
- **To ask "is the key there?" directly**, test the key list: `ARRAY_CONTAINS('agent'::variant, OBJECT_KEYS(v))`. It's true even when the value is `null`.

Which test to use:

| Question | Test |
|---|---|
| No usable value, for either reason | `v:agent::text IS NULL`, or `v:agent IS NULL OR IS_NULL_VALUE(v:agent)` |
| Key missing | `v:agent IS NULL` |
| Key present but `null` | `IS_NULL_VALUE(v:agent)` |
| Key present, whatever its value | `ARRAY_CONTAINS('agent'::variant, OBJECT_KEYS(v))` |

**Turning JSON nulls into missing keys:** `STRIP_NULL_VALUE(v:agent)` converts a JSON null to SQL NULL. `STRIP_NULL_VALUE(PARSE_JSON('{"agent": null}'):agent) IS NULL` returned true. For a whole load, the JSON file format option `STRIP_NULL_VALUES = TRUE` drops every `"key": null` pair as the data loads. `FF_JSON_LOGS` keeps the default `FALSE`. Stripping makes filters simpler, but it loses the information that the source sent an explicit null.

**On `GAME_LOGS`:** `COUNT_IF(raw_log:agent IS NULL)` gave 284 and `COUNT_IF(IS_NULL_VALUE(raw_log:agent))` gave 0. The updated feed leaves `agent` out entirely, so the filter in 16.6 is correct.

### 16.8 Recording the source file during the load
Every staged file has **metadata columns** you can select next to `$1`:

| Column | Value |
|---|---|
| `METADATA$FILENAME` | File path **relative to the stage**, e.g. `updated_feed/DNGW_updated_feed_0_0_0.json`. `LIST` shows the full `s3://` URL instead |
| `METADATA$FILE_ROW_NUMBER` | Row number within the file, starting at 1. With `STRIP_OUTER_ARRAY` it counts array elements |
| `METADATA$FILE_LAST_MODIFIED` | When the file was last written to storage, as `TIMESTAMP_NTZ` in UTC |
| `METADATA$FILE_CONTENT_KEY` | Checksum of the file content |
| `METADATA$START_SCAN_TIME` | When Snowflake started reading the file |

They exist only while Snowflake reads files from a stage. A plain `COPY` doesn't keep them, so `GAME_LOGS` has no record of which file each row came from. That's why 16.6 had to tell the files apart by their keys.

`sql/16_copy_with_file_metadata.sql` shows the pattern. It loads into a **temporary table**, which exists only for the session and is dropped when the session ends, so the lab's `GAME_LOGS` stays exactly as the lab expects.

**1. Reading the metadata from the stage, before any load:**
```sql
SELECT METADATA$FILENAME AS file_name,
       MIN(METADATA$FILE_ROW_NUMBER) AS first_row, MAX(METADATA$FILE_ROW_NUMBER) AS last_row,
       ANY_VALUE(METADATA$FILE_LAST_MODIFIED) AS file_last_modified, COUNT(*) AS n_rows
FROM @uni_kishore (file_format => 'ff_json_logs')
GROUP BY 1 ORDER BY 1;
```
| file_name | first_row | last_row | file_last_modified | n_rows |
|---|---|---|---|---|
| `kickoff/DNGW_Sample_from_Agnies_Game.json` | 1 | 250 | 2022-12-04 15:08:22 | 250 |
| `updated_feed/DNGW_updated_feed_0_0_0.json` | 1 | 284 | 2023-02-25 17:10:52 | 284 |

**2. Loading with COPY plus a SELECT** (a "transforming" COPY):
```sql
CREATE TEMPORARY TABLE game_logs_with_file (
    raw_log VARIANT, file_name VARCHAR, file_row_number NUMBER, loaded_at TIMESTAMP_LTZ);

COPY INTO game_logs_with_file (raw_log, file_name, file_row_number, loaded_at)
FROM (
  SELECT $1, METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, CURRENT_TIMESTAMP()
  FROM @uni_kishore
)
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
PATTERN = '.*[.]json'
ON_ERROR = ABORT_STATEMENT;
```
Both files loaded: `updated_feed` with 284 rows and `kickoff` with 250, and no errors.
- **The column list** `(raw_log, file_name, ...)` matches the SELECT's columns by position.
- **Stage queries in this form allow only simple transforms:** picking `$` columns, casts, metadata columns, and functions such as `CURRENT_TIMESTAMP()`. Snowflake's "Transforming data during a load" page rules out `WHERE`, `GROUP BY`, `JOIN`, `FLATTEN`, `ORDER BY`, `LIMIT` and `MATCH_BY_COLUMN_NAME`.
- **`VALIDATION_MODE` can't be used with a transforming COPY** (section 12.2). For a dry run, query the stage with the same SELECT first.
- **`PATTERN`** limits the load to `.json` files across both folders. `FROM @uni_kishore` alone would also pick up any other files in the bucket.
- **A fresh table has fresh load metadata**, so both files loaded even though `GAME_LOGS` had already loaded them. Load metadata belongs to the table, not to the stage.

**3. Filtering by file, not by shape:**
```sql
SELECT file_name, COUNT(*) FROM game_logs_with_file GROUP BY 1 ORDER BY 1;
-- kickoff/DNGW_Sample_from_Agnies_Game.json    250
-- updated_feed/DNGW_updated_feed_0_0_0.json    284

SELECT raw_log:ip_address::text AS ip_address, raw_log:user_login::text AS user_login,
       file_name, file_row_number
FROM game_logs_with_file
WHERE file_name LIKE 'updated_feed/%'
ORDER BY file_row_number LIMIT 3;
```
| ip_address | user_login | file_name | file_row_number |
|---|---|---|---|
| 184.105.65.130 | Woźniak31 | updated_feed/DNGW_updated_feed_0_0_0.json | 1 |
| 185.180.206.138 | Nowak11 | updated_feed/DNGW_updated_feed_0_0_0.json | 2 |
| 212.77.102.236 | Adamski76 | updated_feed/DNGW_updated_feed_0_0_0.json | 3 |

**Why this is common practice:**
- **Lineage:** each row points back to its exact file and line. A bad value can be traced to the delivery it came in.
- **Filtering:** "rows from the second file" becomes `WHERE file_name LIKE 'updated_feed/%'`. It keeps working when a later file has the same keys as an earlier one, which the 16.6 shape filter can't handle.
- **Reloading:** to replace one bad file, run `DELETE ... WHERE file_name = '...'` and then `COPY ... FILES = ('...') FORCE = TRUE`. Nothing else is touched.
- **Audit:** `loaded_at` records when the row arrived. That's different from the event time inside the JSON.

The cost is a few extra columns per row, which compress well because they repeat. Afterwards, `SHOW TABLES` in `RAW` listed only `GAME_LOGS` with 534 rows, which confirms the temporary table was gone.


## 17. Updating the LOGS view
The view from section 14 was built for the kickoff file. It now shows all 534 rows, with `AGENT` empty for the 284 new ones and no `IP_ADDRESS` column. `sql/17_update_logs_view.sql` replaces it:
```sql
CREATE OR REPLACE VIEW AGS_GAME_AUDIENCE.RAW.LOGS AS (
  SELECT
      raw_log:ip_address::text                  AS ip_address
    , raw_log:user_event::text                  AS user_event
    , raw_log:user_login::text                  AS user_login
    , raw_log:datetime_iso8601::timestamp_ntz   AS datetime_iso8601
    , raw_log
  FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
  WHERE raw_log:ip_address::text IS NOT NULL
);
```
- **`CREATE OR REPLACE`** swaps the definition in one statement. A plain `CREATE VIEW` fails because `LOGS` already exists. Replacing a view also resets its grants unless you add `COPY GRANTS`. That doesn't matter here, because only SYSADMIN uses it.
- **`AGENT` is dropped** because no row the view returns has it. **`IP_ADDRESS` is added** as text.
- **The `WHERE` clause hides the kickoff rows. It doesn't delete them.** A view is a saved query, so `GAME_LOGS` still holds all 534 rows. The filter tests for the key the new file has, as section 16.6 recommends.
- **Column order doesn't matter** to anyone querying by name. `raw_log` stays last so the parsed columns come first.

**Checks:**
- `SELECT COUNT(*), COUNT(ip_address) FROM LOGS` gave 284 and 284.
- `SELECT COUNT(*) FROM GAME_LOGS` still gave 534.
- `DESC VIEW LOGS` lists `IP_ADDRESS`, `USER_EVENT`, `USER_LOGIN` (all `VARCHAR`), `DATETIME_ISO8601` (`TIMESTAMP_NTZ(9)`) and `RAW_LOG` (`VARIANT`).

**Schema-on-read.** The table took both files without any change, because a VARIANT column accepts any JSON. The structure is decided when the data is read, by the view. When the source changed its keys, only the view had to change. In a schema-on-write system the load itself would have failed or needed a table change first (section 16.3).

## 18. Checking the time zone with a known test event
A test record with a known time is a simple way to find out which clock a feed uses. Here the test login happened at **7:22 PM on Saturday, 15 October 2022**, local time, in a zone at UTC-6.
- **On the 24-hour clock**, 7:22 PM is 19:22. ISO 8601 always uses the 24-hour clock (the `HH24` element from section 15).
- **In UTC**, add 6 hours: 19:22 + 6:00 = 25:22, which rolls over to **01:22 on Sunday, 16 October**.

So the log should show either `2022-10-15 19:22` (local time) or `2022-10-16 01:22` (UTC).

**Searching when only part of a value is known.** `ILIKE` is a case-insensitive `LIKE`, and `%` matches any run of characters, including none. Assuming the test user's login contains `prajina` somewhere, `'%prajina%'` matches it whether it is `prajina`, `Prajina99` or `princess_prajina`. `sql/18_find_test_records.sql`:
```sql
SELECT user_login, user_event, datetime_iso8601, ip_address
FROM AGS_GAME_AUDIENCE.RAW.LOGS
WHERE user_login ILIKE '%prajina%'
ORDER BY datetime_iso8601;
```
| user_login | user_event | datetime_iso8601 | ip_address |
|---|---|---|---|
| princess_prajina | login | 2022-10-16 01:22:15 | 100.41.16.160 |
| princess_prajina | logout | 2022-10-16 01:39:15 | 100.41.16.160 |

- **Two rows match:** a login and a logout 17 minutes later, from the same IP.
- **The login is at 01:22 on Sunday, the UTC value.** No row exists at 19:22 on Saturday.
- **Conclusion: the `updated_feed` timestamps are UTC**, even though they no longer carry a `Z`. They are not in the user's local time (LTZ). This settles the question from section 16.2. Both files are UTC, so `TIMESTAMP_NTZ` in the view holds UTC wall-clock times throughout.

## 19. Time zones from IP addresses
The feed has UTC times but no local time zone, and the source can't add one yet. The `ip_address` column can fill the gap: an IP address can be **geolocated**, and the location gives a time zone. Adding a time zone to each row is the first **transformation** of the logs. It **enhances** (enriches) the raw data with information the source didn't send.

**Caveat:** a VPN or proxy shows the address of its exit server, not the user's. Those rows get the wrong zone. An approximate zone for most rows is still better than none.

**Ways to geolocate:**

| Option | How it works | Drawbacks |
|---|---|---|
| Lookup API | Call a web service per address | Usually a fee per lookup, often a contract up front. Calls leave Snowflake |
| Downloadable database | Load a file of IP ranges into a table | Often country only, so a second mapping from country to time zone is needed. Countries with several zones stay ambiguous |
| [Snowflake Marketplace](https://app.snowflake.com/marketplace) share | A provider shares tables that appear as a read-only database in your account | Free samples are partial. Full coverage is a paid listing |

A Marketplace share needs no file loads or API calls. The data stays with the provider and is queried in place, and updates arrive without any work on your side. The next step uses the free IPinfo sample listing.

### 19.1 `PARSE_IP`
[`PARSE_IP(expr, type [, permissive])`](https://docs.snowflake.com/en/sql-reference/functions/parse_ip) splits an IPv4 or IPv6 string into its parts and returns an OBJECT.
- **`type`** is `'INET'` for a single address, or `'CIDR'` for a network.
- **`permissive`** (optional): `0`, the default, fails on a bad address. `1` returns an object with only an `error` field, which suits bulk checks such as the one in section 16.2.

`sql/19_parse_ip.sql` uses the test user's address from section 18:
```sql
SELECT PARSE_IP('100.41.16.160', 'inet');
```
```json
{
  "family": 4,
  "host": "100.41.16.160",
  "ip_fields": [1680412832, 0, 0, 0],
  "ip_type": "inet",
  "ipv4": 1680412832,
  "netmask_prefix_length": null,
  "snowflake$type": "ip_address"
}
```
| Key | Meaning |
|---|---|
| `family` | `4` for IPv4, `6` for IPv6 |
| `host` | The address as text |
| `ip_fields` | The address as four 32-bit numbers. IPv4 fills only the first. IPv6 (128 bits) uses all four |
| `ip_type` | The `type` argument: `inet` or `cidr` |
| `ipv4` | The address as **one integer** |
| `netmask_prefix_length` | The `/n` of a network. `null` for a single address |
| `snowflake$type` | Always `ip_address`. Marks the object as `PARSE_IP` output |

IPv6 input returns `hex_ipv6` instead of `ipv4`.

### 19.2 Pulling out one field
The result is an OBJECT, so the `:` path syntax from section 14 works directly after the function call:
```sql
SELECT PARSE_IP('100.41.16.160', 'inet'):host::text  AS host,     -- 100.41.16.160
       PARSE_IP('100.41.16.160', 'inet'):family::int AS family,   -- 4
       PARSE_IP('100.41.16.160', 'inet'):ipv4::int   AS ipv4;     -- 1680412832
```
**Why `ipv4` as an integer:** an IPv4 address is a 32-bit number. The dotted form writes its four bytes in base 10. Each byte is a digit in base 256:

`100·256³ + 41·256² + 16·256 + 160 = 1,680,412,832`

The query in the script gave the same value. As text, addresses compare badly: `'100.41.16.160' < '9.0.0.0'`, because the comparison goes character by character. As integers they sort in network order, and a range test is a plain `BETWEEN`.

**Networks give a range.** With a `/n` suffix, `PARSE_IP` also returns where the network starts and ends:
```sql
SELECT PARSE_IP('100.41.16.0/24', 'inet');
-- "ipv4_range_start": 1680412672, "ipv4_range_end": 1680412927, "netmask_prefix_length": 24
```
`/24` means the first 24 bits are fixed and the last 8 vary, so the network holds 256 addresses: 1680412672 to 1680412927. Geolocation tables store rows like this, one range per location. Looking up an address then means finding the range where `ipv4 BETWEEN range_start AND range_end`.

## 20. Enhancement infrastructure
### 20.1 The `ENHANCED` schema
The raw feed lives in `RAW`. Enriched data goes in a separate schema, so the untouched source and the transformed result never mix. Each stage of a pipeline gets its own **layer**, and a layer can be rebuilt from the one before it. `sql/20_enhanced_schema.sql` creates `AGS_GAME_AUDIENCE.ENHANCED` as SYSADMIN.

### 20.2 Getting a Marketplace listing
A [listing](https://docs.snowflake.com/en/user-guide/data-marketplace-intro) is a provider's offer of a share: tables, views and functions in the provider's account. **Getting** it creates an **imported database** in your account that points at the provider's objects.
- **No storage cost.** No data is copied. You pay only for the warehouse that runs your queries.
- **Read-only.** You can't add or change objects in it.
- **Always current.** The provider refreshes the data and you see the change at once. This listing is updated daily.

Getting a listing needs ACCOUNTADMIN, or a role with the `IMPORT SHARE` privilege. The listing used here is **"IPinfo: IP Geolocation Training/Education Sample"**, free and licensed for internal training. It covers 7 countries at city level. In Snowsight's Get dialog:
- **Database name:** `IPINFO_GEOLOC`.
- **Roles that can access it, besides ACCOUNTADMIN:** `SYSADMIN`. The database then shows the grant `USAGE` to SYSADMIN.

**Finding the listing's global name.** Every listing has a **global name**, a short ID such as `GZSTZ3VDMEH` that SQL uses in place of the title. Two places show it:
- **Snowsight:** the listing page URL ends in it: `app.snowflake.com/marketplace/listing/GZSTZ3VDMEH`.
- **SQL:** [`SHOW AVAILABLE LISTINGS`](https://docs.snowflake.com/en/sql-reference/sql/show-available-listings) lists every listing visible to the account (4,430 here). The command has no `LIKE` filter in its syntax. `LIKE '%IPinfo%'` was accepted but ignored, and still returned all 4,430 rows. `IS_IMPORTED = TRUE` narrows the list to listings already got. To search by title, filter the SHOW output with the [pipe operator `->>`](https://docs.snowflake.com/en/sql-reference/operators-flow). `$1` refers to the previous statement's result, and SHOW output columns are lowercase, so they need double quotes:

```sql
SHOW AVAILABLE LISTINGS
  ->> SELECT "global_name", "title", "is_monetized", "is_ready_for_import"
      FROM $1 WHERE "title" ILIKE '%ipinfo%' ORDER BY "title";
```
| global_name | title | is_monetized | is_ready_for_import |
|---|---|---|---|
| GZSTZSHKQ56D | IPinfo Core | true | true |
| GZSTZ3VDMG3 | IPinfo Custom | false | false |
| GZSTZSHKQ55S | IPinfo Lite | false | true |
| GZSTZSHKQ56H | IPinfo Plus | true | true |
| GZSTZ3VDMEH | IPinfo: IP Geolocation Training/Education Sample | false | true |

`is_monetized = false` means free, and `is_ready_for_import = true` means the data is available in this account's region. The training sample is `GZSTZ3VDMEH`. [`DESCRIBE AVAILABLE LISTING GZSTZ3VDMEH`](https://docs.snowflake.com/en/sql-reference/sql/desc-available-listing) then shows its details, including `listing_terms` (`STANDARD` here) and usage examples such as `SELECT * FROM demo.location LIMIT 10`.

**SQL route.** [`CREATE DATABASE ... FROM LISTING '<global_name>'`](https://docs.snowflake.com/en/sql-reference/sql/create-database) does the same as Get, with `GRANT IMPORTED PRIVILEGES ON DATABASE ... TO ROLE SYSADMIN` for the role access. Two limits apply:
- The listing must be free.
- If its terms are of type `STANDARD`, they must first be accepted once in Snowsight. Before that, the CREATE fails with "the terms for the associated listing ... have not been accepted."

This listing has `STANDARD` terms, so the first Get happened in Snowsight. `sql/21_ipinfo_listing.sql` holds the SQL version, which reports "already exists" from then on, and the checks below.

### 20.3 What the database contains
| Schema | Contents |
|---|---|
| `DEMO` | The view `LOCATION`: 274,910 IP ranges with a place and time zone |
| `PUBLIC` | Many secure views (`IP_GEOLOCATION`, `IP_PRIVACY` and others), sample tables such as `SAMPLE_IPS`, and helper functions such as `TO_INT`, `TO_IP` and `IP_LOCATION` |
| `INFORMATION_SCHEMA` | Snowflake's metadata views, present in every database |

There is no `RAW` schema. That name belongs to this project's own database.

The provider's views are **secure views**. Their definitions are hidden from consumers, which a provider needs to protect its logic. The functions are secure too (`is_secure = Y`).

`DEMO.LOCATION` columns:

| Column | Type | Meaning |
|---|---|---|
| `START_IP`, `END_IP` | VARCHAR | The range in dotted form |
| `START_IP_INT`, `END_IP_INT` | VARIANT | The same range as integers |
| `JOIN_KEY` | VARCHAR | A coarse key that narrows the range search before the `BETWEEN` |
| `CITY`, `REGION`, `COUNTRY`, `POSTAL` | VARCHAR | The place |
| `LAT`, `LNG` | FLOAT | Latitude and longitude |
| `TIMEZONE` | VARCHAR | An IANA name such as `America/Denver` |

The integer columns are the range layout from section 19.2. `PUBLIC.TO_INT` converts an address to that integer: `TO_INT('100.41.16.160')` returns `1680412832`, the same value `PARSE_IP(...):ipv4` gave.

## Run order
```bash
P=02-snow-hands-on-labs/b05-data-engineering
source scripts/use-project.sh $P
snow sql -f projects/$P/sql/02_setup.sql
snow sql -f projects/$P/sql/03_verify.sql
snow sql -f projects/$P/sql/04_dora_api_integration.sql
snow sql -f projects/$P/sql/05_dora_grader.sql
snow sql -f projects/$P/sql/06_dora_test.sql
snow sql -f projects/$P/sql/07_ags_game_audience.sql
snow sql -f projects/$P/sql/08_ags_verify.sql
snow sql -f projects/$P/sql/09_explore_kickoff.sql
snow sql -f projects/$P/sql/10_load_game_logs.sql
snow sql -f projects/$P/sql/11_logs_view.sql
snow sql -f projects/$P/sql/12_time_zones.sql
snow sql -f projects/$P/sql/13_load_updated_feed.sql
snow sql -f projects/$P/sql/14_filter_new_rows.sql
snow sql -f projects/$P/sql/15_missing_key_vs_json_null.sql
snow sql -f projects/$P/sql/16_copy_with_file_metadata.sql
snow sql -f projects/$P/sql/17_update_logs_view.sql
snow sql -f projects/$P/sql/18_find_test_records.sql
snow sql -f projects/$P/sql/19_parse_ip.sql
snow sql -f projects/$P/sql/20_enhanced_schema.sql
snow sql -f projects/$P/sql/21_ipinfo_listing.sql   # after the terms are accepted in Snowsight
```

## Next
Join `LOGS` to `IPINFO_GEOLOC.DEMO.LOCATION` on the IP range to add a time zone to each row.
