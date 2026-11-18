-- One column per JSON key, plus the original RAW_LOG last.
-- datetime_iso8601 ends in Z (UTC), so it is cast to TIMESTAMP_NTZ: the wall-clock UTC time, no zone stored.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

CREATE OR REPLACE VIEW AGS_GAME_AUDIENCE.RAW.LOGS AS (
  SELECT
      raw_log:agent::text                       AS agent
    , raw_log:user_event::text                  AS user_event
    , raw_log:user_login::text                  AS user_login
    , raw_log:datetime_iso8601::timestamp_ntz   AS datetime_iso8601
    , raw_log
  FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
);

SELECT * FROM AGS_GAME_AUDIENCE.RAW.LOGS LIMIT 5;
SELECT COUNT(*) AS n_rows FROM AGS_GAME_AUDIENCE.RAW.LOGS;
