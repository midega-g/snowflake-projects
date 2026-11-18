USE ROLE SYSADMIN;
CREATE <% db_kw %> DATABASE IF NOT EXISTS <% db_name %>
  DATA_RETENTION_TIME_IN_DAYS = <% db_retention_days %>
  COMMENT = 'project <% project_key %>';
GRANT OWNERSHIP ON DATABASE <% db_name %> TO ROLE <% owner_role %> COPY CURRENT GRANTS;
