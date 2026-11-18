# 02-snow-hands-on-labs / b05 - Data Engineering

Badge 5. Shared setup and lab exceptions: `../README.md`. Commands, errors and reasoning: `LAB_NOTES.md`.

## Setup state
| Item | State |
|---|---|
| Warehouse | `COMPUTE_WH`: XSMALL, `AUTO_SUSPEND=60`, `AUTO_RESUME`, starts suspended, owner SYSADMIN |
| Resource monitor | `COMPUTE_WH_RM`: 15 credits/week, notify 75%, suspend 100%, suspend immediately 110%. Owner ACCOUNTADMIN |
| Database | `UTIL_DB` (home of the DORA grader function). `UTIL_DB` and `UTIL_DB.PUBLIC` are owned by SYSADMIN |
| API integration | `DORA_API_INTEGRATION` (DORA step 1): AWS API Gateway, allowlist `https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora`, owner ACCOUNTADMIN |
| Grader function | `UTIL_DB.PUBLIC.GRADER` (DORA step 2): external function via `DORA_API_INTEGRATION`, owner ACCOUNTADMIN. Connection test passed 2026-11-18, which starts the 90-day DORA window |
| Lab database | `AGS_GAME_AUDIENCE` (no `PUBLIC`), schema `RAW`: table `GAME_LOGS(RAW_LOG VARIANT)`, external stage `UNI_KISHORE` (`s3://uni-kishore`, directory table on), file format `FF_JSON_LOGS` (JSON, strip outer array), view `LOGS` (4 typed columns plus `RAW_LOG`). `GAME_LOGS` holds 534 rows: 250 from `kickoff/` and 284 from `updated_feed/`. All owned by SYSADMIN |
| User defaults | role `SYSADMIN`, warehouse `COMPUTE_WH`, namespace `UTIL_DB.PUBLIC` |
| Query tag | `{"project":"snow-hol-b05-data-engineering","env":"dev","tool":"snow","owner":"midega-g"}` |

## Files
- `badge.env`: badge name and connection name, layered on the shared `../.env`.
- `sql/01_session.sql`: worksheet header (query tag and a context check).
- `sql/02_setup.sql`: creates or enforces everything above. Idempotent.
- `sql/03_verify.sql`: shows the objects, owners, monitor and user defaults.
- `sql/04_dora_api_integration.sql`: DORA step 1, the API integration (ACCOUNTADMIN). Idempotent.
- `sql/05_dora_grader.sql`: DORA step 2, the grader external function (ACCOUNTADMIN). Safe to rerun.
- `sql/06_dora_test.sql`: DORA step 3, the connection test. Uses `COMPUTE_WH` and sends data to DORA.
- `sql/07_ags_game_audience.sql`: lab database, schema, table, stage and file format (SYSADMIN). Idempotent.
- `sql/08_ags_verify.sql`: SHOW checks and `LIST @uni_kishore/kickoff`.
- `sql/09_explore_kickoff.sql`: queries the staged file, plus a `VALIDATION_MODE` dry run.
- `sql/10_load_game_logs.sql`: COPY INTO `GAME_LOGS`. Safe to rerun (load metadata).
- `sql/11_logs_view.sql`: the first `LOGS` view (kickoff columns).
- `sql/12_time_zones.sql`: session time zone demo.
- `sql/13_load_updated_feed.sql`: checks and loads the `updated_feed/` file. Safe to rerun.
- `sql/14_filter_new_rows.sql`: returns only the `updated_feed` rows, plus a cross-check.
- `sql/15_missing_key_vs_json_null.sql`: missing key vs JSON null, on literals.
- `sql/16_copy_with_file_metadata.sql`: COPY with `METADATA$FILENAME` into a temporary table. `GAME_LOGS` is untouched.
- `sql/17_update_logs_view.sql`: replaces `LOGS`: adds `ip_address`, drops `agent`, shows only the 284 new rows.
- `sql/18_find_test_records.sql`: finds the test login and logout. Shows the timestamps are UTC.
- `data/`: local copies of lab data, gitignored.

## Run it
```bash
P=02-snow-hands-on-labs/b05-data-engineering
source scripts/use-project.sh $P
snow connection test
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
```
