USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS <% wh_name %> WITH
  WAREHOUSE_SIZE = '<% wh_size %>' AUTO_SUSPEND = <% wh_auto_suspend %>
  AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'project <% project_key %>';
-- attach monitor (ACCOUNTADMIN only) - skipped by the runner when the resource_monitor step is not enabled
