-- Section 4: support_cases, loaded from S3.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SWT_SUPPORT_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/support/'
  COMMENT = 'External stage on the public lab S3 bucket: support cases.';

CREATE OR REPLACE TABLE SUPPORT_CASES (
  ID VARCHAR(16777216),
  TITLE VARCHAR(16777216),
  PRODUCT VARCHAR(16777216),
  TRANSCRIPT VARCHAR(16777216),
  DATE DATE
)
  COMMENT = 'Customer support cases with free-text transcripts.';

COPY INTO SUPPORT_CASES
  FROM @SWT_SUPPORT_DATA_STAGE;
