# AI NEXUS — Flutter Performance Optimization Rules

> Add this to your project at docs/PERFORMANCE_RULES.md
> These rules MUST be followed for every widget, screen, and component.

---

## MANDATORY RULES (Apply to EVERY file)

### 1. const Everything
```dart
// ✅ ALWAYS
const SizedBox(height: 16),
const Icon(Icons.home, size: 24),
const Text('Hello', style: TextStyle(fontSize: 14)),
const EdgeInsets.all(16),
const BorderRadius.all(Radius.circular(12)),

// ❌ NEVER (when values are known at compile time)
SizedBox(height: 16),  // Missing const
Icon(Icons.home, size: 24),  // Missing const
```
Mark EVERY widget, EdgeInsets, BorderRadius, TextStyle, Color, and decoration as `const` when values are known at compile-time. This prevents unnecessary rebuilds and is the single biggest performance win.

### 2. ListView.builder for ALL Lists
```dart
// ✅ ALWAYS — only builds visible items
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemCard(item: items[index]),
)

// ❌ NEVER — builds ALL items upfront, kills performance
ListView(
  children: items.map((item) => ItemCard(item: item)).toList(),
)
Column(
  children: items.map((item) => ItemCard(item: item)).toList(),
)
```
Use `ListView.builder`, `GridView.builder`, or `SliverList.builder` for ANY list with more than 5 items.

### 3. RepaintBoundary on Expensive Widgets
```dart
// ✅ Wrap charts, animations, and frequently-updating widgets
RepaintBoundary(
  child: CustomPaint(
    painter: DonutChartPainter(),
    size: const Size(180, 180),
  ),
)

// ✅ Wrap items in long lists
ListView.builder(
  itemBuilder: (context, index) => RepaintBoundary(
    child: NewsArticleCard(article: articles[index]),
  ),
)
```
Use RepaintBoundary on: CustomPaint widgets (charts), animated widgets, list items in scrollable lists, any widget that updates independently of its parent.

### 4. Split Large Widgets into Small Components
```dart
// ✅ Each section is its own widget file
class HomeScreen extends ConsumerWidget {
  Widget build(context, ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: const BalanceCard()),
        SliverToBoxAdapter(child: const SpendingDonutChart()),
        SliverToBoxAdapter(child: const ActivityTrackingSection()),
        SliverToBoxAdapter(child: const SmartTipCard()),
      ],
    );
  }
}

// ❌ NEVER: One massive build() method with everything inline
```
Every screen section should be its own widget in a separate file. Max 150 lines per widget file.

### 5. Riverpod — Watch in build(), Read in callbacks
```dart
// ✅ CORRECT
Widget build(context, ref) {
  final state = ref.watch(homeControllerProvider);  // Reactive
  return ElevatedButton(
    onPressed: () => ref.read(homeControllerProvider.notifier).refresh(),  // One-time
  );
}

// ❌ WRONG
Widget build(context, ref) {
  final state = ref.read(homeControllerProvider);  // Won't rebuild on changes!
}
```

### 6. Dispose EVERYTHING
```dart
// ✅ ALWAYS dispose controllers
class _MyScreenState extends ConsumerState<MyScreen> {
  late final AnimationController _animController;
  late final ScrollController _scrollController;
  late final TextEditingController _textController;

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }
}
```
AnimationControllers, ScrollControllers, TextEditingControllers, StreamSubscriptions, FocusNodes — ALL must be disposed.

### 7. Use FadeTransition, NOT Opacity for Animations
```dart
// ✅ GPU-accelerated, smooth
FadeTransition(
  opacity: _animation,
  child: MyWidget(),
)

// ❌ Expensive, causes full repaint
AnimatedOpacity(opacity: value, child: MyWidget())  // OK for simple cases
Opacity(opacity: value, child: MyWidget())  // NEVER for animations
```

### 8. Image Optimization
```dart
// ✅ ALWAYS use cached_network_image with placeholder
CachedNetworkImage(
  imageUrl: article.imageUrl,
  placeholder: (context, url) => const ShimmerBox(width: double.infinity, height: 200),
  errorWidget: (context, url, error) => const Icon(Icons.error),
  fadeInDuration: const Duration(milliseconds: 200),
)

// ❌ NEVER load images directly
Image.network(url)  // No caching, no placeholder, janky loading
```

