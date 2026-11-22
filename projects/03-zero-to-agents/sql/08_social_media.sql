-- Section 4: social_media, loaded from S3.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SWT_SOCIAL_MEDIA_DATA_STAGE
  FILE_FORMAT = SWT_CSVFORMAT
  URL = 's3://sfquickstarts/sfguide_getting_started_with_snowflake_intelligence/social_media/'
  COMMENT = 'External stage on the public lab S3 bucket: social media mentions.';

CREATE OR REPLACE TABLE SOCIAL_MEDIA (
  DATE DATE,
  CATEGORY VARCHAR(16777216),
  PLATFORM VARCHAR(16777216),
  INFLUENCER VARCHAR(16777216),
  MENTIONS NUMBER(38,0)
)
  COMMENT = 'Social media mentions by date, category, platform and influencer.';

COPY INTO SOCIAL_MEDIA
  FROM @SWT_SOCIAL_MEDIA_DATA_STAGE;
