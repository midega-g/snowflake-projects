-- Section 8: Cortex AI functions on the support transcripts (lab "Extract Trends").
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

UPDATE SUPPORT_CASES SET PRODUCT = 'Fitness Wear' WHERE PRODUCT = 'ThermoJacket Pro';

SELECT
    TITLE,
    AI_SENTIMENT(TRANSCRIPT):categories[0]:sentiment::STRING AS SENTIMENT,
    AI_CLASSIFY(TRANSCRIPT, ['Return', 'Quality', 'Shipping']):labels[0]::STRING AS ISSUE_CATEGORY
FROM SUPPORT_CASES;
