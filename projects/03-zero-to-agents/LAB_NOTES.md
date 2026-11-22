# 03 - Lab notes

## The scenario
You are on the marketing team of a fictional retail company that sells sports and outdoor gear. The company has plenty of data, from campaign performance for paid ads to customer feedback.

The problems the team faces:
- Campaign performance data is siloed from customer feedback
- Customer feedback is unstructured and unanalyzed
- Analysts can't self-serve insights from this data

What the lab builds to solve them:
- Cortex AI turns raw transcripts into structured sentiment and category labels
- Dynamic Tables keep that data current as new feedback arrives
- A Semantic View bridges campaign metrics and customer feedback into one model
- Snowflake Intelligence lets analysts ask natural language questions

## What we're learning
1. How to use Cortex AI functions for sentiment analysis and text classification
2. How to create Dynamic Tables for automated AI enrichment pipelines
3. How to build a Semantic View that maps technical columns to business terms
4. How to create and configure an AI Agent with Analyst and Search tools
5. How to implement Role-Based Access Control (RBAC) with Dynamic Data Masking

These notes hold more than the code. For each step they record the commands we ran, the results, the errors we hit, the fixes, and the reasoning behind them, so the Snowflake concepts are written down next to the SQL. For the short version, read `README.md`. The SQL for each section is in `sql/`.

Placeholders stand in for real values: `<user_name>` (from `SELECT CURRENT_USER();`), `<orgname>-<accountname>` and `<password>`.

## 1. Connecting with a password
The CLI connects with a login name and password. The settings live in a gitignored `.env`.

```bash
# projects/03-zero-to-agents/.env (gitignored, chmod 600)
SNOWFLAKE_ACCOUNT=<orgname>-<accountname>
SNOWFLAKE_USER=<login_name>
SNOWFLAKE_ROLE=ACCOUNTADMIN
SNOWFLAKE_PASSWORD=<password>
```
```toml
# connections.toml.template: no password line
[${PROJECT_CONN}]
account = "${SNOWFLAKE_ACCOUNT}"
user = "${SNOWFLAKE_USER}"
authenticator = "snowflake"
role = "${SNOWFLAKE_ROLE}"
session_parameters = { QUERY_TAG = '{"project":"${PROJECT_NAME}", ... }' }
```
```bash
source scripts/use-project.sh 03-zero-to-agents
snow connection test        # Status OK, Role ACCOUNTADMIN
```

**Where the password lives.** `use-project.sh` loads `.env` with `set -a`, so `SNOWFLAKE_PASSWORD` becomes an environment variable, and the `snow` CLI reads it from there. The rendered `connections.toml` contains no password. Removing the variable proves it:
```bash
env -u SNOWFLAKE_PASSWORD snow connection test
-- Could not connect to Snowflake. Reason: 251006: Password is empty
```
**Reasoning:**
- **Why not put the password in `connections.toml`.** That file is gitignored, but it is rendered by a script and sits inside the project folder. Keeping the secret in `.env` alone leaves one file to protect, and `chmod 600` on both files covers the rest.
- **`authenticator = "snowflake"`** is the plain user-and-password login.
- **Login name.** `SNOWFLAKE_USER` is the *login name* from Snowsight (Account > View account details). Here it matches the user name (`<user_name>`, uppercase).
- **Account identifier.** The `<orgname>-<accountname>` form is used, not the account locator.

**Noticed:**
- **The session already had a warehouse.** `snow connection test` reported `Warehouse = COMPUTE_WH` before any of our objects existed. Where it came from was not checked. The connection template sets no warehouse, so it was the user's default at that point.
- **Query tag.** `SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;` returned the project tag at level `SESSION`, so every statement from the CLI is attributable.
- **No MFA.** The login worked with the password alone. MFA is not enabled on the user.

**Error: a key from another project leaks into this one.** Sourcing this project in a shell that had already sourced another project failed the test:
```bash
snow connection test
-- Private Key authentication requires authenticator set to SNOWFLAKE_JWT
```
**Why:** `use-project.sh` exports every variable in the new `.env`, but it didn't clear variables the previous project had set. `SNOWFLAKE_PRIVATE_KEY_FILE` from that project stayed exported, so the CLI saw a private key and a password together. It treats a private key as key-pair auth, which needs `authenticator = SNOWFLAKE_JWT`, and this connection uses `snowflake`.

**Fix:** `use-project.sh` now unsets every `SNOWFLAKE_*` variable before loading the project:
```bash
for _v in $(compgen -e | grep '^SNOWFLAKE_'); do unset "$_v"; done
```
Check: `env | grep ^SNOWFLAKE_` lists only this project's values. After re-sourcing, `snow connection test` reports `Status OK`, `Role ACCOUNTADMIN`, `Warehouse DASH_WH_SI`.

**Lessons:**
- Leftover environment variables stay in the shell and add to the new settings. A stray one can change the authentication method, and the only sign is an error at login.
- Switching projects in the same shell should always go through `use-project.sh`, and never through hand-exported `SNOWFLAKE_*` variables.
## 2. The project role and user defaults
The lab does its work as its own role, `SNOWFLAKE_INTELLIGENCE_ADMIN`, and not as `ACCOUNTADMIN`. This step runs once as `ACCOUNTADMIN`, because only that role can grant account-level privileges. It creates the role, gives it the three account privileges it needs, hands it to your user, and makes it the user's default.

```sql
USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE WAREHOUSE   ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE DATABASE    ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

SET current_user = (SELECT CURRENT_USER());
GRANT ROLE SNOWFLAKE_INTELLIGENCE_ADMIN TO USER IDENTIFIER($current_user);
ALTER USER SET DEFAULT_ROLE = SNOWFLAKE_INTELLIGENCE_ADMIN;
ALTER USER SET DEFAULT_WAREHOUSE = DASH_WH_SI;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/02_role_and_grants.sql
```

**Reasoning:**
- **Three account privileges.** A role starts with no rights. `CREATE WAREHOUSE` and `CREATE DATABASE` let it build the compute and storage in the next steps. `CREATE INTEGRATION` covers integrations, which are account-level objects that connect Snowflake to outside services, so they can't be created by a role that only owns a database.
- **Least privilege.** The role gets exactly those three grants. Everything it creates afterwards belongs to it, so day-to-day work doesn't need `ACCOUNTADMIN`.
- **Session variables.** `SET current_user = (SELECT CURRENT_USER())` stores your login name in a session variable, and `$current_user` reads it back. `IDENTIFIER(...)` turns that string into an object name, which `GRANT ... TO USER` needs. Here the variable holds `<user_name>`, and the grant succeeds.
- **User defaults.** `DEFAULT_ROLE` is the role Snowflake uses for a new session unless the connection names one. `DEFAULT_WAREHOUSE` is the warehouse it starts. Both apply to the next login, not to the session that set them.
- **A default warehouse that doesn't exist yet.** `DASH_WH_SI` is created in the next step, and `ALTER USER SET DEFAULT_WAREHOUSE` still succeeded. Snowflake doesn't check that the warehouse exists when the default is set.

**Why `IF NOT EXISTS` and not `CREATE OR REPLACE ROLE`.** `CREATE OR REPLACE` drops the old role and creates a new one with the same name. Dropping a role removes its grants, and the objects it owned then have no owner, so a re-run on a populated account would break everything the role built. `CREATE ROLE IF NOT EXISTS` leaves an existing role alone, and the `GRANT` statements can be repeated safely. On a brand-new account the two behave the same.

**Checked:** `ALTER USER SET ...` without a user name. This form changes the current user. It seemed likely to fail with a syntax error, so I ran it, and it succeeded:
```sql
ALTER USER SET DEFAULT_ROLE = SNOWFLAKE_INTELLIGENCE_ADMIN;
-- Statement executed successfully.
```
The file keeps a commented-out alternative for accounts where it fails. It names the user explicitly and wraps the name in double quotes, which matters when the login name is lower or mixed case:
```sql
SET my_user = '"' || CURRENT_USER() || '"';
GRANT ROLE SNOWFLAKE_INTELLIGENCE_ADMIN TO USER IDENTIFIER($my_user);
ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'SNOWFLAKE_INTELLIGENCE_ADMIN';
```

**Verify:**
```sql
SHOW GRANTS TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;   -- CREATE WAREHOUSE / DATABASE / INTEGRATION on the account
SHOW GRANTS OF ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;   -- granted to USER <user_name>
DESC USER <user_name>;                              -- DEFAULT_ROLE and DEFAULT_WAREHOUSE
```
```text
DEFAULT_WAREHOUSE | DASH_WH_SI
DEFAULT_ROLE      | SNOWFLAKE_INTELLIGENCE_ADMIN
```

**Noticed:**
- **The defaults show up in the connection test.** Before this step the test reported `Warehouse = COMPUTE_WH`. Afterwards it reports `Warehouse = DASH_WH_SI`. The connection settings name no warehouse, so Snowflake falls back to the user's default.
- **The role still comes from the connection.** The test still says `Role = ACCOUNTADMIN`, because `SNOWFLAKE_ROLE` in `.env` names it, and a role set by the connection wins over the user default. Changing `DEFAULT_ROLE` doesn't change the roles in a session that is already open either.
- **`SNOWFLAKE_INTELLIGENCE_ADMIN` isn't granted to `SYSADMIN`.** The lab doesn't do it, so the role and its objects are managed only by the role itself and by `ACCOUNTADMIN`.

## 3. Warehouse, databases and a resource monitor
This step creates the compute and the two databases the rest of the lab uses. It runs as `SNOWFLAKE_INTELLIGENCE_ADMIN`, so that role owns them. Only the resource monitor needs `ACCOUNTADMIN`.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

