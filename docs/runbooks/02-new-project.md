# New project
1. `cp -r projects/01-dbt-tutorial projects/NN-name` (delete `.env`, `.snowflake/`).
2. Change in `bootstrap.conf`: PROJECT_KEY, names (RM/WH/DB), sizes, MY_USER, CONNECTION. Edit `roles.csv`, `schemas.csv`. Update `.env.example` and `connections.toml.template` names.
3. Multi-part project (like `02-snow-hands-on-labs`): keep shared `.env`, `.env.example`, `connections.toml.template` in the project folder, and give each sub-project a committed `badge.env` with only what differs (`PROJECT_NAME`, `PROJECT_CONN`). `use-project.sh <proj>/<sub>` sources each `.env` then `badge.env` from `projects/` down to the target (later wins) and uses the nearest template.
4. Run `pre-commit run --all-files` before the first commit of the new project.
5. Follow `03-bootstrap.md`. Shared SQL lives in `bootstrap/`; never copy it into the project unless overriding a step.
