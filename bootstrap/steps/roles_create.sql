-- per role row. USERADMIN creates roles (not ACCOUNTADMIN).
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS <% role_name %> COMMENT = 'project <% project_key %>';
