-- per role row with db_access != NONE/OWNER
USE ROLE <% owner_role %>;
GRANT USAGE ON DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% schema_privs %> ON ALL SCHEMAS IN DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% schema_privs %> ON FUTURE SCHEMAS IN DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% object_privs %> ON ALL TABLES IN DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% object_privs %> ON FUTURE TABLES IN DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% object_privs %> ON ALL VIEWS IN DATABASE <% db_name %> TO ROLE <% role_name %>;
GRANT <% object_privs %> ON FUTURE VIEWS IN DATABASE <% db_name %> TO ROLE <% role_name %>;
