-- Session time zone demo. ALTER SESSION lasts only for this session (one snow sql run).
-- No warehouse needed: CURRENT_TIMESTAMP and SHOW PARAMETERS run in cloud services.
USE ROLE SYSADMIN;
SELECT CURRENT_TIMESTAMP();                       -- account default, America/Los_Angeles
ALTER SESSION SET TIMEZONE = 'UTC';
SELECT CURRENT_TIMESTAMP();
ALTER SESSION SET TIMEZONE = 'Africa/Nairobi';
SELECT CURRENT_TIMESTAMP();
ALTER SESSION SET TIMEZONE = 'Pacific/Funafuti';
SELECT CURRENT_TIMESTAMP();
ALTER SESSION SET TIMEZONE = 'Asia/Shanghai';
SELECT CURRENT_TIMESTAMP();
SHOW PARAMETERS LIKE 'timezone';                  -- value is the session's; level shows where it was set
SHOW PARAMETERS LIKE 'timezone' IN ACCOUNT;       -- the account default stays unchanged
