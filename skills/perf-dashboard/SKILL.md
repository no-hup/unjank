---
name: perf-dashboard
description: >
  Generate an interactive local HTML dashboard from Firebase Performance query results.
  Shows worst-performing screens, highest-volume screens, and 30-day trends with Chart.js.
  TRIGGER when: user asks for a dashboard, visualization, chart, report, or HTML output
  of performance data. Also trigger when user says "show me the results" or "open dashboard"
  after running /perf-query. Requires /perf-query to have been run first (checks for .perf/data/).
allowed-tools: Bash, Read, Write
---

# Firebase Performance Dashboard

Generate a self-contained HTML dashboard from BigQuery performance data. This skill uses a helper script for deterministic template assembly.

## IMPORTANT: Autonomous Execution

Run all steps without asking for confirmation. Verify data, assemble dashboard, open in browser, and print summary — all in one go. **Only pause if** data files are missing (tell the user to run `/perf-query` first). Do NOT ask "Ready to proceed?" or "Should I open the dashboard?"

## Step 1: Verify Data Exists

Check that these files exist:
- `.perf/config.json`
- `.perf/data/screen_summary.json`
- `.perf/data/app_daily_trend.json`
- `.perf/data/query_metadata.json`

If any are missing, STOP: "Query data not found. Run `/perf-query` first."

## Step 2: Assemble Dashboard

Locate and run the assembly script. Check these paths in order:
- `.claude/skills/perf-dashboard/scripts/assemble_dashboard.sh`
- `skills/perf-dashboard/scripts/assemble_dashboard.sh`

```bash
bash {script_path}/assemble_dashboard.sh .
```

The script:
1. Reads all data JSON files from `.perf/data/`
2. Reads the `dashboard-template.html` from its own skill directory
3. Injects the data into template placeholders
4. Writes `.perf/dashboard.html`
5. Auto-opens in the default browser

If the script is not found, assemble the dashboard manually:
1. Read the `dashboard-template.html` from the skill directory
2. Replace `{{SCREEN_SUMMARY_JSON}}` with contents of `.perf/data/screen_summary.json`
3. Replace `{{SCREEN_DAILY_JSON}}` with contents of `.perf/data/screen_daily.json` (or `[]` if missing)
4. Replace `{{APP_TREND_JSON}}` with contents of `.perf/data/app_daily_trend.json`
5. Replace `{{QUERY_METADATA_JSON}}` with contents of `.perf/data/query_metadata.json`
6. Replace `{{APP_ID}}`, `{{PLATFORM}}`, `{{TABLE_NAME}}` from `.perf/config.json`
7. Replace `{{GENERATED_AT}}` with current ISO timestamp
8. Write to `.perf/dashboard.html`

## Step 3: Open in Browser

If the script didn't auto-open, open manually:

```bash
if [[ "$OSTYPE" == "darwin"* ]]; then open .perf/dashboard.html
elif [[ "$OSTYPE" == "linux"* ]]; then xdg-open .perf/dashboard.html 2>/dev/null
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then explorer.exe .perf/dashboard.html 2>/dev/null
else echo "Open .perf/dashboard.html in your browser"
fi
```

## Step 4: Print Summary and Recommend Next Fix

Read `.perf/data/screen_summary.json`. Rank the top 5 worst screens by composite score (frozen * 0.6 + slow * 0.4). Then look at the source code for each — quickly scan if obvious anti-patterns exist (heavy `onBind`/`cellForRow`, main-thread image loading, nested layouts). Pick the one that has the highest composite score AND likely has easy wins in the code, and recommend it.

```
Dashboard generated at .perf/dashboard.html

Quick stats:
- {N} screens analyzed
- Worst screen: {name} (frozen: {X}%, slow: {Y}%)
- Highest volume: {name} ({N} samples)
- 30-day trend: frozen {direction}, slow render {direction}

Top 5 worst performing:
  1. {name} — frozen: {X}%, slow: {Y}%
  2. {name} — frozen: {X}%, slow: {Y}%
  3. {name} — frozen: {X}%, slow: {Y}%
  4. {name} — frozen: {X}%, slow: {Y}%
  5. {name} — frozen: {X}%, slow: {Y}%

Recommended: Start with {name} — it has the worst metrics and I can see
some quick wins in the code. Run: /perf-fix {name}
```

If you can't quickly determine which has easy wins, just recommend the highest composite score screen.

## Error Handling

| Error | Action |
|-------|--------|
| Data files missing | "Run `/perf-query` first to fetch performance data." |
| Template not found | "Dashboard template not found. Reinstall the perf-dashboard skill." |
| python3 not available | "Python 3 is required for dashboard assembly. Install from python.org." |
| Browser open fails | "Dashboard saved to `.perf/dashboard.html` — open it manually in your browser." |
| Empty screen summary | "No screen data to display. Run `/perf-query` to refresh." |
