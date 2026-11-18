-- Run first in any VS Code worksheet.
USE ROLE SYSADMIN;
ALTER SESSION SET QUERY_TAG='{"project":"snow-hol-b01-data-warehousing","env":"dev","tool":"vscode","owner":"midega-g"}';
SELECT CURRENT_ROLE(), CURRENT_SESSION();
SHOW PARAMETERS LIKE 'QUERY_TAG' IN SESSION;
