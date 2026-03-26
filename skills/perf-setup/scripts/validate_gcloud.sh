#!/usr/bin/env bash
# Validate gcloud CLI installation, authentication, and BigQuery access.
# Outputs JSON to stdout with validation results.
#
# Usage: ./validate_gcloud.sh <gcp_project_id> <table_name>
# Exit codes: 0 = all checks passed, 1 = one or more checks failed

set -euo pipefail

PROJECT_ID="${1:-}"
TABLE_NAME="${2:-}"

if [ -z "$PROJECT_ID" ]; then
  echo '{"error": "Usage: validate_gcloud.sh <gcp_project_id> <table_name>"}'
  exit 1
fi

# ---- Check gcloud installed ----
GCLOUD_INSTALLED="false"
GCLOUD_VERSION=""
if command -v gcloud >/dev/null 2>&1; then
  GCLOUD_INSTALLED="true"
  GCLOUD_VERSION=$(gcloud version 2>/dev/null | head -1 || true)
fi

if [ "$GCLOUD_INSTALLED" = "false" ]; then
  cat <<EOF
{
  "gcloud_installed": false,
  "error": "gcloud CLI not found",
  "fix": "Install from https://cloud.google.com/sdk/docs/install"
}
EOF
  exit 1
fi

# ---- Check logged in ----
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
if [ -z "$ACTIVE_ACCOUNT" ]; then
  cat <<EOF
{
  "gcloud_installed": true,
  "logged_in": false,
  "error": "No active gcloud account",
  "fix": "Run: gcloud auth login"
}
EOF
  exit 1
fi

# ---- Check/set project ----
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
PROJECT_MATCH="true"
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
  PROJECT_MATCH="false"
  gcloud config set project "$PROJECT_ID" 2>/dev/null || true
fi

# ---- Check ADC ----
ADC_VALID="false"
if gcloud auth application-default print-access-token >/dev/null 2>&1; then
  ADC_VALID="true"
fi

# ---- Check bq CLI ----
BQ_INSTALLED="false"
if command -v bq >/dev/null 2>&1; then
  BQ_INSTALLED="true"
fi

# ---- Check BigQuery table exists ----
TABLE_EXISTS="false"
TABLE_ERROR=""
SMOKE_TEST_COUNT=0
if [ "$BQ_INSTALLED" = "true" ] && [ -n "$TABLE_NAME" ]; then
  # Convert dot notation to colon notation for bq show
  BQ_TABLE=$(echo "$TABLE_NAME" | sed 's/\./:/1')
  if bq show --format=json "$BQ_TABLE" >/dev/null 2>&1; then
    TABLE_EXISTS="true"

    # Run smoke test
    SMOKE_RESULT=$(bq query --nouse_legacy_sql --format=json --max_rows=1 \
      "SELECT COUNT(*) as cnt FROM \`$TABLE_NAME\` WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY) AND event_type = 'SCREEN_TRACE'" 2>/dev/null || echo "[]")

    SMOKE_TEST_COUNT=$(echo "$SMOKE_RESULT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data[0].get('cnt', 0) if data else 0)
" 2>/dev/null || echo "0")
  else
    TABLE_ERROR="Table not found. Enable BigQuery export in Firebase Console > Settings > Integrations > BigQuery."
  fi
fi

cat <<EOF
{
  "gcloud_installed": true,
  "gcloud_version": "$GCLOUD_VERSION",
  "logged_in": true,
  "active_account": "$ACTIVE_ACCOUNT",
  "project_id": "$PROJECT_ID",
  "project_was_set": $( [ "$PROJECT_MATCH" = "true" ] && echo "false" || echo "true" ),
  "adc_valid": $ADC_VALID,
  "bq_installed": $BQ_INSTALLED,
  "table_exists": $TABLE_EXISTS,
  "table_error": "$TABLE_ERROR",
  "smoke_test_count": $SMOKE_TEST_COUNT
}
EOF
