-- LOGS view, second version (replaces the one from 11): only the updated_feed rows.
-- AGENT is gone (the new rows don't have it) and IP_ADDRESS is added.
-- The WHERE clause hides the kickoff rows. GAME_LOGS keeps all 534 rows.
-- datetime_iso8601 is cast to TIMESTAMP_NTZ: the wall-clock time, no zone stored.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

CREATE OR REPLACE VIEW AGS_GAME_AUDIENCE.RAW.LOGS AS (
  SELECT
      raw_log:ip_address::text                  AS ip_address
    , raw_log:user_event::text                  AS user_event
    , raw_log:user_login::text                  AS user_login
    , raw_log:datetime_iso8601::timestamp_ntz   AS datetime_iso8601
    , raw_log
  FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
  WHERE raw_log:ip_address::text IS NOT NULL
);

SELECT * FROM AGS_GAME_AUDIENCE.RAW.LOGS LIMIT 5;
SELECT COUNT(*) AS n_rows, COUNT(ip_address) AS n_with_ip FROM AGS_GAME_AUDIENCE.RAW.LOGS;
SELECT COUNT(*) AS n_table_rows FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS;
