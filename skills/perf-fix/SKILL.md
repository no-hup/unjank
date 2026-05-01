---
name: perf-fix
description: >
  Fix screen rendering jank, frozen frames, and slow rendering for specific
  screens in Android or iOS apps. ONLY invoke when the developer explicitly
  asks to fix or optimize rendering performance of a named screen.
  Do NOT invoke during general code review, refactoring, bug fixes, or
  feature development — even if you notice performance smells.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Write, Glob, Edit
---

# Screen Rendering Performance Fixer

> **Optional skill.** The main Unjank workflow is `/perf-setup` → `/perf-query` → `/perf-dashboard`. This skill goes one step further — use it when you want to act on what the dashboard showed you.

Fix frozen frames and slow rendering for a specific screen. Work one screen at a time. Apply safe fixes immediately, get one batch approval for behavioral changes, leave architectural decisions as notes.

**Try first, surface only when stuck.** If you can figure something out (find the file, identify the pattern, apply the fix), do it. Only pause when you genuinely cannot proceed without a human decision. The only real decision the developer needs to make is approving Tier 2 fixes — everything else you handle.

## Input

The developer invokes: `/perf-fix ScreenName` (or up to 5 screen names separated by commas).

If more than 5 screens are provided: "Let's focus on up to 5 screens per session. Which 5 are highest priority?"

---

## Step 0: Check fix history

Before anything else, look for `.perf/fix-history/{ScreenName}.json`.

**If it exists**, read it and surface a one-line recap:
```
Previous session ({date}): Applied {N} fix(es) — {brief list}. Baseline was frozen={X}%, slow={Y}%.
```
Load the `applied` list into memory — you'll use it in Step 3 to skip already-fixed patterns and flag regressions.

**If it doesn't exist**, proceed silently.

---

## Step 1: Load performance metrics

Read `.perf/data/screen_summary.json` for the target screen. If missing: "No performance data found. Run `/perf-query` first."

Extract `frozen_frames_pct`, `slow_render_pct`, `total_samples`.

If the screen name isn't found, suggest the 3 closest matches (fuzzy match on screen name) and ask which one.

If fix history exists, compute and show the delta:
```
Current: frozen={X}%, slow={Y}%  (was frozen={A}%, slow={B}% at last session — {improved/regressed/unchanged})
```

Classify the metric shape to guide where to look first:

| Shape | Likely cause | Where to look first |
|-------|-------------|-------------------|
| High frozen, low slow | Blocking stall, sync I/O | Lifecycle callbacks, data loading, SDK init |
| High slow, low frozen | Per-frame work, image decode | Adapter bind, layout complexity, draw code |
| Both high | Mixed structural | List pipeline + startup path |

---

## Step 2: Map screen to source files

Find all source files that own this screen. Search systematically:

**Android:**
1. `**/{ScreenName}.kt`, `**/{ScreenName}.java`
2. `grep -r "class {ScreenName}"` across `.kt` and `.java`
3. Navigation XML for destination references
4. Walk outward: layout XML → adapter/ViewHolder → ViewModel → image loading calls

**iOS:**
1. `**/{ScreenName}.swift`, `**/{ScreenName}.m`
2. `grep -r "class {ScreenName}"` across `.swift`
3. Storyboards for scene identifiers
4. Walk outward: cell classes → ViewModel/Coordinator → image loading

**If you find files:** State them inline and move on — "Scanning HomeFragment.kt, HomeAdapter.kt, home_layout.xml..." — do not ask for confirmation.

**If you find zero files after exhausting all strategies:** Then ask. "Couldn't locate source files for {ScreenName}. Is the screen named differently in code, or is it in a module I should look in?"

---

## Step 3: Scan for anti-patterns

Read [references/detection-patterns.md](references/detection-patterns.md) for platform-specific grep patterns.

Run all relevant grep passes against discovered files. For each hit, note: file, line, pattern ID, tier.

**If fix history exists:** For each detected pattern:
- If it's in the `applied` list from last session → mark as **REGRESSION** (was fixed, now re-detected) instead of a normal finding
- If it's in the `skipped` list (T3/T4 from last session) → include normally, they were never applied

