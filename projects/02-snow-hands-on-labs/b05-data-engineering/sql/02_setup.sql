-- b05 trial account setup: COMPUTE_WH, its resource monitor, UTIL_DB, user defaults. Idempotent.
-- Run: snow sql -f sql/02_setup.sql   (after: source scripts/use-project.sh 02-snow-hands-on-labs/b05-data-engineering)
-- Lab exception: the lab requires COMPUTE_WH (steering normally forbids it). Cost guards still apply.

-- 1. Warehouse + database, created by SYSADMIN so SYSADMIN owns them (and UTIL_DB.PUBLIC) from the start.
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Shared lab warehouse for 02-snow-hands-on-labs';
ALTER WAREHOUSE COMPUTE_WH SET WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;  -- enforce if it pre-existed
CREATE DATABASE IF NOT EXISTS UTIL_DB COMMENT = 'Home for the DORA grader function';

-- 2. Resource monitor: account-level object, ACCOUNTADMIN only. Adjust CREDIT_QUOTA per lab.
USE ROLE ACCOUNTADMIN;
CREATE RESOURCE MONITOR IF NOT EXISTS COMPUTE_WH_RM
  WITH CREDIT_QUOTA = 15 FREQUENCY = WEEKLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = COMPUTE_WH_RM;

-- 3. User defaults for whoever runs this (a user can alter itself). The variable wraps CURRENT_USER()
--    in double quotes so a lowercase user name keeps its case; IDENTIFIER() turns it into a name.
USE ROLE SYSADMIN;
SET my_user = '"' || CURRENT_USER() || '"';
ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'SYSADMIN';
ALTER USER IDENTIFIER($my_user) SET DEFAULT_WAREHOUSE = 'COMPUTE_WH';
ALTER USER IDENTIFIER($my_user) SET DEFAULT_NAMESPACE = 'UTIL_DB.PUBLIC';
