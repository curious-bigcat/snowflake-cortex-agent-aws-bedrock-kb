-------------------------------------------------------------------------------
-- Snowflake Setup Script for Retail Intelligence Agent
--
-- This script creates ALL Snowflake objects needed for the Retail Intelligence
-- Agent. Run sections in order. Some sections require manual steps (noted).
--
-- Prerequisites:
--   - ACCOUNTADMIN role (or equivalent privileges)
--   - A warehouse (DEMO_WH used here - change if needed)
--   - AWS setup completed (config/aws_setup.sh) - you need the KB_ID
--   - Data loaded into tables (Phase 4 of README)
--   - Cortex Code CLI installed (for agent creation)
--
-- Usage:
--   Run each section in order in a Snowflake worksheet or via SnowSQL.
--   Sections marked [MANUAL] require CLI commands, not SQL.
-------------------------------------------------------------------------------

-- ============================================================================
-- PHASE 1: DATABASE, SCHEMA, WAREHOUSE
-- ============================================================================

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS RETAIL_AGENT_DB;
CREATE SCHEMA IF NOT EXISTS RETAIL_AGENT_DB.AGENTS;

-- Create warehouse if it doesn't exist (adjust size as needed)
CREATE WAREHOUSE IF NOT EXISTS DEMO_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE DATABASE RETAIL_AGENT_DB;
USE SCHEMA AGENTS;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- PHASE 2: CREATE TABLES
-- ============================================================================

-- Customers table (5000 rows)
CREATE OR REPLACE TABLE CUSTOMERS (
    CUSTOMER_ID VARCHAR(16777216),
    FIRST_NAME VARCHAR(16777216),
    LAST_NAME VARCHAR(16777216),
    FULL_NAME VARCHAR(16777216),
    GENDER VARCHAR(6),
    DATE_OF_BIRTH DATE,
    EMAIL VARCHAR(16777216),
    PHONE VARCHAR(16777216),
    STATE VARCHAR(16777216),
    CITY VARCHAR(16777216),
    CUSTOMER_SEGMENT VARCHAR(12),
    REGISTRATION_DATE DATE,
    STATUS VARCHAR(8)
);

-- Products table (5000 rows)
CREATE OR REPLACE TABLE PRODUCTS (
    PRODUCT_ID VARCHAR(16777216),
    PRODUCT_NAME VARCHAR(16777216),
    CATEGORY VARCHAR(16),
    SUB_CATEGORY VARCHAR(16777216),
    BRAND VARCHAR(16777216),
    PRICE_INR NUMBER(10,2),
    RATING NUMBER(9,1),
    STOCK_STATUS VARCHAR(12),
    SHIPPING_TYPE VARCHAR(8),
    INVENTORY_COUNT NUMBER(3,0)
);

-- Transactions table (10000 rows)
CREATE OR REPLACE TABLE TRANSACTIONS (
    TRANSACTION_ID VARCHAR(16777216),
    CUSTOMER_ID VARCHAR(16777216),
    PRODUCT_ID VARCHAR(16777216),
    TRANSACTION_DATE DATE,
    QUANTITY NUMBER(2,0),
    UNIT_PRICE NUMBER(10,2),
    TOTAL_AMOUNT NUMBER(12,2),
    ORDER_STATUS VARCHAR(10),
    PAYMENT_METHOD VARCHAR(16),
    CHANNEL VARCHAR(17),
    DISCOUNT_PERCENT NUMBER(2,0)
);

-- Customer Events table (5000 rows)
CREATE OR REPLACE TABLE CUSTOMER_EVENTS (
    EVENT_ID VARCHAR(16777216),
    CUSTOMER_ID VARCHAR(16777216),
    EVENT_TIMESTAMP TIMESTAMP_LTZ(9),
    EVENT_TYPE VARCHAR(18),
    EVENT_DATA VARIANT
);

-- Reviews table (5000 rows)
CREATE OR REPLACE TABLE REVIEWS (
    REVIEW_ID VARCHAR(16777216),
    PRODUCT_ID VARCHAR(16777216),
    CUSTOMER_ID VARCHAR(16777216),
    REVIEW_DATE DATE,
    RATING NUMBER(38,0),
    REVIEW_TEXT VARCHAR(16777216)
);

-- Support Tickets table (5000 rows)
CREATE OR REPLACE TABLE SUPPORT_TICKETS (
    TICKET_ID VARCHAR(16777216),
    CUSTOMER_ID VARCHAR(16777216),
    PRODUCT_ID VARCHAR(16777216),
    CREATED_DATE DATE,
    ISSUE_CATEGORY VARCHAR(16),
    PRIORITY VARCHAR(8),
    TICKET_STATUS VARCHAR(11),
    ISSUE_DESCRIPTION VARCHAR(16777216),
    RESOLUTION_NOTES VARCHAR(16777216),
    RESOLUTION_HOURS NUMBER(2,0),
    CSAT_SCORE NUMBER(2,0)
);

