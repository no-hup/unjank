# Detection Patterns

Grep patterns for finding rendering anti-patterns in source code. Organized by platform and tier.

## Table of Contents
- [Android Tier 1 (safe fixes)](#android-tier-1)
- [Android Tier 2 (fix with review)](#android-tier-2)
- [Android Tier 3 (suggest only)](#android-tier-3)
- [Android Tier 4 (mention and defer)](#android-tier-4)
- [iOS Tier 1 (safe fixes)](#ios-tier-1)
- [iOS Tier 2 (fix with review)](#ios-tier-2)
- [iOS Tier 3 (suggest only)](#ios-tier-3)
- [iOS Tier 4 (mention and defer)](#ios-tier-4)
- [Cross-platform patterns](#cross-platform)

---

## Android Tier 1

### A3: Heavy work in onBindViewHolder / item composables
```
onBindViewHolder
onBind
DateFormat
SimpleDateFormat
String.format
NumberFormat
Html.fromHtml
Spannable
sorted(
filter {
map {
```
Match: formatting, parsing, sorting, filtering, or string building inside adapter bind methods.

### A4: Whole-list invalidation
```
notifyDataSetChanged
notifyDataSetChanged()
```
Match: full-list refresh instead of DiffUtil. Confirm by checking if model has `equals()` or `data class`.

### A8: Allocations in onDraw / onMeasure
```
onDraw
onMeasure
new Paint(
new Rect(
new Path(
new RectF(
Paint()
Rect()
Path()
```
Match: object creation inside draw/measure methods. Look for `new` or constructor calls inside these methods.

### A11: RecyclerView prefetch misconfiguration
```
RecyclerView
setInitialPrefetchItemCount
setItemPrefetchEnabled
setRecycledViewPool
RecycledViewPool
```
Match: nested RecyclerViews WITHOUT shared pool or prefetch count set. The absence of `setRecycledViewPool` near nested RVs is the signal.

### A12: Compose LazyColumn missing contentType
```
LazyColumn
LazyRow
LazyVerticalGrid
items(
itemsIndexed(
contentType
```
Match: `items(` or `itemsIndexed(` calls WITHOUT `contentType` parameter nearby.

### A13: Redundant backgrounds / overdraw
```
android:background
setBackgroundDrawable
setBackgroundColor
windowBackground
```
Match: multiple background declarations on the same view hierarchy path.

## Android Tier 2

### A5: Synchronous image decode
```
BitmapFactory.decode
BitmapFactory.decodeResource
BitmapFactory.decodeStream
BitmapFactory.decodeFile
setImageBitmap
painterResource
```
Match: bitmap decode/load calls in UI thread code (adapters, fragments, activities).

### A6: Deep / weight-heavy layouts
```
layout_weight
LinearLayout
android:visibility="gone"
```
Match: nested LinearLayouts with `layout_weight` (causes double measure pass). Count nesting depth in XML files.

### A7: Nested RecyclerViews without optimization
```
RecyclerView
setAdapter
LinearLayoutManager
GridLayoutManager
```
Match: RecyclerView setup inside ViewHolder or adapter code (indicates nesting).

### A9: Compose unstable params / broad state reads
```
mutableListOf
mutableMapOf
mutableSetOf
ArrayList
HashMap
mutableStateOf
remember {
derivedStateOf
AndroidView
```
Match: mutable collections passed as composable params, or missing `remember` around expensive computations.

### A14: Hardware layer on dynamic content
```
setLayerType
LAYER_TYPE_HARDWARE
LAYER_TYPE_SOFTWARE
```
Match: hardware layer set on views that are frequently invalidated.

### A16: Animation-driven layout thrashing
```
onAnimationUpdate
requestLayout
LayoutTransition
TransitionManager
setLayoutTransition
```
Match: `requestLayout()` or `invalidate()` called inside animation update callbacks.

### X1: Network-driven full reload
```
notifyDataSetChanged
submitList
reloadData
```
Match: full list invalidation inside API response callbacks (Retrofit, network handler).

## Android Tier 3

### A1: Main-thread startup work
```
Application.onCreate
Activity.onCreate
Fragment.onViewCreated
onResume
ContentProvider.onCreate
```
Match: heavy initialization (DI setup, Room, SharedPreferences, JSON parsing) in these callbacks.

### A2: Third-party SDK init
```
FirebaseApp.initializeApp
FacebookSdk.sdkInitialize
Crashlytics
Analytics
MobileAds.initialize
AppsFlyerLib
Branch.init
```
Match: SDK initialization in Application class or startup providers.

### X2: Deep link handling in launch
```
handleDeepLink
handleIntent
onNewIntent
handleUrl
```
Match: synchronous deep link processing in launch callbacks.

## Android Tier 4

### A10: Lock contention / sync I/O
```
synchronized
runBlocking
Dispatchers.IO
.await()
Thread.sleep
BlockingQueue
```
Match: blocking calls on or reachable from the main thread.

### A15: WebView in lists
```
WebView
loadUrl
loadData
```
Match: WebView creation or loading inside RecyclerView adapter code.

---

## iOS Tier 1

### I1: Heavy work in cell callbacks
```
cellForRowAt
cellForItemAt
willDisplay
dequeueReusableCell
DateFormatter()
NumberFormatter()
JSONDecoder()
sorted(
filter(
map(
```
Match: expensive computation inside cell configuration callbacks.

### I4: Full reloadData / snapshot rebuilds
```
reloadData()
reloadSections
performBatchUpdates
NSDiffableDataSourceSnapshot
snapshot.appendItems
snapshot.appendSections
```
Match: `reloadData()` or building a full snapshot from scratch on every data change.

### I9: Repeated formatter allocation
```
DateFormatter()
NumberFormatter()
NSAttributedString(
NSMutableAttributedString(
MeasurementFormatter()
```
Match: formatter constructors inside cell callbacks or frequently-called view code.

### I11: Snapshot generation on main thread
```
NSDiffableDataSourceSnapshot
appendItems
appendSections
apply(
```
Match: snapshot construction (not just `apply`) happening without `DispatchQueue.global()`.

### shadowPath addition (subset of I6)
```
shadowOpacity
shadowOffset
shadowRadius
shadowColor
shadowPath
```
Match: shadow properties set WITHOUT `shadowPath` — adding shadowPath is T1 safe.

## iOS Tier 2

### I2: Synchronous image decode
```
Data(contentsOf:
UIImage(contentsOfFile:
UIImage(data:
CGImageSourceCreateImageAtIndex
imageWithContentsOfFile
```
Match: synchronous image loading in cell callbacks or view setup.

### I7: Heavy SwiftUI body computation
```
var body: some View
sorted(by:
filter(
map(
reduce(
DateFormatter
NumberFormatter
```
Match: expensive computation directly inside SwiftUI `body` property.

### I8: Broad SwiftUI invalidation
```
@ObservedObject
@StateObject
@EnvironmentObject
ForEach
\.id
UUID()
.task
.onAppear
GeometryReader
```
Match: large observable objects, unstable ForEach IDs (especially `UUID()`), heavy `.task`/`.onAppear` in rows.

### I12: UIHostingController in cells
```
UIHostingController
UIHostingConfiguration
hostingController
```
Match: `UIHostingController` instantiation inside cell configuration code.

### I13: Core Data faulting in cells
```
NSManagedObject
NSFetchRequest
relationship
fault
```
Match: Core Data relationship access inside cell callbacks (triggers synchronous SQLite fetch).

### X1: Network-driven full reload (iOS)
```
reloadData
apply(
snapshot
```
Match: full reload/snapshot rebuild inside API completion handlers.

## iOS Tier 3

### I3: Main-thread launch work
```
didFinishLaunchingWithOptions
viewDidLoad
viewWillAppear
applicationDidBecomeActive
```
Match: heavy work in launch lifecycle (SDK init, data fetch, large view construction).

### I5: Auto Layout self-sizing churn
```
systemLayoutSizeFitting
estimatedRowHeight
estimatedItemSize
UITableView.automaticDimension
preferredLayoutAttributesFitting
intrinsicContentSize
```
Match: complex self-sizing in high-churn list cells.

### I6: Offscreen rendering
```
masksToBounds
layer.mask
cornerRadius
UIVisualEffectView
UIBlurEffect
```
Match: compositing triggers in list cells. Exception: `shadowPath` addition is T1.

### X2: Deep link handling in launch (iOS)
```
handleDeepLink
handle(_ url:
openURL
userActivity
```
Match: synchronous deep link processing in AppDelegate/SceneDelegate.

## iOS Tier 4

### I10: Lock contention / priority inversion
```
DispatchQueue.main.sync
.sync {
semaphore.wait
DispatchGroup.wait
os_unfair_lock
NSLock
pthread_mutex
```
Match: blocking calls reachable from the main thread.

### I14: Swift concurrency architecture
```
@MainActor
MainActor.run
await
Task {
```
Match: frequent actor hops in hot paths (cell callbacks, body recomputation).

---

## Cross-platform

### Metric-shape heuristic
Use these to prioritize which patterns to grep for first:

| Metric shape | Grep first |
|-------------|-----------|
| Frozen-heavy | A1, A2, A10, I3, I10, X2 (blocking/startup patterns) |
| Slow-heavy | A3, A4, A8, I1, I4, I9 (per-frame/list patterns) |
| Both high | A3+A1, I1+I3 (list pipeline + startup) |
| Scroll-only | A4, A7, A8, I1, I2, I5 (list-specific patterns) |
| First-open only | A1, A2, I3 (cold-path patterns) |
