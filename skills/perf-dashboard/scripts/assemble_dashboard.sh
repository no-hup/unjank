#!/usr/bin/env bash
# Assemble the HTML dashboard by injecting data into the template.
# Reads .perf/data/*.json and .perf/config.json, outputs .perf/dashboard.html.
#
# Usage: ./assemble_dashboard.sh [project_root]
# Exit codes: 0 = success, 1 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
ROOT="${1:-.}"

# ---- Validate inputs ----
CONFIG="$ROOT/.perf/config.json"
DATA_DIR="$ROOT/.perf/data"
TEMPLATE="$SKILL_DIR/dashboard-template.html"
OUTPUT="$ROOT/.perf/dashboard.html"

for f in "$CONFIG" "$DATA_DIR/screen_summary.json" "$DATA_DIR/app_daily_trend.json" "$DATA_DIR/query_metadata.json"; do
  if [ ! -f "$f" ]; then
    echo "Error: Required file not found: $f" >&2
    echo "Run /perf-query first to generate data." >&2
    exit 1
  fi
done

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: Dashboard template not found at $TEMPLATE" >&2
  exit 1
fi

# ---- Validate config has required fields ----
python3 -c "
import json, sys
with open('$CONFIG') as f:
    cfg = json.load(f)
required = ['version', 'platform', 'gcp_project_id', 'app_id', 'table_name']
missing = [k for k in required if not cfg.get(k)]
if missing:
    print(f'Error: .perf/config.json missing required fields: {missing}', file=sys.stderr)
    sys.exit(1)
if cfg.get('version', 0) != 1:
    print(f'Warning: config version {cfg.get(\"version\")} — expected 1. Results may vary.', file=sys.stderr)
" || exit 1

# ---- Read values ----
APP_ID=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('app_id', 'unknown'))" 2>/dev/null)
PLATFORM=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('platform', 'UNKNOWN'))" 2>/dev/null)
TABLE_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('table_name', ''))" 2>/dev/null)
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

SCREEN_SUMMARY=$(cat "$DATA_DIR/screen_summary.json")
APP_TREND=$(cat "$DATA_DIR/app_daily_trend.json")
QUERY_META=$(cat "$DATA_DIR/query_metadata.json")

# screen_daily.json may not exist if no top screens were found
if [ -f "$DATA_DIR/screen_daily.json" ]; then
  SCREEN_DAILY=$(cat "$DATA_DIR/screen_daily.json")
else
  SCREEN_DAILY="[]"
fi

# ---- Perform substitutions using python3 for reliability ----
python3 <<PYEOF
import sys

with open("$TEMPLATE", "r") as f:
    html = f.read()

replacements = {
    "{{SCREEN_SUMMARY_JSON}}": '''$SCREEN_SUMMARY''',
    "{{SCREEN_DAILY_JSON}}": '''$SCREEN_DAILY''',
    "{{APP_TREND_JSON}}": '''$APP_TREND''',
    "{{QUERY_METADATA_JSON}}": '''$QUERY_META''',
    "{{APP_ID}}": "$APP_ID",
    "{{PLATFORM}}": "$PLATFORM",
    "{{TABLE_NAME}}": "$TABLE_NAME",
    "{{GENERATED_AT}}": "$GENERATED_AT",
}

for placeholder, value in replacements.items():
    html = html.replace(placeholder, value)

with open("$OUTPUT", "w") as f:
    f.write(html)

print(f"Dashboard written to $OUTPUT")
PYEOF

# ---- Open in browser ----
if [[ "$OSTYPE" == "darwin"* ]]; then
  open "$OUTPUT" 2>/dev/null || true
elif [[ "$OSTYPE" == "linux"* ]]; then
  xdg-open "$OUTPUT" 2>/dev/null || true
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
  explorer.exe "$OUTPUT" 2>/dev/null || true
fi
