-- Section 13, lab version: Cortex Search service on the campaign table (lab "Create a Cortex Search Service").
-- The lab builds this in Snowsight. This file writes the same service in SQL.
-- Run after 20_semantic_view.sql. Run this file or 21a_search_service_governed.sql, not both: they create the same service.
-- Warning: the service indexes the table as its owner, so the masking policy on CLICKS does not apply
-- to a role that is granted USAGE on the service. 21a_search_service_governed.sql avoids that.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH
  ON CAMPAIGN_NAME
  ATTRIBUTES DATE, CATEGORY, IMPRESSIONS, CLICKS
  WAREHOUSE = DASH_WH_SI
  TARGET_LAG = '1 day'
  COMMENT = 'Text search over campaign names in MARKETING_CAMPAIGN_METRICS. Used by MarketingAgent. Lab version: CLICKS is not masked.'
  AS (
    SELECT CAMPAIGN_NAME, DATE, CATEGORY, IMPRESSIONS, CLICKS
    FROM MARKETING_CAMPAIGN_METRICS
  );

SHOW CORTEX SEARCH SERVICES IN SCHEMA DASH_DB_SI.RETAIL;
