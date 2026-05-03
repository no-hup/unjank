---
name: perf-query
description: >
  Query Firebase Performance data from BigQuery for screen rendering metrics.
  Runs cost-optimized queries for 30-day screen summaries and daily trends.
  TRIGGER when: user wants to fetch/refresh performance data, see screen metrics,
  find worst-performing screens, or run BigQuery queries for rendering data.
  SKIP if: user is asking about setup or configuration (use /perf-setup),
  asking to visualize existing data (use /perf-dashboard), or asking to fix
  a specific screen (use /perf-fix). Requires /perf-setup to have run first.
allowed-tools: Bash, Read, Write
---

# Firebase Performance Query

Fetch screen rendering performance data from BigQuery using cost-optimized queries. This skill uses a helper script for deterministic SQL templating and query execution.

## IMPORTANT: Autonomous Execution

Run all steps without asking for confirmation. Proceed from config validation through query execution to summary output in one continuous flow. **Only pause when:**
- Cost estimate exceeds 100 GB even after retrying at 15 and 7 days (explain and stop)
- Authentication has expired (tell the user what to run)
- A query returns zero results (report and stop)

**Do NOT ask** "Should I proceed?" between steps. Just execute.

## Step 1: Read Configuration

Read `.perf/config.json`. If the file doesn't exist, STOP: "No configuration found. Run `/perf-setup` first."

Extract: `table_name`, `lookback_days`, `min_samples`, `min_daily_samples`, `max_screens`, `platform`, `app_id`, `gcp_project_id`.

If `created_at` is older than 30 days, note it inline and continue: "Config is {N} days old — proceeding, but consider re-running `/perf-setup` if queries fail."

## Step 2: Verify Authentication

```bash
gcloud auth application-default print-access-token >/dev/null 2>&1
```

If this fails, STOP: "Authentication expired. Run: `gcloud auth application-default login`"

## Step 3: Locate Query Script

Find the query execution script. Check these paths in order:
- `.claude/skills/perf-query/scripts/run_bq_query.sh`
- `skills/perf-query/scripts/run_bq_query.sh`

Also locate the SQL template files in the `queries/` directory adjacent to the script:
- `screen_summary.sql`
- `screen_daily.sql`
- `app_daily_trend.sql`

If the script or SQL files are not found, you can execute the queries manually using `bq query` with the SQL from the bundled query files. The SQL templates use these placeholders: `{{TABLE}}`, `{{DAYS}}`, `{{MIN_SAMPLES}}`, `{{MIN_DAILY_SAMPLES}}`, `{{MAX_SCREENS}}`, `{{TOP_SCREENS}}`.

## Step 4: Cost Estimation (Dry Run)

Set environment variables and run dry-run for each query:

```bash
export BQ_TABLE="{table_name}"
export BQ_DAYS="{lookback_days}"
export BQ_MIN_SAMPLES="{min_samples}"
export BQ_MIN_DAILY="{min_daily_samples}"
export BQ_MAX_SCREENS="{max_screens}"

bash {script_path}/run_bq_query.sh screen_summary.sql /dev/null --dry-run
bash {script_path}/run_bq_query.sh app_daily_trend.sql /dev/null --dry-run
```

Each dry-run outputs `{"bytes_processed": N}`. Sum the bytes across all queries. Calculate cost: `total_bytes / 1e12 * 5.00` (BigQuery on-demand = $5/TB).

Display the cost estimate. Many frontend developers have never used BigQuery, so briefly explain:

"Estimated scan: **{X} GB** (~${Y}). For context: Google BigQuery gives you **1 TB of free queries per month** — this is well within that. Typical Unjank runs scan 0.5–2 GB, so you'd need to run this 500+ times in a month before any charges apply."

**Cost gates:**
- \> 100 GB: Before stopping, silently retry with a narrower window:
  1. Retry with `BQ_DAYS=15` — if below 100 GB, proceed. Note: "30-day scan was large — using last 15 days ({size} GB, ~${cost})."
  2. Still > 100 GB → retry with `BQ_DAYS=7` — if below 100 GB, proceed. Note: "Using last 7 days ({size} GB, ~${cost})."
  3. Still > 100 GB → STOP and involve the user. "Estimated scan is unusually large even for 7 days ({size} GB). This may indicate the table is not partitioned correctly. Check BigQuery → firebase_performance dataset and confirm partition pruning is working."
