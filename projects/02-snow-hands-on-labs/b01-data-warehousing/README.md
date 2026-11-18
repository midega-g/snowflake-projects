# 02-snow-hands-on-labs / b01 - Data Warehousing

Badge 1. Shared setup and lab exceptions: `../README.md`. Commands, errors and reasoning: `LAB_NOTES.md`.

## How this lab was set up
Started from the `01-dbt-tutorial` layout, then reduced. Provisioning scripts (`bootstrap.sh`, `bootstrap.conf`, `roles.csv`, `schemas.csv`) are not used for now: no project roles, warehouse or monitor have been created.

| Item | State |
|---|---|
| Database | `DEMO_DB`, created by ACCOUNTADMIN, ownership transferred to SYSADMIN (`sql/02_demo_db.sql`) |
| Roles | No custom roles. Work as SYSADMIN. Add `<PROJ>_ADMIN`/`<PROJ>_READER` only when access separation is needed |
| Query tag | Set on the connection and in worksheets: `{"project":"snow-hol-b01-data-warehousing","env":"dev","tool":"snow","owner":"midega-g"}` |
| Warehouse | None of its own. The shared `COMPUTE_WH` was created in b05 and is the user default |

## Authentication
The CLI uses key-pair auth (`SNOWFLAKE_JWT`) because the web UI login is Google sign-in. `SNOWFLAKE_USER` must be the login name. See `LAB_NOTES.md` for the steps.

ACCOUNTADMIN is used once, in `sql/02_demo_db.sql`, and is not the session default.

## Files
- `badge.env`: badge name and connection name, layered on the shared `../.env`.
- `sql/01_session.sql`: worksheet header (role and query tag).
- `sql/02_demo_db.sql`: creates `DEMO_DB` and transfers ownership.
- `LAB_NOTES.md`: commands, problems hit, fixes and reasoning.

## Run it
```bash
P=02-snow-hands-on-labs/b01-data-warehousing
source scripts/use-project.sh $P
snow connection test
snow sql -f projects/$P/sql/02_demo_db.sql
```
