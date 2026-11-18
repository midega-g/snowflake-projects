-- Run first in any VS Code worksheet. (Redundant if the user-level QUERY_TAG is set.)
USE ROLE DBT_TUT_TRANSFORMER;
USE WAREHOUSE DBT_TUT_WH;
USE SCHEMA DBT_TUT_DEV.STAGING;
ALTER SESSION SET QUERY_TAG='{"project":"dbt-tutorial","env":"dev","tool":"vscode","owner":"midega-g"}';
SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_SCHEMA(), CURRENT_SESSION();
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
