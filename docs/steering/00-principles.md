# Principles
1. Never work as ACCOUNTADMIN. Use it only for one-time bootstrap (`sql/00_bootstrap.sql`), then switch.
2. Least privilege: functional roles own nothing but grants; a project role owns the project objects.
3. Dedicated, tiny, auto-suspending warehouse per project (XSMALL, AUTO_SUSPEND=60). Never use COMPUTE_WH.
4. Every session sets a QUERY_TAG first (project, env, tool) so cost and history are attributable.
5. Everything is code: SQL/dbt in git, no click-ops without a note in the project README.
6. No secrets in git. Credentials via env vars / keypair; templates use `.example` suffix.
7. Resource monitor on every project warehouse.
