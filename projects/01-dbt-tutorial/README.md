# 01 - dbt tutorial
Objects: DB `DBT_TUT_DEV` (RAW/STAGING/MARTS/GOVERNANCE), WH `DBT_TUT_WH` (XSMALL, 60s), roles `DBT_TUT_{ADMIN,TRANSFORMER,READER}`, monitor `DBT_TUT_RM` (5 credits/mo).
Flow: `.env` + `bootstrap.conf`/`roles.csv`/`schemas.csv` -> `scripts/bootstrap.sh 01-dbt-tutorial` -> `source scripts/use-project.sh 01-dbt-tutorial` -> work as TRANSFORMER.
dbt: copy `dbt/profiles.yml.example` to `~/.dbt/profiles.yml` (or set `DBT_PROFILES_DIR`).
