-- DORA step 1: API integration so this account can call Snowflake's DORA grader service.
-- Run: snow sql -f sql/04_dora_api_integration.sql   (after: source scripts/use-project.sh 02-snow-hands-on-labs/b05-data-engineering)
-- Integrations are account-level objects. Creating one needs CREATE INTEGRATION (ACCOUNTADMIN by default);
-- SYSADMIN gets 003001 "SQL access control error".
-- The lab uses CREATE OR REPLACE. IF NOT EXISTS is used here so a rerun keeps the existing object.
-- Values come from the lab and point at Snowflake's own AWS account, not ours. Nothing secret here.

USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION IF NOT EXISTS dora_api_integration
  API_PROVIDER = aws_api_gateway
  API_AWS_ROLE_ARN = 'arn:aws:iam::321463406630:role/snowflakeLearnerAssumedRole'
  ENABLED = TRUE
  API_ALLOWED_PREFIXES = ('https://awy6hshxy4.execute-api.us-west-2.amazonaws.com/dev/edu_dora');

-- Check. DESCRIBE also shows API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID: account-specific, keep them out of notes.
SHOW API INTEGRATIONS LIKE 'DORA_API_INTEGRATION';
SHOW GRANTS ON INTEGRATION dora_api_integration;

USE ROLE SYSADMIN;
