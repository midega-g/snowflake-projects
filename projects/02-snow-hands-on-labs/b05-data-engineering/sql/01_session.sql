-- Run first in any VS Code worksheet. Role/warehouse/namespace come from the user defaults (02_setup.sql).
ALTER SESSION SET QUERY_TAG='{"project":"snow-hol-b05-data-engineering","env":"dev","tool":"vscode","owner":"midega-g"}';
SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
