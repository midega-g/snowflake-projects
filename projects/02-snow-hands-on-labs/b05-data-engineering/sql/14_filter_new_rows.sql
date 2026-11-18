-- Only rows from the second file. Either key works; both are shown and must agree.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

SELECT
    raw_log:ip_address::text                  AS ip_address
  , raw_log:user_event::text                  AS user_event
  , raw_log:user_login::text                  AS user_login
  , raw_log:datetime_iso8601::timestamp_ntz   AS datetime_iso8601
  , raw_log
FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
WHERE raw_log:agent IS NULL                   -- removed field: missing in the new rows
  AND raw_log:ip_address IS NOT NULL;         -- added field: present only in the new rows

-- Cross-check: split the table by which key each row has.
SELECT (raw_log:agent IS NOT NULL)      AS has_agent,
       (raw_log:ip_address IS NOT NULL) AS has_ip,
       COUNT(*)                         AS n_rows
FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS
GROUP BY 1, 2
ORDER BY 1, 2;
