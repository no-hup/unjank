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

Fix frozen frames and slow rendering for specific screens. You work one screen at a time, fix safe things first, and never change code without the developer's approval.

## Why this ordering matters

Large codebases have many potential optimizations, but each change carries risk. Legacy code has implicit dependencies — a "simple" fix can break flows you can't see. The tier system below exists because **the safest, highest-impact fixes should land first**. This builds developer trust and delivers measurable improvement before attempting anything risky.

## Input

The developer invokes: `/perf-fix ScreenName` (or up to 5 screen names separated by commas).

If more than 5 screens are provided, respond: "Let's focus on up to 5 screens per session for accuracy. Which 5 are highest priority?"

## Step 1: Load performance metrics

Read `.perf/data/screen_summary.json` for the target screen's metrics. If the file doesn't exist, tell the developer: "No performance data found. Run `/perf-query` first to fetch data from BigQuery."

Extract `frozen_frames_pct`, `slow_render_pct`, and `total_samples` for $ARGUMENTS.

If the screen name isn't in the data, suggest close matches and ask the developer to confirm.

Classify the metric shape — this guides where to look first:

| Shape | Likely cause | Where to look first |
|-------|-------------|-------------------|
| High frozen, low slow | Blocking stall, startup work, sync I/O | Lifecycle callbacks, data loading, SDK init |
| High slow, low frozen | Repeated per-frame work, image decode | Adapter/cell bind, layout complexity, draw code |
| Both high | Mixed structural problem | List pipeline + startup path together |

Read [references/detection-patterns.md](references/detection-patterns.md) for the full grep patterns to use in step 3.

## Step 2: Map screen to source files

Find the source files that own this screen. Search in order of confidence:

**Android:**
1. Glob for `**/{ScreenName}.kt`, `**/{ScreenName}.java` — exact Activity/Fragment match
2. Grep for `class {ScreenName}` across `.kt` and `.java` files
3. Check navigation graph XMLs for destination references

Then walk outward to related files:
- Layout XML: grep for `setContentView`, `inflate`, or Compose `@Composable` in the screen file
- Adapter/ViewHolder: grep for `RecyclerView.Adapter`, `ListAdapter` references
- ViewModel: grep for `viewModel`, `by viewModels`, `ViewModelProvider`
- Image loading: grep for `Glide`, `Coil`, `Picasso`, `BitmapFactory` in the adapter

**iOS:**
1. Glob for `**/{ScreenName}.swift`, `**/{ScreenName}.m` — exact ViewController/View match
2. Grep for `class {ScreenName}` across `.swift` files
3. Check storyboards for scene identifiers

Then walk outward to:
- Cell classes: grep for `UITableViewCell`, `UICollectionViewCell` subclasses referenced in data source
- ViewModel/Coordinator: grep for imports and property declarations
- Image loading: grep for `UIImage`, `Data(contentsOf:)`, `Kingfisher`, `SDWebImage`

If you find the screen file but can't identify the platform, read the file to determine it.

List all discovered files to the developer before proceeding: "I found these files related to {ScreenName}: [list]. Does this look right, or am I missing anything?"

## Step 3: Scan for anti-patterns

Read [references/detection-patterns.md](references/detection-patterns.md) for the platform-specific grep patterns.

Run the relevant grep passes against ALL discovered files from step 2. For each hit, note:
- The file and line number
- Which anti-pattern it matches
- Its tier (T1, T2, T3, or T4)

Do NOT read the full knowledge base yet — only load [references/knowledge-base.md](references/knowledge-base.md) if you need deeper context on a specific pattern.

## Step 4: Present findings by tier

Group all findings and present them to the developer in this exact structure:

```
## Performance Analysis: {ScreenName}
Metrics: frozen={X}%, slow={Y}%, samples={N}

### SAFE TO FIX NOW (Tier 1)
These are pure, mechanical transforms with no behavioral side effects.
I can apply these immediately if you approve.

1. [file:line] — {description of issue}
   Fix: {one-line description of the fix}

2. [file:line] — {description}
   Fix: {description}

### FIX WITH REVIEW (Tier 2)
These improve performance but change some behavior (loading UX, async flow).
I'll show you the diff and explain trade-offs before applying.

1. [file:line] — {description}
   Fix: {description}
   Trade-off: {what changes}

### SUGGESTIONS FOR DISCUSSION (Tier 3)
High-impact but high-risk changes. These need your input on product/design tradeoffs.

1. [file:line] — {description}
   Recommended fix: {description}
   Why this needs discussion: {explanation}

### NOTED FOR FUTURE (Tier 4)
These require architectural changes. Noting for your team's backlog.

- [file:line] — {brief description}
```

If a tier has no findings, omit it entirely.

After presenting, ask: "Which tier would you like me to work on? I recommend starting with Tier 1."

## Step 5: Apply fixes (only on approval)

**For Tier 1:** When the developer approves, apply ALL T1 fixes. Show the diff for each file changed. After applying, summarize: "Applied {N} Tier 1 fixes across {M} files."

**For Tier 2:** Apply ONE fix at a time. For each:
1. Show the full diff before applying
2. Explain the trade-off clearly
3. Wait for explicit "yes" / "go ahead" / approval
4. Apply and confirm

**For Tier 3:** Do NOT generate code unless the developer explicitly asks. Only explain the issue, the standard fix pattern, and what would change. If they ask you to draft it, show the code but let them apply it.

**For Tier 4:** Never attempt. Just list them.

## Step 6: Summary

After all approved fixes are applied, output:

```
## Summary: {ScreenName}

### Applied
- [T1] {description} — {file}
- [T1] {description} — {file}
- [T2] {description} — {file}

### Suggested (not applied)
- [T3] {description} — needs discussion with screen owner
- [T4] {description} — architectural, for team backlog

### Verification
To verify the impact of these changes:
- Android: run Macrobenchmark or check Firebase Performance after next release
- iOS: run XCTest performance tests or check Xcode Organizer metrics
```

## Stop conditions

Stop and tell the developer instead of proceeding when:

- The suspected problematic code is in a third-party library or SDK (not the team's code)
- The fix would change user-visible behavior (loading states, animation, data freshness)
- You're not confident in the screen-to-code mapping (say so explicitly)
- Multiple root causes are tangled together and the smallest safe change isn't clear
- The code is generated or heavily meta-programmed (e.g., code-gen from Protobuf/GraphQL)

## Reference files

These are loaded on demand — do not read them all upfront:

- [references/detection-patterns.md](references/detection-patterns.md) — grep patterns organized by platform and tier. **Read this in Step 3.**
- [references/knowledge-base.md](references/knowledge-base.md) — full anti-pattern catalog with mechanisms and fix templates. **Read specific sections when you need deeper context on a pattern you found.**
- [references/fix-templates.md](references/fix-templates.md) — before/after code examples for common fixes. **Read when applying T1/T2 fixes to ensure correctness.**
