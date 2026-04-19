# Snowflake Cortex Agent with AWS Bedrock Knowledge Base

Build a **multi-tool Snowflake Cortex Agent** that combines three tool types — **Cortex Analyst** (text-to-SQL), **Cortex Search** (vector search), and an **AWS Bedrock Knowledge Base** (external retrieval) — into a single conversational agent accessible from **Snowflake Intelligence**.

This repo provides a complete, reproducible implementation using a retail e-commerce example. Swap in your own data for any domain.

---

## What You'll Build

```
                         Snowflake Intelligence UI
                                   |
                          Cortex Agent (orchestrator)
                        /          |            \
              Tool 1: Analyst   Tool 2: Search   Tool 3: Generic
              (text-to-SQL)     (vector search)  (stored procedure)
                   |                 |                   |
            Semantic View    Cortex Search Svc    Python SP + boto3
                   |                 |                   |
            Structured         Unstructured        AWS Bedrock KB
            Tables             Text Data           (AOSS + S3)
                                                        |
                                                   S3 Documents
                                                   (CSV/PDF/TXT)
```

### Three Tool Types in One Agent

| Tool Type | Snowflake Feature | What It Does | Example Use Case |
|-----------|-------------------|--------------|------------------|
| `cortex_analyst_text_to_sql` | Cortex Analyst + Semantic View | Converts natural language to SQL over structured tables | "What is revenue by segment?" |
| `cortex_search` | Cortex Search Service | Semantic vector search over unstructured text | "What are customers saying about quality?" |
| `generic` | Stored Procedure (Python) | Calls any external API via External Access Integration | "What are the top campaigns by ROI?" (via AWS Bedrock KB) |

---

## Key Concepts

### Snowflake Side
- **Cortex Agent**: Orchestrates multiple tools to answer questions. Accepts an agent spec JSON defining tools, instructions, and sample questions.
- **Cortex Analyst + Semantic View**: Text-to-SQL engine. A YAML semantic model defines tables, dimensions, facts, relationships, and verified queries.
- **Cortex Search Service**: Vector search over text data. Requires a table with `CHANGE_TRACKING = TRUE` and an embedding model.
- **External Access Integration**: Allows Snowflake stored procedures to call external APIs. Requires network rules (egress endpoints) and secrets (credentials).
- **Snowflake Intelligence**: The conversational UI in Snowsight where agents are registered and accessible to end users.

### AWS Side
- **S3 Bucket**: Stores documents (CSVs, PDFs, text files) that feed the Knowledge Base.
- **Bedrock Knowledge Base**: Managed RAG service that chunks, embeds, and indexes documents for retrieval.
- **OpenSearch Serverless (AOSS)**: Vector store backend for the KB. Uses HNSW/faiss index with Amazon Titan Embed v2 (1024 dimensions).
- **IAM Role**: Service role that Bedrock assumes to read S3 and write to AOSS.

### The Integration Pattern
```
S3 (documents) → Bedrock KB (embed + index in AOSS) → Bedrock retrieve() API
                                                            ↑
Snowflake SP (boto3) → External Access Integration → Network Rule (egress)
                            ↑                              ↑
                     Secrets (AWS keys)              Allowed endpoints
                            ↑
                    Cortex Agent (generic tool) → Snowflake Intelligence
```

---

## Included Example: Retail E-Commerce

The repo ships with a working retail e-commerce example:

| Data | Rows | Tool | Storage |
|------|------|------|---------|
| Customers, Products, Transactions, Events | 25K | Cortex Analyst (Semantic View) | Snowflake tables |
| Reviews + Support Tickets | 10K | Cortex Search | Snowflake table → Search Service |
| Marketing Campaigns, Competitor Intelligence | 1K | Bedrock KB (generic tool) | S3 → AOSS |

