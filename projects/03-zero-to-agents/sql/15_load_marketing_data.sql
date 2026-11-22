-- Section 9: lab step "Updating Marketing Data", done with the CLI instead of Snowsight > Load Data.
-- Appends the rows from marketing_data.csv to MARKETING_CAMPAIGN_METRICS.
-- Not safe to rerun as is. OVERWRITE = TRUE uploads the file again as a new version, so COPY loads
-- its rows a second time (tested: 105 rows became 210). Run this file once per table.
-- To redo the step, first recreate the table with 05_marketing_campaign_metrics.sql (back to 23 rows),
-- then run this file again. Without OVERWRITE, PUT skips a file already on the stage and COPY loads nothing.
-- The last statement drops the stage, so the schema keeps the seven stages the lab's setup creates.
-- Run: snow sql -f 15_load_marketing_data.sql -D csv_path="$PWD/projects/03-zero-to-agents/data/marketing_data.csv"   (from the repo root)
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE STAGE IF NOT EXISTS MARKETING_UPLOAD_STAGE FILE_FORMAT = SWT_CSVFORMAT
  COMMENT = 'Internal stage for the marketing_data.csv upload.';
PUT 'file://<% csv_path %>' @MARKETING_UPLOAD_STAGE OVERWRITE = TRUE;

COPY INTO MARKETING_CAMPAIGN_METRICS FROM @MARKETING_UPLOAD_STAGE;
SELECT COUNT(*) AS ROWS_NOW FROM MARKETING_CAMPAIGN_METRICS;

DROP STAGE MARKETING_UPLOAD_STAGE;
