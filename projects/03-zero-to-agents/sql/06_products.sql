-- Section 4: products, loaded from S3.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SWT_PRODUCTS_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/product/'
  COMMENT = 'External stage on the public lab S3 bucket: products.';

CREATE OR REPLACE TABLE PRODUCTS (
  PRODUCT_ID NUMBER(38,0),
  PRODUCT_NAME VARCHAR(16777216),
  CATEGORY VARCHAR(16777216)
)
  COMMENT = 'Product catalogue: id, name and category.';

COPY INTO PRODUCTS
  FROM @SWT_PRODUCTS_DATA_STAGE;
