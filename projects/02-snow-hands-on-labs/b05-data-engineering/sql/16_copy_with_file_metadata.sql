-- Recording the source file of every row. Uses a TEMPORARY table, so the lab's GAME_LOGS is unchanged
-- and nothing is left behind when the session ends. Needs COMPUTE_WH.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

-- 1. Metadata columns can be read straight from the stage, before any load.
SELECT METADATA$FILENAME           AS file_name
     , MIN(METADATA$FILE_ROW_NUMBER) AS first_row
     , MAX(METADATA$FILE_ROW_NUMBER) AS last_row
     , ANY_VALUE(METADATA$FILE_LAST_MODIFIED) AS file_last_modified
     , COUNT(*)                    AS n_rows
FROM @uni_kishore (file_format => 'ff_json_logs')
GROUP BY 1
ORDER BY 1;

-- 2. A load that keeps them: COPY with a SELECT (a "transforming" COPY).
CREATE TEMPORARY TABLE game_logs_with_file (
    raw_log         VARIANT
  , file_name       VARCHAR
  , file_row_number NUMBER
  , loaded_at       TIMESTAMP_LTZ
);

COPY INTO game_logs_with_file (raw_log, file_name, file_row_number, loaded_at)
FROM (
  SELECT $1
       , METADATA$FILENAME
       , METADATA$FILE_ROW_NUMBER
       , CURRENT_TIMESTAMP()
  FROM @uni_kishore
)
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
PATTERN = '.*[.]json'
ON_ERROR = ABORT_STATEMENT;

-- 3. Filtering by file instead of by shape.
SELECT file_name, COUNT(*) AS n_rows
FROM game_logs_with_file
GROUP BY 1
ORDER BY 1;

SELECT raw_log:ip_address::text AS ip_address, raw_log:user_login::text AS user_login, file_name, file_row_number
FROM game_logs_with_file
WHERE file_name LIKE 'updated_feed/%'
ORDER BY file_row_number
LIMIT 3;
