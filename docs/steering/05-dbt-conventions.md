# dbt
- Layers: `staging` (views, 1:1 with source, rename/cast) -> `intermediate` -> `marts` (tables).
- Materialization set in `dbt_project.yml` per folder, not per model.
- Every model: `unique` + `not_null` test on PK. Sources declared with freshness where possible.
- Targets: `dev` (own schema per developer) and `prod`. Role = `<PROJ>_TRANSFORMER`.
- Set `query_tag` in profile so dbt queries are attributable.
