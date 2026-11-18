-- Grant project roles to your user and set non-admin defaults + user-level default QUERY_TAG
-- (applies to every client incl. the VS Code extension).
USE ROLE USERADMIN;
GRANT ROLE <% owner_role %>   TO USER <% my_user %>;
GRANT ROLE <% default_role %> TO USER <% my_user %>;
USE ROLE SECURITYADMIN;
ALTER USER <% my_user %> SET DEFAULT_ROLE = '<% default_role %>' DEFAULT_WAREHOUSE = '<% wh_name %>'
  DEFAULT_NAMESPACE = '<% db_name %>.<% default_schema %>';
ALTER USER <% my_user %> SET QUERY_TAG = '{"project":"<% project_name %>","env":"<% project_env %>","owner":"<% project_owner %>"}';
