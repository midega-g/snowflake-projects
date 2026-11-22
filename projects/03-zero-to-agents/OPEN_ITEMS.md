# Open items

Things not yet checked or decided. Remove an item when it is resolved and the notes say so. Last updated 2026-11-22.

## Not written or not finished
- **Appendix cost.** AI usage of the two appendix builds (query IDs in the appendix block of `VERIFICATION_NOTES.md`). Expected about 0.03 credits for `CASE_SENTIMENT`. The usage view lags by hours.
- **Appendix and the agent.** The semantic view and the agent still use `ENRICHED_MARKETING_INTELLIGENCE`. Pointing them at `ENRICHED_MARKETING_INTELLIGENCE_BY_CASE` is not done or tested.
- **Agent checks left open.** Access for `MARKETING_INTELLIGENCE_ROLE` (needs grants on the agent, the semantic view and the search service), the Snowsight trace view, whether the agent appears in the Snowflake Intelligence page, version 2 of the search service with this agent, `max_results` 4 being ignored, and the AI cost of question 4 (`AI_AGG`).

## Checks waiting on time
- **AI usage of that build** (query `01c89344-0109-9f39-0005-a7b60008e5ce`) in `CORTEX_AI_FUNCTIONS_USAGE_HISTORY`. Expected 0.8986 credits.
- **XSMALL run of section 8** (query `01c88fb8-0209-9ad3-0005-a7b60007f466`): rerun `14a_ai_cost.sql` for its attributed warehouse credits and update section 8.

## Unexplained
- **Warehouse credits for the LARGE run** in section 8: 0.05997 attributed against 0.00472 calculated, about 13 times higher.

## Untested until the rebuild
- Order of the SQL files after the renumbering (`16` to `19`), and the README loop.
- `COMMENT` clauses on the objects.
- `16_marketing_role_and_view.sql` with `USE ROLE SECURITYADMIN`. Its role block was tested only on throwaway roles. If a grant fails, switch to `ACCOUNTADMIN` as the file's comment says.
- `17_masking_policy.sql` and `18_verify_masking.sql` rerun from nothing.
- The redo path of section 9: recreate the table with `05` and rerun `15`.
- `15_load_marketing_data.sql` from nothing, including its final `DROP STAGE`. Running it here would append 105 rows.

## Questions
- **Two search service files.** `21_search_service.sql` is the lab's version (CLICKS unmasked for anyone granted the service). `21a_search_service_governed.sql` applies the mask. Version 1 is deployed. Test version 2 with the real `MarketingAgent` in section 14 or 15. In the temporary test `max_results` 4 returned 10 results. The rebuild test should run both files, one after the other.
- **Grader.** To run `workshop_greeting.sql` last, as `ACCOUNTADMIN` with `snow sql` (approved for this file only). It leaves `UTIL_DB` and an API integration behind. My local copies of its six checks all pass after section 13. The agent is not graded. Not yet run against the endpoint.

- **Semantic view by hand.** Section 12 writes the view in SQL instead of Autopilot. The result was checked with `SEMANTIC_VIEW(...)` queries, not through the agent. Check the agent's answers for Q1 to Q4 before trusting the descriptions.

- **Per-case score table.** The dynamic table calls `AI_SENTIMENT` once per joined row (975 times, 0.9 credits per build) and gives one case different scores on different rows. Writing the 30 scores to their own table first would cost less and be stable. Not tested. Keep the lab query or try it?

## Housekeeping
- Nothing is committed. Use a feature branch and let pre-commit pass (steering rule 04).
- `~/Downloads/marketing_data (1).csv` is an identical copy of the file now in `data/`.
