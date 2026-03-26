# Unjank — Firebase Performance Skills for AI Coding Agents

Agent skills for tracking and fixing screen rendering performance in Android, iOS, and Flutter apps. Works with any AI coding agent (Claude Code, Codex, etc.).

## What This Does

4 skills that give any developer a complete performance workflow:

| Skill | Command | What it does |
|-------|---------|-------------|
| **perf-setup** | `/perf-setup` | Discovers Firebase/GCP config, validates BigQuery access, runs smoke test |
| **perf-query** | `/perf-query` | Runs cost-optimized BigQuery queries for 30-day screen metrics |
| **perf-dashboard** | `/perf-dashboard` | Generates interactive HTML dashboard (worst screens, highest volume, trends) |
| **perf-fix** | `/perf-fix ScreenName` | Finds and fixes rendering anti-patterns in your code, safe changes first |

## Quick Start

### 1. Install the skills

Run this from your project root:

```bash
npx unjank-perf
```

Alternative methods:

```bash
# curl one-liner
curl -fsSL https://raw.githubusercontent.com/no-hup/unjank/main/install.sh | bash

# manual
git clone https://github.com/no-hup/unjank.git /tmp/unjank
cp -r /tmp/unjank/skills/perf-{setup,query,dashboard,fix} .claude/skills/
rm -rf /tmp/unjank
```

### 2. Run the workflow

```
/perf-setup              # one-time: discovers config, validates BigQuery
/perf-query              # fetches 30-day performance data
/perf-dashboard          # opens interactive dashboard in browser
/perf-fix HomeFragment   # finds and fixes rendering issues for a screen
```

## Prerequisites

- **gcloud CLI** installed and authenticated
- **Firebase Performance SDK** integrated in your app
- **BigQuery export** enabled in Firebase Console (one-time, data takes ~48h)

### Authentication (simplest path)

```bash
gcloud auth login
gcloud auth application-default login
```

That's it. No service accounts or key files needed for local development.

## Dashboard

The dashboard shows three views:

- **Worst Performing** — screens ranked by rendering severity (frozen frames + slow rendering composite score), color-coded red/yellow/green
- **Highest Volume** — screens ranked by sample count (most-used screens)
- **30-Day Trends** — app-wide frozen frame and slow rendering trends over time, with per-screen sparklines

## Performance Fixer

`/perf-fix` uses a tiered approach to protect legacy codebases:

| Tier | Agent behavior | Example |
|------|---------------|---------|
| **T1** | Fixes immediately (safe, no behavior change) | Cache DateFormatter, add DiffUtil, hoist allocations out of onDraw |
| **T2** | Shows diff + explains trade-off, waits for approval | Async image loading, flatten layouts, add Compose remember |
| **T3** | Suggests only, developer decides | Defer SDK init, move startup work off main thread |
| **T4** | Notes for backlog, never attempts | Lock contention fixes, SDK replacement, architecture rewrites |

The agent exhausts T1 before suggesting T2, and T2 before surfacing T3.

## Project Structure

```
skills/
├── README.md
├── REQUIREMENTS.txt
├── perf-setup/
│   ├── SKILL.md
│   └── scripts/
│       ├── detect_config.sh
│       └── validate_gcloud.sh
├── perf-query/
│   ├── SKILL.md
│   ├── queries/
│   │   ├── smoke_test.sql
│   │   ├── screen_summary.sql
│   │   ├── screen_daily.sql
│   │   └── app_daily_trend.sql
│   └── scripts/
│       └── run_bq_query.sh
├── perf-dashboard/
│   ├── SKILL.md
│   ├── dashboard-template.html
│   └── scripts/
│       └── assemble_dashboard.sh
└── perf-fix/
    ├── SKILL.md
    └── references/
        ├── detection-patterns.md
        ├── fix-templates.md
        └── knowledge-base.md
```

## How It Works Under the Hood

- **No Gradle plugin, no build system dependency** — pure skill files that any AI agent can follow
- **BigQuery queries via `bq` CLI** — no client libraries or SDK dependencies
- **Cost-optimized** — partition pruning + dry-run estimation before every query (~$0.05 for 30 days)
- **Helper scripts** for deterministic operations (config parsing, SQL templating, dashboard assembly)
- **Agent-agnostic** — scripts use `dirname "$0"` instead of Claude-specific variables

## Analytics

The install script pings an anonymous hit counter ([hits.sh](https://hits.sh)) so we know how many people are using Unjank. **No personal data is collected** — it just increments a number.

To opt out: `curl -fsSL ... | UNJANK_NO_ANALYTICS=1 bash`
