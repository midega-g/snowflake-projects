-- DORA step 2: the grader external function (lab SQL, unchanged apart from comments).
-- Run as ACCOUNTADMIN: it owns DORA_API_INTEGRATION, and the lab calls the grader as ACCOUNTADMIN.
-- OR REPLACE is safe to rerun here: the function holds no generated values (unlike the integration).
-- Each call sends the context headers below (timestamp, account locator, statement text, account name) to DORA.
USE ROLE ACCOUNTADMIN;
USE SCHEMA UTIL_DB.PUBLIC;

CREATE OR REPLACE EXTERNAL FUNCTION util_db.public.grader(
      step varchar
    , passed boolean
    , actual integer
    , expected integer
    , description varchar)
RETURNS VARIANT
API_INTEGRATION = dora_api_integration
CONTEXT_HEADERS = (current_timestamp, current_account, current_statement, current_account_name)
AS 'https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora/grader';
