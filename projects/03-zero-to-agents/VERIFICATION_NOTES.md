# 03 - Verification notes

`LAB_NOTES.md` is the step-by-step guide. This file is its companion. For each section it lists the commands that were run to check what was created, the output seen, and what that output confirms. Sections are added as `LAB_NOTES.md` grows.

Run every command from the repo root after `source scripts/use-project.sh 03-zero-to-agents`. Placeholders: `<user_name>` (from `SELECT CURRENT_USER();`).

**Two things that make a check return nothing:**
- `information_schema.query_history` and `copy_history` need a schema in the session (`USE SCHEMA DASH_DB_SI.RETAIL`). Without one, `snow sql` prints the statement and no table.
- `query_history` only lists queries run by the current user. Run it under the role that ran them, for example `USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN`.

## 1. Connecting with a password

| Check | Command | Seen | Confirms |
|---|---|---|---|
| Login works | `snow connection test` | `Status OK`, `Role ACCOUNTADMIN`, `Warehouse DASH_WH_SI` | Account, user and password are right. The warehouse is the user default set in section 2 (it was `COMPUTE_WH` before). |
| Password comes from the environment | `env -u SNOWFLAKE_PASSWORD snow connection test` | `251006: Password is empty` | The rendered `connections.toml` holds no password. |
| Session query tag | `SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;` | project tag, level `SESSION` | Every statement from the CLI carries the project tag. |
| Only this project's variables are set | `env \| grep ^SNOWFLAKE_` | `SNOWFLAKE_ACCOUNT`, `_USER`, `_ROLE`, `_PASSWORD`, `_HOME` | `use-project.sh` cleared everything left from an earlier project. |
| Home file untouched | `ls ~/.snowflake` and `ls projects/03-zero-to-agents/.snowflake` | rendered `connections.toml` only in the project folder | The connection lives in the project folder, not in `~/.snowflake`. |
| MFA | a login with the password alone | worked | MFA is not enabled on the user. |

## 2. The project role and user defaults

```sql
SHOW GRANTS TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
SHOW GRANTS OF ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
DESC USER <user_name>;
SELECT name, default_role, default_warehouse FROM snowflake.account_usage.users WHERE name = '<user_name>';
```

| Check | Seen | Confirms |
|---|---|---|
| `SHOW GRANTS TO ROLE` | `CREATE WAREHOUSE`, `CREATE DATABASE`, `CREATE INTEGRATION` on the account, then ownership of about 30 objects | The three account privileges are in place, and the list shows what a `CREATE OR REPLACE ROLE` would orphan. |
| `SHOW GRANTS OF ROLE` | one row, user `<user_name>` | The role is held by the user and by no other role, so `SYSADMIN` has no grant on it. |
| `DESC USER` | `DEFAULT_ROLE = SNOWFLAKE_INTELLIGENCE_ADMIN`, `DEFAULT_WAREHOUSE = DASH_WH_SI` | The two `ALTER USER` statements took effect. |
| `account_usage.users` | same two defaults | Same result from a second source. This view can lag, so `DESC USER` is the primary check. |

**The lab's form of `ALTER USER`.** The lab's statements were run unchanged from a temporary file before the project file was written:
```sql
ALTER USER SET DEFAULT_ROLE = SNOWFLAKE_INTELLIGENCE_ADMIN;
ALTER USER SET DEFAULT_WAREHOUSE = DASH_WH_SI;
-- Statement executed successfully. (both)
```
This confirms the form without a user name works and changes the current user.

**Undoing an extra grant.** An earlier version of the project file also granted the role to `SYSADMIN`. The lab doesn't, so it was removed and the result checked:
```sql
REVOKE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN FROM ROLE SYSADMIN;
SHOW GRANTS OF ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;   -- only the user remains
```

## 3. Warehouse, databases and a resource monitor

```sql
SHOW WAREHOUSES LIKE 'DASH_WH_SI';
SHOW RESOURCE MONITORS LIKE 'DASH_WH_SI_RM';
SHOW SCHEMAS IN DATABASE DASH_DB_SI;
SHOW GRANTS ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
```
Each `SHOW` was followed by a `SELECT` on `result_scan(last_query_id())` to keep only the columns of interest.
```sql
SELECT "name", "size", "auto_suspend", "auto_resume", "owner", "resource_monitor"
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

| Check | Seen | Confirms |
|---|---|---|
| Warehouse | `DASH_WH_SI`, `Large` at first, owner `SNOWFLAKE_INTELLIGENCE_ADMIN`, auto-suspend 60, auto-resume true, monitor `DASH_WH_SI_RM` | The warehouse is owned by the project role and attached to the monitor. |
| Resize | `ALTER WAREHOUSE DASH_WH_SI SET WAREHOUSE_SIZE = XSMALL;` then `SHOW WAREHOUSES` | Size `X-Small`, state `SUSPENDED`. The resize applied, and the warehouse isn't running. |
| Resource monitor | quota `10.00`, `MONTHLY`, notify `75%`, suspend `100%`, suspend immediately `110%` | The triggers match the file. |
| Schemas | `RETAIL` and `PUBLIC` owned by the project role, plus `INFORMATION_SCHEMA` | `CREATE DATABASE` added `PUBLIC`, and the role owns what it created. |
| Agent grant | `CREATE AGENT` on `SNOWFLAKE_INTELLIGENCE.AGENTS` granted to the project role, and the role holds `OWNERSHIP` of the schema | Agents can be created there. |

## 4. Loading five tables from public S3 stages

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE SCHEMA DASH_DB_SI.RETAIL;

-- rows and status per loaded file (one UNION ALL branch per table, shown for one)
SELECT table_name, file_name, row_count, status, last_load_time
FROM TABLE(information_schema.copy_history(table_name => 'SALES', start_time => DATEADD(day, -3, CURRENT_TIMESTAMP())));

-- duration and warehouse size of each COPY
SELECT REGEXP_SUBSTR(query_text, 'COPY INTO \\w+') q, warehouse_size, total_elapsed_time ms, execution_time, compilation_time
FROM TABLE(information_schema.query_history(result_limit => 10000))
WHERE query_text ILIKE 'COPY INTO%' ORDER BY start_time;

LIST @SWT_MARKETING_DATA_STAGE;
```

| Check | Seen | Confirms |
|---|---|---|
| `copy_history` | one file per table, all `Loaded`: 23, 40, 14,560, 273 and 30 rows | Every table loaded completely, with no errors. |
| `query_history` | the five loads ran at `Large`, 1.9 to 2.7 s each | The loads happened at the lab's size. These timings are the baseline for the size check. |
| `LIST @SWT_MARKETING_DATA_STAGE` | one file, `marketing_campaign_metrics.csv`, 1,368 bytes | The public bucket is reachable without credentials. |
| Size comparison | `CREATE TEMPORARY TABLE SALES_XS_TEST LIKE SALES;` then `COPY INTO SALES_XS_TEST FROM @SWT_SALES_DATA_STAGE;` on `XSMALL`: 14,560 rows loaded, `X-Small`, 3,954 ms (execution 3,004, compilation 238) | `XSMALL` is about a second slower than `LARGE` for the biggest load. The temporary table disappears when the session ends. |
| Quoting need | `SELECT COUNT(*), COUNT_IF(CONTAINS(transcript, ',')) FROM support_cases;` returned 30 and 30 | Every transcript contains a comma, so the file format's quote handling is needed. |

