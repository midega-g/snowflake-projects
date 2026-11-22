-- Section 4: shared CSV file format for the five public S3 stages.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE FILE FORMAT SWT_CSVFORMAT
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TYPE = 'CSV'
  COMMENT = 'CSV with one header row and optionally quoted fields. Shared by the lab S3 stages.';
