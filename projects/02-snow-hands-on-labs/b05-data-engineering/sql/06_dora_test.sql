-- DORA step 3: connection test. Expect a success message in GRADED_RESULTS.
-- Needs a running warehouse (COMPUTE_WH auto-resumes, then auto-suspends after 60 s).
USE ROLE ACCOUNTADMIN;
USE SCHEMA UTIL_DB.PUBLIC;

SELECT util_db.public.grader(step, (actual = expected), actual, expected, description) AS graded_results
FROM (
  SELECT 'DORA_IS_WORKING' AS step
       , (SELECT 123)      AS actual
       , 123               AS expected
       , 'Dora is working!' AS description
);
