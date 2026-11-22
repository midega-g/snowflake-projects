-- Section 10: same query as two roles. Admin sees real clicks, marketing role sees 0.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

-- COPY GRANTS keeps the SELECT grant from 17; a plain CREATE OR REPLACE would drop it.
CREATE OR REPLACE SECURE VIEW MARKETING_INTELLIGENCE_VIEW COPY GRANTS
  COMMENT = 'Secure view of marketing campaign metrics with business-friendly column names.'
AS
SELECT
    campaign_name AS "Ad Campaign",
    category AS "Product Category",
    clicks AS "Engagement Clicks",
    -- avg_sentiment will come from the Dynamic Table
    0 AS "Customer Sentiment Score"
FROM marketing_campaign_metrics;

SELECT CURRENT_ROLE() AS ROLE_NAME, "Ad Campaign", "Engagement Clicks" FROM MARKETING_INTELLIGENCE_VIEW;

-- Without this, the session also gets the privileges of every other role granted to the user.
USE SECONDARY ROLES NONE;
USE ROLE MARKETING_INTELLIGENCE_ROLE;
USE SCHEMA DASH_DB_SI.RETAIL;
SELECT CURRENT_ROLE() AS ROLE_NAME, "Ad Campaign", "Engagement Clicks" FROM MARKETING_INTELLIGENCE_VIEW;