## 5. Git integration and the semantic model file

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE SCHEMA DASH_DB_SI.RETAIL;

SHOW STAGES LIKE 'SEMANTIC_MODELS';
SHOW API INTEGRATIONS LIKE 'SNOWFLAKE_LABS%';
DESC API INTEGRATION SNOWFLAKE_LABS_SI_GIT_API_INTEGRATION;
SHOW GIT REPOSITORIES;
SHOW GIT BRANCHES IN SNOWFLAKE_LABS_SFGUIDE_SI_REPO;
LS @SNOWFLAKE_LABS_SFGUIDE_SI_REPO/branches/main/;
LIST @SEMANTIC_MODELS;

-- which warehouse each statement used
SELECT warehouse_size, total_elapsed_time ms, LEFT(query_text, 30) q
FROM TABLE(information_schema.query_history(result_limit => 10000))
WHERE query_text ILIKE 'copy files%' OR query_text ILIKE 'create%git%' ORDER BY start_time;
```
```bash
# read the staged file back to check its contents
snow stage copy @DASH_DB_SI.RETAIL.SEMANTIC_MODELS/marketing_campaigns.yaml /tmp/sm --role snowflake_intelligence_admin
grep -n "^name\|^  - name\|base_table\|^relationships\|^verified_queries" /tmp/sm/marketing_campaigns.yaml
```

| Check | Seen | Confirms |
|---|---|---|
| `SHOW STAGES` | type `INTERNAL NO CSE`, `directory_enabled = Y`, owner project role | The stage is internal with a directory table, and the role owns it. |
| `SHOW API INTEGRATIONS` | `EXTERNAL_API`, category `API`, enabled `true` | The integration exists and is on. |
| `DESC API INTEGRATION` | `API_PROVIDER GIT_HTTPS_API`, `API_ALLOWED_PREFIXES https://github.com/Snowflake-Labs`, `ALLOWED_AUTHENTICATION_SECRETS []` | Only that GitHub organisation is reachable, and no secret is stored. |
| `SHOW GIT REPOSITORIES` | origin is the lab repo, uses the integration, owner project role | The repository object is wired to the integration. |
| `SHOW GIT BRANCHES` | `main`, commit `d7976cb1...` | The clone fetched the branch. |
| `LS @repo/branches/main/` | 11 files, among them `marketing_campaigns.yaml` (10,000 bytes), `setup.sql` and five CSV files under `data/` | The remote content is readable from Snowflake. |
| `LIST @SEMANTIC_MODELS` | `semantic_models/marketing_campaigns.yaml`, 10,000 bytes | The copy reached the stage, and only that file did. |
| Query history | integration 131 ms, repository 4,750 ms, `COPY FILES` 5,410 ms, warehouse size `None` for all three | These statements didn't use the warehouse. |
| File contents | 350 lines, model `Sales_And_Marketing_Data`, four tables with `base_table` in `DASH_DB_SI.RETAIL`, two relationships, one verified query | The model matches the tables created in section 4. The temporary download was deleted afterwards. |

## 6. Email integration and the SEND_EMAIL procedure

```sql
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE SCHEMA DASH_DB_SI.RETAIL;

SHOW NOTIFICATION INTEGRATIONS;
DESC NOTIFICATION INTEGRATION EMAIL_INTEGRATION;
SHOW PROCEDURES LIKE 'SEND_EMAIL';
DESC PROCEDURE SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR);

SELECT LEFT(query_text, 45) q, execution_status, total_elapsed_time ms, warehouse_size
FROM TABLE(information_schema.query_history(result_limit => 10000))
WHERE query_text ILIKE 'call%send%' OR query_text ILIKE 'create%notification%' OR query_text ILIKE 'create%procedure%'
ORDER BY start_time;
```
```sql
SHOW USERS LIKE '<user_name>';   -- then read the "email" column; only whether it is set, not its value, is recorded here
```

