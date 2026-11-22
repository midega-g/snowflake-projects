-- Section 14: the MarketingAgent (lab "Create an Agent"). The lab builds it in Snowsight; this file writes the same agent in SQL.
-- Run after 20_semantic_view.sql, 21_search_service.sql (or 21a_search_service_governed.sql) and the SEND_EMAIL procedure (file 11).
-- Tool and parameter descriptions are the lab's wording. Settings the lab does not give: orchestration model "auto" (default).
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE AGENT MarketingAgent
  COMMENT = 'I am a specialized Marketing & Sales Intelligence Assistant. My primary role is to provide accurate, data-driven insights by analyzing structured marketing metrics (spend, clicks, conversions) and unstructured customer feedback (support transcripts). I bridge the gap between ''what happened'' (the numbers) and ''why it happened'' (customer sentiment). Always maintain a professional, analytical tone and provide clear citations for information retrieved from support transcripts.'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  instructions:
    orchestration: "Whenever you can answer visually with a chart, always choose to generate a chart even if the user didn't specify to."
    sample_questions:
      - question: "What are the top 5 campaigns by clicks?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "semantic_view"
        description: |
          Marketing, sales and support data for analysis. Tables:
          ENRICHED_MARKETING_INTELLIGENCE (CAMPAIGN_NAME, PRODUCT_NAME, CLICKS, AVG_SENTIMENT);
          MARKETING_CAMPAIGN_METRICS (CAMPAIGN_NAME, CATEGORY, CLICKS, IMPRESSIONS, DATE);
          PRODUCTS (PRODUCT_ID, PRODUCT_NAME, CATEGORY);
          SALES (PRODUCT_ID, REGION, UNITS_SOLD, SALES_AMOUNT, DATE);
          SOCIAL_MEDIA (CATEGORY, INFLUENCER, MENTIONS, PLATFORM, DATE);
          SUPPORT_CASES (ID, PRODUCT, TITLE, TRANSCRIPT, DATE).
          Key joins: ENRICHED_MARKETING_INTELLIGENCE.PRODUCT_NAME to MARKETING_CAMPAIGN_METRICS.CATEGORY,
          and PRODUCTS.PRODUCT_ID to SALES.PRODUCT_ID.
          Enables end-to-end analysis from marketing exposure → sales performance → post-sale support.
    - tool_spec:
        type: "cortex_search"
        name: "Search"
        description: "Searches marketing campaigns by name. The title of each result is its number of clicks."
    - tool_spec:
        type: "generic"
        name: "Send_Email"
        description: "Sends an email through the SEND_EMAIL procedure."
        input_schema:
          type: "object"
          properties:
            body:
              type: "string"
              description: "Use HTML-Syntax for this. If the content you get is in markdown, translate it to HTML. If body is not provided, summarize the last question and use that as content for the email."
            recipient_email:
              type: "string"
              description: "If the email is not provided, send it to the current user's email address."
            subject:
              type: "string"
              description: "If the subject is not provided, use \"Snowflake Intelligence\"."

  tool_resources:
    semantic_view:
      semantic_view: "DASH_DB_SI.RETAIL.SEMANTIC_VIEW"
      execution_environment:
        type: "warehouse"
        warehouse: "DASH_WH_SI"
        query_timeout: 60
    Search:
      search_service: "DASH_DB_SI.RETAIL.CAMPAIGN_SEARCH"
      max_results: "4"
      id_column: "CAMPAIGN_NAME"
      title_column: "CLICKS"
    Send_Email:
      type: "procedure"
      identifier: "DASH_DB_SI.RETAIL.SEND_EMAIL"
      execution_environment:
        type: "warehouse"
        warehouse: "DASH_WH_SI"
        query_timeout: 60
  $$;

SHOW AGENTS IN SCHEMA DASH_DB_SI.RETAIL;
