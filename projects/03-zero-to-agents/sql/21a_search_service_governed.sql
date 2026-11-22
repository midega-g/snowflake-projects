-- Section 13, alternative: the same service, but it honors the masking policy on CLICKS.
-- Run after 20_semantic_view.sql, instead of 21_search_service.sql. Both create CAMPAIGN_SEARCH.
-- Differences from the lab version:
--   * INHERIT_DATA_GOVERNANCE_POLICIES = TRUE applies the table's masking policy to the role that searches.
--   * That setting needs a primary key. ROW_ID is built from the three columns that are unique together (128 of 128 rows).
--   * SEARCH_PREVIEW, the REST API and the Python API do not work on such a service. Agents and
--     the SQL functions CORTEX_SEARCH_RETRIEVE and CORTEX_SEARCH_BATCH do.
--   * The source query runs again on every search, so keep it simple.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE CORTEX SEARCH SERVICE CAMPAIGN_SEARCH
  ON CAMPAIGN_NAME
  PRIMARY KEY (ROW_ID)
  ATTRIBUTES DATE, CATEGORY, IMPRESSIONS, CLICKS
  WAREHOUSE = DASH_WH_SI
  TARGET_LAG = '1 day'
  INHERIT_DATA_GOVERNANCE_POLICIES = TRUE
  COMMENT = 'Text search over campaign names in MARKETING_CAMPAIGN_METRICS. Used by MarketingAgent. Governed version: CLICKS is masked per role.'
  AS (
    SELECT CAMPAIGN_NAME || '|' || CATEGORY || '|' || TO_VARCHAR(DATE) AS ROW_ID,
           CAMPAIGN_NAME, DATE, CATEGORY, IMPRESSIONS, CLICKS
    FROM MARKETING_CAMPAIGN_METRICS
  );

SHOW CORTEX SEARCH SERVICES IN SCHEMA DASH_DB_SI.RETAIL;