To use your own domain, see [Bring Your Own Data](#bring-your-own-data) below.

---

## Prerequisites

### Snowflake
- Account with **Cortex Agent**, **Cortex Analyst**, and **Cortex Search** enabled
- Role: `ACCOUNTADMIN` (or equivalent privileges)
- Warehouse: X-SMALL or larger
- [Cortex Code CLI](https://docs.snowflake.com/en/user-guide/cortex-code) installed

### AWS
- AWS account with access to **Amazon Bedrock** (us-west-2), **S3**, **OpenSearch Serverless**, **IAM**
- AWS CLI v2 installed and configured
- Python 3.11+ with `boto3` and `opensearch-py`
- IAM user with programmatic access (access key + secret key)

---

## Project Structure

```
├── README.md                           # This guide
├── config/
│   ├── agent_spec.json                 # Agent spec: 3 tools, 30 sample questions (retail example)
│   ├── semantic_model.yaml             # Semantic View YAML: 4 tables, 3 relationships (retail example)
│   ├── snowflake_setup.sql             # Complete Snowflake DDL (10 phases)
│   ├── aws_setup.sh                    # AWS automation: S3, IAM, AOSS, Bedrock KB
│   ├── aws_iam_trust_policy.json       # IAM trust policy for Bedrock service role
│   └── aws_iam_user_policy.json        # IAM policy for S3 + AOSS + Bedrock access
├── data/
│   └── sample_data_generator.py        # Generates 8 CSVs (retail example data)
```

---

## Implementation Guide

### Phase 1: Generate Sample Data

```bash
cd data/
python sample_data_generator.py
```

Generates 8 CSVs:
- **6 for Snowflake tables**: customers, products, transactions, customer_events, reviews, support_tickets
- **2 for S3/Bedrock KB**: marketing_campaigns, competitor_intelligence

---

### Phase 2: Create AWS Bedrock Knowledge Base

This phase creates: S3 bucket → IAM role → AOSS collection (with security policies) → vector index → Bedrock KB → data source + sync.

#### 2.1 Configure

Edit `config/aws_setup.sh`:
```bash
AWS_ACCOUNT_ID="<your-12-digit-account-id>"
AWS_REGION="us-west-2"
AWS_IAM_USER="<your-iam-username>"
```

Update `config/aws_iam_trust_policy.json` and `config/aws_iam_user_policy.json`:
- Replace `<YOUR_AWS_ACCOUNT_ID>` with your account ID
- Replace `<YOUR_S3_BUCKET_NAME>` with your bucket name

#### 2.2 Run

```bash
cd config/
chmod +x aws_setup.sh
./aws_setup.sh
```

**Save the Knowledge Base ID** printed at the end — you'll need it in Phase 6.

#### 2.3 Verify

```bash
aws bedrock-agent get-knowledge-base --knowledge-base-id <KB_ID>
aws bedrock-agent-runtime retrieve \
    --knowledge-base-id <KB_ID> \
    --retrieval-query '{"text": "marketing campaigns"}' \
    --retrieval-configuration '{"vectorSearchConfiguration": {"numberOfResults": 3}}'
```

---

### Phase 3: Create Snowflake Database, Tables, Load Data

Run **Phases 1-3** from `config/snowflake_setup.sql` in a Snowflake worksheet:

```sql
-- Phase 1: Creates database, schema, warehouse
-- Phase 2: Creates all 6 tables
-- Phase 3: Load data (Snowsight UI upload, COPY INTO, or cross-database INSERT)
```

**Verify**:
```sql
SELECT 'CUSTOMERS' AS tbl, COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM TRANSACTIONS
UNION ALL SELECT 'CUSTOMER_EVENTS', COUNT(*) FROM CUSTOMER_EVENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'SUPPORT_TICKETS', COUNT(*) FROM SUPPORT_TICKETS;
```

---

### Phase 4: Create Cortex Search Service

Run **Phase 4** from `config/snowflake_setup.sql`:

```sql
-- Creates combined CUSTOMER_FEEDBACK table (reviews + tickets)
-- Enables CHANGE_TRACKING = TRUE
-- Creates Cortex Search Service with snowflake-arctic-embed-m-v1.5
```

**Verify**:
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA RETAIL_AGENT_DB.AGENTS;
-- indexing_state = ACTIVE, source_data_num_rows = 10000
```

---

### Phase 5: Create Semantic View (Cortex Analyst)

**Option A** — Use the provided YAML:
```bash
# From Cortex Code CLI semantic-view skill directory:
SNOWFLAKE_CONNECTION_NAME=default uv run python scripts/upload_semantic_view_yaml.py \
    /path/to/config/semantic_model.yaml RETAIL_AGENT_DB.AGENTS
```

**Option B** — Auto-generate with FastGen:
```sql
SELECT SYSTEM$CORTEX_ANALYST_FAST_GENERATION(
    TABLE_NAMES => ['RETAIL_AGENT_DB.AGENTS.CUSTOMERS',
                     'RETAIL_AGENT_DB.AGENTS.PRODUCTS',
                     'RETAIL_AGENT_DB.AGENTS.TRANSACTIONS',
                     'RETAIL_AGENT_DB.AGENTS.CUSTOMER_EVENTS'],
    SEMANTIC_MODEL_NAME => 'RETAIL_ANALYTICS_SV'
);
```

---

### Phase 6: Create External Access Integration + Stored Procedure

Run **Phases 6-7** from `config/snowflake_setup.sql`. Replace placeholders:

- `<YOUR_AWS_ACCESS_KEY_ID>` — Your AWS access key
- `<YOUR_AWS_SECRET_ACCESS_KEY>` — Your AWS secret key
- `<YOUR_BEDROCK_KB_ID>` — The KB ID from Phase 2

This creates:
1. **Secrets** (GENERIC_STRING) — AWS credentials stored securely in Snowflake
2. **Network Rule** (EGRESS) — Allows calls to `bedrock-agent-runtime.us-west-2.amazonaws.com`
3. **External Access Integration** — Binds secrets + network rule
4. **Stored Procedure** — Python SP using boto3 to call Bedrock `retrieve()` API

**Verify**:
```sql
CALL SEARCH_RETAIL_KB('marketing campaigns');
-- Returns JSON with retrieval results
```

---

### Phase 7: Create the Cortex Agent

Review `config/agent_spec.json` — ensure `tool_resources` point to your objects:
- `semantic_view`: your semantic view name
- `search_service`: your Cortex Search Service name
- `identifier`: your stored procedure name

Create via Cortex Code CLI:
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

**Test each tool**:
```bash
uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB --schema AGENTS --connection default \
    --question "What is total revenue by segment?"           # Cortex Analyst

uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB --schema AGENTS --connection default \
    --question "What are customers saying about quality?"    # Cortex Search

uv run python scripts/test_agent.py \
    --agent-name RETAIL_INTELLIGENCE_AGENT \
    --database RETAIL_AGENT_DB --schema AGENTS --connection default \
    --question "Top 5 marketing campaigns by ROI?"           # Bedrock KB
```

---

### Phase 8: Register in Snowflake Intelligence

```sql
-- Set agent profile (display name + color in SI UI)
ALTER AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT
    SET COMMENT = 'Multi-tool Cortex Agent with Bedrock KB integration',
        PROFILE = '{"display_name": "Retail Intelligence Agent", "color": "blue"}';

-- Grant required role
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ACCOUNTADMIN;

-- Register in Snowflake Intelligence
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
    ADD AGENT RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;
```

The agent is now available in **Snowsight > AI & ML > Snowflake Intelligence**.

---

## Bring Your Own Data

The retail example is fully swappable. To adapt for your own domain:

### 1. Structured Data (Cortex Analyst)
- Create your own tables in Snowflake
- Generate a semantic model YAML using FastGen:
  ```sql
  SELECT SYSTEM$CORTEX_ANALYST_FAST_GENERATION(
      TABLE_NAMES => ['DB.SCHEMA.YOUR_TABLE_1', 'DB.SCHEMA.YOUR_TABLE_2'],
      SEMANTIC_MODEL_NAME => 'YOUR_MODEL_NAME'
  );
  ```
- Upload via Cortex Code CLI

### 2. Unstructured Text (Cortex Search)
- Create a table with a text column (e.g., descriptions, notes, documents)
- Enable `CHANGE_TRACKING = TRUE`
- Create a Cortex Search Service with `ON <text_column>` and `ATTRIBUTES` for filtering

### 3. External Documents (Bedrock KB)
- Upload your CSVs, PDFs, or text files to S3
- The `aws_setup.sh` script works with any file types — Bedrock handles chunking and embedding
- Update the stored procedure's KB ID

### 4. Agent Spec
- Update `agent_spec.json`:
  - Change tool names and descriptions to match your domain
  - Update `tool_resources` to point to your objects
  - Write domain-specific `instructions.orchestration`
  - Add relevant `sample_questions`

---

## Troubleshooting

### AOSS Collection Not Becoming ACTIVE
- Takes 2-10 minutes. Check: `aws opensearchserverless batch-get-collection --names <name>`
- Encryption and network policies must exist before creating the collection

### AOSS Vector Index Creation Fails
- Data access policy must include both your IAM user AND the Bedrock role
- Index name must be `bedrock-knowledge-base-default-index` (Bedrock's expected default)
- Install: `pip install opensearch-py`

### Bedrock KB Sync Fails
- Verify IAM role trust policy allows `bedrock.amazonaws.com`
- Verify role has S3 read + AOSS access
- Check: `aws bedrock-agent list-ingestion-jobs --knowledge-base-id <KB_ID> --data-source-id <DS_ID>`

### Stored Procedure Returns Empty Results
- Test KB directly via AWS CLI first
- Verify KB_ID in the procedure matches your actual KB
- Ensure data source sync completed

### Cortex Search Not Returning Results
- Table must have `CHANGE_TRACKING = TRUE`
- Wait for `indexing_state = ACTIVE`
- Verify table has data

### Agent Not Visible in Snowflake Intelligence
- Run `SHOW AGENTS IN SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT`
- Ensure you ran `ALTER SNOWFLAKE INTELLIGENCE ... ADD AGENT`
- Grant `SNOWFLAKE.CORTEX_AGENT_USER` to the accessing role

---

## Cleanup

**Snowflake** (see CLEANUP section in `config/snowflake_setup.sql`):
```sql
DROP AGENT IF EXISTS RETAIL_AGENT_DB.AGENTS.RETAIL_INTELLIGENCE_AGENT;
DROP CORTEX SEARCH SERVICE IF EXISTS RETAIL_AGENT_DB.AGENTS.CUSTOMER_FEEDBACK_SEARCH;
DROP SEMANTIC VIEW IF EXISTS RETAIL_AGENT_DB.AGENTS.RETAIL_ANALYTICS_SV;
DROP PROCEDURE IF EXISTS RETAIL_AGENT_DB.AGENTS.SEARCH_RETAIL_KB(VARCHAR);
DROP INTEGRATION IF EXISTS BEDROCK_KB_ACCESS;
-- ... see snowflake_setup.sql for full cleanup
DROP DATABASE IF EXISTS RETAIL_AGENT_DB;
```

**AWS**:
```bash
aws bedrock-agent delete-knowledge-base --knowledge-base-id <KB_ID>
aws opensearchserverless delete-collection --id <COLLECTION_ID>
aws s3 rb s3://<bucket-name> --force
aws iam delete-role-policy --role-name BedrockKBRole --policy-name BedrockKBPolicy
aws iam delete-role --role-name BedrockKBRole
```
