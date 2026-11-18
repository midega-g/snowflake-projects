-- Lookup table from hour (0-23) to a time-of-day name. Run as SYSADMIN.
-- OR REPLACE so a rerun rebuilds the 24 rows instead of duplicating them.
USE ROLE SYSADMIN;
CREATE OR REPLACE TABLE AGS_GAME_AUDIENCE.RAW.TIME_OF_DAY_LU (
    hour     NUMBER,
    tod_name VARCHAR(25)
);
INSERT INTO AGS_GAME_AUDIENCE.RAW.TIME_OF_DAY_LU VALUES
(6,'Early morning'), (7,'Early morning'), (8,'Early morning'),
(9,'Mid-morning'), (10,'Mid-morning'),
(11,'Late morning'), (12,'Late morning'),
(13,'Early afternoon'), (14,'Early afternoon'),
(15,'Mid-afternoon'), (16,'Mid-afternoon'),
(17,'Late afternoon'), (18,'Late afternoon'),
(19,'Early evening'), (20,'Early evening'),
(21,'Late evening'), (22,'Late evening'), (23,'Late evening'),
(0,'Late at night'), (1,'Late at night'), (2,'Late at night'),
(3,'Toward morning'), (4,'Toward morning'), (5,'Toward morning');

SELECT tod_name, LISTAGG(hour, ',') WITHIN GROUP (ORDER BY hour) AS hours
FROM AGS_GAME_AUDIENCE.RAW.TIME_OF_DAY_LU
GROUP BY tod_name
ORDER BY MIN((hour + 18) % 24);   -- 6 AM first
