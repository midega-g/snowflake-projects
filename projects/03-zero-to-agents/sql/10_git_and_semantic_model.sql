-- Section 5: internal stage for semantic models, Git integration, and copying the YAML from GitHub.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE STAGE SEMANTIC_MODELS
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Internal stage for semantic model YAML files copied from the Git repository.';

CREATE OR REPLACE API INTEGRATION SNOWFLAKE_LABS_SI_GIT_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs')
  ENABLED = TRUE
  COMMENT = 'Lets Snowflake reach GitHub repositories under Snowflake-Labs. Used by the lab Git repository.';

CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_LABS_SFGUIDE_SI_REPO
  API_INTEGRATION = SNOWFLAKE_LABS_SI_GIT_API_INTEGRATION
  ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-getting-started-with-snowflake-intelligence'
  COMMENT = 'Clone of the lab GitHub repository: semantic model YAML and sample data.';

COPY FILES INTO @SEMANTIC_MODELS
  FROM @SNOWFLAKE_LABS_SFGUIDE_SI_REPO/branches/main/
  FILES = ('marketing_campaigns.yaml');
