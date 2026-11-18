-- Enhanced logs: local time, day of week and time of day, saved with CTAS. Run as SYSADMIN.
-- OR REPLACE because the table is fully derived from LOGS, the share and the lookup.
USE ROLE SYSADMIN;

CREATE OR REPLACE TABLE AGS_GAME_AUDIENCE.ENHANCED.LOGS_ENHANCED AS (
    SELECT logs.ip_address,
           logs.user_login       AS gamer_name,
           logs.user_event       AS game_event_name,
           logs.datetime_iso8601 AS game_event_utc,
           city,
           region,
           country,
           timezone              AS gamer_ltz_name,
           CONVERT_TIMEZONE('UTC', timezone, logs.datetime_iso8601) AS game_event_ltz,
           DAYNAME(game_event_ltz) AS dow_name,
           tod.tod_name
    FROM AGS_GAME_AUDIENCE.RAW.LOGS logs
    JOIN IPINFO_GEOLOC.DEMO.LOCATION loc
      ON IPINFO_GEOLOC.PUBLIC.TO_JOIN_KEY(logs.ip_address) = loc.join_key
     AND IPINFO_GEOLOC.PUBLIC.TO_INT(logs.ip_address) BETWEEN start_ip_int AND end_ip_int
    JOIN AGS_GAME_AUDIENCE.RAW.TIME_OF_DAY_LU tod
      ON HOUR(game_event_ltz) = tod.hour
);

-- Test rows: 01:22 UTC on Sunday should be 19:22 on Saturday in Denver.
SELECT gamer_name, game_event_name, game_event_utc, gamer_ltz_name,
       game_event_ltz, dow_name, tod_name
FROM AGS_GAME_AUDIENCE.ENHANCED.LOGS_ENHANCED
WHERE gamer_name ILIKE '%prajina%'
ORDER BY game_event_utc;

-- Checks: rows, columns, location and owner.
SELECT COUNT(*) AS rows_enhanced FROM AGS_GAME_AUDIENCE.ENHANCED.LOGS_ENHANCED;
SELECT column_name, data_type
FROM AGS_GAME_AUDIENCE.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'ENHANCED' AND table_name = 'LOGS_ENHANCED'
ORDER BY ordinal_position;
SHOW TABLES LIKE 'LOGS_ENHANCED' IN SCHEMA AGS_GAME_AUDIENCE.ENHANCED;