| Check | Seen | Confirms |
|---|---|---|
| `SHOW NOTIFICATION INTEGRATIONS` | `EMAIL_INTEGRATION`, type `EMAIL`, enabled `true`, direction `OUTBOUND` | The integration exists and is on. |
| `DESC NOTIFICATION INTEGRATION` | `ALLOWED_RECIPIENTS []`, `DEFAULT_RECIPIENTS []`, `DEFAULT_SUBJECT snowflake intelligence` | No allow list, so any verified address in the account is accepted. |
| `SHOW PROCEDURES` | `SEND_EMAIL(VARCHAR, VARCHAR, VARCHAR) RETURN VARCHAR`, schema `RETAIL` | The procedure has three string arguments. |
| `DESC PROCEDURE` | Python, runtime `3.12`, handler `send_email`, `execute as OWNER`, package `snowflake-snowpark-python` from `snowflake.snowpark.pypi_shared_repository` | The runtime and package match the file, and the procedure runs with its owner's rights. |
| Query history | integration `SUCCESS`, 63 ms, warehouse `None`. Procedure `SUCCESS`, 8,837 ms, warehouse `Large` | Both created without errors. The procedure creation ran on the larger warehouse that existed at the time. |
| User email | set | An address exists. |
| Test call | `CALL SEND_EMAIL($em, 'Snowflake lab: SEND_EMAIL test', '<p>...</p>')`, with `$em` read from `DESC USER` (the address isn't printed) | Returned `Email sent successfully`. Snowflake rejects unverified recipients, so the address is very likely verified. |
| Delivery | pending: inbox check by the user | The returned text only says Snowflake accepted the send. |

## 7. Cortex cross-region setting and a setup check

```sql
SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;
SELECT CURRENT_REGION();
```
```bash
snow sql -f projects/03-zero-to-agents/sql/13_verify.sql

# reproduce the CLI error with the lab's block unwrapped (a temporary file, deleted afterwards)
snow sql -f /tmp/unwrapped.sql
```

| Check | Seen | Confirms |
|---|---|---|
| Parameter | `AWS_US`, default `DISABLED`, level `ACCOUNT` | The setting is on and was set on the account, not on a user or session. |
| Region | `AWS_EU_CENTRAL_1` | The account is in Europe, so `AWS_US` lets Cortex requests leave the region. |
| `13_verify.sql` | `Setup complete: 5 tables created and loaded with data.` | All five tables exist and `SALES` has rows. |
| Row counts | 128, 40, 14,560, 273, 30 | Matches section 4, plus 105 rows added to the marketing table after section 4. |
| Unwrapped block | `001003 (42000) ... syntax error line 2 at position 34 unexpected '<EOF>'`, shown after the first statement `DECLARE table_count INTEGER DEFAULT 0;` | The CLI cuts the block at the first semicolon. The same error was seen when the file was first run. |

## 8. AI functions on the support transcripts

```sql
SELECT PRODUCT, COUNT(*) FROM SUPPORT_CASES GROUP BY PRODUCT ORDER BY PRODUCT;
SELECT CATEGORY, COUNT(*) FROM PRODUCTS GROUP BY 1 ORDER BY 1;
SELECT COUNT(*) FROM PRODUCTS WHERE PRODUCT_NAME ILIKE '%thermojacket%';
SELECT AI_SENTIMENT(TRANSCRIPT) FROM SUPPORT_CASES LIMIT 1;
SELECT AI_CLASSIFY(TRANSCRIPT, ['Return','Quality','Shipping']) FROM SUPPORT_CASES LIMIT 1;
```
The `14_ai_enrichment.sql` `SELECT` was run again and its query-history entry read.

| Check | Seen | Confirms |
|---|---|---|
| Cases per product | 4, 15, 5, 4, 2 with `Fitness Wear` at 15 | The `UPDATE` applied to the 15 `ThermoJacket Pro` cases, and none are left under the old name. |
| `PRODUCTS` categories | Four categories of 10 each, including `Fitness Wear` | `Fitness Wear` is a real category in `PRODUCTS`. |
| `ThermoJacket` in `PRODUCTS` | 0 | The old name matched nothing in the products table. |
| Marketing categories | `Fitness Wear` 44 rows, and four product names | `Fitness Wear` is also a value in `MARKETING_CAMPAIGN_METRICS`. |
| Raw `AI_SENTIMENT` | `{"categories":[{"name":"overall","sentiment":"positive"}]}` | The JSON shape that the `:categories[0]:sentiment` path reads. |
| Raw `AI_CLASSIFY` | `{"labels":["Return"]}` | The JSON shape that the `:labels[0]` path reads. |
| Query history | `SUCCESS`, X-Small, 1,513 ms | The AI query ran on XSMALL and took about 1.5 s. |
| Label counts | 23 mixed, 7 positive. 19 Quality, 11 Return | A snapshot only. The model's labels can change between runs. |

**Cost of the AI query, LARGE against XSMALL.** The queries are in `sql/14a_ai_cost.sql` (read-only).
```sql
-- AI credits per query and function
SELECT query_id, function_name, credits, metrics[0]:value::NUMBER AS tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY;
-- warehouse side
SELECT query_id, warehouse_size, execution_time, total_elapsed_time FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;
SELECT query_id, credits_attributed_compute FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY;
SELECT start_time, credits_used_compute FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY WHERE warehouse_name = 'DASH_WH_SI';
```

| Check | LARGE (2026-11-19) | XSMALL (2026-11-21) | Confirms |
|---|---|---|---|
| Size in query history | Large | X-Small | Each run used the size the notes say. |
| Execution / elapsed time | 2,125 / 2,545 ms | 1,086 / 1,513 ms | XSMALL ran faster here, within the noise of a 30-row query. Compilation took about 420 ms on both. |
| Tokens | 35,313 (18,316 + 16,997) | 35,313 (18,316 + 16,997) | The two runs processed identical input. |
| AI credits | 0.056867 | 0.056867 | The AI cost does not depend on warehouse size. |
| Warehouse credits, calculated | 0.00472 | 0.00030 | Execution time x 8 or 1 credits per hour. |
| Warehouse credits, attributed | 0.05997 | not in the view yet | See below. |

- **Unexplained difference.** The attributed figure for the LARGE run is about 13 times the calculated one. I haven't found why, and I didn't test the cause. It may include some of the warehouse's resume time. Recheck the XSMALL figure when it appears, since the view can lag by hours.
- **Same data, same cost.** The two query IDs show identical AI credits to 9 decimal places, so the token count is the only driver.
- **Hourly metering.** `WAREHOUSE_METERING_HISTORY` is billed per hour and mixes in every other query of that hour, so it can't be tied to one query. It shows 1.278 credits for the first hour on 2026-11-19 (when the tables were loaded at LARGE) against 0.041 and 0.060 credits for the two hours of 2026-11-21, which ran at XSMALL.
- **View choice.** The older views `CORTEX_FUNCTIONS_USAGE_HISTORY` and `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` returned no rows for these queries. `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` has them.

## 9. Loading the marketing CSV with PUT and COPY

Run on 2026-11-21. The load itself ran earlier (2026-11-19); this block checks its result and tests what a rerun does.
```sql
SELECT COUNT(*), COUNT(DISTINCT DATE||CATEGORY||CAMPAIGN_NAME||IMPRESSIONS) FROM MARKETING_CAMPAIGN_METRICS;
SELECT file_name, row_count, status FROM DASH_DB_SI.INFORMATION_SCHEMA.LOAD_HISTORY WHERE table_name = 'MARKETING_CAMPAIGN_METRICS';
```
```bash
wc -l projects/03-zero-to-agents/data/marketing_data.csv
```

| Check | Result | Confirms |
|---|---|---|
| `wc -l` of the CSV | 106 | One header line plus 105 data rows. |
| `LOAD_HISTORY`, S3 file | 23 rows, `LOADED` | Section 4 loaded 23 rows. |
| `LOAD_HISTORY`, `marketing_data.csv.gz` | 105 rows, `LOADED` | The CSV was loaded once. |
| Table count | 128 total, 128 distinct | 23 + 105, and no duplicate rows. |
| Git repository stage listing (`ls @...SNOWFLAKE_LABS_SFGUIDE_SI_REPO/branches/main/`) | `data/` holds `marketing_campaign_metrics.csv`, `products.csv`, `sales.csv`, `social_media_mentions.csv`, `support_cases.csv` | `marketing_data.csv` is not in the lab repository. A rebuild needs the file saved locally. |
| `~/Downloads` before the move | `marketing_data.csv` and `marketing_data (1).csv`, byte-identical | The second is a duplicate download. I moved `marketing_data.csv` to `projects/03-zero-to-agents/data/` and left the duplicate. |

**Rerun test** on a temporary table, so `MARKETING_CAMPAIGN_METRICS` was not touched:

| Sequence | Rows in the test table | Confirms |
|---|---|---|
| `COPY`, then `COPY` again (file unchanged) | 105 | The second `COPY` reported `0 files processed`. |
| Same, then `PUT ... OVERWRITE = TRUE` of the same file, then `COPY` | 210 | `PUT` uploaded the file as new, and `COPY` loaded it again. |
| Temporary stage, `PUT` and `COPY` three times, no `OVERWRITE` | 105 | The 2nd and 3rd `PUT` returned `SKIPPED`, and `COPY` processed 0 files. |

- **Decision.** `15_load_marketing_data.sql` keeps `OVERWRITE = TRUE`, as the lab flow suggests, with a header comment saying a second run appends 105 rows and how to redo the step (recreate the table with `05`, then rerun `15`). The no-`OVERWRITE` variant is described in the lab notes as the alternative. The redo sequence has not been run on the real table.
- **Side effect of the test.** My first test ran `PUT ... OVERWRITE = TRUE` against the real `MARKETING_UPLOAD_STAGE`, which replaced `marketing_data.csv.gz` there. `MARKETING_CAMPAIGN_METRICS` did not load that new version, and its count stayed 128. That stage has since been dropped (see below), so the hazard is gone.

**Dropping the stage** on 2026-11-22. The lab's setup check expects exactly 7 stages in `DASH_DB_SI` and counted 8 here.
```sql
DROP STAGE MARKETING_UPLOAD_STAGE;
SELECT COUNT(*) FROM DASH_DB_SI.INFORMATION_SCHEMA.STAGES;
SELECT COUNT(*) FROM MARKETING_CAMPAIGN_METRICS;
```

| Check | Result | Confirms |
|---|---|---|
| Rows before and after the drop | 128 and 128 | Dropping the stage does not touch the loaded rows. |
| Stage count | 7 | Matches the expected count. |

- **Not tested.** `15_load_marketing_data.sql` with the new last line. It would append 105 rows to the real table, so it waits for the rebuild.

## 10. A restricted role, a secure view and a masking policy

Parts 1 and 2 first ran on 2026-11-19. I checked their result on 2026-11-22, changed part 3, then reran parts 1 and 3.
```sql
SHOW GRANTS ON VIEW MARKETING_INTELLIGENCE_VIEW;
SHOW GRANTS TO ROLE MARKETING_INTELLIGENCE_ROLE;   -- as ACCOUNTADMIN
SELECT * FROM TABLE(DASH_DB_SI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'MASK_ENGAGEMENT_CLICKS'));
SELECT CURRENT_ROLE(), COUNT(*), SUM("Engagement Clicks"), MIN("Engagement Clicks"), MAX("Engagement Clicks") FROM MARKETING_INTELLIGENCE_VIEW;
SELECT CURRENT_SECONDARY_ROLES();
```

| Check | Result | Confirms |
|---|---|---|
| Role grants | `USAGE` on database, schema, warehouse and `SNOWFLAKE.CORTEX_USER`. The role is granted to user `MIDEGA`. | Part 1 granted what the notes list. |
| `POLICY_REFERENCES` | `MARKETING_CAMPAIGN_METRICS.CLICKS`, `MASK_ENGAGEMENT_CLICKS`, `MASKING_POLICY` | The policy is on the column. |
| View as admin | 128 rows, sum 67,156, min 178, max 889 | The admin sees real clicks. |
| View as marketing role | 128 rows, sum 0, min 0, max 0 | Every value is masked. |
| Base table as marketing role | 128 rows, sum 0 | The mask applies to the table column as well as the view. |

**Two problems found in the lab's file.**
- **Lost grant.** Before my change, `SHOW GRANTS ON VIEW` listed only `OWNERSHIP`. The `SELECT` grant from part 1 was gone, because the plain `CREATE OR REPLACE SECURE VIEW` in part 3 drops grants. The view was replaced at 02:38:49 and the grant was made at 02:38:20.
- **The demo hid it.** `CURRENT_SECONDARY_ROLES()` returned `{"roles":"SNOWFLAKE_INTELLIGENCE_ADMIN,MARKETING_INTELLIGENCE_ROLE,ORGADMIN","value":"ALL"}`. The marketing role could read the view anyway, through the admin role. After `USE SECONDARY ROLES NONE` the same query failed: `Object 'MARKETING_INTELLIGENCE_VIEW' does not exist or not authorized. Your primary role MARKETING_INTELLIGENCE_ROLE must have at least one privilege granted on TABLE MARKETING_INTELLIGENCE_VIEW.` The marketing role could also read `ENRICHED_MARKETING_INTELLIGENCE` (975 rows) without a grant, for the same reason.

**What I changed.** In `18_verify_masking.sql` the view statement now has `COPY GRANTS` and `USE SECONDARY ROLES NONE` comes before `USE ROLE MARKETING_INTELLIGENCE_ROLE`. I ran `GRANT SELECT ON VIEW ... TO ROLE MARKETING_INTELLIGENCE_ROLE` once by hand to restore the grant, then ran the edited file. Afterwards `SHOW GRANTS ON VIEW` lists `OWNERSHIP` for the admin role and `SELECT` for the marketing role, and the file returned `0` for every row as the marketing role with secondary roles off. I then ran `17` and `19` again on the existing account. After `17` the view lists `SELECT` for the marketing role and `OWNERSHIP` for the admin role. After `19` the same two lines are listed, so `COPY GRANTS` keeps the grant, and the marketing role returned 0 in all 128 rows with secondary roles off. I did not rerun `18`. Attaching the policy rebuilt the dynamic table once (about 0.9 AI credits), and I have not tested what a second run does. The order `17`, `18`, `19` from an empty account is untested until the rebuild.

**Which role can run part 1 (tested 2026-11-22).** Throwaway roles named `TMP_PART1_TEST*`, each statement in its own session with `USE SECONDARY ROLES NONE`, all dropped afterwards (`SHOW ROLES LIKE 'TMP_PART1%'` returned no data).

| Statement | `SNOWFLAKE_INTELLIGENCE_ADMIN` | `USERADMIN` | `SECURITYADMIN` |
|---|---|---|---|
| `CREATE ROLE` | `Insufficient privileges` | created | created |
| `GRANT USAGE` on warehouse, database, schema, `GRANT SELECT` on the view | worked | not tested | worked |
| `GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER` | failed | failed | worked |
| `GRANT ROLE ... TO USER` | failed | worked | worked |

- **First attempt was wrong.** With the default secondary roles `ALL`, every statement appeared to work for `SNOWFLAKE_INTELLIGENCE_ADMIN`, because `ACCOUNTADMIN` was lent to the session. Only `CREATE ROLE` failed, since creating objects needs the primary role. The table above is the second run with secondary roles off.
- **All of part 1 as `SECURITYADMIN`.** The role, the five grants and the grant to the user all ran in one file, and `SHOW GRANTS` listed the five grants. I did not run the view statement as `SECURITYADMIN`.
- **File change.** `16_marketing_role_and_view.sql` now uses `USE ROLE SECURITYADMIN;`, with a comment to switch back to `ACCOUNTADMIN` if a grant fails on a rebuild. The edited file has not been rerun, because its role block was tested only on the throwaway role.
- **`PUBLIC`.** `SHOW GRANTS TO ROLE PUBLIC` lists `USAGE` on `SNOWFLAKE.CORTEX_USER` since 2026-11-17.

**`CORTEX_USER` grant (tested 2026-11-22).** With `USE SECONDARY ROLES NONE`, the marketing role ran `SELECT AI_SENTIMENT('The helmet is great')` and got `positive`. I then revoked `SNOWFLAKE.CORTEX_USER` from the role as `SECURITYADMIN`, ran the same query, and it still worked, so `PUBLIC` supplies the privilege. I granted it again and `SHOW GRANTS` lists it.

**Order change.** The security section now comes before the dynamic table, and the files were renamed (`17`, `18`, `19` became `16`, `17`, `18`). The existing account was built in the old order. The new order has not been run, so the rebuild is its test.

## 11. A dynamic table that joins campaigns to support cases

Checked on 2026-11-21. The table was created on 2026-11-19 at 02:37.
```sql
SHOW DYNAMIC TABLES LIKE 'ENRICHED_MARKETING_INTELLIGENCE' IN SCHEMA DASH_DB_SI.RETAIL;
SELECT state, refresh_action, refresh_trigger, data_timestamp FROM TABLE(DASH_DB_SI.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(NAME=>'DASH_DB_SI.RETAIL.ENRICHED_MARKETING_INTELLIGENCE')) ORDER BY data_timestamp DESC;
SELECT product_name, COUNT(*) FROM ENRICHED_MARKETING_INTELLIGENCE GROUP BY 1 ORDER BY 1;
SELECT category, COUNT(*) FROM MARKETING_CAMPAIGN_METRICS GROUP BY 1 ORDER BY 1;
SELECT product, COUNT(*) FROM SUPPORT_CASES GROUP BY 1 ORDER BY 1;
SELECT query_id, function_name, SUM(credits), SUM(metrics[0]:value::NUMBER) FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY GROUP BY ALL;
```

| Check | Result | Confirms |
|---|---|---|
| `SHOW DYNAMIC TABLES` | 975 rows, `target_lag` 1 hour, `refresh_mode` `ADAPTIVE`, warehouse `DASH_WH_SI` | The table exists with the lag from the file. The file's own definition text shows `refresh_mode = 'AUTO'`, and Snowflake resolved it. |
| `scheduling_state`, latest `data_timestamp` | `ACTIVE`, 2026-11-21 07:09 | Refreshes are running. |
| Refresh history, last six | All `SUCCEEDED`, `NO_DATA`, `SCHEDULED`, 51 to 52 minutes apart | Nothing changed upstream, so the refreshes did no work. |
| Refresh history, other actions | `INCREMENTAL` at creation (975 inserted). `REINITIALIZE` on 2026-11-19 at 03:06 (975 deleted, 975 inserted) | The table has been fully rebuilt twice. |
| Rows per product | 84 / 660 / 105 / 84 / 42 | Matches the marketing row count times the case count per category. |
| Marketing rows per category | 21 / 44 / 21 / 21 / 21 | Used in the product below. |
| Support cases per product | 4 / 15 / 5 / 4 / 2 | 21x4 + 44x15 + 21x5 + 21x4 + 21x2 = 975. |
| `MIN` and `MAX` of `avg_sentiment` | 0 and 1 | No case scored negative. |
| `CORTEX_AI_FUNCTIONS_USAGE_HISTORY`, creation refresh (query `01c8837d-0109-8b1c-0005-a7b6000352a2`) | `AI_SENTIMENT`, 561,637 tokens, 0.898619 credits | Cost of the first build. |
| Same view, reinitialize (query `01c8839a-0109-8c9a-0005-a7b60003602a`) | `AI_SENTIMENT`, 561,637 tokens, 0.898619 credits | Same cost for the second build. |
| Section 8 query, `AI_SENTIMENT` only | 16,997 tokens, 0.027195 credits for 30 cases | 561,637 / 16,997 = 33.0, which is close to the 32.5 ratio of 975 rows to 30 cases. |

- **What this shows.** `AI_SENTIMENT` ran for every joined row. I did not test an alternative that scores each case once before the join, so I can't say what it would cost.

**Two versions compared (2026-11-21, throwaway dynamic tables `TMP_DT_CHEAP` and `TMP_DT_LAB`, dropped afterwards).** Both used `TARGET_LAG = '1 day'` and `DASH_WH_SI`.

| | Rewrite (score cases in a `WITH` step) | Lab query |
|---|---|---|
| Refresh query | `01c892f9-0109-9f39-0005-a7b60008e292` | `01c892f9-0109-9b1d-0005-a7b60007ea4e` |
| Rows | 975 | 975 |
| `AI_SENTIMENT` tokens | 561,637 | 561,637 |
| AI credits | 0.898619 | 0.898619 |
| Sum of `avg_sentiment` | 234 | 231 (live table: not equal on `Cyclone Helmet`, 29 against 36) |
| `MINUS` between the two tables, both directions | 0 rows | 0 rows |

- **Result.** The rewrite cost the same as the lab query, so Snowflake did not score each case once. The token count is the same as the creation build (561,637).
- **Scores vary per row.** `Cyclone Helmet` has 21 marketing rows, and its sum was 39 in the rewrite, 36 in the lab query and 29 in the live table. A sum of per-case scores repeated across 21 rows would be a multiple of 21. The other four products were multiples (21, 21, 132, 132 in every table). The `MINUS` check is blind to this, because it ignores duplicate rows.
- **Tested later.** A version that forces one score per case is in the appendix (`23_appendix_case_scores.sql`), checked at the end of this file.
- **Cause of the reinitialize.** The `REINIT_REASON` column of `DYNAMIC_TABLE_REFRESH_HISTORY` for the 2026-11-19 03:06 refresh reads `Data governance policy changed on 'DASH_DB_SI.RETAIL.MARKETING_CAMPAIGN_METRICS'.` `QUERY_HISTORY` shows `ALTER TABLE MARKETING_CAMPAIGN_METRICS MODIFY COLUMN CLICKS SET MASKING POLICY MASK_ENGAGEMENT_CLICKS` at 02:38:38, 28 minutes after the table was created. The reinitialize ran at the next scheduled refresh. Its query ran as an `alter dynamic table` statement on the LARGE warehouse, which was the warehouse in use at that time.
- **Not run.** `19_dynamic_table.sql` was not run again, because each run costs about 0.9 AI credits. It has two header comment lines about that cost, a new header line about the run order, and a column list that puts the masking policy on `clicks`.
- **Order.** The first table was created before the policy, in the lab's order. Section 10 (policy first) is tested as `19_dynamic_table.sql` below.

**Masking and a dynamic table (tested 2026-11-22, throwaway dynamic tables without AI calls, all dropped afterwards).** The policy was already on `CLICKS` of the source table. Every test ran with `USE SECONDARY ROLES NONE`.

| Test | Admin role sum of `clicks` | Marketing role sum of `clicks` | Confirms |
|---|---|---|---|
| `TMP_DT_MASK`: plain `SELECT campaign_name, clicks FROM marketing_campaign_metrics` | 67,156 | 67,156 | The mask does not carry over. The dynamic table is built by its owner, so it stores real values. Creation on a masked column worked (refresh `REINITIALIZE`, trigger `CREATION`, `SUCCEEDED`). |
| `TMP_DT_MASK_A`: same query, then `ALTER DYNAMIC TABLE ... MODIFY COLUMN CLICKS SET MASKING POLICY MASK_ENGAGEMENT_CLICKS` | 67,156 | 0 | Attaching the policy to the dynamic table works. |
| `TMP_DT_MASK_B`: policy named in the `CREATE` column list, `clicks WITH MASKING POLICY MASK_ENGAGEMENT_CLICKS` | 67,156 | 0 | The policy can be attached at creation. |
| `TMP_DT_SYNTAX`: the real column list with `TARGET_LAG`, `WAREHOUSE` and `COMMENT`, and the real join, but a constant instead of `AI_SENTIMENT` | 975 rows, sum 539,787 | not read | The exact statement shape from `19_dynamic_table.sql` is valid. `POLICY_REFERENCES` listed `CLICKS` with `MASK_ENGAGEMENT_CLICKS`. |

- **Timing is not covered.** The refresh history of `TMP_DT_MASK_A` showed only the creation build right after the `ALTER`. The reinitialize on the real table came about 28 minutes after its policy change, at the next scheduled refresh, so I can't say whether the `ALTER` form triggers one later. The create-time form avoids the question.

**`19_dynamic_table.sql` run as written (run on 2026-11-22; `created_on` is 2026-11-21 21:56 UTC-8; policy already on the source column).** The file replaced the existing table. It ran as `SNOWFLAKE_INTELLIGENCE_ADMIN` with secondary roles off for the checks.

| Check | Result | Confirms |
|---|---|---|
| Statement | `Dynamic table ENRICHED_MARKETING_INTELLIGENCE successfully created.`, 975 rows, `refresh_mode` `ADAPTIVE`, `target_lag` 1 hour | The column list, the policy clause, `COMMENT` and the lab query are valid together. |
| `POLICY_REFERENCES` for `MASK_ENGAGEMENT_CLICKS` | `MARKETING_CAMPAIGN_METRICS.CLICKS` and `ENRICHED_MARKETING_INTELLIGENCE.CLICKS` | The policy is on both columns. |
| Newest refresh | `REINITIALIZE`, trigger `CREATION`, `SUCCEEDED`, query `01c89344-0109-9f39-0005-a7b60008e5ce` | One build at creation. |
| Admin role | 975 rows, sum of `clicks` 539,787, `avg_sentiment` 0 to 1 | The owner sees real clicks. |
| Marketing role (temporary `SELECT` grant, revoked afterwards) | 975 rows, sum 0, max 0 | The mask is enforced on the dynamic table. |
| Rows per product | 84 / 660 / 105 / 84 / 42 | Same as before. |

- **Pending.** The AI usage row for that query was not in `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` yet (the view lags by hours). Expected cost is the earlier 0.8986 credits. Check later.
- **Checked later (2026-11-22, 07:54 UTC-8).** The six refreshes after the build are all `NO_DATA` with trigger `SCHEDULED`, the latest at 2026-11-22 07:54 UTC-8, and none is a `REINITIALIZE`. The policy-first order builds the table once. The sum of `avg_sentiment` for `Cyclone Helmet` in this table is 35, not the 29 of the earlier table.
- **Not tested.** Rebuilding from nothing, which is the rebuild test.

## 12. A semantic view over the tables

Created and checked on 2026-11-22. The file ran once and succeeded on the first try.
```sql
SHOW SEMANTIC VIEWS IN SCHEMA DASH_DB_SI.RETAIL;
SHOW SEMANTIC DIMENSIONS IN SEMANTIC_VIEW;
SHOW SEMANTIC METRICS IN SEMANTIC_VIEW;
SHOW SEMANTIC FACTS IN SEMANTIC_VIEW;
SELECT * FROM SEMANTIC_VIEW(SEMANTIC_VIEW METRICS MARKETING_CAMPAIGN_METRICS.TOTAL_CLICKS DIMENSIONS MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME) ORDER BY TOTAL_CLICKS DESC LIMIT 5;
SELECT * FROM SEMANTIC_VIEW(SEMANTIC_VIEW METRICS MARKETING_CAMPAIGN_METRICS.TOTAL_CLICKS, ENRICHED_MARKETING_INTELLIGENCE.AVERAGE_SENTIMENT DIMENSIONS MARKETING_CAMPAIGN_METRICS.CATEGORY) ORDER BY 1;
SELECT * FROM SEMANTIC_VIEW(SEMANTIC_VIEW METRICS SALES.TOTAL_SALES_AMOUNT DIMENSIONS PRODUCTS.PRODUCT_NAME) ORDER BY 2 DESC;
```

| Check | Result | Confirms |
|---|---|---|
| `SHOW SEMANTIC VIEWS` | `SEMANTIC_VIEW`, owner `SNOWFLAKE_INTELLIGENCE_ADMIN`, schema `RETAIL` | The view exists in the schema the lab names. |
| Dimensions, metrics, facts | 20, 6 and 7 | Matches the file: every column once, six metrics. |
| Top 5 campaigns by clicks | 11103, 10966, 10099, 9476, 6799 | Answers the lab's first question. The lab expects 11103 for the top row. |
| Clicks by category with average sentiment (uses `ENRICHED_TO_CAMPAIGN`) | 7058, 10108, 11186, 12753, 26051, summing to 67,156 | The join through the dynamic table did not multiply the click totals. 67,156 equals the sum in section 10. |
| Average sentiment by category | 0.417, 0.2, 0.25, 0.5, 0.2 | The relationship returns the dynamic table's scores. |
| Sales by product name (uses `SALES_TO_PRODUCTS`) | Totals per product, 40 products | The second relationship joins. |

- **Not tested.** Whether Snowsight's Autopilot would build the same view. I did not run it.
- **Not tested.** A query through the view as `MARKETING_INTELLIGENCE_ROLE`. That role has no grant on the view. It belongs to the agent section.
- **Key is not unique.** `CATEGORY` has 21 to 44 rows per value in `MARKETING_CAMPAIGN_METRICS`. Snowflake accepted the key without a check.

## 13. A search service over the campaign names

Created and checked on 2026-11-22. There are two files that create the same service. Both ran from the files. After the checks, `21_search_service.sql` (version 1) was run again, so version 1 is what is deployed. Replacing a service drops its grants, so no role but the owner has `USAGE`.

### Version 1, `21_search_service.sql`
```sql
DESCRIBE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH;
SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW('DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH', '{"query":"summer","columns":["CAMPAIGN_NAME","CLICKS"],"limit":2}');
GRANT USAGE ON CORTEX SEARCH SERVICE CAMPAIGN_SEARCH TO ROLE MARKETING_INTELLIGENCE_ROLE;
-- as MARKETING_INTELLIGENCE_ROLE, secondary roles off: the same SEARCH_PREVIEW
REVOKE USAGE ON CORTEX SEARCH SERVICE CAMPAIGN_SEARCH FROM ROLE MARKETING_INTELLIGENCE_ROLE;
```

| Check | Result | Confirms |
|---|---|---|
| `DESCRIBE` | `ACTIVE`, `ACTIVE`, 128 rows | The service is serving. |
| Search "summer" as admin | First hit `Summer Blitz`, clicks 687 | Search works. An earlier run of the same service returned 687, 468, 871 and 661. |
| Same search as the marketing role | First hit `Summer Blitz`, clicks 687 | **The masking policy does not apply to the search service.** The table returns 0 to that role. |
| `REVOKE` | 1 object affected (earlier run) | The test grant is gone. |
| `SHOW CORTEX SEARCH SERVICES` | model `snowflake-arctic-embed-m-v1.5`, lag 1 day, warehouse `DASH_WH_SI` | The settings match the file. The model is the default. |

### Version 2, `21a_search_service_governed.sql`
```sql
SELECT CAMPAIGN_NAME, CLICKS FROM TABLE(CORTEX_SEARCH_RETRIEVE(service_name => 'DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH', query => 'summer', limit => 4));
-- the same as MARKETING_INTELLIGENCE_ROLE, after granting it USAGE on the service
```

| Check | Result | Confirms |
|---|---|---|
| `DESCRIBE` | `ACTIVE`, `ACTIVE`, 128 rows | The service is serving. |
| `CORTEX_SEARCH_RETRIEVE` as admin | clicks 889, 468, 871, 483 | The owner sees the real numbers. |
| The same as the marketing role (secondary roles off, `USAGE` on the service only, no `SELECT` on the table) | clicks 0, 0, 0, 0 | The mask applies to the caller. |
| `SEARCH_PREVIEW` as the marketing role | Error 390400: REST APIs, including `SEARCH_PREVIEW`, are not supported for services with `INHERIT_DATA_GOVERNANCE_POLICIES = TRUE` | Only the SQL functions and agents can query it. Seen on a temporary service with the same settings. I did not repeat it on the file's service. |

The first attempt at the marketing query used `LISTAGG` over the function's output and failed with a compile error ("`METADATA$REQUEST_ID` is not a valid group by expression"). The plain `SELECT` above works.

**Agent test** on a temporary service with the version 2 settings and a temporary agent `TMP_AGENT_GOV` (only a `cortex_search` tool, `max_results` 4, `id_column` `CAMPAIGN_NAME`). It was run with `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` as each role, secondary roles off, with the question "Search for Summer Blitz campaigns and list the clicks for each result." The marketing role had `USAGE` on the agent and the service, and nothing else on the table.

| Run | What the search tool returned | Agent's answer |
|---|---|---|
| `title_column: CATEGORY`, admin | `CAMPAIGN_NAME` and `CATEGORY` only | `CLICKS` "not returned". The tool returns only the ID and title columns. |
| `title_column: CATEGORY`, marketing | the same | the same |
| `title_column: CLICKS`, admin | `CLICKS` 889, 468, 871, 483 and so on | Ten rows, total 7,003 clicks. |
| `title_column: CLICKS`, marketing | `CLICKS` 0 in every row | Ten rows, all 0, with a remark that this may mean missing data. |

- **Result.** An agent can use a governed service, and the mask applies to the role that runs the agent. With the lab's title column, the marketing role gets 0 and the admin gets the real numbers.
- **Side finding.** The agent returned 10 results although `max_results` was 4.
- **Cleanup.** The temporary agent and service were dropped.
- **Not tested.** Version 2 with the real `MarketingAgent`. That comes in section 14.
- **Grader check.** The lab's grader counts services owned by `SNOWFLAKE_INTELLIGENCE_ADMIN` (BWZA06, expects at least 1). My copy of that query returned 1 with version 1 deployed, and the other five local checks returned 2, 7, 6, 1 and 1, all matching. Either version satisfies it, since both create one service with that owner.

## 14. The agent

Created and checked on 2026-11-22 with `snow sql -f projects/03-zero-to-agents/sql/22_agent.sql`. The file succeeded on the first try. The search service deployed at the time was version 1 (`21_search_service.sql`).
```sql
DESCRIBE AGENT MarketingAgent;
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('DASH_DB_SI.RETAIL.MARKETINGAGENT', $${"parent_message_id":0,"messages":[{"role":"user","content":[{"type":"text","text":"What are the top 5 campaigns by clicks?"}]}]}$$);
```

| Check | Result | Confirms |
|---|---|---|
| `CREATE AGENT` | `Agent MARKETINGAGENT successfully created.` | The specification parsed: tool types, `tool_resources` keys and the `procedure` type are accepted. |
| `DESCRIBE AGENT` | name `MARKETINGAGENT`, schema `DASH_DB_SI.RETAIL`, owner `SNOWFLAKE_INTELLIGENCE_ADMIN` | The agent exists with the right owner. |
| Run as `SNOWFLAKE_INTELLIGENCE_ADMIN`: "What are the top 5 campaigns by clicks?" | Tools used: SQL on the semantic view, then `data_to_chart`. Rows: 11103, 10966, 10099, 9476, 6799 | The analyst tool works and matches section 12. The chart confirms the orchestration instruction. |

- **Not tested.**
  - The `Search` tool inside this agent. The test question did not need it. The same tool settings were tested in section 13 on a temporary agent.
  - The `Send_Email` tool, including whether the identifier `DASH_DB_SI.RETAIL.SEND_EMAIL` without an argument list resolves. Testing it sends a real email.
  - Any access for `MARKETING_INTELLIGENCE_ROLE`. It has no grant on the agent, the semantic view or the search service.
  - Whether the agent shows up in the Snowflake Intelligence page in Snowsight.
- **The SQL function is a test route.** `DATA_AGENT_RUN` is a wrapper around the agent REST API. Snowflake recommends the REST API for applications.

## 15. Asking the agent the validation questions

Run on 2026-11-22 as `SNOWFLAKE_INTELLIGENCE_ADMIN` with secondary roles off, using `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` on `DASH_DB_SI.RETAIL.MARKETINGAGENT`, one call per question, each in a new thread. Version 1 of the search service was deployed.

| Question | Result | Confirms |
|---|---|---|
| 1. Top 5 campaigns by clicks | SQL on `MARKETING_CAMPAIGN_METRICS` through the semantic view. Rows 11103, 10966, 10099, 9476, 6799, then a chart. | The analyst tool works and matches section 12. |
| 2. Campaign metrics and the product relationship | Agent's reasoning: group by campaign and category, join sentiment separately. 41 campaign and product pairs from 8 campaigns and 5 products, a chart. | The agent works around the dynamic table's repeated rows. |
| 3. Clicks and satisfaction by category | Fitness Wear 26,051 clicks, sentiment 0.20, 15 cases. UltraRunner Shoes 12,753 clicks, sentiment 0.50, 2 cases. Correlation about -0.42 over 5 categories. | The join to sentiment works, and the clicks are not multiplied by the repeated rows. |
| 4. Main complaints in support cases | SQL with `AI_AGG` over 30 transcripts. Tears along the seams (ThermoJacket Pro, 15 cases), leaking lids (HydraBottle 2L, 5), smell and grip (PowerYoga Mat, 4), loose padding (Cyclone Helmet, 4). | The agent reads transcripts through the semantic view. |
| 5. Campaigns with summer in the name | `Search` called with query "summer", limit 50. Then SQL: Summer Fitness Campaign 11,103 (23 days), Summer Blitz 10,099 (15 days). | The search tool works inside the agent. The first hits had `doc_title` set to the clicks (687, 468, ...), which is the title column. |
| 6a. Email the top 5 to an address that is on no user in the account | `Send_Email` called with an HTML body. The procedure returned an error: recipients at index 1 are not allowed. | The tool and the procedure identifier work. Snowflake only sends to addresses saved on a user. |
| 6b. Email the top 5 to the address on user `MIDEGA` (from `SHOW USERS`, run as `SECURITYADMIN`) | `Send_Email` called with subject "Top 5 Campaigns by Clicks". The procedure returned `Email sent successfully`. | The agent's email tool works end to end. A direct `CALL SEND_EMAIL(...)` to the same address also returned `Email sent successfully` earlier. The user confirmed on 2026-11-22 that the email arrived at that address. |

- **Email cause for 6a.** `DESCRIBE NOTIFICATION INTEGRATION EMAIL_INTEGRATION` shows `ALLOWED_RECIPIENTS` empty, so only addresses saved on users in the account are accepted. The address I used in 6a was not on `MIDEGA`.
- **`max_results`.** The search tool ran with a limit of 50, not the 4 in the spec. This was also seen in section 13.
- **Not measured.** Credits for these runs, and what Snowsight shows in its trace view.
- **Not tested.** `MARKETING_INTELLIGENCE_ROLE` running the agent. Version 2 of the search service with this agent.

## 16. The auto-grader

Run on 2026-11-22 with `snow sql -f projects/03-zero-to-agents/grader/workshop_greeting.sql`. The file is kept in `grader/`, outside `sql/`, so it only runs when asked. It is the one file that uses `ACCOUNTADMIN`: it creates an API integration, which needs that role. Version 1 of the search service and `MarketingAgent` were deployed.

| Step | Actual | Expected | Result |
|---|---|---|---|
| `AUTO_GRADER_IS_WORKING` | 123 | 123 | passed |
| `BWZA01` databases | 2 | 2 | passed |
| `BWZA02` stages | 7 | 7 | passed |
| `BWZA03` tables | 6 | 6 | passed |
| `BWZA04` role | 1 | 1 | passed |
| `BWZA05` semantic views owned by the admin role | 1 | at least 1 | passed |
| `BWZA06` search services owned by the admin role | 1 | at least 1 | passed |

- **Greeting.** `greeting` returned the account locator and the name and email given. The final query printed "You've successfully completed the From Zero to Agents lab!".
- **Left behind.** The script created API integration `DORA_API_INTEGRATION` and database `UTIL_DB` (with functions `GRADER` and `GREETING`). They were dropped afterwards with `grader/workshop_greeting_cleanup.sql` (see the grader cleanup appendix below). A rebuild from nothing runs the grader file again.
- **Not graded.** The agent. The six checks look only at databases, stages, tables, the role, the semantic view and the search service.

## Appendix. Scoring each support case once

Built on 2026-11-22 with `snow sql -f projects/03-zero-to-agents/sql/23_appendix_case_scores.sql`. The file succeeded on the first try.

| Check | Result | Confirms |
|---|---|---|
| Statements | Both dynamic tables created. `SHOW DYNAMIC TABLES`: `CASE_SENTIMENT` 30 rows, target lag `DOWNSTREAM`, `ADAPTIVE`. `ENRICHED_MARKETING_INTELLIGENCE_BY_CASE` 975 rows, 1 hour, `ADAPTIVE`. | The column lists, the `DOWNSTREAM` lag and the policy clause are valid. |
| Create statements (query IDs, both `CREATE_TABLE_AS_SELECT`) | `01c895b6-0209-9b1d-0005-a7b60009babe` (3,379 ms) and `01c895b6-0209-9b1d-0005-a7b60009bac6` (2,127 ms) | IDs for the usage check below. |
| Refresh history, `CASE_SENTIMENT` | `INCREMENTAL` with trigger `CREATION`, then `NO_DATA` | One build. |
| Refresh history, `ENRICHED_MARKETING_INTELLIGENCE_BY_CASE` | `REINITIALIZE` with trigger `CREATION` | One build. |
| Per product, rows | 84 / 660 / 105 / 84 / 42, the same as the section 11 table | The join gives the same rows. |
| Per product, sum of `clicks` (admin role) | 28,232 / 390,765 / 50,540 / 44,744 / 25,506, total 539,787, the same as the section 11 table | The owner sees real clicks. |
| Per product, sum of `avg_sentiment` | Cyclone Helmet 21, Fitness Wear 132, HydraBottle 2L 21, PowerYoga Mat 21, UltraRunner Shoes 21 (total 216). Section 11 table: 35, 132, 21, 21, 21 (total 230). | Four products agree. `Cyclone Helmet` differs because its section 11 sum is not a multiple of 21. |
| `CASE_SENTIMENT` per product: cases and sum of scores | Cyclone Helmet 4 and 1, Fitness Wear 15 and 3, HydraBottle 2L 5 and 1, PowerYoga Mat 4 and 1, UltraRunner Shoes 2 and 1 | Each by-case sum is the case-score sum times the marketing rows (21, 44, 21, 21, 21). For example 3 x 44 = 132. |
| Marketing role (temporary `SELECT` grant, secondary roles off) | 975 rows, sum of `clicks` 0, min 0, max 0 | The mask is enforced on the new table. |
| `SHOW GRANTS` after `REVOKE` | Only `OWNERSHIP` for `SNOWFLAKE_INTELLIGENCE_ADMIN` | The temporary grant is gone. |

- **Section 11 table is unchanged.** Its refresh history since the build is `NO_DATA`, and its `Cyclone Helmet` sum is still 35.
- **Not measured.** AI credits for the two builds, which the usage view will show after its lag. Expected about 0.03.
- **Not tested.** Pointing the semantic view and the agent at the new table. Whether `CASE_SENTIMENT` refreshes only the new case when a case is added.

## Appendix. Grader cleanup

Run on 2026-11-22 with `snow sql -f projects/03-zero-to-agents/grader/workshop_greeting_cleanup.sql`, after the grader in section 16.

| Check | Result | Confirms |
|---|---|---|
| Statements | `UTIL_DB successfully dropped.` and `DORA_API_INTEGRATION successfully dropped.` | Both objects existed and are gone. |
| `SHOW DATABASES LIKE 'UTIL_DB'` and `SHOW API INTEGRATIONS LIKE 'DORA_API_INTEGRATION'` | `No data` for both | Nothing is left. |

- **They came from the grader.** The grader's own output said `Integration DORA_API_INTEGRATION successfully created.` and `Database UTIL_DB successfully created.`, so neither existed before it ran.
