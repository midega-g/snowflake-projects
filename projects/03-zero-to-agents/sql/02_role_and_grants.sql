-- Section 2: the project role, its account-level privileges and the user defaults.
-- Source: setup.sql, "use role accountadmin" down to "alter user set default_warehouse".
USE ROLE ACCOUNTADMIN;

-- The lab uses CREATE OR REPLACE ROLE. That drops the role and everything it owns when
-- the account is already populated, so this file uses IF NOT EXISTS.
CREATE ROLE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_ADMIN
  COMMENT = 'Owns the Snowflake Intelligence lab objects: warehouse, databases, stages, integrations and agent.';
GRANT CREATE WAREHOUSE   ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE DATABASE    ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;

SET current_user = (SELECT CURRENT_USER());
GRANT ROLE SNOWFLAKE_INTELLIGENCE_ADMIN TO USER IDENTIFIER($current_user);
-- ALTER USER without a user name changes the current user.
ALTER USER SET DEFAULT_ROLE = SNOWFLAKE_INTELLIGENCE_ADMIN;
ALTER USER SET DEFAULT_WAREHOUSE = DASH_WH_SI;

-- Workaround, only if the statements above fail on your account (for example with a
-- syntax error or an unknown user). It names the user explicitly and keeps the quotes,
-- which matters when the login name is lower or mixed case.
-- SET my_user = '"' || CURRENT_USER() || '"';
-- GRANT ROLE SNOWFLAKE_INTELLIGENCE_ADMIN TO USER IDENTIFIER($my_user);
-- ALTER USER IDENTIFIER($my_user) SET DEFAULT_ROLE = 'SNOWFLAKE_INTELLIGENCE_ADMIN';
-- ALTER USER IDENTIFIER($my_user) SET DEFAULT_WAREHOUSE = 'DASH_WH_SI';
