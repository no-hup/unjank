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

# ---- Firebase Config Discovery ----
PROJECT_ID=""
APP_ID=""
CONFIG_FILE=""
CONFIG_FILES_FOUND=""

if [ "$PLATFORM" = "ANDROID" ] || [ "$PLATFORM" = "FLUTTER" ]; then
  # Search for google-services.json
  if [ "$PLATFORM" = "FLUTTER" ]; then
    SEARCH_PATHS="android/app/google-services.json"
  else
    SEARCH_PATHS="app/google-services.json"
  fi

  # Also search broadly
  ALL_GS=$(find . -name "google-services.json" -not -path "*/build/*" -not -path "*/.gradle/*" 2>/dev/null || true)
  CONFIG_FILES_FOUND="$ALL_GS"

  # Pick the first match from preferred paths, then fallback to any found
  GS_FILE=""
  for p in $SEARCH_PATHS; do
    if [ -f "$p" ]; then
      GS_FILE="$p"
      break
    fi
  done
  if [ -z "$GS_FILE" ] && [ -n "$ALL_GS" ]; then
    GS_FILE=$(echo "$ALL_GS" | head -1)
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
  if [ "$PLATFORM" = "FLUTTER" ]; then
    PLIST_SEARCH="ios/Runner/GoogleService-Info.plist"
  else
    PLIST_SEARCH=""
  fi

  ALL_PLIST=$(find . -name "GoogleService-Info.plist" -not -path "*/build/*" -not -path "*/Pods/*" 2>/dev/null || true)

  PLIST_FILE=""
  if [ -n "$PLIST_SEARCH" ] && [ -f "$PLIST_SEARCH" ]; then
    PLIST_FILE="$PLIST_SEARCH"
  elif [ -n "$ALL_PLIST" ]; then
    PLIST_FILE=$(echo "$ALL_PLIST" | head -1)
  fi

  if [ -n "$PLIST_FILE" ] && [ "$PLATFORM" != "ANDROID" ]; then
    CONFIG_FILE="$PLIST_FILE"
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
  "has_application_id_suffix": $HAS_SUFFIX,
  "firebase_perf_sdk_found": $FIREBASE_PERF_FOUND
}
EOF
