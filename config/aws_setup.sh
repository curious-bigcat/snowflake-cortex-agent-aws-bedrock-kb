#!/bin/bash
###############################################################################
# AWS Setup Script — Bedrock Knowledge Base with S3 Data Source
#
# Creates the full AWS infrastructure for a Bedrock KB that Snowflake can call:
#   1. S3 bucket for KB data (upload any CSV/PDF/TXT files)
#   2. IAM role with trust policy for Amazon Bedrock
#   3. IAM policy for the role to access S3, AOSS, Bedrock
#   4. OpenSearch Serverless (AOSS) collection with security policies
#   5. AOSS vector index (Titan Embed v2, 1024 dims, HNSW/faiss)
#   6. Bedrock Knowledge Base with S3 data source
#   7. Data source sync (chunks + embeds your documents)
#
# This script is DOMAIN-AGNOSTIC. The included example uploads retail
# e-commerce CSVs, but you can upload any documents to S3.
#
# Prerequisites:
#   - AWS CLI v2 installed and configured
#   - Python 3.11+ with boto3 and opensearch-py installed
#   - Sufficient IAM permissions (Admin or Bedrock/AOSS/S3/IAM access)
#
# Usage:
#   1. Edit the CONFIGURATION section below with your values
#   2. chmod +x aws_setup.sh
#   3. ./aws_setup.sh
###############################################################################

set -euo pipefail

# ============================================================================
# CONFIGURATION - Edit these values
# ============================================================================
AWS_ACCOUNT_ID="<YOUR_AWS_ACCOUNT_ID>"          # e.g., 484577546576
AWS_REGION="us-west-2"
AWS_IAM_USER="<YOUR_IAM_USERNAME>"               # e.g., bharaths
S3_BUCKET_NAME="bedrock-kb-data-${AWS_IAM_USER}"
IAM_ROLE_NAME="BedrockKBRole"
AOSS_COLLECTION_NAME="bedrock-kb-collection"
AOSS_INDEX_NAME="bedrock-knowledge-base-default-index"
KB_NAME="cortex-agent-kb"
KB_DESCRIPTION="Bedrock Knowledge Base for Snowflake Cortex Agent"
EMBEDDING_MODEL_ARN="arn:aws:bedrock:${AWS_REGION}::foundation-model/amazon.titan-embed-text-v2:0"
DATA_DIR="../data"  # Directory containing your documents (CSVs, PDFs, etc.)

echo "============================================"
echo "Bedrock Knowledge Base - AWS Setup"
echo "============================================"
echo "Account: ${AWS_ACCOUNT_ID}"
echo "Region:  ${AWS_REGION}"
echo "Bucket:  ${S3_BUCKET_NAME}"
echo ""

# ============================================================================
# STEP 1: Create S3 Bucket and Upload Documents
# ============================================================================
echo "[Step 1/7] Creating S3 bucket and uploading data..."

aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null || echo "  Bucket already exists, continuing..."

# Upload documents to S3 (example: retail CSVs — replace with your own files)
if [ -f "${DATA_DIR}/marketing_campaigns.csv" ]; then
    aws s3 cp "${DATA_DIR}/marketing_campaigns.csv" "s3://${S3_BUCKET_NAME}/marketing_campaigns.csv"
    echo "  Uploaded marketing_campaigns.csv"
else
    echo "  WARNING: ${DATA_DIR}/marketing_campaigns.csv not found. Generate data first (see data/sample_data_generator.py)"
fi

if [ -f "${DATA_DIR}/competitor_intelligence.csv" ]; then
    aws s3 cp "${DATA_DIR}/competitor_intelligence.csv" "s3://${S3_BUCKET_NAME}/competitor_intelligence.csv"
    echo "  Uploaded competitor_intelligence.csv"
else
    echo "  WARNING: ${DATA_DIR}/competitor_intelligence.csv not found. Generate data first (see data/sample_data_generator.py)"
fi

echo "  S3 setup complete."
echo ""

# ============================================================================
# STEP 2: Create IAM Role for Bedrock KB
# ============================================================================
echo "[Step 2/7] Creating IAM role for Bedrock KB..."

# Update trust policy with actual account ID
TRUST_POLICY=$(cat aws_iam_trust_policy.json | sed "s/<YOUR_AWS_ACCOUNT_ID>/${AWS_ACCOUNT_ID}/g")

aws iam create-role \
    --role-name "${IAM_ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}" \
    --description "Role for Bedrock Knowledge Base to access S3 and AOSS" \
    2>/dev/null || echo "  Role already exists, continuing..."

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
echo "  Role ARN: ${ROLE_ARN}"

