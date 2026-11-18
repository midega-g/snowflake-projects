-- Second file: updated_feed/ (adds ip_address, drops agent). GAME_LOGS needs no change:
-- RAW_LOG is VARIANT, so any set of keys fits. Only the FROM path differs from 10_load_game_logs.sql.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

-- Shape check: one key set expected.
SELECT OBJECT_KEYS($1)::string AS keys, COUNT(*) AS n_rows
FROM @uni_kishore/updated_feed (file_format => 'ff_json_logs')
GROUP BY 1;

-- Value checks: every IP parses, every timestamp parses.
SELECT COUNT_IF(PARSE_IP($1:ip_address::text, 'INET', 1):error IS NOT NULL) AS bad_ip,
       COUNT_IF(TRY_TO_TIMESTAMP_NTZ($1:datetime_iso8601::text) IS NULL)     AS bad_ts
FROM @uni_kishore/updated_feed (file_format => 'ff_json_logs');

-- Dry run, then the load. Old rows stay; load metadata keeps reruns from duplicating.
COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/updated_feed
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
VALIDATION_MODE = RETURN_ERRORS;

COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/updated_feed
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
ON_ERROR = ABORT_STATEMENT;

SELECT COUNT(*) AS n_rows FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS;   -- 250 + 284 = 534
