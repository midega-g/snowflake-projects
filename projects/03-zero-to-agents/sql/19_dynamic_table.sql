-- Section 11: live enrichment pipeline. Run after 17_masking_policy.sql, so the table is built once.
-- Cost: every full build runs AI_SENTIMENT once per joined row (975 rows, about 0.9 AI credits).
-- Running this file again re-creates the table and pays that again.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

-- A dynamic table does not inherit the mask on its source column, so CLICKS gets the policy here too.
CREATE OR REPLACE DYNAMIC TABLE ENRICHED_MARKETING_INTELLIGENCE (
  campaign_name,
  clicks WITH MASKING POLICY MASK_ENGAGEMENT_CLICKS,
  product_name,
  avg_sentiment
)
TARGET_LAG = '1 hours'
WAREHOUSE = DASH_WH_SI
COMMENT = 'Support cases joined to marketing campaigns by category, with AI sentiment. Refreshes within 1 hour.'
AS
SELECT m.campaign_name, m.clicks, s.product AS product_name,
       CASE AI_SENTIMENT(s.transcript):categories[0]:sentiment::STRING
            WHEN 'positive' THEN 1
            WHEN 'negative' THEN -1
            ELSE 0
       END AS avg_sentiment
FROM marketing_campaign_metrics m
JOIN support_cases s ON m.category = s.product;

SHOW DYNAMIC TABLES IN SCHEMA DASH_DB_SI.RETAIL;
SELECT COUNT(*) AS ROWS_LOADED FROM ENRICHED_MARKETING_INTELLIGENCE;