CREATE DATABASE  IF NOT EXISTS DASH_DB_SI;
CREATE SCHEMA    IF NOT EXISTS DASH_DB_SI.RETAIL;
CREATE WAREHOUSE IF NOT EXISTS DASH_WH_SI
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;
GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS DASH_WH_SI_RM
  WITH CREDIT_QUOTA = 10 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE DASH_WH_SI SET RESOURCE_MONITOR = DASH_WH_SI_RM;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/03_warehouse_and_databases.sql
```

**What the lab specifies, and what is added.** The lab gives the names (`DASH_DB_SI`, `RETAIL`, `DASH_WH_SI`, `SNOWFLAKE_INTELLIGENCE`, `AGENTS`), the `LARGE` size and the `CREATE AGENT` grant. It says nothing about auto-suspend or cost limits, so the file adds `AUTO_SUSPEND = 60` and the resource monitor.

**Start small, resize when needed.** The file creates the warehouse as `XSMALL`. Statements such as `CREATE`, `GRANT` and `ALTER` run in the cloud services layer and use no warehouse compute, and the lab's tables hold at most a few thousand rows. The warehouse is resized to `LARGE` for the data loading steps, as the lab says, and later steps check whether a smaller size is enough. Resizing is one statement and applies to queries that start afterwards:
```sql
ALTER WAREHOUSE DASH_WH_SI SET WAREHOUSE_SIZE = LARGE;   -- or XSMALL / MEDIUM
```

**Reasoning:**
- **Ownership follows `USE ROLE`.** The role that runs a `CREATE` owns the new object. Switching to `SNOWFLAKE_INTELLIGENCE_ADMIN` first means the database, schemas and warehouse belong to it, as the check below shows.
- **`CREATE DATABASE` adds a `PUBLIC` schema.** `DASH_DB_SI` ends up with `PUBLIC` and `RETAIL`, plus the read-only `INFORMATION_SCHEMA` that every database has.
- **Why `SNOWFLAKE_INTELLIGENCE.AGENTS`.** Snowflake Intelligence lists the agents that live in this schema. `CREATE AGENT` on the schema lets the project role create them there.
- **Warehouse options.** `AUTO_RESUME = TRUE` starts the warehouse when a query arrives. `INITIALLY_SUSPENDED = TRUE` creates it stopped, so it uses no credits until the first query. `AUTO_SUSPEND = 60` stops it after 60 idle seconds.
- **Why the monitor matters.** Credits per hour double with each size: `XSMALL` 1, `SMALL` 2, `MEDIUM` 4, `LARGE` 8. The 10-credit monthly quota is about 10 hours at `XSMALL` and about 75 minutes at `LARGE`. The triggers act at 75% (notify), 100% (suspend after running queries finish) and 110% (suspend and cancel running queries).
- **Why `ACCOUNTADMIN` again.** Resource monitors are account-level objects, and only `ACCOUNTADMIN` can create one. `ALTER WAREHOUSE ... SET RESOURCE_MONITOR` attaches it to the warehouse.
- **`IF NOT EXISTS` and properties.** It skips an object that exists, as in section 2, but it doesn't change an existing object's settings. That is why the live warehouse was resized with `ALTER WAREHOUSE`: re-running this file wouldn't have changed it.

**Verify:**
```sql
SHOW WAREHOUSES LIKE 'DASH_WH_SI';
SHOW RESOURCE MONITORS LIKE 'DASH_WH_SI_RM';
SHOW SCHEMAS IN DATABASE DASH_DB_SI;
SHOW GRANTS ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
```
```text
name        | size  | auto_suspend | auto_resume | owner                        | resource_monitor
DASH_WH_SI  | X-Small | 60           | true        | SNOWFLAKE_INTELLIGENCE_ADMIN | DASH_WH_SI_RM

name           | credit_quota | frequency | notify_at | suspend_at | suspend_immediately_at
DASH_WH_SI_RM  | 10.00        | MONTHLY   | 75%       | 100%       | 110%

RETAIL, PUBLIC       owner SNOWFLAKE_INTELLIGENCE_ADMIN
CREATE AGENT on SNOWFLAKE_INTELLIGENCE.AGENTS granted to SNOWFLAKE_INTELLIGENCE_ADMIN
```

**Noticed:** the warehouse is the one the user default from section 2 points to. Nothing resumes it until a query runs, so it stays suspended until then.

## 4. Loading five tables from public S3 stages
The lab's retail data sits as CSV files in a public S3 bucket. This step defines one file format, then for each of five tables creates a stage that points at the bucket, creates the table, and runs `COPY INTO`. The files are `04` to `09` under `sql/`.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE FILE FORMAT SWT_CSVFORMAT
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TYPE = 'CSV';

-- repeated per table, shown for sales
CREATE OR REPLACE STAGE SWT_SALES_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/sales/';

CREATE OR REPLACE TABLE SALES (
  DATE DATE, REGION VARCHAR(16777216), PRODUCT_ID NUMBER(38,0),
  UNITS_SOLD NUMBER(38,0), SALES_AMOUNT NUMBER(38,2)
);

COPY INTO SALES FROM @SWT_SALES_DATA_STAGE;
```
```bash
for f in 04_file_format 05_marketing_campaign_metrics 06_products 07_sales 08_social_media 09_support_cases; do
  snow sql -f projects/03-zero-to-agents/sql/$f.sql
done
```
The other four tables follow the same pattern with these stage paths and columns:

| Table | Bucket folder | Columns |
|---|---|---|
| `MARKETING_CAMPAIGN_METRICS` | `marketing/` | `DATE`, `CATEGORY`, `CAMPAIGN_NAME`, `IMPRESSIONS`, `CLICKS` |
| `PRODUCTS` | `product/` | `PRODUCT_ID`, `PRODUCT_NAME`, `CATEGORY` |
| `SOCIAL_MEDIA` | `social_media/` | `DATE`, `CATEGORY`, `PLATFORM`, `INFLUENCER`, `MENTIONS` |
| `SUPPORT_CASES` | `support/` | `ID`, `TITLE`, `PRODUCT`, `TRANSCRIPT`, `DATE` |

**Reasoning:**
- **External stage.** A stage with a `URL` is a named pointer to files in cloud storage. The bucket is public, so the stage needs no credentials or storage integration. `LIST @SWT_MARKETING_DATA_STAGE` shows one file, `marketing_campaign_metrics.csv`, 1,368 bytes.
- **File format.** `SKIP_HEADER = 1` drops each file's header row. `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` lets a field contain commas when it is wrapped in quotes, which the support transcripts rely on. Attaching the format to the stage means `COPY INTO` doesn't need to name it.
- **`COPY INTO` maps by position.** With no column list, the first CSV field goes to the first table column, and so on. That's why each table's column order matches its file.
- **`COPY INTO` with no file list** loads every file under the stage path. Snowflake records each loaded file against the table and skips it on later runs, so repeating the command on the same table doesn't load it twice.
- **`CREATE OR REPLACE`.** The lab's files use it, and so do ours. It is safe for a first load. On a table that has since received other data it throws that data away, so don't re-run these files on a table you have added to.

**Verify:**
```sql
SELECT table_name, file_name, row_count, status
FROM TABLE(information_schema.copy_history(table_name => 'SALES', start_time => DATEADD(day, -3, CURRENT_TIMESTAMP())));
```
```text
MARKETING_CAMPAIGN_METRICS | marketing_campaign_metrics.csv |    23 | Loaded
PRODUCTS                   | products.csv                   |    40 | Loaded
SALES                      | sales.csv                      | 14560 | Loaded
SOCIAL_MEDIA               | social_media_mentions.csv      |   273 | Loaded
SUPPORT_CASES              | support_cases.csv              |    30 | Loaded
```

**Warehouse size for loading.** The lab runs these loads on a `LARGE` warehouse, and the five loads in the log above did run at `LARGE`. The query history gives the timings:

| Load | Warehouse size | Elapsed |
|---|---|---|
| `MARKETING_CAMPAIGN_METRICS` | Large | 2.4 s |
| `PRODUCTS` | Large | 1.9 s |
| `SALES` (14,560 rows) | Large | 2.7 s |
| `SOCIAL_MEDIA` | Large | 1.9 s |
| `SUPPORT_CASES` | Large | 2.0 s |

To compare, the `SALES` load was repeated into a temporary table on the `XSMALL` warehouse:
```sql
CREATE TEMPORARY TABLE SALES_XS_TEST LIKE SALES;
COPY INTO SALES_XS_TEST FROM @SWT_SALES_DATA_STAGE;   -- 14,560 rows, X-Small, 4.0 s
```
`XSMALL` took 4.0 s against 2.7 s at `LARGE`, about a second more. Each file is read by one thread, and every table here comes from a single small file, so extra nodes have nothing to share out. At `XSMALL` the load costs about 0.001 credits, against about 0.006 at `LARGE`. The warehouse stays at `XSMALL` for the rest of the lab until a step shows it is too slow.

## 5. Git integration and the semantic model file
The lab keeps its semantic model definition, a YAML file, in a public GitHub repository. This step connects Snowflake to that repository and copies the file into a stage in the `RETAIL` schema. The file is `sql/10_git_and_semantic_model.sql`.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SEMANTIC_MODELS
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = TRUE);

CREATE OR REPLACE API INTEGRATION SNOWFLAKE_LABS_SI_GIT_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs')
  ENABLED = TRUE;

CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_LABS_SFGUIDE_SI_REPO
  API_INTEGRATION = SNOWFLAKE_LABS_SI_GIT_API_INTEGRATION
  ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-getting-started-with-snowflake-intelligence';

