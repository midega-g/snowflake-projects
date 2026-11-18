-- Load every file under kickoff/ into GAME_LOGS. ON_ERROR is the bulk default, written out on purpose.
-- Safe to rerun: load metadata skips files already loaded ("Copy executed with 0 files processed."). Don't add FORCE = TRUE.
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/kickoff
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
ON_ERROR = ABORT_STATEMENT;

SELECT COUNT(*) AS n_rows FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS;