-- ============================================================================
-- PHASE 3: LOAD DATA INTO TABLES
-- ============================================================================
-- Option A: Load from local CSVs via Snowsight UI (Upload Data button)
-- Option B: Load from a Snowflake stage
-- Option C: Copy from an existing database (if CORTEX_TEST.RETAIL_360 exists)

-- Option C example (copy from existing tables):
/*
INSERT INTO CUSTOMERS SELECT * FROM CORTEX_TEST.RETAIL_360.CUSTOMERS;
INSERT INTO PRODUCTS SELECT * FROM CORTEX_TEST.RETAIL_360.PRODUCTS;
INSERT INTO TRANSACTIONS SELECT * FROM CORTEX_TEST.RETAIL_360.TRANSACTIONS;
INSERT INTO CUSTOMER_EVENTS SELECT * FROM CORTEX_TEST.RETAIL_360.CUSTOMER_EVENTS;
INSERT INTO REVIEWS SELECT * FROM CORTEX_TEST.RETAIL_360.REVIEWS;
INSERT INTO SUPPORT_TICKETS SELECT * FROM CORTEX_TEST.RETAIL_360.SUPPORT_TICKETS;
*/

-- Verify data loaded
SELECT 'CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM CUSTOMERS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS
UNION ALL SELECT 'CUSTOMER_EVENTS', COUNT(*) FROM CUSTOMER_EVENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'SUPPORT_TICKETS', COUNT(*) FROM SUPPORT_TICKETS;

-- ============================================================================
-- PHASE 4: CORTEX SEARCH - Combined Feedback Table + Search Service
-- ============================================================================

-- Create a combined CUSTOMER_FEEDBACK table (UNION of reviews + tickets)
-- Cortex Search needs a single table with consistent schema and change tracking

CREATE OR REPLACE TABLE CUSTOMER_FEEDBACK AS
SELECT
    REVIEW_ID AS DOC_ID,
    'review' AS DOC_TYPE,
    PRODUCT_ID,
    CUSTOMER_ID,
    REVIEW_DATE AS DOC_DATE,
    CAST(RATING AS VARCHAR) AS RATING,
    NULL AS PRIORITY,
    NULL AS ISSUE_CATEGORY,
    NULL AS TICKET_STATUS,
    REVIEW_TEXT AS CONTENT
FROM REVIEWS
UNION ALL
SELECT
    TICKET_ID AS DOC_ID,
    'support_ticket' AS DOC_TYPE,
    PRODUCT_ID,
    CUSTOMER_ID,
    CREATED_DATE AS DOC_DATE,
    NULL AS RATING,
    PRIORITY,
    ISSUE_CATEGORY,
    TICKET_STATUS,
    COALESCE(ISSUE_DESCRIPTION, '') || ' ' || COALESCE(RESOLUTION_NOTES, '') AS CONTENT
FROM SUPPORT_TICKETS;

-- Enable change tracking (required for Cortex Search)
ALTER TABLE CUSTOMER_FEEDBACK SET CHANGE_TRACKING = TRUE;

-- Verify combined table
SELECT DOC_TYPE, COUNT(*) FROM CUSTOMER_FEEDBACK GROUP BY DOC_TYPE;
-- Expected: review = 5000, support_ticket = 5000

-- Create Cortex Search Service
CREATE OR REPLACE CORTEX SEARCH SERVICE CUSTOMER_FEEDBACK_SEARCH
    ON CONTENT
    ATTRIBUTES DOC_TYPE, PRODUCT_ID, CUSTOMER_ID, RATING, PRIORITY, ISSUE_CATEGORY, TICKET_STATUS
    WAREHOUSE = DEMO_WH
    TARGET_LAG = '1 hour'
    EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'
AS (
    SELECT
      DOC_ID,
      DOC_TYPE,
      PRODUCT_ID,
      CUSTOMER_ID,
      DOC_DATE,
      RATING,
      PRIORITY,
      ISSUE_CATEGORY,
      TICKET_STATUS,
      CONTENT
    FROM CUSTOMER_FEEDBACK
);

-- Verify search service is active
SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- ============================================================================
-- PHASE 5: SEMANTIC VIEW (Cortex Analyst)
-- [MANUAL] - Run via Cortex Code CLI, not SQL
-- ============================================================================

