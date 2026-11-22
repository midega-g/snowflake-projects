-- Appendix to section 11: score each support case once, then join the scores to the campaigns.
-- It builds two new dynamic tables and leaves ENRICHED_MARKETING_INTELLIGENCE (file 19) as it is.
-- Cost: AI_SENTIMENT runs 30 times (once per case) instead of 975 times, about 0.03 AI credits per full build.
-- Run after 17_masking_policy.sql and 19_dynamic_table.sql.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

-- One row per support case. DOWNSTREAM means it refreshes when the table below needs it.
CREATE OR REPLACE DYNAMIC TABLE CASE_SENTIMENT (
  id,
  product,
  sentiment_score
)
TARGET_LAG = DOWNSTREAM
WAREHOUSE = DASH_WH_SI
COMMENT = 'One AI_SENTIMENT score per support case: 1 positive, -1 negative, 0 otherwise.'
AS
SELECT id, product,
       CASE AI_SENTIMENT(transcript):categories[0]:sentiment::STRING
            WHEN 'positive' THEN 1
            WHEN 'negative' THEN -1
            ELSE 0
       END
FROM support_cases;

-- Same columns and rows as ENRICHED_MARKETING_INTELLIGENCE, with no AI function in the query.
CREATE OR REPLACE DYNAMIC TABLE ENRICHED_MARKETING_INTELLIGENCE_BY_CASE (
  campaign_name,
  clicks WITH MASKING POLICY MASK_ENGAGEMENT_CLICKS,
  product_name,
  avg_sentiment
)
TARGET_LAG = '1 hours'
WAREHOUSE = DASH_WH_SI
COMMENT = 'Campaigns joined to the per-case scores in CASE_SENTIMENT. Refreshes within 1 hour.'
AS
SELECT m.campaign_name, m.clicks, c.product, c.sentiment_score
FROM marketing_campaign_metrics m
JOIN case_sentiment c ON m.category = c.product;

SHOW DYNAMIC TABLES IN SCHEMA DASH_DB_SI.RETAIL;
SELECT COUNT(*) AS CASES_SCORED FROM CASE_SENTIMENT;
SELECT COUNT(*) AS ROWS_LOADED FROM ENRICHED_MARKETING_INTELLIGENCE_BY_CASE;
