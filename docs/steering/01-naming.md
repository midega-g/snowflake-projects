# Naming (UPPER_SNAKE_CASE in Snowflake)
| Object | Pattern | Example |
|---|---|---|
| Database | `<PROJ>_<ENV>` | `DBT_TUT_DEV` |
| Warehouse | `<PROJ>_WH` | `DBT_TUT_WH` |
| Role (owner) | `<PROJ>_ADMIN` | `DBT_TUT_ADMIN` |
| Role (dbt/transform) | `<PROJ>_TRANSFORMER` | `DBT_TUT_TRANSFORMER` |
| Role (read) | `<PROJ>_READER` | `DBT_TUT_READER` |
| User (service) | `SVC_<PROJ>_<TOOL>` | `SVC_DBT_TUT_DBT` |
| Schemas | `RAW`, `STAGING`, `MARTS` | |
| Tag | `<PROJ>_<DIMENSION>` | `COST_CENTER` |
| Project folder | `NN-kebab-name` | `01-dbt-tutorial` |
