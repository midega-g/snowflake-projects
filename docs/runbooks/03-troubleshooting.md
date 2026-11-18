# Troubleshooting
- Query tag empty in VS Code: run `sql/01_session.sql` first, or confirm the user-level QUERY_TAG exists (`SHOW PARAMETERS LIKE 'QUERY_TAG' IN USER <you>`).
- "Role not granted": check `SHOW GRANTS TO USER <you>`; run `bootstrap.sh <p> --step grants --step user_defaults`.
- Warehouse not resuming: `ALTER WAREHOUSE <wh> SET AUTO_RESUME=TRUE`; check resource monitor suspended it.
- gh pushes as wrong user: `gh auth switch -u midega-g` (or run `scripts/setup-git.sh`).
- Commit blocked by "Detect hardcoded secrets": betterleaks found a secret in the staged diff (shown redacted). Unstage it and move the value to `.env`. If the secret already reached a commit or the remote, rotate it in its source system first; rewriting history doesn't un-leak it. Genuine false positive only: add `# betterleaks:allow` on that line, or add its fingerprint to `.betterleaksignore`.
- `betterleaks: command not found` in the hook: install the binary (`01-first-time-setup.md` step 2) and check `~/.local/bin` is on PATH.
- Commit blocked by end-of-file / trailing-whitespace: the hook already fixed the file. `git add` it and commit again.
- Credits unexpectedly high: query tag audit (see steering/03), then `SHOW RESOURCE MONITORS`.
