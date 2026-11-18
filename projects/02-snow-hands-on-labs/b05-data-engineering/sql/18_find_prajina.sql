-- Find Prajina's test login/logoff and check which clock the timestamps use.
-- Expected: 2022-10-15 19:22 if recorded in local time (Denver, MDT, UTC-6),
-- or 2022-10-16 01:22 if converted to UTC.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

SELECT user_login, user_event, datetime_iso8601, ip_address
FROM AGS_GAME_AUDIENCE.RAW.LOGS
WHERE user_login ILIKE '%prajina%'
ORDER BY datetime_iso8601;
