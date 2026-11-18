-- Missing key vs JSON null, on literal JSON (no tables touched). No warehouse needed for literals.
USE ROLE SYSADMIN;

WITH samples AS (
  SELECT 'key present, string' AS case_name, PARSE_JSON('{"agent": "Mozilla/5.0"}') AS v UNION ALL
  SELECT 'key present, null',                PARSE_JSON('{"agent": null}')          UNION ALL
  SELECT 'key missing',                      PARSE_JSON('{"ip_address": "1.2.3.4"}')
)
SELECT case_name
     , v:agent                    AS agent_variant
     , v:agent IS NULL            AS is_sql_null
     , IS_NULL_VALUE(v:agent)     AS is_json_null
     , TYPEOF(v:agent)            AS typeof_agent
     , v:agent::text              AS agent_text
     , v:agent::text IS NULL      AS text_is_null
     , OBJECT_KEYS(v)             AS keys
     , ARRAY_CONTAINS('agent'::variant, OBJECT_KEYS(v)) AS has_key
FROM samples;

-- STRIP_NULL_VALUE turns a JSON null into SQL NULL. The file format option STRIP_NULL_VALUES = TRUE
-- does the same for every "key": null pair at load time, so it then looks like a missing key.
SELECT STRIP_NULL_VALUE(PARSE_JSON('{"agent": null}'):agent)         AS stripped,
       STRIP_NULL_VALUE(PARSE_JSON('{"agent": null}'):agent) IS NULL AS now_sql_null;

-- On the real table: the 284 updated_feed rows lack the key; none hold a JSON null.
SELECT COUNT_IF(raw_log:agent IS NULL)        AS missing_or_sql_null,
       COUNT_IF(IS_NULL_VALUE(raw_log:agent)) AS json_null
FROM AGS_GAME_AUDIENCE.RAW.GAME_LOGS;
