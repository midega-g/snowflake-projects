-- per role row. Builds the hierarchy: child role granted to parent role.
USE ROLE USERADMIN;
GRANT ROLE <% role_name %> TO ROLE <% parent_role %>;