### 9. Async Operations Off Main Thread
```dart
// ✅ Heavy computation in isolate
final result = await compute(parseJsonData, rawJsonString);

// ✅ Async data loading with loading state
AsyncValue.when(
  data: (data) => ContentWidget(data: data),
  loading: () => const ShimmerLoading(),
  error: (err, stack) => ErrorWidget(message: err.toString()),
)

// ❌ NEVER block the UI thread
final data = heavyJsonParsing(hugeString);  // Freezes UI
```

### 10. CustomScrollView + Slivers for Complex Screens
```dart
// ✅ All main screens use CustomScrollView
CustomScrollView(
  physics: const BouncingScrollPhysics(),
  slivers: [
    SliverToBoxAdapter(child: const Header()),
    SliverToBoxAdapter(child: const BalanceCard()),
    SliverList.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) => TransactionTile(tx: transactions[index]),
    ),
  ],
)

// ❌ NEVER nest ScrollViews
SingleChildScrollView(
  child: Column(
    children: [
      Header(),
      ListView(shrinkWrap: true, physics: NeverScrollableScrollPhysics()),  // TERRIBLE
    ],
  ),
)
```

### 11. Animation Best Practices
```dart
// ✅ Use Curves.easeOutCubic for all transitions (feels premium)
CurvedAnimation(parent: controller, curve: Curves.easeOutCubic)

// ✅ Duration guidelines
const fast = Duration(milliseconds: 150);    // Micro-interactions
const normal = Duration(milliseconds: 300);  // Page transitions
const slow = Duration(milliseconds: 500);    // Emphasis animations

// ✅ Stagger animations for lists
AnimatedBuilder with delay: index * 50ms per item

// ❌ NEVER use duration > 600ms (feels sluggish)
// ❌ NEVER animate without curves (linear feels robotic)
```

### 12. Minimize Build Method Complexity
```dart
// ✅ Pre-compute outside build()
class MyWidget extends StatelessWidget {
  const MyWidget({super.key, required this.data});
  final Data data;

  @override
  Widget build(BuildContext context) {
    // Build method is ONLY for building UI tree
    return Text(data.formattedValue);
  }
}

// ❌ NEVER compute inside build()
Widget build(context) {
  final sorted = items.sort((a, b) => a.date.compareTo(b.date));  // Runs every rebuild!
  final filtered = sorted.where((i) => i.amount > 100).toList();
  // ...
}
```

### 13. TextScaler.noScaling at App Level
```dart
// In app.dart MaterialApp.router builder:
builder: (context, child) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: child!,
  );
},
```
Prevents system font scaling from breaking AMOLED layouts.

### 14. Shimmer Loading Everywhere
```dart
// ✅ Show shimmer while data loads — NEVER show blank screens
if (state.isLoading) return const HomeShimmer();

// HomeShimmer shows gray animated boxes matching the layout shape
// This makes the app feel instant even on slow connections
```

---

## PERFORMANCE TARGETS

| Metric | Target | How to Verify |
|---|---|---|
| Cold start | <800ms | `flutter run --profile`, measure with stopwatch |
| Screen transition | 60fps | DevTools → Performance tab, no red frames |
| List scroll | 60fps | Scroll fast through Discover feed, no jank |
| Local DB write | <5ms | Logger output from Drift write operations |
| LLM response (cached) | <100ms | LiteLLM Redis cache hit |
| LLM response (uncached) | <3s | Groq/Gemini inference time |
| APK size | <25MB | `flutter build apk --release`, check build output |
| Memory | <150MB | DevTools → Memory tab during normal use |

---

## TESTING CHECKLIST

After building each screen, verify:
- [ ] `flutter analyze` shows zero errors
- [ ] All widgets that CAN be const ARE const
- [ ] All lists use .builder constructor
- [ ] All CustomPaint wrapped in RepaintBoundary
- [ ] All controllers disposed in dispose()
- [ ] All images use CachedNetworkImage
- [ ] Shimmer placeholders shown during loading
- [ ] Scroll performance is smooth (no jank)
- [ ] Animations use Curves.easeOutCubic
- [ ] No nested ScrollViews
