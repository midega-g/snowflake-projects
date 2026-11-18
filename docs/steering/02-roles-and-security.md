# Roles & security
- Hierarchy: `ACCOUNTADMIN` (bootstrap only) > `SYSADMIN` owns DB/WH via project admin > `<PROJ>_ADMIN` > `<PROJ>_TRANSFORMER` / `<PROJ>_READER`.
- Grant every project role to `SYSADMIN` so objects stay manageable.
- Your human user: default role = `<PROJ>_TRANSFORMER`, not ACCOUNTADMIN. Set with `ALTER USER ... SET DEFAULT_ROLE`.
- Enable MFA on the human user; prefer key-pair auth for CLI/dbt (private key outside the repo, `chmod 600`).
- Use `FUTURE GRANTS` rather than per-object grants.
