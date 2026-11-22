-- Run first in any VS Code worksheet.
ALTER SESSION SET QUERY_TAG='{"project":"zero-to-agents","env":"dev","tool":"vscode","owner":"midega-g"}';
SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