- < 100 GB: proceed automatically — show the estimate inline but do NOT ask for confirmation.

## Step 5: Execute Screen Summary Query

```bash
export BQ_TABLE="{table_name}" BQ_DAYS="{lookback_days}" BQ_MIN_SAMPLES="{min_samples}" BQ_MAX_SCREENS="{max_screens}"
bash {script_path}/run_bq_query.sh screen_summary.sql .perf/data/screen_summary.json
```

If 0 rows returned, STOP: "No screen trace data found in the last {lookback_days} days."

## Step 6: Execute Screen Daily Query (Cost-Optimized)

Extract the **top 10 screens** by composite score from screen_summary.json:

```bash
TOP=$(python3 -c "
import json
data = json.load(open('.perf/data/screen_summary.json'))
# BigQuery's JSON output serialises numerics as strings; cast before arithmetic
# or sorted() raises TypeError mid-pipeline.
ranked = sorted(data, key=lambda s: float(s['frozen_frames_pct'])*0.6 + float(s['slow_render_pct'])*0.4, reverse=True)[:10]
print(','.join(s['screen_name'] for s in ranked))
")
```

Then run the daily query filtered to only these screens:

```bash
export BQ_TOP_SCREENS="$TOP"
bash {script_path}/run_bq_query.sh screen_daily.sql .perf/data/screen_daily.json
```

## Step 7: Execute App Daily Trend Query

```bash
bash {script_path}/run_bq_query.sh app_daily_trend.sql .perf/data/app_daily_trend.json
```

## Step 8: Write Query Metadata

Write `.perf/data/query_metadata.json`:

```json
{
  "queried_at": "{ISO timestamp}",
  "lookback_days": {lookback_days},
  "bytes_scanned": {total_bytes_from_dry_run},
  "estimated_cost_usd": {calculated_cost},
  "screen_count": {number_of_screens_in_summary},
  "top_screens_queried": ["screen1", "screen2", "..."],
  "platform": "{platform}",
  "app_id": "{app_id}",
  "table_name": "{table_name}"
}
```

**Sanity check before writing:** if the dry-run reported `bytes_processed: 0` but the queries returned rows (so they clearly scanned *something*), the cost extraction failed upstream rather than the queries being free. In that case, write `"bytes_scanned": null`, `"estimated_cost_usd": null`, and add `"cost_estimation_failed": true`. Don't write `0` — auditors reading this metadata downstream will treat zero as ground truth and miss real spend.

## Step 9: Print Summary

```
Query complete:
- {N} screens found with sufficient data
- Top 3 worst performers:
  1. {screen} (frozen: {X}%, slow: {Y}%)
  2. {screen} (frozen: {X}%, slow: {Y}%)
  3. {screen} (frozen: {X}%, slow: {Y}%)
- 30-day app trend: frozen frames {up/down/stable}, slow render {up/down/stable}
- Data saved to .perf/data/

Run /perf-dashboard to generate the visual dashboard.
```

Compare last 7 days average vs previous 23 days to determine trend direction.

## Error Handling

| Error | Action |
|-------|--------|
| Config missing | "Run `/perf-setup` first." |
| Auth expired | "Run: `gcloud auth application-default login`" |
| `bq: command not found` | "bq CLI not found. Run: `gcloud components install bq`" |
| Access Denied | "Your account lacks BigQuery permission. Need `roles/bigquery.jobUser`." |
| Table not found | "BigQuery table not found. Re-run `/perf-setup`." |
| Query timeout | "Query timed out. Try reducing lookback_days in `.perf/config.json`." |
| All values zero | "No rendering issues detected. Your app is performing well." |
| Dry-run > 100 GB at 7 days | STOP after retrying 30→15→7 day windows. "Check partition pruning." |
