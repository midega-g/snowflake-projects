# snowflake

Learning workspace for Snowflake. One folder per project under `projects/`. CLI: `snow` (snowsql is legacy and not used).

- `docs/steering/` - standing rules (naming, roles, security, tagging, git). Read before starting a project.
- `docs/runbooks/` - step-by-step procedures (setup, new project, bootstrap, teardown, troubleshooting).
- `bootstrap/` - shared, project-agnostic SQL templates (`<% var %>`, rendered by `snow sql -D`). `steps/` = core, `optional/` = opt-in.
- `scripts/` - `setup-git.sh`, `use-project.sh`, `bootstrap.sh`.
- `.pre-commit-config.yaml` - pre-commit hooks incl. betterleaks secret scan. Setup: `docs/runbooks/01-first-time-setup.md`.
- `projects/NN-name/` - per-project config only: `bootstrap.conf`, `roles.csv`, `schemas.csv`, `.env`, optional `bootstrap/*.sql` overrides.

## Quick start
```bash
./scripts/setup-git.sh                           # gh -> midega-g, git init, local identity
pre-commit install                               # hooks; needs pre-commit + betterleaks (runbook 01)
cp projects/01-dbt-tutorial/.env.example projects/01-dbt-tutorial/.env   # fill in
source scripts/use-project.sh 01-dbt-tutorial    # first in each shell: connections + session tag
scripts/bootstrap.sh 01-dbt-tutorial --dry-run   # inspect, then drop --dry-run
```