-- Option A: Use FastGen to auto-generate the semantic model YAML
-- Run this in a Snowflake worksheet:
/*
SELECT SYSTEM$CORTEX_ANALYST_FAST_GENERATION(
    TABLE_NAMES => ['RETAIL_AGENT_DB.AGENTS.CUSTOMERS',
                     'RETAIL_AGENT_DB.AGENTS.PRODUCTS',
                     'RETAIL_AGENT_DB.AGENTS.TRANSACTIONS',
                     'RETAIL_AGENT_DB.AGENTS.CUSTOMER_EVENTS'],
    SEMANTIC_MODEL_NAME => 'RETAIL_ANALYTICS_SV'
);
-- This returns a query ID. Use it to extract the YAML:
-- SELECT * FROM TABLE(RESULT_SCAN('<query_id>'));
-- Save the YAML content to config/semantic_model.yaml
*/

-- Option B: Use the provided config/semantic_model.yaml directly
-- Upload via Cortex Code CLI:
--   cd <cortex_code_skill_dir>/bundled_skills/semantic-view
--   SNOWFLAKE_CONNECTION_NAME=default uv run python scripts/upload_semantic_view_yaml.py \
--       /path/to/config/semantic_model.yaml RETAIL_AGENT_DB.AGENTS

-- Verify semantic view exists
SHOW SEMANTIC VIEWS IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- ============================================================================
-- PHASE 6: EXTERNAL ACCESS (for AWS Bedrock KB)
-- ============================================================================

-- Create secrets for AWS credentials
-- IMPORTANT: Replace <YOUR_AWS_ACCESS_KEY_ID> and <YOUR_AWS_SECRET_ACCESS_KEY>
CREATE OR REPLACE SECRET AWS_ACCESS_KEY_ID
    TYPE = GENERIC_STRING
    SECRET_STRING = '<YOUR_AWS_ACCESS_KEY_ID>';

CREATE OR REPLACE SECRET AWS_SECRET_ACCESS_KEY
    TYPE = GENERIC_STRING
    SECRET_STRING = '<YOUR_AWS_SECRET_ACCESS_KEY>';

-- Create network rule for Bedrock API egress
CREATE OR REPLACE NETWORK RULE BEDROCK_KB_NETWORK_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('bedrock-agent-runtime.us-west-2.amazonaws.com');

-- Create external access integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION BEDROCK_KB_ACCESS
    ALLOWED_NETWORK_RULES = (RETAIL_AGENT_DB.AGENTS.BEDROCK_KB_NETWORK_RULE)
    ALLOWED_AUTHENTICATION_SECRETS = (
        RETAIL_AGENT_DB.AGENTS.AWS_ACCESS_KEY_ID,
        RETAIL_AGENT_DB.AGENTS.AWS_SECRET_ACCESS_KEY
    )
    ENABLED = TRUE;

-- ============================================================================
-- PHASE 7: STORED PROCEDURE (Bedrock KB Search)
-- ============================================================================

