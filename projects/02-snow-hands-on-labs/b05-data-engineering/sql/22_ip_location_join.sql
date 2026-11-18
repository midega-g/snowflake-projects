-- Look up time zones for the log IPs in IPINFO_GEOLOC.DEMO.LOCATION. Run as SYSADMIN.
USE ROLE SYSADMIN;

-- One address: the test user's IP (from 18_find_test_records.sql).
SELECT start_ip, end_ip, start_ip_int, end_ip_int, city, region, country, timezone
FROM IPINFO_GEOLOC.DEMO.LOCATION
WHERE PARSE_IP('100.41.16.160', 'inet'):ipv4 BETWEEN start_ip_int AND end_ip_int;

-- Every log row, range test only. The profile shows a CartesianJoin:
-- each log row is compared with every one of the 274,910 ranges.
SELECT logs.*, loc.city, loc.region, loc.country, loc.timezone
FROM AGS_GAME_AUDIENCE.RAW.LOGS logs
JOIN IPINFO_GEOLOC.DEMO.LOCATION loc
WHERE PARSE_IP(logs.ip_address, 'inet'):ipv4 BETWEEN start_ip_int AND end_ip_int;

-- Same rows with the provider's functions. The equality on JOIN_KEY lets
-- Snowflake use a hash join, and BETWEEN only checks ranges with the same key.
SELECT logs.ip_address, logs.user_login, logs.user_event, logs.datetime_iso8601,
       city, region, country, timezone
FROM AGS_GAME_AUDIENCE.RAW.LOGS logs
JOIN IPINFO_GEOLOC.DEMO.LOCATION loc
  ON IPINFO_GEOLOC.PUBLIC.TO_JOIN_KEY(logs.ip_address) = loc.join_key
 AND IPINFO_GEOLOC.PUBLIC.TO_INT(logs.ip_address) BETWEEN start_ip_int AND end_ip_int;

-- JOIN_KEY is the first address of the /16 network (a.b.0.0) as an integer.
SELECT IPINFO_GEOLOC.PUBLIC.TO_JOIN_KEY('100.41.16.160') AS join_key,
       PARSE_IP('100.41.0.0/16', 'inet'):ipv4_range_start AS net16_start;
