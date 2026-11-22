-- Section 7: the original setup check, plus row counts per table.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;

-- EXECUTE IMMEDIATE $$ keeps the snow CLI from splitting the block at each semicolon
EXECUTE IMMEDIATE $$
DECLARE
    table_count INTEGER DEFAULT 0;
    row_count INTEGER DEFAULT 0;
BEGIN
    SELECT COUNT(*) INTO :table_count
    FROM dash_db_si.information_schema.tables
    WHERE table_schema = 'RETAIL'
      AND table_name IN ('MARKETING_CAMPAIGN_METRICS','PRODUCTS','SALES','SOCIAL_MEDIA','SUPPORT_CASES');

    IF (:table_count < 5) THEN
        RETURN 'SETUP INCOMPLETE: Found ' || :table_count || ' of 5 required tables.';
    END IF;

    SELECT COUNT(*) INTO :row_count FROM dash_db_si.retail.sales;

    IF (:row_count = 0) THEN
        RETURN 'SETUP INCOMPLETE: Tables exist but contain no data.';
    END IF;

    RETURN 'Setup complete: 5 tables created and loaded with data.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SETUP INCOMPLETE: Required objects not found.';
END;
$$;

SELECT 'MARKETING_CAMPAIGN_METRICS' t, COUNT(*) n FROM dash_db_si.retail.marketing_campaign_metrics
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM dash_db_si.retail.products
UNION ALL SELECT 'SALES', COUNT(*) FROM dash_db_si.retail.sales
UNION ALL SELECT 'SOCIAL_MEDIA', COUNT(*) FROM dash_db_si.retail.social_media
UNION ALL SELECT 'SUPPORT_CASES', COUNT(*) FROM dash_db_si.retail.support_cases;
