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

Discover the project's Firebase configuration, install prerequisites if needed, validate BigQuery access, and prepare for performance queries. This skill uses helper scripts in the `scripts/` directory alongside this file.

## IMPORTANT: Autonomous Execution

Run all steps autonomously without asking the developer for confirmation at each step. **Only ask the developer when:**
- A choice is genuinely ambiguous (e.g., multiple production-like config files)
- A required value cannot be detected automatically
- An auth step requires browser interaction (just tell them what's happening, don't ask permission)
- A permission/access error occurs that you cannot fix

**Do NOT ask:**
- "Should I check gcloud?" — just check it
- "Should I proceed to the next step?" — just proceed
- "Should I run the validation?" — just run it
- "Is this the correct account?" — only ask if there's a clear mismatch (e.g., personal email on a corporate project)

Think of this as a setup wizard that runs to completion, only pausing when it hits an actual blocker.

## Step 1: Install Prerequisites

Check and install required tools. Do NOT report errors — actively fix them. Run all checks together, then fix what's missing.

```bash
echo "gcloud: $(command -v gcloud >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
echo "bq: $(command -v bq >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
echo "python3: $(command -v python3 >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
echo "auth: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || echo 'NONE')"
echo "adc: $(gcloud auth application-default print-access-token >/dev/null 2>&1 && echo 'OK' || echo 'MISSING')"
```

**If everything is OK**: Proceed silently to Step 2. Do not print a status report.

**If gcloud is MISSING**, detect the OS and install:

- **macOS** (check with `uname -s`):
  ```bash
  brew install google-cloud-sdk
  ```
  If `brew` is not available:
  ```bash
  curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-darwin-$(uname -m).tar.gz | tar -xz -C "$HOME"
  $HOME/google-cloud-sdk/install.sh --quiet --path-update true
  source "$HOME/google-cloud-sdk/path.bash.inc"
  ```

- **Linux**:
  ```bash
  curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-$(uname -m).tar.gz | tar -xz -C "$HOME"
  $HOME/google-cloud-sdk/install.sh --quiet --path-update true
  source "$HOME/google-cloud-sdk/path.bash.inc"
  ```

After install, verify: `gcloud --version`. If `gcloud` is still not found, try: `source ~/.bashrc` or `source ~/.zshrc`.

**If bq is MISSING**:
- If gcloud was installed via official installer: `gcloud components install bq --quiet`
- If via Homebrew: try `$(brew --prefix)/share/google-cloud-sdk/bin/bq --version`

**If python3 is MISSING** (rare):
- macOS: `xcode-select --install`
- Linux: `sudo apt install python3` or `sudo yum install python3`

**If auth is NONE**: Tell the developer "Authenticating with Google Cloud — this will open a browser." Then run:
```bash
gcloud auth login --quiet
```

**If ADC is MISSING**: Tell the developer "Setting up BigQuery credentials — one more browser window." Then run:
```bash
gcloud auth application-default login --quiet
```

**IMPORTANT**: Both auth commands open a browser. On remote/headless machines, use `--no-launch-browser` and show the URL to visit manually.

## Step 2: Detect Platform and Firebase Config

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
- `config_files_list`: newline-separated paths of all config files found
- `selected_flavor`: which flavor was auto-selected (if multiple found)
- `has_application_id_suffix`: whether applicationIdSuffix was detected
- `firebase_perf_sdk_found`: whether Firebase Performance SDK was found

## Step 3: Handle Detection Results

**If platform = "UNKNOWN"**: STOP. Tell the developer: "Could not detect project platform. Are you in the root directory of an Android, iOS, or Flutter project?"

**If platform = "FLUTTER"**: Ask the developer: "This is a Flutter project. Configure for **Android** or **iOS**?"

**If gcp_project_id is empty**: Ask the developer: "Could not find Firebase config. Please provide your GCP Project ID (Firebase Console → Project Settings → General)."

**If app_id is empty**: Ask for package name (Android) or bundle ID (iOS).

**If config_files_count > 1 and selected_flavor is set**: The script auto-selected the production config. Tell the developer which one was chosen: "Found multiple Firebase configs (build flavors). Auto-selected **{selected_flavor}** as the production config from: {config_file}". Proceed without asking — only ask if `selected_flavor` is "unknown" or empty.

**If has_application_id_suffix = true**: Note (don't block): "Build uses applicationIdSuffix. Using the **base** applicationId for BigQuery table name."

**If firebase_perf_sdk_found = false**: Warn with platform-specific fix:
- Android: "Firebase Performance SDK not detected. Add `implementation(\"com.google.firebase:firebase-perf\")` and apply the `com.google.firebase.perf` plugin."
- iOS: "Firebase Performance SDK not detected. Add `pod 'FirebasePerformance'` to Podfile. Ensure `FirebaseApp.configure()` is called in AppDelegate."
- Flutter: "Firebase Performance SDK not detected. Add `firebase_performance` to pubspec.yaml."
- Always add: "Screen rendering data takes 24-48 hours to appear in BigQuery after enabling."

## Step 4: Validate BigQuery Access

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

- `gcloud_installed = false`: Should not happen (Step 1 installed it). Re-run Step 1.
- `logged_in = false`: Should not happen. Run `gcloud auth login`.
- `active_account`: Only flag if there's an obvious mismatch (e.g., `@gmail.com` account on a corporate project, or vice versa). Otherwise proceed silently.
- `adc_valid = false`: Run `gcloud auth application-default login` automatically.
- `bq_installed = false`: Run `gcloud components install bq --quiet` automatically.
- `table_exists = false`: STOP. "BigQuery table not found. BigQuery export likely isn't enabled. Go to **Firebase Console → Settings → Integrations → BigQuery** and enable it. Data takes 24-48 hours to appear."
- `smoke_test_count = 0`: WARNING (don't block): "Table exists but no screen trace data in the last 7 days. If recently enabled, data can take up to 48 hours."
- `smoke_test_count > 0`: Proceed. Briefly note: "Found {count} screen traces in the last 7 days."

**If permission denied on BigQuery**: "Your account doesn't have BigQuery access on this project. Ask your project admin to grant the `BigQuery Data Viewer` role (`roles/bigquery.dataViewer`) in **Google Cloud Console → IAM & Admin → IAM**."

## Step 5: Write Configuration

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
