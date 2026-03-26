#!/usr/bin/env bash
# Run a BigQuery query with placeholder substitution.
# Reads SQL template, substitutes values, optionally dry-runs, then executes.
#
# Usage: ./run_bq_query.sh <sql_file> <output_file> [--dry-run]
#
# Environment variables (required):
#   BQ_TABLE       - fully qualified BigQuery table name
#   BQ_DAYS        - lookback days (default: 30)
#   BQ_MIN_SAMPLES - minimum samples (default: 50)
#   BQ_MIN_DAILY   - minimum daily samples (default: 10)
#   BQ_MAX_SCREENS - max screens to return (default: 50)
#   BQ_TOP_SCREENS - comma-separated screen names for IN clause (optional)
#
# Exit codes: 0 = success, 1 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

SQL_FILE="${1:-}"
OUTPUT_FILE="${2:-}"
DRY_RUN="${3:-}"

if [ -z "$SQL_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "Usage: run_bq_query.sh <sql_file> <output_file> [--dry-run]" >&2
  exit 1
fi

# Resolve SQL file path (relative to skill's queries/ dir if not absolute)
if [ ! -f "$SQL_FILE" ]; then
  SQL_FILE="$SKILL_DIR/queries/$SQL_FILE"
fi
if [ ! -f "$SQL_FILE" ]; then
  echo "Error: SQL file not found: $SQL_FILE" >&2
  exit 1
fi

# Read and validate environment variables
TABLE="${BQ_TABLE:?BQ_TABLE environment variable is required}"
DAYS="${BQ_DAYS:-30}"
MIN_SAMPLES="${BQ_MIN_SAMPLES:-50}"
MIN_DAILY="${BQ_MIN_DAILY:-10}"
MAX_SCREENS="${BQ_MAX_SCREENS:-50}"
TOP_SCREENS="${BQ_TOP_SCREENS:-}"

# Validate numeric ranges
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ] || [ "$DAYS" -gt 365 ]; then
  echo "Error: BQ_DAYS must be a number between 1 and 365 (got: $DAYS)" >&2; exit 1
fi
if ! [[ "$MIN_SAMPLES" =~ ^[0-9]+$ ]]; then
  echo "Error: BQ_MIN_SAMPLES must be a number (got: $MIN_SAMPLES)" >&2; exit 1
fi
# Validate table name format (project.dataset.table)
if ! echo "$TABLE" | grep -qP '^[a-z0-9_-]+\.[a-z0-9_]+\.[a-z0-9_]+$'; then
  echo "Warning: Table name '$TABLE' has unexpected format. Expected: project.dataset.table" >&2
fi

SQL=$(cat "$SQL_FILE")
SQL="${SQL//\{\{TABLE\}\}/$TABLE}"
SQL="${SQL//\{\{DAYS\}\}/$DAYS}"
SQL="${SQL//\{\{MIN_SAMPLES\}\}/$MIN_SAMPLES}"
SQL="${SQL//\{\{MIN_DAILY_SAMPLES\}\}/$MIN_DAILY}"
SQL="${SQL//\{\{MAX_SCREENS\}\}/$MAX_SCREENS}"

# Handle TOP_SCREENS substitution (comma-separated → SQL IN values)
# Escapes single quotes in screen names to prevent SQL injection/breakage
if [ -n "$TOP_SCREENS" ]; then
  IN_CLAUSE=$(python3 -c "
import sys
names = sys.argv[1].split(',')
escaped = [\"'\" + n.replace(\"'\", \"\\\\'\") + \"'\" for n in names if n.strip()]
print(','.join(escaped))
" "$TOP_SCREENS")
  SQL="${SQL//\{\{TOP_SCREENS\}\}/$IN_CLAUSE}"
fi

# Dry run mode
if [ "$DRY_RUN" = "--dry-run" ]; then
  RESULT=$(bq query --nouse_legacy_sql --dry_run "$SQL" 2>&1)
  # Extract bytes processed
  BYTES=$(echo "$RESULT" | grep -oP '\d+' | tail -1 || echo "0")
  echo "{\"bytes_processed\": $BYTES, \"sql_length\": ${#SQL}}"
  exit 0
fi

# Execute query
mkdir -p "$(dirname "$OUTPUT_FILE")"
bq query --nouse_legacy_sql --format=json --max_rows=500 "$SQL" > "$OUTPUT_FILE" 2>/dev/null

# Validate output
if [ ! -s "$OUTPUT_FILE" ]; then
  echo "[]" > "$OUTPUT_FILE"
fi

# Count rows
ROW_COUNT=$(python3 -c "
import json, sys
with open('$OUTPUT_FILE') as f:
    data = json.load(f)
print(len(data) if isinstance(data, list) else 0)
" 2>/dev/null || echo "0")

echo "{\"rows\": $ROW_COUNT, \"output\": \"$OUTPUT_FILE\"}"
