# Tagging & cost
## Session (query) tags
Set at session start, JSON string: `{"project":"dbt-tutorial","env":"dev","tool":"snow","owner":"midega-g"}`.
Applied automatically by: `snow` connection `session_parameters` (rendered into per-project `connections.toml`), user-level `QUERY_TAG` set by the `user_defaults` step, `sql/01_session.sql` (VS Code worksheet header), and dbt `query_tag` in profiles.
Audit: `SELECT query_tag, SUM(total_elapsed_time) FROM snowflake.account_usage.query_history GROUP BY 1;`
## Object tags
Created in `<PROJ>_<ENV>.GOVERNANCE`: `COST_CENTER`, `ENV`, `OWNER`. Applied to warehouse and database at bootstrap.
## Cost guards
Resource monitor (e.g. 5 credits/month, notify 75%, suspend 100%), AUTO_SUSPEND=60, XSMALL, AUTO_RESUME.