COPY FILES INTO @SEMANTIC_MODELS
  FROM @SNOWFLAKE_LABS_SFGUIDE_SI_REPO/branches/main/
  FILES = ('marketing_campaigns.yaml');
```
```bash
snow sql -f projects/03-zero-to-agents/sql/10_git_and_semantic_model.sql
```

**Reasoning:**
- **The internal stage.** `SEMANTIC_MODELS` stores files inside Snowflake, unlike the S3 stages in section 4. `ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')` keeps them encrypted with Snowflake-managed keys, in a form that Snowflake services can read. `DIRECTORY = (ENABLE = TRUE)` adds a directory table, so the stage's files can be listed and queried like rows.
- **The API integration.** An integration is an account-level object, which is why section 2 granted `CREATE INTEGRATION`. `API_PROVIDER = GIT_HTTPS_API` says it talks to a Git server over HTTPS. `API_ALLOWED_PREFIXES` is an allow list: Snowflake only contacts URLs that start with `https://github.com/Snowflake-Labs`. The name must be unique in the whole account.
- **No secret needed.** The repository is public, so `ALLOWED_AUTHENTICATION_SECRETS` stays empty and the repository object has no credentials. A private repository would need a secret.
- **The Git repository object.** It is a read-only clone of the remote that Snowflake keeps inside the schema. It is addressed as `@<repo>/branches/<branch>/<path>`. Creating it fetched the repo (`CREATE ... GIT REPOSITORY` took 4.8 s), and `main` points at one commit.
- **`COPY FILES`.** It copies named files from one stage to another without parsing them. `FILES = (...)` limits it to the YAML, so the repo's CSV files and `setup.sql` aren't copied. The repo's own `data/` files are not used, since the tables came from S3 in section 4.
- **No warehouse used.** In the query history, the integration, repository and `COPY FILES` statements all show a warehouse size of `None`, so they ran in the cloud services layer.
- **`CREATE OR REPLACE`.** The lab's form. Re-running it replaces the stage and the repository clone, and anything added to `SEMANTIC_MODELS` by hand is lost. Run the file as a whole, since the repository object depends on the integration.

**What the YAML holds.** The file is 350 lines and defines a semantic model called `Sales_And_Marketing_Data`:
- four tables, `MARKETING_CAMPAIGN_METRICS`, `PRODUCTS`, `SALES` and `SOCIAL_MEDIA`, each with a `base_table` of `DASH_DB_SI.RETAIL.<table>`. Each column has a description, synonyms and sample values.
- two relationships: `SALES` to `PRODUCTS` on `PRODUCT_ID`, and `SOCIAL_MEDIA` to `MARKETING_CAMPAIGN_METRICS` on `CATEGORY`, both many-to-one.
- one verified query, the monthly sales trend by product category.

Because `base_table` names `DASH_DB_SI.RETAIL`, the file only works with the database and schema names from section 3.

**Verify:**
```sql
SHOW GIT BRANCHES IN SNOWFLAKE_LABS_SFGUIDE_SI_REPO;
LS @SNOWFLAKE_LABS_SFGUIDE_SI_REPO/branches/main/;
LIST @SEMANTIC_MODELS;
```
```text
main | /branches/main | d7976cb17abc045908f20ce96d4f65df86a55de2
...branches/main/marketing_campaigns.yaml                    10000 bytes
semantic_models/marketing_campaigns.yaml                     10000 bytes
```
The repo copy and the staged copy are both 10,000 bytes. The listing shows the file under `semantic_models/`, which is the stage's folder for it.

## 6. Email integration and the SEND_EMAIL procedure
The lab sends email from inside Snowflake. That takes a way to send mail and a small procedure that wraps it, and this step creates both. The file is `sql/11_email_integration.sql`.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE NOTIFICATION INTEGRATION EMAIL_INTEGRATION
  TYPE = EMAIL
  ENABLED = TRUE
  DEFAULT_SUBJECT = 'snowflake intelligence';

