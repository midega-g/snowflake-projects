-- Removes what workshop_greeting.sql leaves behind: the UTIL_DB database (with the GRADER and GREETING external functions)
-- and the DORA_API_INTEGRATION API integration. Run it with snow sql after the grader, only when needed.
-- Like the grader, it needs ACCOUNTADMIN, because the API integration was created by that role.
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS UTIL_DB;
DROP API INTEGRATION IF EXISTS DORA_API_INTEGRATION;
SHOW DATABASES LIKE 'UTIL_DB';
SHOW API INTEGRATIONS LIKE 'DORA_API_INTEGRATION';
