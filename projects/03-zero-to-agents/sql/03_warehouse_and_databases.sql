-- Section 3: warehouse, databases and schemas, all created by the project role so it owns them.
-- The lab sets the warehouse size to LARGE. We start at XSMALL and resize to LARGE for the data loading
-- steps, then decide whether to keep it or drop back down. AUTO_SUSPEND and the resource monitor are added defaults,
-- because the lab is silent on them.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

CREATE DATABASE  IF NOT EXISTS DASH_DB_SI
  COMMENT = 'Retail sales, marketing and support data for the Snowflake Intelligence lab.';
CREATE SCHEMA    IF NOT EXISTS DASH_DB_SI.RETAIL
  COMMENT = 'Lab tables, stages, Git repository, dynamic table and views.';
CREATE WAREHOUSE IF NOT EXISTS DASH_WH_SI
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for the Snowflake Intelligence lab. Starts XSMALL, suspends after 60 idle seconds.';

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE
  COMMENT = 'Home of the Snowflake Intelligence agents.';
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS
  COMMENT = 'Agents listed in Snowflake Intelligence. The project role can create agents here.';
GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

-- added default: resource monitor on every project warehouse (resource monitors have no COMMENT property) (account-level object, ACCOUNTADMIN only)
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS DASH_WH_SI_RM
  WITH CREDIT_QUOTA = 10 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE DASH_WH_SI SET RESOURCE_MONITOR = DASH_WH_SI_RM;