CREATE OR REPLACE PROCEDURE SEND_EMAIL(RECIPIENT_EMAIL VARCHAR, SUBJECT VARCHAR, BODY VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'send_email'
AS
$$
def send_email(session, recipient_email, subject, body):
    try:
        escaped_body = body.replace("'", "''")
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL('email_integration', '{recipient_email}',
                                   '{subject}', '{escaped_body}', 'text/html')
        """).collect()
        return "Email sent successfully"
    except Exception as e:
        return f"Error sending email: {str(e)}"
$$;
```
(The file's `COMMENT` clauses are left out above.)
```bash
snow sql -f projects/03-zero-to-agents/sql/11_email_integration.sql
```

**Reasoning:**
- **Notification integration.** Like the Git integration in section 5, it is an account-level object, so the project role needed `CREATE INTEGRATION`. `TYPE = EMAIL` gives Snowflake permission to send mail through its own email service. `DEFAULT_SUBJECT` is used when a call doesn't give one.
- **Who can receive mail.** `ALLOWED_RECIPIENTS` is empty, so mail can go to any address that belongs to a user in the account and has been verified. Snowflake refuses other addresses. The email address on your own user must be verified before a test to yourself works. `SHOW USERS` shows an address is set on this user, but not whether it is verified. The test call below is the check.
- **Why a procedure.** `SYSTEM$SEND_EMAIL` takes five arguments, including the integration name and the content type. The procedure fixes those and exposes three: recipient, subject and body.
- **Python and Snowpark.** The handler gets a Snowpark `session` and runs `CALL SYSTEM$SEND_EMAIL(...)` through it. `PACKAGES = ('snowflake-snowpark-python')` pulls the library from Snowflake's package repository, and `DESC PROCEDURE` lists it under `artifact_repository_packages` with runtime `3.12`.
- **Runs as its owner.** `DESC PROCEDURE` shows `execute as = OWNER`, the default. Whoever calls the procedure sends mail with the owner's right to use the integration, so they need `USAGE` on the procedure and nothing on the integration.
- **Errors come back as text.** The `try/except` catches any failure and returns `Error sending email: ...` as an ordinary result, so a failed send doesn't raise an error in the caller. A caller has to read the returned string to see whether it worked.
- **Quotes.** Only `body` has its single quotes doubled. `recipient_email` and `subject` go into the statement as they are, so a subject with a single quote makes the inner statement invalid and the procedure returns the error text. This comes from reading the code and has not been run.
- **Timing.** In the query history the integration took 63 ms and used no warehouse. Creating the procedure took 8.8 s, mostly resolving the Python package.

**Verify:**
```sql
SHOW NOTIFICATION INTEGRATIONS;
DESC NOTIFICATION INTEGRATION EMAIL_INTEGRATION;
SHOW PROCEDURES LIKE 'SEND_EMAIL';
DESC PROCEDURE SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR);
```
```text
EMAIL_INTEGRATION | EMAIL | NOTIFICATION | enabled true | OUTBOUND
ALLOWED_RECIPIENTS [] | DEFAULT_SUBJECT snowflake intelligence
SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR) RETURN VARCHAR | PYTHON 3.12 | execute as OWNER
```

**Test.** The procedure was called once, with the address on the user as the recipient. `DESC USER` supplies the address, so it doesn't appear in the command:
```sql
DESC USER <user_name>;
SET em = (SELECT "value" FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) WHERE "property" = 'EMAIL');
CALL SEND_EMAIL($em, 'Snowflake lab: SEND_EMAIL test',
                '<p>Test message from the SEND_EMAIL procedure in DASH_DB_SI.RETAIL.</p>');
```
```text
Email sent successfully
```
The procedure reports success when Snowflake accepts the send. Snowflake rejects addresses that aren't verified, so the result points to a verified address. The message arriving in the inbox is the last check.

## 7. Cortex cross-region setting and a setup check
Two small steps. The first lets Cortex run models in other regions. The second is the lab's own check that the tables exist and hold data. The files are `sql/12_cortex_cross_region.sql` and `sql/13_verify.sql`.

```sql
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';
```
```bash
snow sql -f projects/03-zero-to-agents/sql/12_cortex_cross_region.sql
snow sql -f projects/03-zero-to-agents/sql/13_verify.sql
```

**Reasoning:**
- **Why it is needed.** Cortex models run in particular regions, and not every model is in every region. With cross-region inference enabled, a request can run in another region from the list. The default is `DISABLED`, in which case a model that isn't available in the account's own region can't be used.
- **Account level, `ACCOUNTADMIN` only.** It is an account parameter, so it affects every user and role, which is why this file runs as `ACCOUNTADMIN` and the others don't.
- **What the value means here.** `AWS_US` allows requests to run in AWS regions in the US. This account is in `AWS_EU_CENTRAL_1`, so prompts and the text they contain can leave the EU. That is fine for the lab's made-up data. For real data it is a decision to make deliberately: `AWS_EU` is a possible value that keeps requests in Europe, though fewer models may be available there. The lab says `AWS_US`, so that is what the file sets.
- **It can be undone.** `ALTER ACCOUNT UNSET CORTEX_ENABLED_CROSS_REGION;` returns it to `DISABLED`.

**The setup check.** `13_verify.sql` is the lab's anonymous block. It counts the five tables in `RETAIL`, checks that `SALES` has rows, and returns a one-line verdict. We added a row count per table below it.

**Error: the block fails when run through the CLI.** Run as the lab writes it, the `DECLARE ... BEGIN ... END` block fails:
```bash
snow sql -f check.sql
-- 001003 (42000): SQL compilation error: syntax error line 2 at position 34 unexpected '<EOF>'.
```
**Why:** the `snow` CLI splits a file into statements at each semicolon. The block holds many semicolons, so the first piece, `DECLARE table_count INTEGER DEFAULT 0;`, is sent alone and the parser reaches the end of input mid-block. The lab's form is written for Snowsight, which handles the block as a whole.

**Fix:** wrap the block in `EXECUTE IMMEDIATE $$ ... $$;`. The dollar quotes make the whole block one string, and the only semicolon outside it is the final one:
```sql
EXECUTE IMMEDIATE $$
DECLARE
    table_count INTEGER DEFAULT 0;
BEGIN
    -- ... the lab's block, unchanged ...
END;
$$;
```

**What the block does.** `DECLARE` names two integer variables and sets both to zero. The first `SELECT COUNT(*) INTO :table_count` queries `information_schema.tables` and writes the count of matching table names into `table_count`. It counts how many of the five expected tables exist in the `RETAIL` schema. If that number is less than 5, the block returns early with a message saying how many were found. The second `SELECT COUNT(*) INTO :row_count` counts rows in `sales`. If the table is empty the block returns early, catching the case where the table was created but `COPY INTO` never ran. If both checks pass the block reaches the final `RETURN` and outputs the success string. `EXCEPTION WHEN OTHER` catches anything else, mainly a missing table or database, which throws an error rather than returning a zero count. Without it, the block itself would fail instead of returning a readable message. The `:table_count` syntax is Snowflake Scripting's way of referencing a declared variable inside a SQL statement; without the colon the parser treats the name as a column.

**Verify:**
```sql
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;
```
```text
CORTEX_ENABLED_CROSS_REGION | AWS_US | default DISABLED | level ACCOUNT
```
```text
Setup complete: 5 tables created and loaded with data.

MARKETING_CAMPAIGN_METRICS | 128
PRODUCTS                   | 40
SALES                      | 14560
SOCIAL_MEDIA               | 273
SUPPORT_CASES              | 30
```
The marketing table holds more than the 23 rows from section 4, because rows were added to it after that load. A run straight after section 4 shows 23.

## 8. AI functions on the support transcripts
The lab uses Cortex AI functions to read each support chat and label it. This step first fixes one product name, then runs a query that adds a sentiment and an issue category to every case. The file is `sql/14_ai_enrichment.sql`.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

UPDATE SUPPORT_CASES SET PRODUCT = 'Fitness Wear' WHERE PRODUCT = 'ThermoJacket Pro';

SELECT
    TITLE,
    AI_SENTIMENT(TRANSCRIPT):categories[0]:sentiment::STRING AS SENTIMENT,
    AI_CLASSIFY(TRANSCRIPT, ['Return', 'Quality', 'Shipping']):labels[0]::STRING AS ISSUE_CATEGORY
FROM SUPPORT_CASES;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/14_ai_enrichment.sql
```

**Reasoning:**
- **The `UPDATE`.** Fifteen cases name `ThermoJacket Pro`, a product that is not in `PRODUCTS`. `Fitness Wear` is a category that exists in both `PRODUCTS` (10 products) and `MARKETING_CAMPAIGN_METRICS`. Renaming makes the support cases use a value the other tables know. Only the `PRODUCT` column changes. The `TITLE` and `TRANSCRIPT` text still say `ThermoJacket Pro`.
- **Safe to repeat.** After the first run no row matches the `WHERE`, so a second run updates 0 rows.
- **`AI_SENTIMENT`.** It reads the text and returns JSON, for example `{"categories": [{"name": "overall", "sentiment": "positive"}]}`. The path `:categories[0]:sentiment::STRING` takes the first category, then its `sentiment` field, and casts it to text. The value is `positive`, `negative`, `neutral` or `mixed`.
- **`AI_CLASSIFY`.** It picks the best-fitting label from the list you give it and returns JSON such as `{"labels": ["Return"]}`. The path `:labels[0]::STRING` takes the first label. The labels are free text, so changing the list changes the categories.
- **Results come from a model.** The query reads the `TRANSCRIPT` of every row and calls a Cortex model, so the labels are a model's judgement and can differ slightly between runs. The count of rows is exact, but the labels aren't.
- **Cost.** AI functions are billed by the text they process, in credits, on top of the warehouse. The same query ran once on LARGE (the first run) and once on XSMALL, and `sql/14a_ai_cost.sql` reads what each cost:

  | | LARGE | XSMALL |
  |---|---|---|
  | Execution time | 2,125 ms | 1,086 ms |
  | Tokens processed | 35,313 | 35,313 |
  | AI credits (`AI_CLASSIFY` 0.0297 + `AI_SENTIMENT` 0.0272) | 0.0569 | 0.0569 |
  | Warehouse credits, execution time x hourly rate | 0.0047 | 0.0003 |

  The AI cost is the same on both sizes, because it depends on the tokens and not on the warehouse. It works out to about 0.0019 credits per case. The warehouse only runs the query, and its share is small: the AI part is about 12 times the LARGE figure and about 190 times the XSMALL one. Going from LARGE to XSMALL left the AI cost unchanged and cut the calculated warehouse cost from 0.0047 to 0.0003, so XSMALL is enough for this query. The calculated warehouse figure leaves out the 60-second minimum that Snowflake bills each time a suspended warehouse resumes (documented behaviour, not tested here). For a query this short, that minimum is larger than the query's own run time. Snowflake's own per-query figure (`QUERY_ATTRIBUTION_HISTORY`) was 0.0600 for the LARGE run, and it isn't available for the XSMALL run yet. Run the cost file again later to see it.
- **Cross-region.** If a model isn't available in the account's region, these functions depend on the setting from section 7.

**Verify:**
```sql
SELECT PRODUCT, COUNT(*) FROM SUPPORT_CASES GROUP BY PRODUCT ORDER BY PRODUCT;
```
```text
Cyclone Helmet    | 4
Fitness Wear      | 15
HydraBottle 2L    | 5
PowerYoga Mat     | 4
UltraRunner Shoes | 2
```
The `SELECT` with the two AI functions returned 30 rows on XSMALL. In that run 23 were `mixed` and 7 `positive`, and 19 were `Quality` and 11 `Return`. No case was labelled `Shipping` or `negative`. Your run may differ slightly.

## 9. Loading the marketing CSV with PUT and COPY
The lab adds more marketing rows from a file called `marketing_data.csv`. In Snowsight you do it with Load Data. Here the same step is two commands: `PUT` copies the file from your machine to an internal stage, and `COPY INTO` reads it into `MARKETING_CAMPAIGN_METRICS`. The file is not in the lab's Git repository, so save it in `projects/03-zero-to-agents/data/` first.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE STAGE IF NOT EXISTS MARKETING_UPLOAD_STAGE FILE_FORMAT = SWT_CSVFORMAT;
PUT 'file://<path>/marketing_data.csv' @MARKETING_UPLOAD_STAGE OVERWRITE = TRUE;

COPY INTO MARKETING_CAMPAIGN_METRICS FROM @MARKETING_UPLOAD_STAGE;
SELECT COUNT(*) AS ROWS_NOW FROM MARKETING_CAMPAIGN_METRICS;

DROP STAGE MARKETING_UPLOAD_STAGE;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/15_load_marketing_data.sql -D csv_path="$PWD/projects/03-zero-to-agents/data/marketing_data.csv"
```

**Reasoning:**
- **The stage.** It uses `SWT_CSVFORMAT` from section 4, so `COPY` skips the header line and reads the five columns in order. The file has 106 lines and loads 105 rows.
- **`PUT` compresses the file.** It uploads `marketing_data.csv` as `marketing_data.csv.gz`, and `COPY` reads that.
- **The stage is dropped at the end.** The staged file is only a way to get the rows in. After `COPY` it has no use, and the lab's setup check counts the stages in the schema and expects exactly seven. This stage would make eight. The rows already loaded stay in the table. Because the stage is gone, each run starts from a fresh stage.
- **Run it once.** `OVERWRITE = TRUE` makes `PUT` upload the file even when one with the same name is already on the stage. `COPY` treats that upload as a new file and loads its rows again. In a test, a second run took a table from 105 rows to 210. The step adds rows and does not replace them.
- **To redo the step.** Recreate the table first by running `05_marketing_campaign_metrics.sql`, which brings it back to the 23 rows from S3, then run `15_load_marketing_data.sql` again. A new table has no load history, so `COPY` loads the file once more. I tested the pieces on a temporary table but have not run this sequence on the real one.
- **The alternative.** Without `OVERWRITE`, `PUT` skips a file that is already staged and `COPY` loads nothing, so a second run is harmless. The cost is that an edited file with the same name never loads, because the old staged copy is kept. `OVERWRITE = TRUE` is used here so an edited file replaces the staged one.

**Verify:**
```sql
SELECT COUNT(*) FROM MARKETING_CAMPAIGN_METRICS;
```
```text
128
```
That is the 23 rows from section 4 plus the 105 rows from the CSV.

## 10. A restricted role, a secure view and a masking policy
The lab has a security demo near its end. This guide runs it before the dynamic table, for the reason given in part 2. A secure view gives the marketing data friendlier column names. A new role can read that view. A masking policy hides the click counts from every role except two, so the same query returns different numbers for different roles. This section has three files.

**Part 1: the view and the role** (`16_marketing_role_and_view.sql`)
```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE SECURE VIEW MARKETING_INTELLIGENCE_VIEW AS
SELECT
    campaign_name AS "Ad Campaign",
    category AS "Product Category",
    clicks AS "Engagement Clicks",
    0 AS "Customer Sentiment Score"
FROM marketing_campaign_metrics;

USE ROLE SECURITYADMIN;
CREATE OR REPLACE ROLE MARKETING_INTELLIGENCE_ROLE;
GRANT USAGE ON WAREHOUSE DASH_WH_SI TO ROLE MARKETING_INTELLIGENCE_ROLE;
GRANT USAGE ON DATABASE DASH_DB_SI TO ROLE MARKETING_INTELLIGENCE_ROLE;
GRANT USAGE ON SCHEMA DASH_DB_SI.RETAIL TO ROLE MARKETING_INTELLIGENCE_ROLE;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE MARKETING_INTELLIGENCE_ROLE;
GRANT SELECT ON VIEW DASH_DB_SI.RETAIL.MARKETING_INTELLIGENCE_VIEW TO ROLE MARKETING_INTELLIGENCE_ROLE;

SET my_user = '"' || CURRENT_USER() || '"';
GRANT ROLE MARKETING_INTELLIGENCE_ROLE TO USER IDENTIFIER($my_user);
```

**Why part 1 looks like this:**
- **Secure view.** A secure view hides its definition from the roles that read it. The view renames the columns for business users. `Customer Sentiment Score` is the constant `0`. The lab leaves it as a placeholder.
- **`SECURITYADMIN` for the role.** The lab runs these statements as `ACCOUNTADMIN`. `SECURITYADMIN` is enough, and it keeps `ACCOUNTADMIN` out of day-to-day work. I ran each statement with secondary roles off to see which roles can run it:

  | Statement | `SNOWFLAKE_INTELLIGENCE_ADMIN` | `USERADMIN` | `SECURITYADMIN` |
  |---|---|---|---|
  | `CREATE ROLE` | fails | works | works |
  | `GRANT USAGE` on the warehouse, database and schema, `GRANT SELECT` on the view | works | not tested | works |
  | `GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER` | fails | fails | works |
  | `GRANT ROLE ... TO USER` | fails | works | works |

  `SECURITYADMIN` is the only one of the three that runs all of them. If a statement fails with a privilege error, change `USE ROLE SECURITYADMIN;` to `USE ROLE ACCOUNTADMIN;`, which is what the lab uses.
- **`CORTEX_USER` may be redundant.** This account already grants `SNOWFLAKE.CORTEX_USER` to `PUBLIC`, so every role has it. The explicit grant stays because the lab has it. I revoked it from the marketing role, and the role still ran `AI_SENTIMENT` with secondary roles off, through `PUBLIC`. I granted it again afterwards.
- **What the role can do.** `USAGE` on the warehouse, database and schema, `SELECT` on the view, and the Cortex database role so it can call AI functions. It has no privilege on the tables themselves.
- **The grant to your own user.** It lets you switch to the role with `USE ROLE`. `SET my_user` wraps the name in double quotes so a mixed-case user name works.
- **Safe to rerun.** Both objects are replaced and every grant is repeated.
- **Next.** The role can read the view, but the click counts are still real for everyone. Part 2 hides them.

**Part 2: the masking policy** (`17_masking_policy.sql`)
```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE MASKING POLICY MASK_ENGAGEMENT_CLICKS AS (val NUMBER)
RETURNS NUMBER ->
  CASE
    WHEN CURRENT_ROLE() IN ('SNOWFLAKE_INTELLIGENCE_ADMIN', 'ACCOUNTADMIN') THEN val
    ELSE 0
  END;

ALTER TABLE MARKETING_CAMPAIGN_METRICS MODIFY COLUMN CLICKS SET MASKING POLICY MASK_ENGAGEMENT_CLICKS;
```

**Why part 2 looks like this:**
- **What the policy does.** It runs for every query on the column and looks at `CURRENT_ROLE()`. The two named roles see the real number and every other role gets `0`.
- **Where it is attached.** It is attached to the table column, not to the view. The view, and anything else that reads `CLICKS`, is masked too.
- **Relation to part 1.** The marketing role from part 1 is not named in the policy, so it falls into the `ELSE` branch. That is how a role that can read the view still sees `0`.
- **Why it runs before the dynamic table.** The policy needs only this table and its `CLICKS` column, so nothing has to be built first. In the lab it comes after the dynamic table, and attaching it then made Snowflake rebuild that table in full, which cost about 0.9 AI credits. Done first, the next section builds the table once. This is what we look at next, in section 11.
- **Rerunning.** I have not rerun this file on the existing account, so I can't say what a second run does.
- **Next.** Part 3 runs one query as two roles to show the effect.

**Part 3: the same query as two roles** (`18_verify_masking.sql`)
```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE SECURE VIEW MARKETING_INTELLIGENCE_VIEW COPY GRANTS AS
SELECT
    campaign_name AS "Ad Campaign",
    category AS "Product Category",
    clicks AS "Engagement Clicks",
    0 AS "Customer Sentiment Score"
FROM marketing_campaign_metrics;

SELECT CURRENT_ROLE() AS ROLE_NAME, "Ad Campaign", "Engagement Clicks" FROM MARKETING_INTELLIGENCE_VIEW;

USE SECONDARY ROLES NONE;
USE ROLE MARKETING_INTELLIGENCE_ROLE;
USE SCHEMA DASH_DB_SI.RETAIL;
SELECT CURRENT_ROLE() AS ROLE_NAME, "Ad Campaign", "Engagement Clicks" FROM MARKETING_INTELLIGENCE_VIEW;
```
**Why part 3 looks like this:**
- **The view is created again.** The lab's file recreates the view with a plain `CREATE OR REPLACE`, which drops the `SELECT` grant from part 1, so the marketing role could no longer read it. `COPY GRANTS` keeps the grants.
- **`USE SECONDARY ROLES NONE`.** By default a session gets the privileges of all roles granted to the user, not only the one from `USE ROLE`. Without this line the marketing role in the demo reads the view and the tables through your other roles. Only masking looks at the primary role alone, so the demo looks right even when the grants are wrong.
- **The two queries.** They are identical. Only the role differs, so any difference in the result comes from the masking policy.

```bash
for f in 16_marketing_role_and_view 17_masking_policy 18_verify_masking; do snow sql -f projects/03-zero-to-agents/sql/$f.sql; done
```

**Verify:**
```sql
SELECT CURRENT_ROLE(), COUNT(*), SUM("Engagement Clicks") FROM MARKETING_INTELLIGENCE_VIEW;
```
```text
SNOWFLAKE_INTELLIGENCE_ADMIN | 128 | 67156
MARKETING_INTELLIGENCE_ROLE  | 128 | 0
```
The same 128 rows come back for both roles. The admin sees clicks between 178 and 889 and the marketing role sees `0` in every row. `SHOW GRANTS ON VIEW MARKETING_INTELLIGENCE_VIEW` lists `OWNERSHIP` for the admin role and `SELECT` for `MARKETING_INTELLIGENCE_ROLE`.

## 11. A dynamic table that joins campaigns to support cases
A dynamic table is a table defined by a query. Snowflake keeps its result up to date within a lag you choose. This one joins each marketing row to the support cases for the same product category and adds a sentiment score for the case.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE DYNAMIC TABLE ENRICHED_MARKETING_INTELLIGENCE (
  campaign_name,
  clicks WITH MASKING POLICY MASK_ENGAGEMENT_CLICKS,
  product_name,
  avg_sentiment
)
TARGET_LAG = '1 hours'
WAREHOUSE = DASH_WH_SI
AS
SELECT m.campaign_name, m.clicks, s.product AS product_name,
       CASE AI_SENTIMENT(s.transcript):categories[0]:sentiment::STRING
            WHEN 'positive' THEN 1
            WHEN 'negative' THEN -1
            ELSE 0
       END AS avg_sentiment
FROM marketing_campaign_metrics m
JOIN support_cases s ON m.category = s.product;

SHOW DYNAMIC TABLES IN SCHEMA DASH_DB_SI.RETAIL;
SELECT COUNT(*) AS ROWS_LOADED FROM ENRICHED_MARKETING_INTELLIGENCE;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/19_dynamic_table.sql
```

**Reasoning:**
- **The column list.** It names the four output columns so that `clicks` can carry the masking policy from section 10. The lab's version has no column list and no policy. See the masking bullet below.
- **The join key.** The marketing `category` and the support case `product` hold the same product names. The rename in section 8 makes `Fitness Wear` appear on both sides.
- **The row count is a product, not a sum.** Each marketing row pairs with every support case of its category. `Fitness Wear` has 44 marketing rows and 15 cases, which gives 660 rows. The five categories give 84 + 660 + 105 + 84 + 42 = 975 rows.
- **`avg_sentiment` is a score for one case, not an average.** It is 1 for positive, -1 for negative and 0 for anything else. With the current data it is only 0 or 1.
- **`TARGET_LAG = '1 hours'`.** The table may be up to one hour behind its sources. Snowflake checks about every 51 minutes here. When no source has changed, the check records `NO_DATA` and recomputes nothing. The AI usage view has no rows for these checks.
- **Masking on `clicks`.** A dynamic table does not inherit the mask from its source column. The refresh runs as the table's owner, who sees real clicks, so it stores the real values. I built a throwaway dynamic table over the masked column, gave the marketing role `SELECT` on it, and that role read the real sum (67,156) instead of 0. Naming the policy on the column, as above, fixed that: the marketing role read 0 and the admin role 67,156. Running `ALTER DYNAMIC TABLE ... MODIFY COLUMN CLICKS SET MASKING POLICY ...` after the build also worked. The file uses the first form because it needs no second step. I tested both forms on simple dynamic tables without the AI function, then ran `19_dynamic_table.sql` itself with the policy already on the source table. The build succeeded, and the marketing role read 0 in all 975 rows while the admin role read a sum of 539,787.
- **`WAREHOUSE = DASH_WH_SI`.** Refreshes use the same XSMALL warehouse as everything else.
- **Refresh mode.** The statement does not set one, so Snowflake picks. `SHOW DYNAMIC TABLES` reports `ADAPTIVE`.
- **Cost.** `AI_SENTIMENT` runs once per joined row, so 975 times instead of once per case (30). One full build used 561,637 tokens and 0.8986 AI credits, about 33 times the 0.0272 credits that `AI_SENTIMENT` used on the 30 cases in section 8. A full build happens at creation and again when Snowflake reinitializes the table. It does that when something it cannot apply incrementally changes, for example a masking policy attached to a source table. The reason is recorded in the `REINIT_REASON` column of `INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY`. That is why section 10 comes first. In this account the table was built before the policy, so it was built twice and has used about 1.8 AI credits. Running `19_dynamic_table.sql` again costs another 0.9.
- **A rewrite that scores each case first does not help.** I tried the query below, where `AI_SENTIMENT` runs in a `WITH` step over the 30 cases and the join only copies the score:

  ```sql
  WITH case_scores AS (
    SELECT product, CASE AI_SENTIMENT(transcript):categories[0]:sentiment::STRING
                         WHEN 'positive' THEN 1 WHEN 'negative' THEN -1 ELSE 0 END AS score
    FROM support_cases)
  SELECT m.campaign_name, m.clicks, c.product AS product_name, c.score AS avg_sentiment
  FROM marketing_campaign_metrics m JOIN case_scores c ON m.category = c.product;
  ```

  I built it and the lab query as throwaway dynamic tables with the same lag and warehouse, then dropped both. Each used 561,637 tokens and 0.8986 AI credits. Snowflake folds the `WITH` step into the join, so the AI function still runs once per joined row.
- **The score for one case changes between rows.** In both throwaway tables some products have sums that are not a multiple of the product's marketing row count. For example `Cyclone Helmet` has 21 marketing rows, and its sum was 39 in the rewrite and 36 in the lab query. The live table's sum is 29. So the same support case got different scores on different rows, and a rebuild can change them.


**Verify:**
```sql
SELECT PRODUCT_NAME, COUNT(*) FROM ENRICHED_MARKETING_INTELLIGENCE GROUP BY 1 ORDER BY 1;
```
```text
Cyclone Helmet    | 84
Fitness Wear      | 660
HydraBottle 2L    | 105
PowerYoga Mat     | 84
UltraRunner Shoes | 42
```
The total is 975. `SHOW DYNAMIC TABLES` lists the table with `target_lag` `1 hour`, `scheduling_state` `ACTIVE` and 975 rows. After a rebuild in this order, `POLICY_REFERENCES` for `MASK_ENGAGEMENT_CLICKS` lists `CLICKS` on both `MARKETING_CAMPAIGN_METRICS` and `ENRICHED_MARKETING_INTELLIGENCE`. The refresh history shows one `REINITIALIZE` with trigger `CREATION` for the new build.

## 12. A semantic view over the tables
A semantic view maps business terms to tables and columns, and tells the agent how the tables join. The lab builds it in Snowsight with Autopilot. This guide writes it as SQL in `20_semantic_view.sql`, so the rebuild needs no clicking. The view covers the five tables and the dynamic table.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE SEMANTIC VIEW SEMANTIC_VIEW
  TABLES (
    ENRICHED_MARKETING_INTELLIGENCE,
    MARKETING_CAMPAIGN_METRICS
      PRIMARY KEY (CATEGORY),
    PRODUCTS
      PRIMARY KEY (PRODUCT_ID),
    SALES,
    SOCIAL_MEDIA,
    SUPPORT_CASES
      PRIMARY KEY (ID)
  )
  RELATIONSHIPS (
    ENRICHED_TO_CAMPAIGN AS ENRICHED_MARKETING_INTELLIGENCE (PRODUCT_NAME) REFERENCES MARKETING_CAMPAIGN_METRICS (CATEGORY),
    SALES_TO_PRODUCTS AS SALES (PRODUCT_ID) REFERENCES PRODUCTS (PRODUCT_ID)
  )
  FACTS (
    ENRICHED_MARKETING_INTELLIGENCE.CLICKS AS CLICKS,
    ENRICHED_MARKETING_INTELLIGENCE.AVG_SENTIMENT AS AVG_SENTIMENT,
    MARKETING_CAMPAIGN_METRICS.CLICKS AS CLICKS,
    MARKETING_CAMPAIGN_METRICS.IMPRESSIONS AS IMPRESSIONS,
    SALES.UNITS_SOLD AS UNITS_SOLD,
    SALES.SALES_AMOUNT AS SALES_AMOUNT,
    SOCIAL_MEDIA.MENTIONS AS MENTIONS
  )
  DIMENSIONS (
    ENRICHED_MARKETING_INTELLIGENCE.CAMPAIGN_NAME AS CAMPAIGN_NAME,
    ENRICHED_MARKETING_INTELLIGENCE.PRODUCT_NAME AS PRODUCT_NAME,
    MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME AS CAMPAIGN_NAME,
    MARKETING_CAMPAIGN_METRICS.CATEGORY AS CATEGORY,
    MARKETING_CAMPAIGN_METRICS.DATE AS DATE,
    PRODUCTS.PRODUCT_ID AS PRODUCT_ID,
    PRODUCTS.PRODUCT_NAME AS PRODUCT_NAME,
    PRODUCTS.CATEGORY AS CATEGORY,
    SALES.PRODUCT_ID AS PRODUCT_ID,
    SALES.REGION AS REGION,
    SALES.DATE AS DATE,
    SOCIAL_MEDIA.CATEGORY AS CATEGORY,
    SOCIAL_MEDIA.PLATFORM AS PLATFORM,
    SOCIAL_MEDIA.INFLUENCER AS INFLUENCER,
    SOCIAL_MEDIA.DATE AS DATE,
    SUPPORT_CASES.ID AS ID,
    SUPPORT_CASES.TITLE AS TITLE,
    SUPPORT_CASES.PRODUCT AS PRODUCT,
    SUPPORT_CASES.TRANSCRIPT AS TRANSCRIPT,
    SUPPORT_CASES.DATE AS DATE
  )
  METRICS (
    MARKETING_CAMPAIGN_METRICS.TOTAL_CLICKS AS SUM(MARKETING_CAMPAIGN_METRICS.CLICKS),
    MARKETING_CAMPAIGN_METRICS.TOTAL_IMPRESSIONS AS SUM(MARKETING_CAMPAIGN_METRICS.IMPRESSIONS),
    ENRICHED_MARKETING_INTELLIGENCE.AVERAGE_SENTIMENT AS AVG(ENRICHED_MARKETING_INTELLIGENCE.AVG_SENTIMENT),
    SALES.TOTAL_SALES_AMOUNT AS SUM(SALES.SALES_AMOUNT),
    SALES.TOTAL_UNITS_SOLD AS SUM(SALES.UNITS_SOLD),
    SOCIAL_MEDIA.TOTAL_MENTIONS AS SUM(SOCIAL_MEDIA.MENTIONS)
  )
```
```bash
snow sql -f projects/03-zero-to-agents/sql/20_semantic_view.sql
```

**Reasoning:**
- **`TABLES`.** It lists the six objects the view can use. The lab selects "all tables" in the Autopilot dialog, which gives the same six: the five tables from section 4 and the dynamic table from section 11. `MARKETING_INTELLIGENCE_VIEW` from section 10 is left out, as in the lab.
- **`PRIMARY KEY`.** The lab sets `CATEGORY` as the key of `MARKETING_CAMPAIGN_METRICS`, because the relationship needs a key on the side it points to. `CATEGORY` is not unique there (21 to 44 rows per category). Snowflake does not check keys in a semantic view, so it accepted this. The other two keys, `PRODUCTS.PRODUCT_ID` and `SUPPORT_CASES.ID`, are my additions. The first one serves the second relationship, and the case `ID` is the natural key of its table.
- **`RELATIONSHIPS`.** The first one is the lab's: many rows of `ENRICHED_MARKETING_INTELLIGENCE` point at one `CATEGORY` through `PRODUCT_NAME`. The second, `SALES` to `PRODUCTS` on `PRODUCT_ID`, is not a Snowsight step in the lab, but the lab's tool description lists it as a key join. Without it a question about sales by product name could not join the two tables.
- **`FACTS`, `DIMENSIONS`, `METRICS`.** Numbers that can be summed are facts. Descriptive columns, such as names, regions and dates, are dimensions. A metric is an aggregate over facts, for example `SUM(CLICKS)`. Autopilot creates its own definitions in the lab. Here every column is listed once and I added six metrics so that "total clicks" and "average sentiment" have one definition. The `COMMENT` text on each item is what the agent reads, and it is in the file.
- **Same column name in several tables.** `DATE`, `CATEGORY`, `PRODUCT_NAME` and `CLICKS` appear in more than one table, so every item is written as `table.name`.
- **The masking policy still applies.** The view stores no data. A query through it reads the tables as the role that runs it, so `CLICKS` is masked for roles outside the two named in section 10. I have not tested that through the agent yet.
- **Next.** The agent also needs to search campaign names by text, which a semantic view does not do. Section 13 adds a search service for that.

**Verify:**
```sql
SHOW SEMANTIC VIEWS IN SCHEMA DASH_DB_SI.RETAIL;
SELECT * FROM SEMANTIC_VIEW(SEMANTIC_VIEW
  METRICS MARKETING_CAMPAIGN_METRICS.TOTAL_CLICKS
  DIMENSIONS MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME)
ORDER BY TOTAL_CLICKS DESC LIMIT 5;
```
```text
Summer Fitness Campaign | 11103
Fall Hustle Series      | 10966
Summer Blitz            | 10099
Back to Basics          | 9476
Spring Into Action      | 6799
```
The first statement lists `SEMANTIC_VIEW`. The second answers the lab's first question, "top 5 campaigns by clicks", straight from the view. `11103` is the number the lab says to expect.

## 13. A search service over the campaign names
The agent also needs to find campaigns by words, such as "summer", which a semantic view cannot do. A Cortex Search service indexes a text column and returns the closest matches. The lab builds it in Snowsight. This section has two SQL versions of the same service, `CAMPAIGN_SEARCH`. Run one of them. The first follows the lab. The second is an alternative that keeps the masking policy from section 10 working for people who search.

### Version 1: the lab's service (`21_search_service.sql`)
```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH
  ON CAMPAIGN_NAME
  ATTRIBUTES DATE, CATEGORY, IMPRESSIONS, CLICKS
  WAREHOUSE = DASH_WH_SI
  TARGET_LAG = '1 day'
  AS (
    SELECT CAMPAIGN_NAME, DATE, CATEGORY, IMPRESSIONS, CLICKS
    FROM MARKETING_CAMPAIGN_METRICS
  );
```
```bash
snow sql -f projects/03-zero-to-agents/sql/21_search_service.sql
```

**Reasoning:**
- **`ON CAMPAIGN_NAME`.** This is the lab's "search column". The text in it is what gets indexed and matched against the question.
- **`ATTRIBUTES` and the `SELECT`.** The lab selects all attributes and all columns. The query returns five columns, and the four besides the search column are the attributes. Attributes can be returned with each hit and used as filters. The agent tool in section 14 uses `CAMPAIGN_NAME` as its ID column and `CLICKS` as its title column, so both must be in the query.
- **`WAREHOUSE`.** The service uses `DASH_WH_SI` to build and refresh its index, as in the lab.
- **`TARGET_LAG = '1 day'`.** The lab does not show this setting. A service refreshes when the table changes, at most this often. The table changes rarely, so a day is enough. This value is my choice.
- **The mask does not apply.** The service reads the table as `SNOWFLAKE_INTELLIGENCE_ADMIN`, the role that owns it, so it holds the real click numbers. Any role that is granted `USAGE` on the service sees them. See the warning below.
- **Next.** Section 14 creates the agent, which gets this service and the semantic view from section 12 as its two data tools.

**Warning.** I gave `MARKETING_INTELLIGENCE_ROLE` `USAGE` on this service for a test, and a search returned the real `CLICKS` values (687 for the first hit). The same query on the table returns 0 for that role. Nothing grants that role the service in these notes, so nothing leaks as written. Do not grant it without using version 2.

**Verify:**
```sql
DESCRIBE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH;
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW('DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH',
  '{"query":"summer","columns":["CAMPAIGN_NAME","CLICKS"],"limit":2}');
```
```text
indexing_state: ACTIVE   serving_state: ACTIVE   source_data_num_rows: 128
Summer Blitz, 687
```
Both states are `ACTIVE`, which is what the lab waits for in Snowsight. The service holds all 128 rows, and a search for "summer" returns campaigns with that word in the name.

### Version 2: a service that applies the mask (`21a_search_service_governed.sql`)
```sql
CREATE OR REPLACE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH
  ON CAMPAIGN_NAME
  PRIMARY KEY (ROW_ID)
  ATTRIBUTES DATE, CATEGORY, IMPRESSIONS, CLICKS
  WAREHOUSE = DASH_WH_SI
  TARGET_LAG = '1 day'
  INHERIT_DATA_GOVERNANCE_POLICIES = TRUE
  AS (
    SELECT CAMPAIGN_NAME || '|' || CATEGORY || '|' || TO_VARCHAR(DATE) AS ROW_ID,
           CAMPAIGN_NAME, DATE, CATEGORY, IMPRESSIONS, CLICKS
    FROM MARKETING_CAMPAIGN_METRICS
  );
```
```bash
snow sql -f projects/03-zero-to-agents/sql/21a_search_service_governed.sql
```
The file starts with the same three `USE` statements. It creates a service with the same name, so it replaces version 1.

**Reasoning:**
- **`INHERIT_DATA_GOVERNANCE_POLICIES = TRUE`.** The service looks up each hit in the table again as the person who searches, so the masking policy on `CLICKS` applies to that person. This is a Snowflake preview feature.
- **`PRIMARY KEY (ROW_ID)`.** The setting needs a key to find the rows again. The table has no key column. The campaign name, category and date together are unique (128 distinct values for 128 rows), so `ROW_ID` joins the three.
- **What stops working.** `SEARCH_PREVIEW`, the REST API and the Python API are refused on this service. The agent, the `CORTEX_SEARCH_RETRIEVE` function and the `CORTEX_SEARCH_BATCH` function work.
- **Cost.** The source query runs again on every search, so keep it simple.
- **Section 14 is the same** for both versions, with `CLICKS` as the title column.

**Verify** (as the owner, then as `MARKETING_INTELLIGENCE_ROLE` after granting it `USAGE` on the service):
```sql
SELECT CAMPAIGN_NAME, CLICKS
FROM TABLE(CORTEX_SEARCH_RETRIEVE(service_name => 'DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH', query => 'summer', limit => 4));
```
```text
owner:      889, 468, 871, 483
marketing:  0, 0, 0, 0
```
The owner sees the real numbers and the marketing role sees 0, the same as on the table. The agent test in `VERIFICATION_NOTES.md` section 13 shows the same split through an agent.

**Which one to run.** Version 1 matches the lab. Version 2 is the one to use if the marketing role will ever search, or use an agent that searches. The notes after this section assume version 1 is deployed unless they say otherwise.

## 14. The agent
The agent is what answers questions. It reads the question, picks a tool, and writes the answer. It has three tools: the semantic view from section 12 for numbers, the search service from section 13 for words, and the `SEND_EMAIL` procedure from section 6 for sending results. The lab builds it in Snowsight, under AI & ML > Agents. `22_agent.sql` writes the same agent in SQL.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE AGENT MarketingAgent
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    orchestration: "Whenever you can answer visually with a chart, always choose to generate a chart even if the user didn't specify to."
    sample_questions:
      - question: "What are the top 5 campaigns by clicks?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "semantic_view"
        description: |
          Marketing, sales and support data for analysis. Tables:
          ENRICHED_MARKETING_INTELLIGENCE (CAMPAIGN_NAME, PRODUCT_NAME, CLICKS, AVG_SENTIMENT);
          MARKETING_CAMPAIGN_METRICS (CAMPAIGN_NAME, CATEGORY, CLICKS, IMPRESSIONS, DATE);
          PRODUCTS (PRODUCT_ID, PRODUCT_NAME, CATEGORY);
          SALES (PRODUCT_ID, REGION, UNITS_SOLD, SALES_AMOUNT, DATE);
          SOCIAL_MEDIA (CATEGORY, INFLUENCER, MENTIONS, PLATFORM, DATE);
          SUPPORT_CASES (ID, PRODUCT, TITLE, TRANSCRIPT, DATE).
          Key joins: ENRICHED_MARKETING_INTELLIGENCE.PRODUCT_NAME to MARKETING_CAMPAIGN_METRICS.CATEGORY,
          and PRODUCTS.PRODUCT_ID to SALES.PRODUCT_ID.
          Enables end-to-end analysis from marketing exposure → sales performance → post-sale support.
    - tool_spec:
        type: "cortex_search"
        name: "Search"
        description: "Searches marketing campaigns by name. The title of each result is its number of clicks."
    - tool_spec:
        type: "generic"
        name: "Send_Email"
        description: "Sends an email through the SEND_EMAIL procedure."
        input_schema:
          type: "object"
          properties:
            body:
              type: "string"
              description: "Use HTML-Syntax for this. If the content you get is in markdown, translate it to HTML. If body is not provided, summarize the last question and use that as content for the email."
            recipient_email:
              type: "string"
              description: "If the email is not provided, send it to the current user's email address."
            subject:
              type: "string"
              description: "If the subject is not provided, use \"Snowflake Intelligence\"."

  tool_resources:
    semantic_view:
      semantic_view: "DASH_DB_SI.RETAIL.SEMANTIC_VIEW"
      execution_environment:
        type: "warehouse"
        warehouse: "DASH_WH_SI"
        query_timeout: 60
    Search:
      search_service: "DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH"
      max_results: "4"
      id_column: "CAMPAIGN_NAME"
      title_column: "CLICKS"
    Send_Email:
      type: "procedure"
      identifier: "DASH_DB_SI.RETAIL.SEND_EMAIL"
      execution_environment:
        type: "warehouse"
        warehouse: "DASH_WH_SI"
        query_timeout: 60
  $$;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/22_agent.sql
```

**Reasoning:**
- **Where and who.** The agent is `DASH_DB_SI.RETAIL.MarketingAgent`, created by `SNOWFLAKE_INTELLIGENCE_ADMIN`, the role the lab names for access. The name is stored as `MARKETINGAGENT` because it is not quoted.
- **The description.** The lab's description text (the "Marketing & Sales Intelligence Assistant" paragraph) is stored as the agent's comment in the file.
- **`models: orchestration: auto`.** Snowflake picks the model that plans the work. The lab does not name one.
- **The orchestration instruction and the sample question.** Both are the lab's. The instruction makes the agent draw a chart whenever it can.
- **`semantic_view` tool.** It uses `cortex_analyst_text_to_sql`, which turns a question into SQL on the semantic view. The description is the lab's: the six tables with their columns and the two key joins. The agent reads it to decide when to use this tool. It runs on `DASH_WH_SI` with a 60-second query timeout, as in the lab.
- **`Search` tool.** It uses `cortex_search` on `CAMPAIGN_SEARCH`, with a maximum of 4 results, `CAMPAIGN_NAME` as the ID column and `CLICKS` as the title column, as in the lab. The lab does not show a description for this tool, so the text is mine. It works with either version of the service from section 13.
- **`Send_Email` tool.** It is a `generic` tool that calls the procedure `SEND_EMAIL` on `DASH_WH_SI`, with a 60-second timeout. The three parameter descriptions are the lab's. They tell the agent to write the body in HTML, to default the recipient to the current user and to default the subject to "Snowflake Intelligence". The tool's own description is mine.
- **Names.** The tool names are `semantic_view`, `Search` and `Send_Email`, as in the lab. Each `tool_resources` entry uses the same name as its tool.
- **Next.** Section 15 asks the lab's four questions and reads the agent's trace.

**Verify:**
```sql
DESCRIBE AGENT MarketingAgent;
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('DASH_DB_SI.RETAIL.MARKETINGAGENT',
  $${"parent_message_id":0,"messages":[{"role":"user","content":[{"type":"text","text":"What are the top 5 campaigns by clicks?"}]}]}$$);
```
```text
MARKETINGAGENT   DASH_DB_SI   RETAIL   SNOWFLAKE_INTELLIGENCE_ADMIN
Summer Fitness Campaign 11103, Fall Hustle Series 10966, Summer Blitz 10099, Back to Basics 9476, Spring Into Action 6799
```
`DESCRIBE` shows the agent with its owner. The agent answered the lab's sample question with the same five campaigns and clicks that section 12 returned from the semantic view, and it also produced a bar chart because of the orchestration instruction. I did not send a test email, so the `Send_Email` tool is unchecked.

## 15. Asking the agent the validation questions
The lab ends by asking the agent four questions and reading its trace, which lists the plan, the tool it picked and the reflection on the result. In Snowsight, open AI & ML > Snowflake Intelligence, choose `MarketingAgent`, ask each question and open the thinking steps under the answer. To script it, `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` takes the same question and returns the answer together with each tool call:

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('DASH_DB_SI.RETAIL.MARKETINGAGENT',
  $${"parent_message_id":0,"messages":[{"role":"user","content":[{"type":"text","text":"What are the top 5 campaigns by clicks?"}]}]}$$);
```

**Reasoning:**
- **`parent_message_id` 0** starts a new conversation. Each call is independent, so a follow-up question needs the thread ID from a previous answer.
- **What the response holds.** `content` is a list of steps in order. `thinking` is the agent's reasoning, `tool_use` names the tool and its input, `tool_result` is what the tool returned, and `text` is part of the answer. This is the scripted form of the trace.
- **I ran the scripted form.** I did not look at the Snowsight view, so what it shows is not checked here.

| # | Question | Tools the agent used | What to look for |
|---|---|---|---|
| 1 | What are the top 5 campaigns by clicks? | `semantic_view`, SQL on the view, a chart | 11103, 10966, 10099, 9476 and 6799. |
| 2 | Show me all campaign performance metrics and it's relationship to the product | `semantic_view`, SQL, a skill that explains charts, a chart | One row per campaign and product, with impressions, clicks and click rate. The agent returned 41 pairs. |
| 3 | What is the relationship between campaign clicks and customer satisfaction by category? | `semantic_view`, SQL, a chart | Clicks and average sentiment for each of the five categories. The agent took clicks from the campaign table, not from the dynamic table, because it noticed the dynamic table repeats campaign rows for each support case. |
| 4 | What are the main customer complains in support cases? | `semantic_view`, SQL (a title count, then `AI_AGG` over the transcripts), a chart | A summary per product, for example tears along the seams of the ThermoJacket Pro. |

Results from the run on 2026-11-22:
- **Question 1** matched section 12 exactly.
- **Question 3** said more clicks do not mean happier customers. Its correlation of about -0.42 comes from five points, so it is weak evidence. Fitness Wear had about 26,000 clicks, sentiment 0.20 and 15 of the 30 support cases.
- **Question 4** used `AI_AGG`, an AI function, on all 30 transcripts, so each run costs a little AI credit. The cost was not measured.
- **Every answer came with a chart.** That is the orchestration instruction from section 14.

**Testing the search tool.** None of the four questions needs the search service. A fifth question does:
```text
Find campaigns with summer in the name and show their clicks
```
The agent called `Search` with the query "summer" and a limit of 50, although the tool is set to 4 results. It then checked with SQL, because the search was capped, and answered with two campaigns: Summer Fitness Campaign (11,103 clicks) and Summer Blitz (10,099).

**Testing the email tool.**
```text
Email the top 5 campaigns by clicks to <your_email>
```
The agent queried the top 5, wrote an HTML table as the body, set the subject to "Top 5 Campaigns by Clicks" and called `Send_Email`. The procedure returned `Email sent successfully`.

`EMAIL_INTEGRATION` has no `ALLOWED_RECIPIENTS`, so it sends only to the email address saved on a user in the account. A first attempt to an address that belongs to no user in the account failed with "recipients ... are not allowed". Use the address from `SHOW USERS LIKE '<user_name>'`, run as `SECURITYADMIN`.

## Appendix. Scoring each support case once
Section 11 runs `AI_SENTIMENT` 975 times, once for every campaign row joined to a support case, although there are only 30 cases. The scores also differ between rows for the same case. This appendix scores each case once, stores the score, and joins to it. It adds two tables and leaves the section 11 table as it is.

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE DYNAMIC TABLE CASE_SENTIMENT (
  id,
  product,
  sentiment_score
)
TARGET_LAG = DOWNSTREAM
WAREHOUSE = DASH_WH_SI
AS
SELECT id, product,
       CASE AI_SENTIMENT(transcript):categories[0]:sentiment::STRING
            WHEN 'positive' THEN 1
            WHEN 'negative' THEN -1
            ELSE 0
       END
FROM support_cases;

CREATE OR REPLACE DYNAMIC TABLE ENRICHED_MARKETING_INTELLIGENCE_BY_CASE (
  campaign_name,
  clicks WITH MASKING POLICY MASK_ENGAGEMENT_CLICKS,
  product_name,
  avg_sentiment
)
TARGET_LAG = '1 hours'
WAREHOUSE = DASH_WH_SI
AS
SELECT m.campaign_name, m.clicks, c.product, c.sentiment_score
FROM marketing_campaign_metrics m
JOIN case_sentiment c ON m.category = c.product;

SELECT COUNT(*) AS CASES_SCORED FROM CASE_SENTIMENT;
SELECT COUNT(*) AS ROWS_LOADED FROM ENRICHED_MARKETING_INTELLIGENCE_BY_CASE;
```
```bash
snow sql -f projects/03-zero-to-agents/sql/23_appendix_case_scores.sql
```

**Reasoning:**
- **Why a separate table helps.** Section 11 tried a `WITH` step that scores the cases first, and Snowflake folded it into the join. A table of its own cannot be folded away, so the scores are computed once per case.
- **`CASE_SENTIMENT`.** One row per support case, so `AI_SENTIMENT` runs 30 times. `TARGET_LAG = DOWNSTREAM` means it refreshes only when the table that reads it needs fresh data. A new or changed case is scored when the next refresh runs.
- **`ENRICHED_MARKETING_INTELLIGENCE_BY_CASE`.** It has the same four columns and 975 rows as the section 11 table, but no AI function in its query. It carries the same masking policy on `clicks`, for the reason given in section 11.
- **Consistent scores.** Each case now has one score, so a product's sum is the number of marketing rows times the sum of its case scores. In the section 11 table the `Cyclone Helmet` sum is 35, which is not a multiple of 21.
- **What it does not change.** The semantic view and the agent still read the section 11 table. Pointing them at the new one is a separate change.
- **Cost.** About 0.03 AI credits per full build, from the 30 calls in section 8. The measured figure is still to come, because the usage view lags.

**Verify:**
```sql
SELECT product_name, COUNT(*), SUM(avg_sentiment), SUM(clicks) FROM ENRICHED_MARKETING_INTELLIGENCE_BY_CASE GROUP BY 1 ORDER BY 1;
```
```text
Cyclone Helmet    | 84  | 21  | 28232
Fitness Wear      | 660 | 132 | 390765
HydraBottle 2L    | 105 | 21  | 50540
PowerYoga Mat     | 84  | 21  | 44744
UltraRunner Shoes | 42  | 21  | 25506
```
Row counts and click sums match the section 11 table. Sentiment sums match for four products. `Cyclone Helmet` has 21 here and 35 in the section 11 table.

## Appendix. Running the grader
The lab ends with an auto-grader, `grader/workshop_greeting.sql`. It is kept outside `sql/`, so it only runs when you ask. It uses `ACCOUNTADMIN`, because it creates an API integration.

```bash
snow sql -f projects/03-zero-to-agents/grader/workshop_greeting.sql
snow sql -f projects/03-zero-to-agents/grader/workshop_greeting_cleanup.sql
```

**Reasoning:**
- **What the first file does.** It creates `DORA_API_INTEGRATION` and the database `UTIL_DB` with the external functions `GRADER` and `GREETING`, registers your name and email with `greeting`, then runs six checks, `BWZA01` to `BWZA06`. Each call sends the account name and the statement to the grader's endpoint. Edit the `greeting` line to your own email and name first.
- **What the second file does.** It drops `UTIL_DB` and `DORA_API_INTEGRATION`, which are the only things the grader leaves behind. Run it when the grader has passed. A rebuild needs the first file again.
- **The checks.** `BWZA01` counts databases (2), `BWZA02` stages (7), `BWZA03` tables (6), `BWZA04` the admin role (1), `BWZA05` semantic views owned by the admin role (at least 1) and `BWZA06` search services owned by the admin role (at least 1). The final query prints "You've successfully completed the From Zero to Agents lab!" when all six pass.
