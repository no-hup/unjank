# Performance Knowledge Base (Condensed Reference)

This is the condensed reference for the perf-fix skill. For the full knowledge base with sources and case studies, see `analysis_artifacts/screen_rendering_knowledge_base_2026-03-26.md` in the project root.

## Table of Contents
- [Metric Semantics](#metric-semantics)
- [Android Anti-Patterns (A1-A16)](#android-anti-patterns)
- [iOS Anti-Patterns (I1-I14)](#ios-anti-patterns)
- [Cross-Platform Patterns (X1-X3)](#cross-platform-patterns)
- [Minimum Evidence Gate](#minimum-evidence-gate)
- [Screen-to-Code Navigation](#screen-to-code-navigation)

## Metric Semantics

Firebase reports:
- **Slow rendering**: % of screen instances where >50% of frames took >16ms
- **Frozen frames**: % of screen instances where >0.1% of frames took >700ms
- Both use a 60 Hz assumption — may not match behavior on 90/120 Hz devices

iOS equivalents:
- Slow rendering ≈ scroll hitch rate
- Frozen frames ≈ hangs
- Apple's thresholds: <5 hitch ms/s acceptable, 5-10 noticeable, >10 degraded

Key insight: a hung main thread can show **low CPU** because it's waiting (lock, I/O, IPC), not computing.

## Android Anti-Patterns

### T1 — Safe to fix

**A3: Heavy onBindViewHolder work** — formatting, sorting, filtering, HTML parsing in bind.
Fix: precompute in ViewModel/data layer, cache results.

**A4: notifyDataSetChanged()** — full-list invalidation.
Fix: DiffUtil/ListAdapter. Requires stable IDs on model.

**A8: Allocations in onDraw/onMeasure** — Paint, Rect, Path objects created per-frame.
Fix: hoist to class fields, reuse.

**A11: Nested RV without shared pool** — inner RecyclerViews miss prefetch.
Fix: add `setRecycledViewPool()` and `setInitialPrefetchItemCount()`.

**A12: LazyColumn without contentType** — Compose can't reuse compositions across types.
Fix: add `contentType` and `key` parameters.

**A13: Redundant backgrounds** — overdraw from window + layout backgrounds.
Fix: remove duplicate `android:background` or set window background transparent.

### T2 — Fix with review

**A5: Sync image decode** — BitmapFactory on main thread.
Fix: async load/decode, downsample. Changes loading UX.

**A6: Weight-heavy layouts** — nested LinearLayout with `layout_weight`.
Fix: flatten, use ConstraintLayout. Verify visual layout.

**A7: Nested RV overhead** — RecyclerView inside RecyclerView without optimization.
Fix: shared pool, prefetch, simplify variants.

**A9: Compose unstable params** — mutable collections, broad state reads.
Fix: stable/immutable params, `remember`, `derivedStateOf`.

**A14: Hardware layer on dynamic content** — LAYER_TYPE_HARDWARE on invalidated views.
Fix: remove or scope to animation only.

**A16: Animation layout thrashing** — requestLayout in onAnimationUpdate.
Fix: use property animations that don't trigger layout.

### T3 — Suggest only

**A1: Main-thread startup work** — heavy init in onCreate/onViewCreated.
Fix: defer, lazy-load, background thread. Changes launch ordering.

**A2: SDK cold-path init** — analytics/crash/ad SDKs blocking first frame.
Fix: App Startup, lazy init. Product-sensitive.

### T4 — Defer

**A10: Lock contention / sync I/O** — synchronized, runBlocking on main thread.
**A15: WebView in lists** — architecture decision to replace.

## iOS Anti-Patterns

### T1 — Safe to fix

**I1: Heavy cell callback work** — computation in cellForRowAt.
Fix: precompute, cache formatters, minimize cell setup.

**I4: Full reloadData()** — rebuilds entire list.
Fix: diffable data source, incremental updates.

**I9: Repeated formatter allocation** — DateFormatter() per cell.
Fix: cache as static/shared instance.

**I11: Snapshot construction on main thread** — large snapshot build blocking UI.
Fix: move to background queue, apply on main.

**shadowPath (I6 subset)** — shadow without path forces offscreen render.
Fix: add `shadowPath`. Pure additive.

### T2 — Fix with review

**I2: Sync image load** — Data(contentsOf:) in cell setup.
Fix: async fetch + background decode. Changes loading UX.

**I7: Heavy SwiftUI body** — sorting, filtering, formatting in body.
Fix: precompute in ViewModel.

**I8: Broad SwiftUI invalidation** — large @ObservedObject, unstable ForEach IDs.
Fix: stable IDs, smaller state, dedupe .task.

**I12: UIHostingController in cells** — SwiftUI-in-UIKit bridging cost.
Fix: UIHostingConfiguration (iOS 16+) or native UIKit cells.

**I13: Core Data faulting in cells** — relationship access triggers sync SQLite.
Fix: relationshipKeyPathsForPrefetching or DTO mapping.

### T3 — Suggest only

**I3: Main-thread launch work** — heavy didFinishLaunching/viewDidLoad.
Fix: defer, background. Changes launch semantics.

**I5: Auto Layout self-sizing churn** — complex constraints in cells.
Fix: simplify constraints, cache heights.

**I6: Offscreen rendering** — masks, blur, transparency in lists.
Fix: shadowPath (T1), design tradeoffs for the rest (T3).

### T4 — Defer

**I10: Lock contention / DispatchQueue.main.sync** — concurrency architecture.
**I14: @MainActor overhead** — actor hop cost in hot paths.

## Cross-Platform Patterns

**X1: Network-driven full reload** [T2] — API response triggers full list rebuild.
Fix: incremental/partial updates, debounce.

**X2: Deep link handling on cold start** [T3] — compounds launch cost.
Fix: defer navigation until after first frame.

**X3: Device tier awareness** [Context] — same code performs differently on low-end devices.
Agent should note when a fix trades memory for speed (riskier on low-end).

## Minimum Evidence Gate

Before the agent edits code, it needs at least:
1. **Metric signal** — the screen is actually bad in production data
2. **Static signal** — a grep hit matches a known anti-pattern
3. **Mechanism match** — the suspected pattern explains the metric shape (frozen vs slow)
4. **Behavior safety** — the fix preserves semantics

If only 1-2 are met: **suggest, don't patch**.

## Screen-to-Code Navigation

### Android resolution order
1. Exact match: `{ScreenName}.kt` / `.java` — Fragment, Activity, or Composable
2. Class name match: `class {ScreenName}`
3. Navigation graph: destination IDs or route strings
4. Analytics constants: custom screen name mappings

### iOS resolution order
1. Exact match: `{ScreenName}.swift` / `.m` — ViewController or SwiftUI View
2. Class name match: `class {ScreenName}`
3. Storyboard: scene identifiers
4. Analytics constants: custom screen name mappings

### Walk outward from screen file
- **Layout/UI**: XML layouts, XIBs, Composable content, SwiftUI body
- **List pipeline**: Adapter/DataSource → ViewHolder/Cell → item layout
- **Data layer**: ViewModel → Repository → API/DB calls
- **Image pipeline**: loader config, decode, cache
- **Startup**: Application/AppDelegate, ContentProvider, DI graph
