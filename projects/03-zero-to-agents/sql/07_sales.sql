-- Section 4: sales, loaded from S3.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SWT_SALES_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/sales/'
  COMMENT = 'External stage on the public lab S3 bucket: sales.';

CREATE OR REPLACE TABLE SALES (
  DATE DATE,
  REGION VARCHAR(16777216),
  PRODUCT_ID NUMBER(38,0),
  UNITS_SOLD NUMBER(38,0),
  SALES_AMOUNT NUMBER(38,2)
)
  COMMENT = 'Sales by date, region and product.';

COPY INTO SALES
  FROM @SWT_SALES_DATA_STAGE;
