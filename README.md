# Retail Intelligence Agent - Implementation Guide

A multi-tool Snowflake Cortex Agent for Indian e-commerce analytics, combining **Cortex Analyst** (structured data), **Cortex Search** (text search), and **AWS Bedrock Knowledge Base** (external KB) into a single conversational agent accessible from **Snowflake Intelligence**.

---

## Architecture

```
                          Snowflake Intelligence UI
                                    |
                    RETAIL_INTELLIGENCE_AGENT (Cortex Agent)
                     /              |               \
            Tool 1: Analyst    Tool 2: Search    Tool 3: Generic
            (text-to-SQL)      (vector search)   (stored procedure)
                 |                  |                    |
          Semantic View     Cortex Search Svc     Python SP + boto3
               |                  |                    |
         4 Tables            CUSTOMER_FEEDBACK    AWS Bedrock KB
         (structured)        (10K reviews+tickets) (AOSS + S3)
                                                       |
                                                  S3 CSVs
                                                  (marketing +
                                                   competitor data)
```

### Three Tools

| Tool | Type | Data Source | Use Case |
|------|------|-------------|----------|
| `query_retail_data` | `cortex_analyst_text_to_sql` | Semantic View over 4 tables | Revenue, orders, customers, products, trends |
| `search_customer_feedback` | `cortex_search` | 10K reviews + support tickets | Sentiment, complaints, feedback, CSAT |
| `search_retail_kb` | `generic` (stored procedure) | AWS Bedrock KB (S3 CSVs) | Marketing campaigns, competitor intelligence |

---

## Prerequisites