Only load [references/knowledge-base.md](references/knowledge-base.md) if you need deeper context on a specific pattern.

---

## Step 4: Present findings and apply Tier 1

Organize findings by tier and present them:

```
## Performance Analysis: {ScreenName}
Metrics: frozen={X}%, slow={Y}%, samples={N}
[If history: ↓ from frozen={A}%, slow={B}% last session]

### TIER 1 — Applying now (safe mechanical transforms)
1. [file:line] — {issue description}
   Fix: {one-line description}

### TIER 2 — Need your approval (changes loading/async behavior)
1. [file:line] — {issue description}
   Fix: {description} | Trade-off: {what changes}

### TIER 3 — For discussion (high-impact, high-risk)
1. [file:line] — {description} | Why it needs discussion: {reason}

### TIER 4 — Team backlog (architectural)
- [file:line] — {brief description}
```

Omit any tier with no findings.

**Immediately after presenting:** Apply all Tier 1 fixes without waiting. Say "Applying Tier 1 fixes..." and do it. Show a single combined diff at the end.

If there are **REGRESSION** findings (patterns re-detected after prior fix), call them out prominently:
```
⚠ REGRESSION: sync_image_load re-detected in HomeAdapter.kt:47 — this was fixed last session. Check if the fix was reverted.
```

---

## Step 5: Tier 2 batch approval

If there are Tier 2 findings, show all diffs together:

```
--- Tier 2 diffs ---

[1] HomeFragment.kt:23 — Move network call off main thread
  - val data = api.fetch()  // blocking
  + lifecycleScope.launch { val data = withContext(Dispatchers.IO) { api.fetch() } }
  Trade-off: loading state will show briefly before data arrives

[2] ...

Apply Tier 2 fixes? Reply: all / 1,2 / skip
```

Apply exactly what they approve. If they say "skip" or don't respond to a fix, note it in the history as `declined`.

**Tier 3:** Explain the issue and standard fix pattern. Do not generate code unless they explicitly ask. If they ask, show it but let them apply it.

**Tier 4:** Never attempt. Listed only.

---

## Step 6: Summary

```
## Summary: {ScreenName}

### Applied
- [T1] {description} — {file}
- [T2] {description} — {file}  (if approved)

### Suggested (not applied)
- [T3] {description} — needs discussion
- [T4] {description} — architectural, for team backlog

### Verification
Run after next release:
- Android: Firebase Performance Console → Screen Rendering, or Macrobenchmark
- iOS: Xcode Organizer metrics, or Firebase Performance Console
```

---

## Step 7: Write fix history

Write (or update) `.perf/fix-history/{ScreenName}.json`:

```json
{
  "screen_name": "{ScreenName}",
  "sessions": [
    {
      "date": "{ISO timestamp}",
      "baseline": {
        "frozen_pct": 0.0,
        "slow_pct": 0.0,
        "samples": 0
      },
      "applied": [
        {
          "tier": 1,
          "file": "HomeAdapter.kt",
          "line": 47,
          "pattern": "sync_image_load",
          "description": "Moved Glide load off bind method"
        }
      ],
      "declined": ["pattern_id"],
      "skipped_tiers": ["nested_layout_depth"]
    }
  ]
}
```

If the file already exists, **append** the new session to the `sessions` array — never overwrite prior sessions. Keep last 5 sessions max (drop oldest).

---

## Stop conditions

Stop and tell the developer instead of proceeding when:

- The problematic code is in a third-party library (not team's code)
- A fix would change user-visible behavior AND you can't fully characterize the trade-off
- You found zero files after all search strategies
- Multiple root causes are tangled and the smallest safe change isn't clear
- Code is generated (Protobuf/GraphQL codegen) — flag it, don't touch it

---

## Reference files (load on demand)

- [references/detection-patterns.md](references/detection-patterns.md) — grep patterns by platform and tier. **Read in Step 3.**
- [references/knowledge-base.md](references/knowledge-base.md) — full anti-pattern catalog. **Read only for specific patterns you need deeper context on.**
- [references/fix-templates.md](references/fix-templates.md) — before/after code examples. **Read when applying T1/T2 fixes.**
