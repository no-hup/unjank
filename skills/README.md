# Firebase Performance Skills for Claude Code

Three installable agent skills that discover Firebase config, query BigQuery performance data, and generate a local HTML dashboard — for Android, iOS, and Flutter apps.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| `perf-setup` | `/perf-setup` | Discover Firebase/GCP config, validate BigQuery access, run smoke test |
| `perf-query` | `/perf-query` | Run cost-optimized BigQuery queries, output structured JSON |
| `perf-dashboard` | `/perf-dashboard` | Generate interactive HTML dashboard with Chart.js |

## Installation

Copy the skill directories into your project's `.claude/skills/`:

```bash
cp -r perf-setup perf-query perf-dashboard /path/to/your/app/.claude/skills/
```

## Prerequisites

- **gcloud CLI** installed and authenticated (`gcloud auth login && gcloud auth application-default login`)
- **Firebase Performance SDK** integrated in your app
- **BigQuery export** enabled in Firebase Console (Settings → Integrations → BigQuery)
- **BigQuery permissions**: `roles/bigquery.dataViewer` + `roles/bigquery.jobUser`

## Usage

```
/perf-setup           # Discover config, validate access
/perf-query           # Fetch 30-day performance data
/perf-dashboard       # Generate and open HTML dashboard
```

## Output

All files are written to `.perf/` (gitignored):
- `.perf/config.json` — discovered configuration
- `.perf/data/*.json` — query results
- `.perf/dashboard.html` — interactive dashboard
