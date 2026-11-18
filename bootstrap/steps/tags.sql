-- Object tags (cost attribution / governance). Needs a schema named by tag_schema in schemas.csv.
USE ROLE <% owner_role %>;
CREATE TAG IF NOT EXISTS <% db_name %>.<% tag_schema %>.COST_CENTER;
CREATE TAG IF NOT EXISTS <% db_name %>.<% tag_schema %>.ENV;
CREATE TAG IF NOT EXISTS <% db_name %>.<% tag_schema %>.OWNER;
ALTER DATABASE  <% db_name %> SET TAG <% db_name %>.<% tag_schema %>.ENV = '<% project_env %>',
  <% db_name %>.<% tag_schema %>.OWNER = '<% project_owner %>', <% db_name %>.<% tag_schema %>.COST_CENTER = '<% cost_center %>';
ALTER WAREHOUSE <% wh_name %> SET TAG <% db_name %>.<% tag_schema %>.ENV = '<% project_env %>',
  <% db_name %>.<% tag_schema %>.OWNER = '<% project_owner %>', <% db_name %>.<% tag_schema %>.COST_CENTER = '<% cost_center %>';
