-- Section 8 (optional, read-only): what the AI functions query in 14_ai_enrichment.sql cost.
-- Finds every run of that SELECT by its text, so no query IDs are needed. Run it after the
-- query has run at least once. Account Usage views lag, so a recent run can show NULLs.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;

-- Per run: AI credits (billed by tokens, whatever the warehouse size) next to warehouse credits.
-- WH_CREDITS_CALC = execution time x the size's hourly credit rate, with no 60 s resume minimum.
-- WH_CREDITS_ATTRIBUTED = the figure Snowflake attributes to the query (can take hours to appear).
WITH runs AS (
    SELECT query_id, start_time, warehouse_size, execution_time, total_elapsed_time
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE warehouse_name = 'DASH_WH_SI'
      AND execution_status = 'SUCCESS'
      AND query_text ILIKE 'SELECT%AI_SENTIMENT(TRANSCRIPT):categories[0]%'
      AND query_text ILIKE '%FROM SUPPORT_CASES%'
      AND query_text NOT ILIKE '%ACCOUNT_USAGE%'
), ai AS (
    SELECT query_id,
           SUM(credits)                       AS ai_credits,
           SUM(metrics[0]:value::NUMBER)      AS tokens
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
    GROUP BY query_id
)
SELECT r.start_time,
       r.warehouse_size,
       r.execution_time                       AS execution_ms,
       ai.tokens,
       ai.ai_credits,
       r.execution_time / 3600000 * DECODE(r.warehouse_size,
           'X-Small', 1, 'Small', 2, 'Medium', 4, 'Large', 8, 'X-Large', 16) AS wh_credits_calc,
       a.credits_attributed_compute           AS wh_credits_attributed
FROM runs r
LEFT JOIN ai ON ai.query_id = r.query_id
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY a ON a.query_id = r.query_id
ORDER BY r.start_time;

-- Per function, for the same runs.
SELECT u.query_id, u.function_name, u.credits, u.metrics[0]:value::NUMBER AS tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY u
WHERE u.query_id IN (
    SELECT query_id FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE warehouse_name = 'DASH_WH_SI'
      AND query_text ILIKE 'SELECT%AI_SENTIMENT(TRANSCRIPT):categories[0]%'
      AND query_text NOT ILIKE '%ACCOUNT_USAGE%')
ORDER BY u.start_time, u.query_id, u.function_name;

-- Warehouse credits billed per hour, which include the 60 s minimum each time the warehouse resumes.
SELECT start_time, credits_used_compute
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'DASH_WH_SI' AND credits_used_compute > 0
ORDER BY start_time;
