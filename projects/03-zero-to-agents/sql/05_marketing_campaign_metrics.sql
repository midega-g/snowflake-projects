-- Section 4: marketing_campaign_metrics, loaded from S3.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SWT_MARKETING_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/marketing/'
  COMMENT = 'External stage on the public lab S3 bucket: marketing campaign metrics.';

CREATE OR REPLACE TABLE MARKETING_CAMPAIGN_METRICS (
  DATE DATE,
  CATEGORY VARCHAR(16777216),
  CAMPAIGN_NAME VARCHAR(16777216),
  IMPRESSIONS NUMBER(38,0),
  CLICKS NUMBER(38,0)
)
  COMMENT = 'Daily impressions and clicks per campaign and product category.';

COPY INTO MARKETING_CAMPAIGN_METRICS
  FROM @SWT_MARKETING_DATA_STAGE;
