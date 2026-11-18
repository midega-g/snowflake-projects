-- Find a known test login/logout and check which clock the timestamps use.
-- The test happened at 2022-10-15 19:22 local time (UTC-6), which is 2022-10-16 01:22 UTC.
-- The row's timestamp shows which of the two the feed records.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

SELECT user_login, user_event, datetime_iso8601, ip_address
FROM AGS_GAME_AUDIENCE.RAW.LOGS
WHERE user_login ILIKE '%prajina%'
ORDER BY datetime_iso8601;