# Attach inline policy for S3 + AOSS + Bedrock access
ROLE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${S3_BUCKET_NAME}", "arn:aws:s3:::${S3_BUCKET_NAME}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["aoss:APIAccessAll"],
      "Resource": "arn:aws:aoss:${AWS_REGION}:${AWS_ACCOUNT_ID}:collection/*"
    },
    {
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel"],
      "Resource": "arn:aws:bedrock:${AWS_REGION}::foundation-model/*"
    }
  ]
}
EOF
)

aws iam put-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-name "BedrockKBPolicy" \
    --policy-document "${ROLE_POLICY}"

echo "  IAM role setup complete."
echo ""

# ============================================================================
# STEP 3: Create OpenSearch Serverless (AOSS) Collection
# ============================================================================
echo "[Step 3/7] Creating AOSS collection and security policies..."

# Encryption policy
aws opensearchserverless create-security-policy \
    --name "${AOSS_COLLECTION_NAME}-enc" \
    --type "encryption" \
    --policy "{\"Rules\":[{\"ResourceType\":\"collection\",\"Resource\":[\"collection/${AOSS_COLLECTION_NAME}\"]}],\"AWSOwnedKey\":true}" \
    2>/dev/null || echo "  Encryption policy already exists"

# Network policy (public access for simplicity - restrict in production)
aws opensearchserverless create-security-policy \
    --name "${AOSS_COLLECTION_NAME}-net" \
    --type "network" \
    --policy "[{\"Rules\":[{\"ResourceType\":\"collection\",\"Resource\":[\"collection/${AOSS_COLLECTION_NAME}\"]},{\"ResourceType\":\"dashboard\",\"Resource\":[\"collection/${AOSS_COLLECTION_NAME}\"]}],\"AllowFromPublic\":true}]" \
    2>/dev/null || echo "  Network policy already exists"

# Data access policy
aws opensearchserverless create-access-policy \
    --name "${AOSS_COLLECTION_NAME}-access" \
    --type "data" \
    --policy "[{\"Rules\":[{\"ResourceType\":\"index\",\"Resource\":[\"index/${AOSS_COLLECTION_NAME}/*\"],\"Permission\":[\"aoss:*\"]},{\"ResourceType\":\"collection\",\"Resource\":[\"collection/${AOSS_COLLECTION_NAME}\"],\"Permission\":[\"aoss:*\"]}],\"Principal\":[\"arn:aws:iam::${AWS_ACCOUNT_ID}:user/${AWS_IAM_USER}\",\"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}\"]}]" \
    2>/dev/null || echo "  Data access policy already exists"

# Create the collection
COLLECTION_RESPONSE=$(aws opensearchserverless create-collection \
    --name "${AOSS_COLLECTION_NAME}" \
    --type "VECTORSEARCH" \
    --description "Vector store for Bedrock Knowledge Base" \
    2>/dev/null || echo "{}")

echo "  Waiting for AOSS collection to become ACTIVE (this takes 2-5 minutes)..."
aws opensearchserverless wait collection-active \
    --names "${AOSS_COLLECTION_NAME}" \
    2>/dev/null || true

# Get collection endpoint
COLLECTION_ENDPOINT=$(aws opensearchserverless batch-get-collection \
    --names "${AOSS_COLLECTION_NAME}" \
    --query "collectionDetails[0].collectionEndpoint" \
    --output text)

COLLECTION_ARN=$(aws opensearchserverless batch-get-collection \
    --names "${AOSS_COLLECTION_NAME}" \
    --query "collectionDetails[0].arn" \
    --output text)

echo "  Collection Endpoint: ${COLLECTION_ENDPOINT}"
echo "  Collection ARN: ${COLLECTION_ARN}"
echo ""

# ============================================================================
# STEP 4: Create AOSS Vector Index
# ============================================================================
echo "[Step 4/7] Creating AOSS vector index..."
echo "  NOTE: This step uses Python with opensearch-py. Run separately if this fails."

python3 - <<PYEOF
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
import boto3, time

region = "${AWS_REGION}"
host = "${COLLECTION_ENDPOINT}".replace("https://", "")

credentials = boto3.Session().get_credentials()
auth = AWSV4SignerAuth(credentials, region, "aoss")

client = OpenSearch(
    hosts=[{"host": host, "port": 443}],
    http_auth=auth,
    use_ssl=True,
    verify_certs=True,
    connection_class=RequestsHttpConnection,
    timeout=60,
)

index_name = "${AOSS_INDEX_NAME}"

