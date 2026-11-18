-- per role row with wh_access != NONE
USE ROLE <% owner_role %>;
GRANT <% wh_privs %> ON WAREHOUSE <% wh_name %> TO ROLE <% role_name %>;