-- IMPORTANT: Replace <YOUR_BEDROCK_KB_ID> with your actual KB ID from AWS setup
CREATE OR REPLACE PROCEDURE SEARCH_RETAIL_KB(QUERY VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('boto3', 'snowflake-snowpark-python')
HANDLER = 'search_kb'
EXTERNAL_ACCESS_INTEGRATIONS = (BEDROCK_KB_ACCESS)
SECRETS = (
    'AWS_ACCESS_KEY_ID' = RETAIL_AGENT_DB.AGENTS.AWS_ACCESS_KEY_ID,
    'AWS_SECRET_ACCESS_KEY' = RETAIL_AGENT_DB.AGENTS.AWS_SECRET_ACCESS_KEY
)
EXECUTE AS OWNER
AS
$$
import boto3
import json
import _snowflake

def search_kb(session, query: str) -> str:
    aws_access_key = _snowflake.get_generic_secret_string("AWS_ACCESS_KEY_ID")
    aws_secret_key = _snowflake.get_generic_secret_string("AWS_SECRET_ACCESS_KEY")

    client = boto3.client(
        'bedrock-agent-runtime',
        region_name='us-west-2',
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key
    )

    response = client.retrieve(
        knowledgeBaseId='<YOUR_BEDROCK_KB_ID>',
        retrievalQuery={'text': query},
        retrievalConfiguration={
            'vectorSearchConfiguration': {
                'numberOfResults': 10
            }
        }
    )

    results = []
    for result in response.get('retrievalResults', []):
        content = result.get('content', {}).get('text', '')
        score = result.get('score', 0)
        source = result.get('location', {}).get('s3Location', {}).get('uri', 'unknown')
        results.append({
            'content': content,
            'relevance_score': score,
            'source': source
        })

    return json.dumps({
        'query': query,
        'result_count': len(results),
        'results': results
    })
$$;

-- Test the stored procedure
-- CALL SEARCH_RETAIL_KB('top marketing campaigns by ROI');

-- ============================================================================
-- PHASE 8: CREATE AGENT
-- [MANUAL] - Run via Cortex Code CLI, not SQL
-- ============================================================================

-- The agent is created using the Cortex Code CLI script because the agent spec
-- JSON with $$ delimiters is complex to handle in raw SQL.
--
-- Command:
--   cd <cortex_code_install_dir>/bundled_skills/cortex-agent
--   uv run python scripts/create_or_alter_agent.py create \
--       --agent-name RETAIL_INTELLIGENCE_AGENT \
--       --database RETAIL_AGENT_DB \
--       --schema AGENTS \
--       --role ACCOUNTADMIN \
--       --connection default \
--       --config-file /path/to/config/agent_spec.json

-- ============================================================================
-- PHASE 9: AGENT PROFILE + SNOWFLAKE INTELLIGENCE
-- ============================================================================

-- Set agent profile for Snowflake Intelligence display
ALTER AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT
    SET COMMENT = 'Retail 360 Intelligence Agent - Analyzes sales, customer feedback, marketing campaigns, and competitor data for an Indian e-commerce platform.',
        PROFILE = '{"display_name": "Retail Intelligence Agent", "color": "blue"}';

-- Grant Cortex Agent User role
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ACCOUNTADMIN;

-- Add agent to Snowflake Intelligence
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
    ADD AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;

-- Verify agent is registered in Snowflake Intelligence
SHOW AGENTS IN SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;

-- ============================================================================
-- PHASE 10: VERIFICATION QUERIES
-- ============================================================================

-- Verify all tables have data
SELECT 'CUSTOMERS' AS tbl, COUNT(*) AS cnt FROM CUSTOMERS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS
UNION ALL SELECT 'CUSTOMER_EVENTS', COUNT(*) FROM CUSTOMER_EVENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'SUPPORT_TICKETS', COUNT(*) FROM SUPPORT_TICKETS
UNION ALL SELECT 'CUSTOMER_FEEDBACK', COUNT(*) FROM CUSTOMER_FEEDBACK;

-- Verify search service
SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- Verify semantic view
SHOW SEMANTIC VIEWS IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- Verify agent
SHOW AGENTS IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- Verify secrets
SHOW SECRETS IN SCHEMA RETAIL_AGENT_DB.AGENTS;

-- Test: Quick call to Cortex Search (from SQL)
-- SELECT SNOWFLAKE.CORTEX.SEARCH(
--     'RETAIL_AGENT_DB.AGENTS.CUSTOMER_FEEDBACK_SEARCH',
--     '{"query": "delivery complaints", "columns": ["CONTENT", "DOC_TYPE"], "limit": 3}'
-- );

-- ============================================================================
-- CLEANUP (if needed - uncomment to drop everything)
-- ============================================================================
/*
DROP AGENT IF EXISTS RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;
DROP CORTEX SEARCH SERVICE IF EXISTS RETAIL_AGENT_DB.AGENTS.CUSTOMER_FEEDBACK_SEARCH;
DROP SEMANTIC VIEW IF EXISTS RETAIL_AGENT_DB.AGENTS.RETAIL_ANALYTICS_SV;
DROP PROCEDURE IF EXISTS RETAIL_AGENT_DB.AGENTS.SEARCH_RETAIL_KB(VARCHAR);
DROP INTEGRATION IF EXISTS BEDROCK_KB_ACCESS;
DROP NETWORK RULE IF EXISTS RETAIL_AGENT_DB.AGENTS.BEDROCK_KB_NETWORK_RULE;
DROP SECRET IF EXISTS RETAIL_AGENT_DB.AGENTS.AWS_ACCESS_KEY_ID;
DROP SECRET IF EXISTS RETAIL_AGENT_DB.AGENTS.AWS_SECRET_ACCESS_KEY;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.CUSTOMER_FEEDBACK;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.SUPPORT_TICKETS;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.REVIEWS;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.CUSTOMER_EVENTS;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.TRANSACTIONS;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.PRODUCTS;
DROP TABLE IF EXISTS RETAIL_AGENT_DB.AGENTS.CUSTOMERS;
DROP SCHEMA IF EXISTS RETAIL_AGENT_DB.AGENTS;
DROP DATABASE IF EXISTS RETAIL_AGENT_DB;
*/