index_body = {
    "settings": {
        "index": {
            "knn": True,
            "number_of_shards": 2,
            "number_of_replicas": 0,
            "knn.algo_param.ef_search": 512,
        }
    },
    "mappings": {
        "properties": {
            "bedrock-knowledge-base-default-vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "engine": "faiss",
                    "space_type": "l2",
                    "name": "hnsw",
                    "parameters": {"ef_construction": 512, "m": 16},
                },
            },
            "AMAZON_BEDROCK_METADATA": {"type": "text", "index": False},
            "AMAZON_BEDROCK_TEXT_CHUNK": {"type": "text"},
        }
    },
}

try:
    client.indices.create(index=index_name, body=index_body)
    print(f"  Vector index '{index_name}' created successfully.")
except Exception as e:
    if "already exists" in str(e).lower() or "resource_already_exists" in str(e).lower():
        print(f"  Vector index '{index_name}' already exists.")
    else:
        print(f"  Error creating index: {e}")
        print("  You may need to create the index manually. See README.md troubleshooting section.")
PYEOF

echo ""

# ============================================================================
# STEP 5: Create Bedrock Knowledge Base
# ============================================================================
echo "[Step 5/7] Creating Bedrock Knowledge Base..."

KB_RESPONSE=$(aws bedrock-agent create-knowledge-base \
    --name "${KB_NAME}" \
    --description "${KB_DESCRIPTION}" \
    --role-arn "${ROLE_ARN}" \
    --knowledge-base-configuration "{
        \"type\": \"VECTOR\",
        \"vectorKnowledgeBaseConfiguration\": {
            \"embeddingModelArn\": \"${EMBEDDING_MODEL_ARN}\"
        }
    }" \
    --storage-configuration "{
        \"type\": \"OPENSEARCH_SERVERLESS\",
        \"opensearchServerlessConfiguration\": {
            \"collectionArn\": \"${COLLECTION_ARN}\",
            \"vectorIndexName\": \"${AOSS_INDEX_NAME}\",
            \"fieldMapping\": {
                \"vectorField\": \"bedrock-knowledge-base-default-vector\",
                \"textField\": \"AMAZON_BEDROCK_TEXT_CHUNK\",
                \"metadataField\": \"AMAZON_BEDROCK_METADATA\"
            }
        }
    }" \
    2>/dev/null)

KB_ID=$(echo "${KB_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['knowledgeBase']['knowledgeBaseId'])" 2>/dev/null || echo "UNKNOWN")

echo "  Knowledge Base ID: ${KB_ID}"
echo "  IMPORTANT: Save this KB_ID - you need it in the Snowflake stored procedure!"
echo ""

# ============================================================================
# STEP 6: Create Data Source and Sync
# ============================================================================
echo "[Step 6/7] Creating data source and syncing..."

DS_RESPONSE=$(aws bedrock-agent create-data-source \
    --knowledge-base-id "${KB_ID}" \
    --name "s3-data-source" \
    --description "S3 data source for Bedrock Knowledge Base" \
    --data-source-configuration "{
        \"type\": \"S3\",
        \"s3Configuration\": {
            \"bucketArn\": \"arn:aws:s3:::${S3_BUCKET_NAME}\"
        }
    }" \
    2>/dev/null)

DS_ID=$(echo "${DS_RESPONSE}" | python3 -c "import sys,json; print(json.load(sys.stdin)['dataSource']['dataSourceId'])" 2>/dev/null || echo "UNKNOWN")

echo "  Data Source ID: ${DS_ID}"

# Start sync
echo "  Starting data source sync..."
aws bedrock-agent start-ingestion-job \
    --knowledge-base-id "${KB_ID}" \
    --data-source-id "${DS_ID}" \
    2>/dev/null

echo "  Sync started. It may take a few minutes to complete."
echo ""

# ============================================================================
# STEP 7: Summary
# ============================================================================
echo "[Step 7/7] Summary"
echo "============================================"
echo "AWS Setup Complete!"
echo "============================================"
echo ""
echo "Resources created:"
echo "  S3 Bucket:        s3://${S3_BUCKET_NAME}"
echo "  IAM Role:         ${ROLE_ARN}"
echo "  AOSS Collection:  ${AOSS_COLLECTION_NAME}"
echo "  AOSS Endpoint:    ${COLLECTION_ENDPOINT}"
echo "  Knowledge Base:   ${KB_ID}"
echo "  Data Source:      ${DS_ID}"
echo ""
echo "NEXT STEPS:"
echo "  1. Wait for data source sync to complete (~2-5 min)"
echo "     aws bedrock-agent list-ingestion-jobs --knowledge-base-id ${KB_ID} --data-source-id ${DS_ID}"
echo ""
echo "  2. Update the KB_ID in config/snowflake_setup.sql (stored procedure)"
echo "     Replace '<YOUR_BEDROCK_KB_ID>' with: ${KB_ID}"
echo ""
echo "  3. Proceed to Snowflake setup: config/snowflake_setup.sql"
echo ""
