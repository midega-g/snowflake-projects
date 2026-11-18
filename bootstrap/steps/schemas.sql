-- per schema row; owner role creates schemas.
USE ROLE <% owner_role %>;
CREATE <% schema_kw %> SCHEMA IF NOT EXISTS <% db_name %>.<% schema_name %> <% schema_managed %>;
