-- PARSE_IP on the test user's IP address (from 18_find_test_records.sql).
-- Pure functions: no table, no warehouse needed.
USE ROLE SYSADMIN;

SELECT PARSE_IP('100.41.16.160', 'inet') AS parsed;

SELECT PARSE_IP('100.41.16.160', 'inet'):host::text   AS host,
       PARSE_IP('100.41.16.160', 'inet'):family::int  AS family,
       PARSE_IP('100.41.16.160', 'inet'):ipv4::int    AS ipv4;

-- ipv4 is the address as one 32-bit number: a*256^3 + b*256^2 + c*256 + d.
SELECT (100*POWER(256,3) + 41*POWER(256,2) + 16*256 + 160)::int AS ipv4_by_hand;

-- A /24 network: the integer range a lookup table can match with BETWEEN.
SELECT PARSE_IP('100.41.16.0/24', 'inet') AS parsed_network;
