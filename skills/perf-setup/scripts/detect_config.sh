#!/usr/bin/env bash
# Detect platform, Firebase config, and extract project ID + app ID.
# Outputs JSON to stdout. Agent reads this and handles missing values interactively.
#
# Usage: ./detect_config.sh [project_root]
# Exit codes: 0 = success (some fields may be null), 1 = fatal error

set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# ---- Platform Detection ----
PLATFORM="UNKNOWN"
if [ -f "pubspec.yaml" ] && grep -q "flutter:" pubspec.yaml 2>/dev/null; then
  PLATFORM="FLUTTER"
elif [ -f "app/build.gradle" ] || [ -f "app/build.gradle.kts" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  if grep -rq "com.android.application" app/build.gradle* build.gradle* 2>/dev/null; then
    PLATFORM="ANDROID"
  fi
elif ls *.xcodeproj >/dev/null 2>&1 || ls *.xcworkspace >/dev/null 2>&1 || [ -f "Podfile" ]; then
  PLATFORM="IOS"
fi

# ---- Flavor selection helper ----
# Given a list of config file paths, auto-select the production one.
# Returns the path of the best match, or empty if ambiguous.
select_prod_config() {
  local files="$1"
  local count
  count=$(echo "$files" | wc -l | tr -d ' ')

  # If only one file, return it
  if [ "$count" -eq 1 ]; then
    echo "$files"
    return
  fi

  # Priority 1: Look for paths containing production indicators
  # Common patterns: /prod/, /production/, /release/, /main/, /live/
  local prod_patterns="prod production release main live"
  for pattern in $prod_patterns; do
    local match
    match=$(echo "$files" | grep -i "/$pattern/" | head -1 || true)
    if [ -n "$match" ]; then
      echo "$match"
      return
    fi
  done

  # Priority 2: Exclude known non-prod paths
  # Common patterns: /debug/, /staging/, /beta/, /dev/, /test/, /qa/, /uat/, /internal/
  local non_prod_patterns="debug staging beta dev test qa uat internal sandbox mock demo"
  local remaining="$files"
  for pattern in $non_prod_patterns; do
    local filtered
    filtered=$(echo "$remaining" | grep -iv "/$pattern/" || true)
    if [ -n "$filtered" ]; then
      remaining="$filtered"
    fi
  done

  # If filtering reduced to one file, use it
  local remaining_count
  remaining_count=$(echo "$remaining" | wc -l | tr -d ' ')
  if [ "$remaining_count" -eq 1 ]; then
    echo "$remaining"
    return
  fi

  # Priority 3: Prefer the default/root-level config
  # e.g., app/google-services.json over app/src/staging/google-services.json
  local shortest=""
  local shortest_len=9999
  while IFS= read -r f; do
    local len=${#f}
    if [ "$len" -lt "$shortest_len" ]; then
      shortest="$f"
      shortest_len="$len"
    fi
  done <<< "$remaining"

  echo "$shortest"
}

# Determine which flavor was selected
get_flavor_name() {
  local filepath="$1"
  # Extract flavor from path like app/src/prod/google-services.json → prod
  # Or ios/Targets/Production/GoogleService-Info.plist → Production
  local flavor
  flavor=$(echo "$filepath" | grep -oiE '(prod|production|release|debug|staging|beta|dev|test|qa|uat|internal|main|live|sandbox)[^/]*' | head -1 || true)
  if [ -n "$flavor" ]; then
    echo "$flavor"
  else
    # If no recognizable flavor in path, use parent directory name
    echo "$(basename "$(dirname "$filepath")")"
  fi
}

# ---- Firebase Config Discovery ----
PROJECT_ID=""
APP_ID=""
CONFIG_FILE=""
CONFIG_FILES_FOUND=""
SELECTED_FLAVOR=""

if [ "$PLATFORM" = "ANDROID" ] || [ "$PLATFORM" = "FLUTTER" ]; then
  # Search for google-services.json
  ALL_GS=$(find . -name "google-services.json" -not -path "*/build/*" -not -path "*/.gradle/*" -not -path "*/node_modules/*" 2>/dev/null || true)
  CONFIG_FILES_FOUND="$ALL_GS"

  GS_FILE=""
  if [ -n "$ALL_GS" ]; then
    GS_COUNT=$(echo "$ALL_GS" | wc -l | tr -d ' ')
    if [ "$GS_COUNT" -eq 1 ]; then
      GS_FILE="$ALL_GS"
    else
      # Multiple configs found — auto-select production
      GS_FILE=$(select_prod_config "$ALL_GS")
      SELECTED_FLAVOR=$(get_flavor_name "$GS_FILE")
    fi
  fi

  if [ -n "$GS_FILE" ]; then
    CONFIG_FILE="$GS_FILE"
    # Extract project_id
    PROJECT_ID=$(python3 -c "
import json, sys
with open('$GS_FILE') as f:
    data = json.load(f)
print(data.get('project_info', {}).get('project_id', ''))
" 2>/dev/null || true)

    # Extract package_name (app ID)
    APP_ID=$(python3 -c "
import json, sys
with open('$GS_FILE') as f:
    data = json.load(f)
clients = data.get('client', [])
if clients:
    info = clients[0].get('client_info', {})
    android_info = info.get('android_client_info', {})
    print(android_info.get('package_name', ''))
" 2>/dev/null || true)
  fi

  # Fallback: parse applicationId from build.gradle
  if [ -z "$APP_ID" ]; then
    for gf in app/build.gradle.kts app/build.gradle build.gradle.kts build.gradle; do
      if [ -f "$gf" ]; then
        PARSED=$(grep -oP 'applicationId\s*[=( ]*"([^"]+)"' "$gf" 2>/dev/null | head -1 | grep -oP '"[^"]+"' | tr -d '"' || true)
        if [ -n "$PARSED" ]; then
          APP_ID="$PARSED"
          break
        fi
      fi
    done
  fi
fi

if [ "$PLATFORM" = "IOS" ] || [ "$PLATFORM" = "FLUTTER" ]; then
  # Search for GoogleService-Info.plist
  ALL_PLIST=$(find . -name "GoogleService-Info.plist" -not -path "*/build/*" -not -path "*/Pods/*" -not -path "*/node_modules/*" 2>/dev/null || true)

  PLIST_FILE=""
  if [ -n "$ALL_PLIST" ]; then
    PLIST_COUNT=$(echo "$ALL_PLIST" | wc -l | tr -d ' ')
    if [ "$PLIST_COUNT" -eq 1 ]; then
      PLIST_FILE="$ALL_PLIST"
    else
      # Multiple configs found — auto-select production
      PLIST_FILE=$(select_prod_config "$ALL_PLIST")
      if [ -z "$SELECTED_FLAVOR" ]; then
        SELECTED_FLAVOR=$(get_flavor_name "$PLIST_FILE")
      fi
    fi
  fi

  if [ -n "$PLIST_FILE" ] && [ "$PLATFORM" != "ANDROID" ]; then
    CONFIG_FILE="$PLIST_FILE"
    CONFIG_FILES_FOUND="$ALL_PLIST"
    # macOS has PlistBuddy; Linux may not
    if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
      PROJECT_ID=$(/usr/libexec/PlistBuddy -c "Print :PROJECT_ID" "$PLIST_FILE" 2>/dev/null || true)
      APP_ID=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$PLIST_FILE" 2>/dev/null || true)
    elif command -v python3 >/dev/null 2>&1; then
      PROJECT_ID=$(python3 -c "
import plistlib, sys
with open('$PLIST_FILE', 'rb') as f:
    data = plistlib.load(f)
print(data.get('PROJECT_ID', ''))
" 2>/dev/null || true)
      APP_ID=$(python3 -c "
import plistlib, sys
with open('$PLIST_FILE', 'rb') as f:
    data = plistlib.load(f)
print(data.get('BUNDLE_ID', ''))
" 2>/dev/null || true)
    fi
  fi
fi

# ---- Check for applicationIdSuffix ----
HAS_SUFFIX="false"
for gf in app/build.gradle.kts app/build.gradle; do
  if [ -f "$gf" ] && grep -q "applicationIdSuffix" "$gf" 2>/dev/null; then
    HAS_SUFFIX="true"
    break
  fi
done

# ---- Firebase Performance SDK Check ----
FIREBASE_PERF_FOUND="false"
if [ "$PLATFORM" = "ANDROID" ] || [ "$PLATFORM" = "FLUTTER" ]; then
  if grep -rq "firebase-perf\|firebase_performance" app/build.gradle* build.gradle* pubspec.yaml 2>/dev/null; then
    FIREBASE_PERF_FOUND="true"
  fi
fi
if [ "$PLATFORM" = "IOS" ] || [ "$PLATFORM" = "FLUTTER" ]; then
  if grep -q "FirebasePerformance\|firebase_performance" Podfile Package.swift pubspec.yaml 2>/dev/null; then
    FIREBASE_PERF_FOUND="true"
  fi
fi

# ---- Count config files (for flavor detection) ----
CONFIG_COUNT=0
if [ -n "$CONFIG_FILES_FOUND" ]; then
  CONFIG_COUNT=$(echo "$CONFIG_FILES_FOUND" | wc -l | tr -d ' ')
fi

# ---- Output JSON ----
cat <<EOF
{
  "platform": "$PLATFORM",
  "gcp_project_id": "$PROJECT_ID",
  "app_id": "$APP_ID",
  "config_file": "$CONFIG_FILE",
  "config_files_count": $CONFIG_COUNT,
  "config_files_list": $(echo "$CONFIG_FILES_FOUND" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip().split('\n')))" 2>/dev/null || echo '[]'),
  "selected_flavor": "$SELECTED_FLAVOR",
  "has_application_id_suffix": $HAS_SUFFIX,
  "firebase_perf_sdk_found": $FIREBASE_PERF_FOUND
}
EOF
