# Fix Templates

Before/after code examples for common performance fixes. Use these as patterns when applying Tier 1 and Tier 2 fixes.

## Table of Contents
- [Android Tier 1 Templates](#android-tier-1-templates)
- [Android Tier 2 Templates](#android-tier-2-templates)
- [iOS Tier 1 Templates](#ios-tier-1-templates)
- [iOS Tier 2 Templates](#ios-tier-2-templates)

---

## Android Tier 1 Templates

### Cache formatter in onBindViewHolder

**Before:**
```kotlin
override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    val item = items[position]
    val formatter = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
    holder.dateText.text = formatter.format(item.date)
}
```

**After:**
```kotlin
companion object {
    private val dateFormatter = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
}

override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    val item = items[position]
    holder.dateText.text = dateFormatter.format(item.date)
}
```

**Prerequisite:** Locale/timezone don't change per-cell.

### Replace notifyDataSetChanged with DiffUtil

**Before:**
```kotlin
fun updateItems(newItems: List<Item>) {
    items = newItems
    notifyDataSetChanged()
}
```

**After:**
```kotlin
class ItemDiffCallback(
    private val oldList: List<Item>,
    private val newList: List<Item>
) : DiffUtil.Callback() {
    override fun getOldListSize() = oldList.size
    override fun getNewListSize() = newList.size
    override fun areItemsTheSame(old: Int, new: Int) = oldList[old].id == newList[new].id
    override fun areContentsTheSame(old: Int, new: Int) = oldList[old] == newList[new]
}

fun updateItems(newItems: List<Item>) {
    val diff = DiffUtil.calculateDiff(ItemDiffCallback(items, newItems))
    items = newItems
    diff.dispatchUpdatesTo(this)
}
```

**Prerequisite:** Model has stable `id` and correct `equals()`. If using `data class`, equals is auto-generated.

**Even better — use ListAdapter:**
```kotlin
class MyAdapter : ListAdapter<Item, ViewHolder>(ItemDiff()) {
    class ItemDiff : DiffUtil.ItemCallback<Item>() {
        override fun areItemsTheSame(old: Item, new: Item) = old.id == new.id
        override fun areContentsTheSame(old: Item, new: Item) = old == new
    }
}
// Then: adapter.submitList(newItems)
```

### Hoist allocation out of onDraw

**Before:**
```kotlin
override fun onDraw(canvas: Canvas) {
    val paint = Paint().apply {
        color = Color.RED
        strokeWidth = 2f
    }
    val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
    canvas.drawRoundRect(rect, 8f, 8f, paint)
}
```

**After:**
```kotlin
private val paint = Paint().apply {
    color = Color.RED
    strokeWidth = 2f
}
private val rect = RectF()

override fun onDraw(canvas: Canvas) {
    rect.set(0f, 0f, width.toFloat(), height.toFloat())
    canvas.drawRoundRect(rect, 8f, 8f, paint)
}
```

### Add contentType to LazyColumn

**Before:**
```kotlin
LazyColumn {
    items(feedItems) { item ->
        when (item) {
            is Header -> HeaderCard(item)
            is Post -> PostCard(item)
            is Ad -> AdCard(item)
        }
    }
}
```

**After:**
```kotlin
LazyColumn {
    items(
        items = feedItems,
        key = { it.id },
        contentType = { it::class }
    ) { item ->
        when (item) {
            is Header -> HeaderCard(item)
            is Post -> PostCard(item)
            is Ad -> AdCard(item)
        }
    }
}
```

### Add shared RecycledViewPool for nested RecyclerViews

**Before:**
```kotlin
override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    holder.innerRecyclerView.adapter = InnerAdapter(items[position].children)
    holder.innerRecyclerView.layoutManager = LinearLayoutManager(context, HORIZONTAL, false)
}
```

**After:**
```kotlin
private val sharedPool = RecyclerView.RecycledViewPool()

override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    holder.innerRecyclerView.adapter = InnerAdapter(items[position].children)
    holder.innerRecyclerView.layoutManager = LinearLayoutManager(context, HORIZONTAL, false).apply {
        initialPrefetchItemCount = 4 // number of items visible in the horizontal list
    }
    holder.innerRecyclerView.setRecycledViewPool(sharedPool)
}
```

### Remove redundant background

**Before (Activity):**
```kotlin
// Theme has windowBackground = @color/white
// Layout root also has android:background="@color/white"
```

**After:**
```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    window.setBackgroundDrawableResource(android.R.color.transparent)
    setContentView(R.layout.activity_home)
}
```

Only do this when the root layout has its own opaque background.

---

## Android Tier 2 Templates

### Move heavy bind work to ViewModel

**Before:**
```kotlin
override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    val item = items[position]
    val processed = item.rawHtml.let { Html.fromHtml(it, FROM_HTML_MODE_COMPACT) }
    holder.content.text = processed
}
```

**After:**
```kotlin
// In ViewModel or data mapping layer:
data class ProcessedItem(
    val id: String,
    val displayContent: Spanned // pre-processed
)

fun mapItems(raw: List<RawItem>): List<ProcessedItem> = raw.map {
    ProcessedItem(id = it.id, displayContent = Html.fromHtml(it.rawHtml, FROM_HTML_MODE_COMPACT))
}

// In adapter:
override fun onBindViewHolder(holder: ViewHolder, position: Int) {
    holder.content.text = items[position].displayContent
}
```

---

## iOS Tier 1 Templates

### Cache DateFormatter

**Before:**
```swift
func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM dd, yyyy"
    cell.textLabel?.text = formatter.string(from: items[indexPath.row].date)
    return cell
}
```

**After:**
```swift
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM dd, yyyy"
    return f
}()

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    cell.textLabel?.text = Self.dateFormatter.string(from: items[indexPath.row].date)
    return cell
}
```

### Replace reloadData with diffable updates

**Before:**
```swift
func updateData(_ newItems: [Item]) {
    self.items = newItems
    tableView.reloadData()
}
```

**After:**
```swift
private lazy var dataSource = UITableViewDiffableDataSource<Section, Item>(tableView: tableView) { tableView, indexPath, item in
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    cell.textLabel?.text = item.title
    return cell
}

func updateData(_ newItems: [Item]) {
    var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
    snapshot.appendSections([.main])
    snapshot.appendItems(newItems)
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

**Prerequisite:** `Item` must conform to `Hashable` with O(1) implementation.

### Move snapshot construction to background

**Before:**
```swift
func refreshData(_ items: [Item]) {
    var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
    snapshot.appendSections([.main])
    snapshot.appendItems(items) // expensive for 1000+ items
    dataSource.apply(snapshot)
}
```

**After:**
```swift
func refreshData(_ items: [Item]) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        DispatchQueue.main.async {
            self?.dataSource.apply(snapshot)
        }
    }
}
```

### Add shadowPath

**Before:**
```swift
cell.layer.shadowColor = UIColor.black.cgColor
cell.layer.shadowOpacity = 0.2
cell.layer.shadowOffset = CGSize(width: 0, height: 2)
cell.layer.shadowRadius = 4
```

**After:**
```swift
cell.layer.shadowColor = UIColor.black.cgColor
cell.layer.shadowOpacity = 0.2
cell.layer.shadowOffset = CGSize(width: 0, height: 2)
cell.layer.shadowRadius = 4
cell.layer.shadowPath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: cell.layer.cornerRadius).cgPath
```

Note: if cell size changes, update `shadowPath` in `layoutSubviews`.

---

## iOS Tier 2 Templates

### Add prefetching for relationship data

**Before:**
```swift
let request: NSFetchRequest<Post> = Post.fetchRequest()
request.predicate = NSPredicate(format: "feed == %@", feed)
let posts = try context.fetch(request)
```

**After:**
```swift
let request: NSFetchRequest<Post> = Post.fetchRequest()
request.predicate = NSPredicate(format: "feed == %@", feed)
request.relationshipKeyPathsForPrefetching = ["author", "comments"]
let posts = try context.fetch(request)
```

### Move heavy body computation to ViewModel (SwiftUI)

**Before:**
```swift
var body: some View {
    let sorted = items.sorted { $0.date > $1.date }
    let filtered = sorted.filter { $0.isActive }
    List(filtered) { item in
        ItemRow(item: item)
    }
}
```

**After:**
```swift
// In ViewModel:
@Published var displayItems: [Item] = []

func processItems(_ items: [Item]) {
    displayItems = items.sorted { $0.date > $1.date }.filter { $0.isActive }
}

// In View:
var body: some View {
    List(viewModel.displayItems) { item in
        ItemRow(item: item)
    }
}
```
