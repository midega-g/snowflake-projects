# 03 - Zero to Agents

Snowflake Intelligence setup (Cortex AI, semantic model, agent) on a new account with password auth. Source: `setup.sql` from the "From Zero to Agents" guide, split into one file per section. Notes will go in `LAB_NOTES.md` after the code has run and been debugged.

## Config
| File | Committed | Holds |
|---|---|---|
| `.env.example` | yes | Template |
| `.env` | no (`chmod 600`) | Account, login name, role, `SNOWFLAKE_PASSWORD` |
| `badge.env` | yes | `PROJECT_NAME`, `PROJECT_CONN` |
| `connections.toml.template` | yes | Password auth, no password in the file (the CLI reads `SNOWFLAKE_PASSWORD`) |

## Exceptions to `docs/steering/`
- Object names come from the guide (`DASH_DB_SI`, `DASH_WH_SI`, `SNOWFLAKE_INTELLIGENCE_ADMIN`).
- The lab says LARGE. The warehouse starts at XSMALL, is resized to LARGE for the data loading steps, and is then resized as the workload needs. `AUTO_SUSPEND=60` and the resource monitor are added because the lab is silent on them. LARGE burns 8 credits/hour, so the 10 credits/month quota is about 75 minutes at that size.
- `SNOWFLAKE_INTELLIGENCE_ADMIN` is not granted to `SYSADMIN` (the lab doesn't do it). The role is created with `IF NOT EXISTS` so a re-run doesn't drop what it owns.
- Password auth instead of key pair (trial account), so enable MFA when possible.

## Run it
```bash
P=03-zero-to-agents
source scripts/use-project.sh $P
snow connection test
for f in 02_role_and_grants 03_warehouse_and_databases 04_file_format 05_marketing_campaign_metrics \
         06_products 07_sales 08_social_media 09_support_cases 10_git_and_semantic_model \
         11_email_integration 12_cortex_cross_region 13_verify 14_ai_enrichment; do  # 15 needs -D csv_path=..., see below
  snow sql -f projects/$P/sql/$f.sql || break
done
```
After `02_role_and_grants.sql`, set `SNOWFLAKE_ROLE=SNOWFLAKE_INTELLIGENCE_ADMIN` in `.env` and re-source.

## Lab steps done in Snowsight (click-ops, per steering recorded here)
Run in this order, between the SQL files:
1. `15_load_marketing_data.sql` loads `marketing_data.csv` with `PUT` + `COPY` (no Snowsight upload needed): `snow sql -f projects/$P/sql/15_load_marketing_data.sql -D csv_path="$PWD/projects/$P/data/marketing_data.csv"`. It appends, so run it once; to redo it, recreate the table with `05` first.
2. Run `16_marketing_role_and_view.sql`, `17_masking_policy.sql` and `18_verify_masking.sql` (the security section). They come before the dynamic table so it is built once.
3. Run `19_dynamic_table.sql`.
4. Run `20_semantic_view.sql` (the lab builds this view in Snowsight; the file does the same in SQL).
5. Run `21_search_service.sql` (the lab builds this service in Snowsight; the file does the same in SQL). Alternative: `21a_search_service_governed.sql` creates the same service but applies the mask on `CLICKS` to the role that searches. Run one of the two.
6. Run `22_agent.sql` (the lab builds `MarketingAgent` in Snowsight under AI & ML > Agents; the file does the same in SQL, with the semantic view, search service and `SEND_EMAIL` tools).
7. Optional: `23_appendix_case_scores.sql` builds the same enrichment with 30 AI calls instead of 975 (appendix in `LAB_NOTES.md`).
- `OPEN_ITEMS.md` lists what is unchecked, undecided or not yet written.
- `LAB_NOTES.md` is the step-by-step guide. `VERIFICATION_NOTES.md` lists, per section, the commands used to check what was created and what each result confirms.
