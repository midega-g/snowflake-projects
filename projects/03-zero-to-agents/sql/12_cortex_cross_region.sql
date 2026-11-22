-- Section 7: allow Cortex models to run in other AWS US regions. Account-level setting, ACCOUNTADMIN only.
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';