### Snowflake
- **Account** with Cortex Agent, Cortex Analyst, and Cortex Search enabled
- **Role**: ACCOUNTADMIN (or role with CREATE DATABASE, CREATE INTEGRATION, CREATE AGENT privileges)
- **Warehouse**: X-SMALL or larger
- **Cortex Code CLI** installed ([docs](https://docs.snowflake.com/en/user-guide/cortex-code))

### AWS
- **AWS Account** with access to:
  - Amazon Bedrock (us-west-2 region)
  - Amazon S3
  - OpenSearch Serverless (AOSS)
  - IAM
- **AWS CLI v2** installed and configured
- **Python 3.11+** with `boto3` and `opensearch-py` packages
- **IAM User** with programmatic access (access key + secret key)

### Local
- Python 3.11+
- `pip install faker pandas boto3 opensearch-py`

---

## Project Structure

```
retail-intelligence-agent/
├── README.md                        # This file
├── config/
│   ├── agent_spec.json              # Cortex Agent specification (3 tools, 30 questions)
│   ├── semantic_model.yaml          # Semantic View YAML (4 tables, 3 relationships)
│   ├── snowflake_setup.sql          # Complete Snowflake DDL script
│   ├── aws_setup.sh                 # AWS infrastructure setup (S3, IAM, AOSS, Bedrock)
│   ├── aws_iam_trust_policy.json    # IAM trust policy for Bedrock role
│   └── aws_iam_user_policy.json     # IAM policy for user/role accessing KB
├── data/
│   └── sample_data_generator.py     # Generates all 8 CSV datasets
└── (generated after running data generator)
    ├── customers.csv
    ├── products.csv
    ├── transactions.csv
    ├── customer_events.csv
    ├── reviews.csv
    ├── support_tickets.csv
    ├── marketing_campaigns.csv
    └── competitor_intelligence.csv
```

---

## Implementation Steps

### Phase 1: Generate Sample Data

```bash
cd data/
pip install faker pandas
python sample_data_generator.py
```

This creates 8 CSV files:
- **6 for Snowflake tables**: customers, products, transactions, customer_events, reviews, support_tickets
- **2 for AWS Bedrock KB**: marketing_campaigns, competitor_intelligence

**Verify**: You should see 8 `.csv` files in the `data/` directory.

---

### Phase 2: AWS Setup (Bedrock Knowledge Base)

This phase creates the S3 bucket, IAM role, OpenSearch Serverless collection, and Bedrock Knowledge Base.

#### 2.1 Configure the script

Edit `config/aws_setup.sh` and update the CONFIGURATION section:

```bash
AWS_ACCOUNT_ID="<your-12-digit-aws-account-id>"
AWS_REGION="us-west-2"
AWS_IAM_USER="<your-iam-username>"
S3_BUCKET_NAME="retail-agent-kb-data-<your-username>"
```

Also update `config/aws_iam_trust_policy.json` and `config/aws_iam_user_policy.json`:
- Replace all `<YOUR_AWS_ACCOUNT_ID>` with your actual AWS account ID
- Replace `<YOUR_S3_BUCKET_NAME>` with your bucket name

#### 2.2 Run the setup

```bash
cd config/
chmod +x aws_setup.sh
./aws_setup.sh
```

The script will:
1. Create S3 bucket and upload CSVs
2. Create IAM role with Bedrock trust policy
3. Create AOSS collection with encryption, network, and data access policies
4. Wait for AOSS to become ACTIVE (~2-5 minutes)
5. Create vector index (1024 dimensions, HNSW/faiss, Titan Embed v2)
6. Create Bedrock Knowledge Base
7. Create S3 data source and start sync

**IMPORTANT**: Note the **Knowledge Base ID** (e.g., `TM07QB27QC`) printed at the end. You need this for Phase 5.

#### 2.3 Verify

```bash
# Check KB status
aws bedrock-agent get-knowledge-base --knowledge-base-id <YOUR_KB_ID>

# Check sync status
aws bedrock-agent list-ingestion-jobs \
    --knowledge-base-id <YOUR_KB_ID> \
    --data-source-id <YOUR_DS_ID>

# Test retrieval
aws bedrock-agent-runtime retrieve \
    --knowledge-base-id <YOUR_KB_ID> \
    --retrieval-query '{"text": "top marketing campaigns by ROI"}' \
    --retrieval-configuration '{"vectorSearchConfiguration": {"numberOfResults": 3}}'
```

---

### Phase 3: Snowflake - Database, Tables, and Data

#### 3.1 Create database and tables

Open `config/snowflake_setup.sql` in a Snowflake worksheet (Snowsight) and run **Phases 1-2** (lines 1-120):

```sql
-- Creates: RETAIL_AGENT_DB, AGENTS schema, DEMO_WH warehouse
-- Creates: CUSTOMERS, PRODUCTS, TRANSACTIONS, CUSTOMER_EVENTS, REVIEWS, SUPPORT_TICKETS tables
```

#### 3.2 Load data

**Option A** (Snowsight UI): Use the "Upload Data" button in the database objects panel to upload each CSV file to its corresponding table.

**Option B** (COPY INTO from stage):
```sql
-- Create a stage
CREATE OR REPLACE STAGE RETAIL_DATA_STAGE;

-- PUT files (from SnowSQL)
-- PUT file:///path/to/data/customers.csv @RETAIL_DATA_STAGE;
-- ... repeat for each CSV

-- COPY INTO each table
-- COPY INTO CUSTOMERS FROM @RETAIL_DATA_STAGE/customers.csv
--     FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);
```

**Option C** (Copy from existing database, if CORTEX_TEST.RETAIL_360 exists):
```sql
INSERT INTO CUSTOMERS SELECT * FROM CORTEX_TEST.RETAIL_360.CUSTOMERS;
INSERT INTO PRODUCTS SELECT * FROM CORTEX_TEST.RETAIL_360.PRODUCTS;
-- ... repeat for all 6 tables
```

#### 3.3 Verify

Run the verification query from `snowflake_setup.sql` Phase 3:
```sql
SELECT 'CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM CUSTOMERS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS
UNION ALL SELECT 'CUSTOMER_EVENTS', COUNT(*) FROM CUSTOMER_EVENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'SUPPORT_TICKETS', COUNT(*) FROM SUPPORT_TICKETS;
```

Expected: CUSTOMERS=5000, PRODUCTS=5000, TRANSACTIONS=10000, CUSTOMER_EVENTS=5000, REVIEWS=5000, SUPPORT_TICKETS=5000.

---

### Phase 4: Cortex Search Service

Run **Phase 4** from `config/snowflake_setup.sql`:

```sql
-- Creates CUSTOMER_FEEDBACK table (UNION ALL of reviews + tickets, 10K rows)
-- Enables change tracking
-- Creates CUSTOMER_FEEDBACK_SEARCH Cortex Search Service
```

**Verify**:
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAIL_AGENT_DB.AGENTS;
-- Should show: CUSTOMER_FEEDBACK_SEARCH, indexing_state=ACTIVE, source_data_num_rows=10000
```

The search service uses `snowflake-arctic-embed-m-v1.5` for embeddings and has a 1-hour target lag.

---

### Phase 5: Semantic View (Cortex Analyst)

The semantic view defines the data model for natural language to SQL.

#### Option A: Use the provided YAML

```bash
# From the Cortex Code CLI semantic-view skill directory:
cd <cortex-code-install>/bundled_skills/semantic-view

SNOWFLAKE_CONNECTION_NAME=default uv run python scripts/upload_semantic_view_yaml.py \
    /path/to/config/semantic_model.yaml \
    RETAIL_AGENT_DB.AGENTS
```

#### Option B: Generate with FastGen

Run in a Snowflake worksheet:
```sql
SELECT SYSTEM$CORTEX_ANALYST_FAST_GENERATION(
    TABLE_NAMES => ['RETAIL_AGENT_DB.AGENTS.CUSTOMERS',
                     'RETAIL_AGENT_DB.AGENTS.PRODUCTS',
                     'RETAIL_AGENT_DB.AGENTS.TRANSACTIONS',
                     'RETAIL_AGENT_DB.AGENTS.CUSTOMER_EVENTS'],
    SEMANTIC_MODEL_NAME => 'RETAIL_ANALYTICS_SV'
);
```

Then extract the YAML from the result, save to a file, and upload using the command above.

**Verify**:
```sql
SHOW SEMANTIC VIEWS IN SCHEMA RETAIL_AGENT_DB.AGENTS;
-- Should show: RETAIL_ANALYTICS_SV
```

---

### Phase 6: External Access (AWS Bedrock Integration)

Run **Phase 6** from `config/snowflake_setup.sql`. You must replace placeholders:

```sql
-- Replace <YOUR_AWS_ACCESS_KEY_ID> and <YOUR_AWS_SECRET_ACCESS_KEY>
CREATE OR REPLACE SECRET AWS_ACCESS_KEY_ID
    TYPE = GENERIC_STRING
    SECRET_STRING = '<YOUR_AWS_ACCESS_KEY_ID>';

CREATE OR REPLACE SECRET AWS_SECRET_ACCESS_KEY
    TYPE = GENERIC_STRING
    SECRET_STRING = '<YOUR_AWS_SECRET_ACCESS_KEY>';
```

Then create the network rule and external access integration (Phase 6 of the SQL script).

---

### Phase 7: Stored Procedure (Bedrock KB Search)

Run **Phase 7** from `config/snowflake_setup.sql`. Replace `<YOUR_BEDROCK_KB_ID>` with the KB ID from Phase 2.

```sql
-- The procedure calls AWS Bedrock's retrieve() API via boto3
-- Uses GENERIC_STRING secrets for AWS credentials
-- Egress allowed via BEDROCK_KB_ACCESS integration
```

**Verify**:
```sql
CALL SEARCH_RETAIL_KB('top marketing campaigns by ROI');
-- Should return JSON with retrieval results from the KB
```

---

### Phase 8: Create the Agent

The agent is created via the Cortex Code CLI (not raw SQL) because the agent spec JSON is complex.

#### 8.1 Review agent_spec.json

Review `config/agent_spec.json` to ensure:
- `tool_resources.query_retail_data.semantic_view` points to your semantic view
- `tool_resources.search_customer_feedback.search_service` points to your search service
- `tool_resources.search_retail_kb.identifier` points to your stored procedure
- All warehouse names match your warehouse

#### 8.2 Create the agent

```bash
cd <cortex-code-install>/bundled_skills/cortex-agent

uv run python scripts/create_or_alter_agent.py create \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB \
    --schema AGENTS \
    --role ACCOUNTADMIN \
    --connection default \
    --config-file /path/to/config/agent_spec.json
```

#### 8.3 Test the agent

```bash
# Test Cortex Analyst tool
uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB \
    --schema AGENTS \
    --connection default \
    --question "What is the total revenue by customer segment?"

# Test Cortex Search tool
uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB \
    --schema AGENTS \
    --connection default \
    --question "What are customers saying about product quality?"

# Test Bedrock KB tool
uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB \
    --schema AGENTS \
    --connection default \
    --question "What are the top 5 marketing campaigns by ROI?"
```

---

### Phase 9: Register in Snowflake Intelligence

Run **Phase 9** from `config/snowflake_setup.sql`:

```sql
-- Set profile for display in Snowflake Intelligence
ALTER AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT
    SET COMMENT = 'Retail 360 Intelligence Agent',
        PROFILE = '{"display_name": "Retail Intelligence Agent", "color": "blue"}';

-- Grant required database role
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ACCOUNTADMIN;

-- Register agent in Snowflake Intelligence
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
    ADD AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;

-- Verify
SHOW AGENTS IN SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
```

The agent is now accessible from **AI & ML > Snowflake Intelligence** in Snowsight.

---

## Sample Questions

The agent comes with 30 pre-configured sample questions:

### Individual Tool: Cortex Analyst (structured data)
1. What is the total revenue by customer segment?
2. Which product categories have the highest sales?
3. Show me the monthly revenue trend for 2025
4. Which payment methods are most popular?
5. What is the average order value by sales channel?
6. How many customers are in each segment?
7. Which brands have the highest average product rating?
8. Show me top 10 states by revenue

### Individual Tool: Cortex Search (text search)
9. What are customers saying about product quality?
10. What are the most common support ticket issues?
11. Show me negative reviews for electronics products
12. What complaints do customers have about delivery?
13. Are there any critical priority support tickets still open?
14. What do customers say about product packaging?

### Individual Tool: Marketing & Competitor KB
15. What are the top 5 marketing campaigns by ROI?
16. Compare our prices with Flipkart and Amazon India
17. Which marketing channels have the best conversion rates?
18. What is the competitor pricing trend for electronics?
19. Which competitors have the highest market share in fashion?
20. Compare delivery times across all competitors

### Cross-Tool (2 tools combined)
21. Which products have high sales but poor reviews?
22. Our electronics revenue is growing - what do customers think about our electronics?
23. Which customer segments file the most support tickets?
24. Show me high-value customers who left negative reviews
25. Are our best-selling products in stock at competitors?
26. How does our pricing compare to competitors for top-selling categories?

### Cross-Platform (all 3 tools)
27. Which marketing campaigns drove the most actual transactions?
28. Give me a full 360 view of our electronics business
29. What is the complete picture for the Fashion category - sales, reviews, and competition?
30. Summarize our business health - revenue trends, customer satisfaction, and competitive position

---

## Troubleshooting

### AOSS Collection Not Becoming ACTIVE
- AOSS collections can take 5-10 minutes to become ACTIVE
- Check status: `aws opensearchserverless batch-get-collection --names <collection-name>`
- Ensure encryption and network policies were created first

### AOSS Vector Index Creation Fails
- Ensure the data access policy includes both your IAM user AND the Bedrock role
- Install opensearch-py: `pip install opensearch-py`
- The index name must be `bedrock-knowledge-base-default-index` (Bedrock default)

### Bedrock KB Sync Fails
- Verify the IAM role trust policy allows `bedrock.amazonaws.com`
- Verify the role has S3 read access and AOSS access
- Check sync status: `aws bedrock-agent list-ingestion-jobs --knowledge-base-id <KB_ID> --data-source-id <DS_ID>`

### Stored Procedure Returns Empty Results
- Test the KB directly via AWS CLI first (Phase 2.3)
- Verify the KB_ID in the stored procedure matches your actual KB
- Check that the data source sync completed successfully

### Semantic View Upload Fails
- Ensure database and schema names in YAML match your actual objects
- Verify all referenced tables exist and have data
- Use `cortex reflect config/semantic_model.yaml` to validate the YAML

### Agent Creation Fails
- Ensure all tool_resources reference existing Snowflake objects
- Verify the agent_spec.json is valid JSON
- Check that the semantic view, search service, and stored procedure all exist

### Cortex Search Not Returning Results
- The CUSTOMER_FEEDBACK table must have `CHANGE_TRACKING = TRUE`
- Wait for the search service to finish indexing (check `indexing_state` = ACTIVE)
- Verify the table has data: `SELECT COUNT(*) FROM CUSTOMER_FEEDBACK`

### Agent Not Visible in Snowflake Intelligence
- Run: `SHOW AGENTS IN SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT`
- Ensure you ran the `ALTER SNOWFLAKE INTELLIGENCE ... ADD AGENT` command
- Grant `SNOWFLAKE.CORTEX_AGENT_USER` to the role accessing Snowflake Intelligence

---

## Cleanup

To remove all resources:

**Snowflake** (uncomment the CLEANUP section in `config/snowflake_setup.sql`):
```sql
DROP AGENT IF EXISTS RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;
-- ... (see full cleanup in snowflake_setup.sql)
DROP DATABASE IF EXISTS RETAIL_AGENT_DB;
```

**AWS**:
```bash
# Delete KB
aws bedrock-agent delete-knowledge-base --knowledge-base-id <KB_ID>

# Delete AOSS collection
aws opensearchserverless delete-collection --id <COLLECTION_ID>

# Delete AOSS policies
aws opensearchserverless delete-security-policy --name <collection>-enc --type encryption
aws opensearchserverless delete-security-policy --name <collection>-net --type network
aws opensearchserverless delete-access-policy --name <collection>-access --type data

# Delete S3 bucket
aws s3 rb s3://<bucket-name> --force

# Delete IAM role
aws iam delete-role-policy --role-name BedrockKBRetailRole --policy-name BedrockKBRetailPolicy
aws iam delete-role --role-name BedrockKBRetailRole
```
