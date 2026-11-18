# Bootstrap a project
`scripts/bootstrap.sh <project> [--phase 1|2|all] [--step NAME] [--dry-run]`
Run `--dry-run` first. Steps are idempotent (`IF NOT EXISTS`).

Phase 1 (independent, parameterised): `roles` -> `resource_monitor` -> `warehouse`. Driven by RM_*, WH_*, `roles.csv`.
Phase 2 (project-dependent): `database` -> `schemas` -> `grants` -> `tags` -> `user_defaults`. Driven by DB_*, `schemas.csv`, roles' access columns.
Re-run one step: `--step schemas`.

Optional behaviour (instead of commenting SQL out):
- Skip a step: remove it from PHASE1_STEPS / PHASE2_STEPS (e.g. no resource monitor).
- Opt-in step: add its name, e.g. `sample_data` (from `bootstrap/optional/`).
- Transient DB: `DB_TRANSIENT=Y`. Transient/managed schemas: columns in `schemas.csv`.
- Custom logic: put `projects/<p>/bootstrap/<name>.sql` and list `<name>` in a PHASE*_STEPS. Same name as a core step = override. All bootstrap.conf keys are available as `<% key_lowercase %>`.

Roles used: USERADMIN (roles), SYSADMIN (warehouse, database), ACCOUNTADMIN (resource monitor, drops), SECURITYADMIN (user defaults) - switched inside each template, not the session default.
