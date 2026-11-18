-- Project infrastructure for the AGS game-audience lab. Run as SYSADMIN so it owns everything.
-- Idempotent: IF NOT EXISTS everywhere. DROP SCHEMA is fully qualified so it only touches this database.
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS AGS_GAME_AUDIENCE;
DROP SCHEMA IF EXISTS AGS_GAME_AUDIENCE.PUBLIC;
CREATE SCHEMA IF NOT EXISTS AGS_GAME_AUDIENCE.RAW;
USE SCHEMA AGS_GAME_AUDIENCE.RAW;

-- One VARIANT column holds each JSON record as is.
CREATE TABLE IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.GAME_LOGS (
  RAW_LOG VARIANT
);

-- Public lab bucket, no credentials. Bucket names use dashes, stage names use underscores.
CREATE STAGE IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.UNI_KISHORE
  URL = 's3://uni-kishore'
  DIRECTORY = (ENABLE = TRUE);

-- STRIP_OUTER_ARRAY: a file holding [ {...}, {...} ] loads as one row per element.
CREATE FILE FORMAT IF NOT EXISTS AGS_GAME_AUDIENCE.RAW.FF_JSON_LOGS
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE;
