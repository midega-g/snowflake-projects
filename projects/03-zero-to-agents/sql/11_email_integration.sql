-- Section 6: email notification integration and the send_email procedure.
USE ROLE SNOWFLAKE_INTELLIGENCE_ADMIN;
USE WAREHOUSE DASH_WH_SI;
USE SCHEMA DASH_DB_SI.RETAIL;

CREATE OR REPLACE NOTIFICATION INTEGRATION EMAIL_INTEGRATION
  TYPE = EMAIL
  ENABLED = TRUE
  DEFAULT_SUBJECT = 'snowflake intelligence'
  COMMENT = 'Email notification integration used by the SEND_EMAIL procedure.';

CREATE OR REPLACE PROCEDURE SEND_EMAIL(
    RECIPIENT_EMAIL VARCHAR,
    SUBJECT VARCHAR,
    BODY VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'send_email'
COMMENT = 'Sends an HTML email through EMAIL_INTEGRATION and returns a status message.'
AS
$$
def send_email(session, recipient_email, subject, body):
    try:
        # Escape single quotes in the body
        escaped_body = body.replace("'", "''")

        # Execute the system procedure call
        session.sql(f"""
            CALL SYSTEM$SEND_EMAIL(
                'email_integration',
                '{recipient_email}',
                '{subject}',
                '{escaped_body}',
                'text/html'
            )
        """).collect()

        return "Email sent successfully"
    except Exception as e:
        return f"Error sending email: {str(e)}"
$$;
