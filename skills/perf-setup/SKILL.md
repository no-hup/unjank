---
name: perf-setup
description: >
  Detect Firebase/GCP configuration, validate BigQuery access, and prepare for
  performance data queries. TRIGGER when: user asks about app performance,
  screen rendering metrics, frozen frames, slow rendering, Firebase Performance,
  BigQuery setup, or performance monitoring for their Android/iOS/Flutter app.
allowed-tools: Bash, Read, Grep, Write, Glob
---

# Firebase Performance Setup

Discover the project's Firebase configuration, validate BigQuery access, and prepare for performance queries. This skill uses helper scripts for deterministic config detection — the scripts are located in the `scripts/` directory alongside this file.

## Step 1: Detect Platform and Firebase Config

Run the detection script from this skill's directory:

```bash
bash "$(dirname "$(find .claude/skills/perf-setup -name detect_config.sh 2>/dev/null | head -1)")/detect_config.sh" .
```

If the script is not found at that path, look for it at these alternative locations:
- `.claude/skills/perf-setup/scripts/detect_config.sh`
- `skills/perf-setup/scripts/detect_config.sh`

The script outputs JSON with these fields:
- `platform`: "ANDROID", "IOS", "FLUTTER", or "UNKNOWN"
- `gcp_project_id`: extracted project ID (may be empty)
- `app_id`: extracted app ID (may be empty)
- `config_file`: path to the config file found
- `config_files_count`: number of config files found (>1 means build flavors)
- `has_application_id_suffix`: whether applicationIdSuffix was detected
- `firebase_perf_sdk_found`: whether Firebase Performance SDK was found

## Step 2: Handle Detection Results

Based on the script output:

**If platform = "UNKNOWN"**: STOP. Tell the developer: "Could not detect project platform. Are you in the root directory of an Android, iOS, or Flutter project?"

**If platform = "FLUTTER"**: Ask the developer: "This is a Flutter project. Configure for **Android** or **iOS**?" Use their choice as the platform going forward.

**If gcp_project_id is empty**: Tell the developer: "Firebase configuration files not found. This is common in CI/CD setups where configs are injected at build time. Please provide your GCP Project ID (find it at Firebase Console → Project Settings → General):"

**If app_id is empty**: Ask the developer for their app's package name (Android) or bundle ID (iOS).

**If config_files_count > 1**: Tell the developer: "Found multiple Firebase configuration files (likely build flavors). Which one should be used? The production config is typically the correct one."

**If has_application_id_suffix = true**: Warn: "Your build uses applicationIdSuffix. The BigQuery table uses the **base** applicationId (without suffix)."

**If firebase_perf_sdk_found = false**: Warn with platform-specific instructions:
- Android: "Add `implementation(\"com.google.firebase:firebase-perf\")` and apply the `com.google.firebase.perf` plugin."
- iOS: "Add `pod 'FirebasePerformance'` to your Podfile. Ensure `FirebaseApp.configure()` is called in AppDelegate."
- Flutter: "Add `firebase_performance` to your pubspec.yaml dependencies."
- Always add: "Note: Screen rendering data takes up to 48 hours to appear in BigQuery after enabling."

## Step 3: Validate gcloud and BigQuery

Construct the BigQuery table name:
- Replace dots in app ID with underscores
- Format: `{projectId}.firebase_performance.{sanitized_appId}_{PLATFORM}`
- Example: `my-app-123.firebase_performance.com_example_myapp_ANDROID`

Run the validation script:

```bash
bash "$(dirname "$(find .claude/skills/perf-setup -name validate_gcloud.sh 2>/dev/null | head -1)")/validate_gcloud.sh" "{gcp_project_id}" "{table_name}"
```

Alternative paths:
- `.claude/skills/perf-setup/scripts/validate_gcloud.sh`
- `skills/perf-setup/scripts/validate_gcloud.sh`

The script outputs JSON. Handle each field:

- `gcloud_installed = false`: STOP. Show the `fix` message.
- `logged_in = false`: STOP. Show the `fix` message.
- `active_account`: Ask the developer: "Active gcloud account is **{email}**. Is this the correct account for project **{project_id}**?" If no, tell them to run `gcloud auth login` with the right account.
- `adc_valid = false`: STOP. "Run: `gcloud auth application-default login`"
- `bq_installed = false`: STOP. "bq CLI not found. Run: `gcloud components install bq`"
- `table_exists = false`: STOP. Show: "BigQuery table not found. Enable BigQuery export: Firebase Console → Settings → Integrations → BigQuery. Data takes 24-48 hours."
- `smoke_test_count = 0`: WARNING (don't block): "Table exists but no screen trace data in the last 7 days. If recently enabled, data can take up to 48 hours."
- `smoke_test_count > 0`: "Smoke test passed. Found {count} screen traces in the last 7 days."

## Step 4: Write Configuration

Create `.perf/config.json` with all discovered/confirmed values:

```json
{
  "version": 1,
  "created_at": "{ISO timestamp}",
  "platform": "{ANDROID or IOS}",
  "gcp_project_id": "{project ID}",
  "app_id": "{app ID}",
  "table_name": "{constructed table name}",
  "gcloud_account": "{active gcloud email}",
  "lookback_days": 30,
  "min_samples": 50,
  "min_daily_samples": 10,
  "max_screens": 50
}
```

Add `.perf/` to `.gitignore` if not already present:
```bash
grep -qxF '.perf/' .gitignore 2>/dev/null || echo '.perf/' >> .gitignore
```

Print: "Setup complete. Configuration saved to `.perf/config.json`. Run `/perf-query` to fetch performance data."
