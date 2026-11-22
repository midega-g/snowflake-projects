-- Section 12: semantic view over the five tables and the dynamic table (lab "Create a Cortex Analyst").
-- The lab builds this in Snowsight with Autopilot. This file writes the same objects by hand.
-- Run after 19_dynamic_table.sql.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE SEMANTIC VIEW SEMANTIC_VIEW
  TABLES (
    ENRICHED_MARKETING_INTELLIGENCE
      COMMENT = 'Each marketing row paired with each support case of the same product, with a sentiment score for the case.',
    MARKETING_CAMPAIGN_METRICS
      PRIMARY KEY (CATEGORY)
      COMMENT = 'Daily clicks and impressions per campaign and product category.',
    PRODUCTS
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog.',
    SALES
      COMMENT = 'Sales transactions by region and product.',
    SOCIAL_MEDIA
      COMMENT = 'Influencer mentions by platform and product category.',
    SUPPORT_CASES
      PRIMARY KEY (ID)
      COMMENT = 'Customer support interactions with the full transcript.'
  )
  RELATIONSHIPS (
    ENRICHED_TO_CAMPAIGN AS ENRICHED_MARKETING_INTELLIGENCE (PRODUCT_NAME) REFERENCES MARKETING_CAMPAIGN_METRICS (CATEGORY),
    SALES_TO_PRODUCTS AS SALES (PRODUCT_ID) REFERENCES PRODUCTS (PRODUCT_ID)
  )
  FACTS (
    ENRICHED_MARKETING_INTELLIGENCE.CLICKS AS CLICKS
      COMMENT = 'Clicks of the campaign row. Masked for roles other than the admin roles.',
    ENRICHED_MARKETING_INTELLIGENCE.AVG_SENTIMENT AS AVG_SENTIMENT
      COMMENT = 'Sentiment of the support case: 1 positive, 0 neutral or mixed, -1 negative. Average it for a product.',
    MARKETING_CAMPAIGN_METRICS.CLICKS AS CLICKS
      COMMENT = 'Number of ad clicks. Masked for roles other than the admin roles.',
    MARKETING_CAMPAIGN_METRICS.IMPRESSIONS AS IMPRESSIONS
      COMMENT = 'Number of times the ad was shown.',
    SALES.UNITS_SOLD AS UNITS_SOLD
      COMMENT = 'Units sold in the transaction.',
    SALES.SALES_AMOUNT AS SALES_AMOUNT
      COMMENT = 'Sales amount of the transaction.',
    SOCIAL_MEDIA.MENTIONS AS MENTIONS
      COMMENT = 'Number of mentions.'
  )
  DIMENSIONS (
    ENRICHED_MARKETING_INTELLIGENCE.CAMPAIGN_NAME AS CAMPAIGN_NAME
      COMMENT = 'Campaign name.',
    ENRICHED_MARKETING_INTELLIGENCE.PRODUCT_NAME AS PRODUCT_NAME
      COMMENT = 'Product category name. Matches MARKETING_CAMPAIGN_METRICS.CATEGORY.',
    MARKETING_CAMPAIGN_METRICS.CAMPAIGN_NAME AS CAMPAIGN_NAME
      COMMENT = 'Campaign name.',
    MARKETING_CAMPAIGN_METRICS.CATEGORY AS CATEGORY
      COMMENT = 'Product category.',
    MARKETING_CAMPAIGN_METRICS.DATE AS DATE
      COMMENT = 'Date of the campaign row.',
    PRODUCTS.PRODUCT_ID AS PRODUCT_ID
      COMMENT = 'Product identifier.',
    PRODUCTS.PRODUCT_NAME AS PRODUCT_NAME
      COMMENT = 'Product name.',
    PRODUCTS.CATEGORY AS CATEGORY
      COMMENT = 'Product category.',
    SALES.PRODUCT_ID AS PRODUCT_ID
      COMMENT = 'Product identifier.',
    SALES.REGION AS REGION
      COMMENT = 'Sales region.',
    SALES.DATE AS DATE
      COMMENT = 'Date of the sale.',
    SOCIAL_MEDIA.CATEGORY AS CATEGORY
      COMMENT = 'Product category.',
    SOCIAL_MEDIA.PLATFORM AS PLATFORM
      COMMENT = 'Social media platform.',
    SOCIAL_MEDIA.INFLUENCER AS INFLUENCER
      COMMENT = 'Influencer name.',
    SOCIAL_MEDIA.DATE AS DATE
      COMMENT = 'Date of the mentions.',
    SUPPORT_CASES.ID AS ID
      COMMENT = 'Support case identifier.',
    SUPPORT_CASES.TITLE AS TITLE
      COMMENT = 'Support case title.',
    SUPPORT_CASES.PRODUCT AS PRODUCT
      COMMENT = 'Product category of the case.',
    SUPPORT_CASES.TRANSCRIPT AS TRANSCRIPT
      COMMENT = 'Full support conversation.',
    SUPPORT_CASES.DATE AS DATE
      COMMENT = 'Date of the case.'
  )
  METRICS (
    MARKETING_CAMPAIGN_METRICS.TOTAL_CLICKS AS SUM(MARKETING_CAMPAIGN_METRICS.CLICKS)
      COMMENT = 'Total ad clicks.',
    MARKETING_CAMPAIGN_METRICS.TOTAL_IMPRESSIONS AS SUM(MARKETING_CAMPAIGN_METRICS.IMPRESSIONS)
      COMMENT = 'Total ad impressions.',
    ENRICHED_MARKETING_INTELLIGENCE.AVERAGE_SENTIMENT AS AVG(ENRICHED_MARKETING_INTELLIGENCE.AVG_SENTIMENT)
      COMMENT = 'Average support case sentiment, from -1 to 1.',
    SALES.TOTAL_SALES_AMOUNT AS SUM(SALES.SALES_AMOUNT)
      COMMENT = 'Total sales amount.',
    SALES.TOTAL_UNITS_SOLD AS SUM(SALES.UNITS_SOLD)
      COMMENT = 'Total units sold.',
    SOCIAL_MEDIA.TOTAL_MENTIONS AS SUM(SOCIAL_MEDIA.MENTIONS)
      COMMENT = 'Total social media mentions.'
  )
  COMMENT = 'Marketing, sales, social and support data with AI sentiment. Used by MarketingAgent.';

SHOW SEMANTIC VIEWS IN SCHEMA DASH_DB_SI.RETAIL;
