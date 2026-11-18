# 02 - Snowflake Hands-On Labs

Five badge labs, pure Snowflake (no dbt). Each badge is a mini project in its own folder, and the badges are done in no fixed order.

| Folder | Badge | Main objects |
|---|---|---|
| `b01-data-warehousing/` | 1 - Data Warehousing | `DEMO_DB` |
| `b05-data-engineering/` | 5 - Data Engineering | `COMPUTE_WH` + `COMPUTE_WH_RM`, `UTIL_DB`, `DORA_API_INTEGRATION`, DORA `GRADER` (test passed), user defaults |

## Shared vs per-badge config
| File | Where | Committed | Holds |
|---|---|---|---|
| `.env.example` | here | yes | Template for `.env` |
| `.env` | here | **no** (gitignored, `chmod 600`) | Account, login name, private key path, role: the same for every badge |
| `connections.toml.template` | here | yes | Connection layout used by all badges (key-pair auth + query tag) |
| `badge.env` | each badge | yes, no secrets | `PROJECT_NAME` (query tag) and `PROJECT_CONN` (connection name) |

`source scripts/use-project.sh 02-snow-hands-on-labs/<badge>` loads `./.env` and then `<badge>/badge.env`, so the later file wins. It renders `<badge>/.snowflake/connections.toml` (gitignored) from the nearest template. To change a setting for one badge only, add it to that badge's `badge.env`.

## First-time setup
1. Account values: in Snowsight, open the user menu, then **Account > View account details**. Use the **login name** for `SNOWFLAKE_USER`.
2. `cp .env.example .env` and fill it in.
3. Key pair and `ALTER USER ... SET RSA_PUBLIC_KEY`: see `b01-data-warehousing/LAB_NOTES.md`, sections 3-4. One key pair serves every badge.
4. Run:
   ```bash
   source scripts/use-project.sh 02-snow-hands-on-labs/b05-data-engineering
   snow connection test
   ```

## Lab exceptions to `docs/steering/`
The labs dictate object names and settings, so these rules are relaxed for this project only:
- **`COMPUTE_WH` is used** (steering says a dedicated `<PROJ>_WH`). The lab graders expect it.
- **Names come from the lab** (`DEMO_DB`, `UTIL_DB`) rather than `<PROJ>_<ENV>`.
- **No custom roles.** Work happens as SYSADMIN. Query tags give the cost tracking.
- **Account-wide settings can change per badge.** A badge may change shared objects or user defaults, for example the user default role or the resource monitor quota. The badge's `LAB_NOTES.md` records the change.

These still apply: XSMALL, `AUTO_SUSPEND=60`, `AUTO_RESUME`, a resource monitor on the warehouse (currently 15 credits/week), a query tag per badge, ACCOUNTADMIN only inside setup scripts, and no secrets in git.
