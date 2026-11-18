-- Query the staged file before loading. Needs COMPUTE_WH (auto-resumes).
USE ROLE SYSADMIN;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

-- No file format: the stage default is CSV, so each JSON line is split at commas.
SELECT $1 FROM @uni_kishore/kickoff LIMIT 3;

-- With the file format: one VARIANT per JSON object.
SELECT $1 FROM @uni_kishore/kickoff (file_format => 'ff_json_logs') LIMIT 5;

-- Row count and key sets, to know what the load and the view should produce.
SELECT COUNT(*) AS n_rows,
       COUNT(DISTINCT OBJECT_KEYS($1)::string) AS n_key_sets,
       ANY_VALUE(OBJECT_KEYS($1)) AS keys
FROM @uni_kishore/kickoff (file_format => 'ff_json_logs');

-- Dry run of the COPY: parses every file, loads nothing, returns errors (none expected).
COPY INTO AGS_GAME_AUDIENCE.RAW.GAME_LOGS
FROM @uni_kishore/kickoff
FILE_FORMAT = (FORMAT_NAME = ff_json_logs)
VALIDATION_MODE = RETURN_ERRORS;
