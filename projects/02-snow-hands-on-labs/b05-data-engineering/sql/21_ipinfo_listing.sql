-- IPinfo free training sample from the Marketplace, as database IPINFO_GEOLOC.
-- The listing has STANDARD terms. Accept them once in Snowsight
-- (Marketplace > "IPinfo: IP Geolocation Training/Education Sample" > Get)
-- before CREATE DATABASE ... FROM LISTING can run. Getting it in Snowsight
-- with SYSADMIN added does the same as the CREATE and GRANT below.
USE ROLE ACCOUNTADMIN;

-- Find the global name. SHOW AVAILABLE LISTINGS has no LIKE filter (it is
-- ignored), so filter the output by title with the pipe operator.
SHOW AVAILABLE LISTINGS
  ->> SELECT "global_name", "title", "is_monetized", "is_ready_for_import"
      FROM $1 WHERE "title" ILIKE '%ipinfo%' ORDER BY "title";
DESCRIBE AVAILABLE LISTING GZSTZ3VDMEH;   -- listing_terms: STANDARD

CREATE DATABASE IF NOT EXISTS IPINFO_GEOLOC FROM LISTING 'GZSTZ3VDMEH';
GRANT IMPORTED PRIVILEGES ON DATABASE IPINFO_GEOLOC TO ROLE SYSADMIN;

-- Check from SYSADMIN
USE ROLE SYSADMIN;
SHOW GRANTS ON DATABASE IPINFO_GEOLOC;
SHOW SCHEMAS IN DATABASE IPINFO_GEOLOC;            -- DEMO, INFORMATION_SCHEMA, PUBLIC
SHOW VIEWS LIKE 'LOCATION' IN DATABASE IPINFO_GEOLOC;        -- DEMO.LOCATION
SHOW USER FUNCTIONS LIKE 'TO_INT' IN DATABASE IPINFO_GEOLOC; -- PUBLIC.TO_INT
DESC VIEW IPINFO_GEOLOC.DEMO.LOCATION;
