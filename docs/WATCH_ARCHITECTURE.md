# Watch architecture handover

**Purpose:** Modular, robust price-watcher for AI Nexus. Local-first history from the moment you add a product. Interactive fluid graph. Designed so a later cloud database can sync the **same watches and history across devices** without rewriting the engine.

**Not in scope:** Flipshope-style “years of prices before you tracked it.” History starts at add-time. Cloud is the same series, replicated — not a third-party history vendor.

**Status today:** Watch already scrapes, confirms jumps, alerts, and stores points in Drift. The detail sheet graph is a static `fl_chart` line (no touch, no range, no stats). This document is the target architecture.

---

## 1. Goals

| Goal | Meaning |
|---|---|
| Watcher | User adds a product URL. App checks it on a cadence, records price, notifies on drop / target. |
| Monitoring | Background WorkManager + manual “Check now.” Pause / resume. Failures retry, then back off. |
| Graph | Interactive, modern, 60fps. Scrub, range chips, min/avg/max. Uses **only local points**. |
| Local-first | SQLite (Drift) is the source of truth. UI never waits on the network to show watches or the graph. |
| Cloud-ready | Same domain model can sync to Postgres later. Identity and merge rules are decided **now**, even if the remote is a no-op. |
| Modular | Scrape, policy, persistence, sync, and UI do not import each other except through ports. |

---

## 2. Non-goals

- Do not fetch historical prices from Flipshope or any store “price history” page.
- Do not fake an MRP (`price + 1000`). Graph is honest.
- Do not put scrape HTML or Dio inside widgets.
- Do not make the graph widget talk to Drift or Dio.
- Do not block add-product on cloud. Local insert always wins; sync is eventual.

---

## 3. How it works (user)

1. Paste or share a product URL (Amazon, Flipkart, Myntra, Swiggy today).
2. App canonicalises the URL → stable `(store, productId)`.
3. One live scrape → first `WatchItem` + **first history point** (t = now).
4. WorkManager (and “Check now”) scrape again. Each **accepted** price appends a history point.
5. Graph shows that series only. One point = empty-state spark with a single dot, not a fake line.
6. Later (cloud): phones share the same watches. History is the union of points from every device.

Pending / failed checks **do not** write history. Only `acceptPrice` and the initial insert do. That keeps the graph clean.

---

## 4. Architecture (layers)

Keep Watch as a **vertical slice** under `lib/data/services/price_watch/` and `lib/presentation/screens/watch/`, but split it into ports so cloud and graph stay replaceable.

```
┌─────────────────────────────────────────────────────────────┐
│  UI  watch_screen / add_sheet / PriceHistoryChart            │
│      (Riverpod streams only. No Dio. No Drift.)             │
└───────────────────────────┬─────────────────────────────────┘
                            │ WatchFacade (use-cases)
┌───────────────────────────▼─────────────────────────────────┐
│  Domain                                                     │
│    WatchItem, WatchPricePoint, WatchAlert, ScrapeHit        │
│    HistorySeries (downsample + stats)                       │
│    watch_policy  (confirm / alerts / quiet hours)           │
│    store_url     (canonical identity)                       │
└─────────┬─────────────────────────────┬─────────────────────┘
          │                             │
┌─────────▼─────────┐         ┌─────────▼─────────┐
│  WatchEngine      │         │  WatchSyncPort    │
│  scrape → policy  │         │  Local: no-op     │
│  → persist        │         │  Cloud: later     │
└─────────┬─────────┘         └─────────┬─────────┘
          │                             │
┌─────────▼─────────┐         ┌─────────▼─────────┐
│  WatchStore port  │         │  WatchRemote port │
│  Drift today      │         │  HTTP later       │
└───────────────────┘         └───────────────────┘
          │
┌─────────▼─────────┐
│  WatchHttpFetcher │  adapters/amazon_in, flipkart, myntra, swiggy
│  isolated Dio     │
└───────────────────┘
```

**Rule:** UI → Facade → Engine / Repository. Adapters never import Flutter. Chart never imports the repository.

### 4.1 What already exists (keep)

| Piece | File | Keep as |
|---|---|---|
| Policy | `watch_policy.dart` | Domain. Do not move into UI. |
| Canonical URL | `store_url.dart` | Domain identity. Also the **sync merge key**. |
| Engine | `watch_engine.dart` | Use-case: `addFromUrl`, `check`, `checkDue`. |
| Fetcher + adapters | `watch_http_fetcher.dart`, `adapters/` | Infrastructure. |
| Drift rows | `WatchProducts`, `WatchPriceHistory`, `WatchAlerts` | Local store. |
| Scheduler | `watch_scheduler.dart` | Calls engine only. |
| Notifier | `watch_notifier.dart` | Presentation/infra. Quiet hours stay in policy. |

### 4.2 What to add (modules)

| Module | Responsibility |
|---|---|
| `history_series.dart` | Pure: points → range slice, downsample, min/avg/max/first/last. Unit-testable. |
| `price_history_chart.dart` | Interactive graph widget. Input = `HistorySeries`. |
| `watch_store.dart` | Interface over Drift (`WatchRepository` implements it). |
| `watch_sync_port.dart` | `enqueue`, `pull`, `push`. Default `NoopWatchSync`. |
| `watch_facade.dart` | Thin Riverpod-facing API so screens don’t grow more engine calls. |

Do **not** create a second database. One Drift file. Cloud is a **replica**, not a second local SQLite.

---

## 5. Identity (this is what makes cloud work later)

### 5.1 Two ids

| Id | Role |
|---|---|
| `id` (UUID) | Local row pk. Device-generated. Never shown to the user. |
| `identityKey` | `store + ":" + productId` (fallback: canonicalUrl). **Same product on two phones = same key.** |

Examples:

- `amazon:B0F3K2ABCD`
- `flipkart:PSHGZYH2JEGYFVZ6`
- `myntra:12345678`

If `productId` is missing (short link not yet resolved), keep a temporary key from `canonicalUrl`. After the first scrape, `preferResolvedCanonical` upgrades it. Sync must treat identity-key change as a merge, not a new product.

### 5.2 Merge rules (write them now, even for local-only)

When cloud exists, two devices add the same ASIN:

1. **Product row:** last-write-wins on `updatedAt` for name, image, target, pause, notify flags. `basePrice` = **min** of both (first-seen price should stay the cheaper/earlier baseline — actually: keep the **earliest `createdAt`** basePrice; do not overwrite with a later device’s first scrape).
2. **History:** append-only union. Dedup by `pointId` (UUID). If two points share the same timestamp±60s and same price, keep one.
3. **Delete:** tombstone `{ identityKey, deletedAt }`. Pull tombstones like expenses already do.
4. **Alerts:** local-only is fine; optional sync. Prefer regenerate from history rather than fighting alert-read flags across devices.

Local-only today: still **generate `identityKey` and `updatedAt` / `deletedAt` columns** so the first cloud migration is additive, not a rewrite.

### 5.3 Suggested Drift columns (next schema bump)

On `watch_products` (schema 12+):

- `identityKey` text, unique
- `updatedAt` text (ISO UTC)
- `rev` integer default 0 (bump on every local mutation)
- `syncStatus` text: `local` \| `pending` \| `synced` (optional; outbox is enough)

On `watch_price_history`:

- Keep `id` as point UUID (sync primary key)
- Index `(productId, checkedAt)`
- Optional `deviceId` later (debug / “recorded on phone”)

On new `watch_tombstones`:

- `identityKey`, `deletedAt`

History stays **append-only**. Never update a point’s price. If a scrape was wrong, leave it; policy already parks wild jumps before accept.

---

## 6. History model (graph input)

A point is:

```text
WatchPricePoint
  id          UUID
  productId   WatchItem.id   // local fk
  price       double
  checkedAt   DateTime UTC
  source      string         // amazon.buybox, flipkart.jsonld, …
```

**Write path (already true):**

- `insert` → first point
- `acceptPrice` → another point
- `parkPending` / `markFailure` → **no** point

**Read path (new):** never dump raw rows into `LineChart`.

```text
HistoryQuery { productId, range: 1W | 1M | 3M | ALL }
        ↓
HistorySeries {
  points        // chronological, downsampled for draw
  rawCount
  min, max, avg, first, last
  firstAt, lastAt
  hasEnoughForLine  // rawCount >= 2
}
```

### 6.1 Downsample (draw only)

- Persist every accepted check (15–60 min cadence → ~700–3000 points/year). Cheap.
- For the chart, cap **~180–240 draw points** (LTTB or even-nth). Stats (`min/avg/max`) always use **raw** points in range, not the downsampled polyline.
- Range `ALL` = since `createdAt`. There is no “1D” until you have ≥2 points inside 24h — hide chips that have &lt;2 points.

### 6.2 Time axis

X = `checkedAt.millisecondsSinceEpoch`, not index `0..n`. Uneven checks (manual vs 15 min) must not look equally spaced.

---

## 7. Interactive graph (UI contract)

Extract `PriceHistoryChart` as a **presentation widget**. Mirror the touch pattern already used in expense trends (`LineTouchData`), but dedicated to prices.

### 7.1 Look

- Accent line, 2–2.5px, slight curve (`isCurved`, `preventCurveOverShooting: true`).
- Soft gradient fill under the line (accent → transparent). No rainbow, no fake 3D.
- Hidden default axes; a light hairline + pill tooltip on touch.
- Min / avg / max as three compact stats **above** the chart (not inside fl_chart titles).
- Optional dashed horizontal at `targetPrice` if set.
- Optional dashed horizontal at `basePrice` (price when added).
- 1-point state: large current-price number + “History starts when we check again.” Single dot, no invented second point.
- 0-point (shouldn’t happen after insert): shimmer, then retry.

### 7.2 Interaction

- Drag finger: snap to nearest **raw** point (not downsampled), show `formatInr(price)` + relative time (“12h ago”, “3 Apr”).
- Light haptic on snap change.
- Range chips: `1W` `1M` `3M` `All`. Animated swap (`duration: 280ms`, `curve: easeOutCubic`).
- Pinch-zoom **not required** in v1 (fl_chart pinch is fiddly). Scrub + range is enough and feels more “product.”
- New point arriving: animate last segment (fl_chart `duration` / tween the last FlSpot).

### 7.3 What the widget accepts

```dart
class PriceHistoryChart extends StatelessWidget {
  const PriceHistoryChart({
    required this.series,          // HistorySeries
    this.targetPrice,
    this.basePrice,
    this.accent,
    this.onSelectPoint,            // WatchPricePoint?
  });
}
```

No `WatchRepository` import. Parent loads history via a `StreamProvider.family`.

### 7.4 Performance

- Rebuild chart only when series identity changes (productId + range + lastPointId).
- `RepaintBoundary` around the chart.
- Do not `history(limit: 90)` forever — load by range (ALL can page; 3M is plenty for most users at 15 min cadence).

---

## 8. Watcher / monitor loop (keep, don’t fork)

```
WorkManager 15m ──┐
Check now ────────┼──► WatchEngine.checkDue / check
Add URL ──────────┘         │
                            ▼
                     WatchHttpFetcher.scrape
                            │
                     decideCheck (policy)
                       ├ pending → park, no history
                       ├ fail    → consecutiveFailures, no history
                       └ accept  → currentPrice + history point
                            │
                     decideAlerts → WatchAlerts + tray
                            │
                     WatchSyncPort.enqueue (no-op today)
```

Cadence constants stay in `watch_policy.dart`:

- Pending jump ≥ 35%
- Confirm after 10 min
- Retry 5 min, max 2
- Interval 15–43200 min
- Quiet hours skip tray, still persist alert and history

Background isolate: `AppDatabase.background()` then `close()` in `finally` — already correct.

---

## 9. Cloud later (do not implement now — design so you can)

Nexus is already offline-first (`SyncQueue`, expense tombstones). Watch should reuse that pattern, not invent a second sync stack.

### 9.1 Local outbox

On every local mutation:

```text
enqueueSync(entityType: 'watch_product', entityId: identityKey, action: upsert, payload: json)
enqueueSync(entityType: 'watch_point',   entityId: pointId,     action: insert, payload: json)
enqueueSync(entityType: 'watch_product', entityId: identityKey, action: delete, payload: {deletedAt})
```

`NoopWatchSync` drains nothing. `HttpWatchSync` later POSTs the queue.

History points are **insert-only** in the outbox. Do not collapse them the way `enqueueSync` collapses `(entityType, entityId, action)` for products — **each point id is unique**, so they won’t collapse. Good.

Product upsert **should** collapse: pause/resume/target edits while offline = one latest payload. Existing `enqueueSync` already does that.

### 9.2 Remote shape (Postgres, when you add it)

```text
watch_products  (user_id, identity_key PK, local_id, store, product_id,
                 canonical_url, name, image, prices, flags, rev, updated_at)
watch_points    (id PK, user_id, identity_key, price, checked_at, source)
watch_tombstones (user_id, identity_key, deleted_at)
```

API sketch (mirror expenses):

```text
PUT  /api/v1/watch/products          // upsert batch
POST /api/v1/watch/points            // append batch
GET  /api/v1/watch/since?cursor=     // products + points + tombstones
```

Pull applies tombstones, upserts products by `identityKey`, inserts missing points by `id`.

### 9.3 Conflict

- Two devices check the same SKU 2 minutes apart → two history points. **Both stay.** Graph is more accurate, not a conflict.
- Two devices set different target prices → LWW `updatedAt` / `rev`.
- Device A deletes, device B updates → tombstone wins if `deletedAt >= updatedAt`.

### 9.4 What cloud does **not** do

- Cloud does **not** scrape. Each device scrapes for itself (or a future server worker). Until a worker exists, history = union of device checks. A phone that is off does not create holes on the other phone; the other phone’s checks fill the graph.
- Cloud does **not** invent pre-add history.

---

## 10. Target folder layout

```text
lib/data/services/price_watch/
  price_models.dart
  watch_policy.dart
  store_url.dart
  history_series.dart          # NEW pure
  watch_store.dart             # NEW interface (WatchRepository implements)
  watch_sync_port.dart         # NEW NoopWatchSync
  watch_engine.dart
  watch_repository.dart        # Drift impl
  watch_http_fetcher.dart
  watch_scheduler.dart
  watch_notifier.dart
  watch_prefs.dart
  page_harvest.dart
  price_parse.dart
  adapters/

lib/presentation/screens/watch/
  watch_screen.dart            # list + navigation only
  add_watch_sheet.dart
  watch_providers.dart
  widgets/
    price_history_chart.dart   # NEW
    watch_card.dart            # move out of screen file
    watch_detail_sheet.dart    # move out; owns range chips + chart
```

Tests:

```text
test/data/services/price_watch/
  history_series_test.dart     # NEW
  watch_engine_deep_test.dart  # exists
  store_url_test.dart          # exists
  adapters/ …
```

---

## 11. Build order

### Phase 0 — Hygiene (short)

- Add `identityKey` + `updatedAt` on insert (migration).
- Unique on `identityKey` (and keep unique `canonicalUrl`).
- `history()` query by time range, not only `limit: 90`.
- `StreamProvider.family` for history so the detail sheet is not a one-shot `FutureBuilder`.

### Phase 1 — Graph module (user-visible)

- `HistorySeries` + tests.
- `PriceHistoryChart` with scrub, gradient, stats, range chips, 0/1-point empty states.
- Detail sheet uses it. List cards may show a tiny non-interactive sparkline of last N points (optional).

### Phase 2 — Facade / ports

- `WatchStore` interface.
- `NoopWatchSync` hooked after insert / accept / delete (no network).
- Screens talk to facade/providers only.

### Phase 3 — Cloud (later)

- Postgres tables + `GET since` / batch upsert.
- `HttpWatchSync` using existing `enqueueSync`.
- Tombstones.
- Merge by `identityKey`.

Do not start Phase 3 until Phase 1 is in daily use. Local graph quality matters more than multi-device.

---

## 12. Edge cases (watcher + graph + future sync)

| Case | Behaviour |
|---|---|
| First add | One point. Chart shows current price + “Next check adds the line.” |
| Two points | Line appears. 1W chip enabled if both fall in 7 days. |
| Pending 35% jump | No new graph point until confirm agrees. |
| Confirm disagree | Keep last accepted; graph unchanged. |
| Failure | No point; card can show last error; graph stale but valid. |
| Pause | No checks, no points; graph frozen. |
| Duplicate URL | `WatchDuplicateException` — open existing detail, don’t second row. |
| Same SKU different URL | Canonicalise to same `identityKey`; treat as duplicate. |
| Short link | Identity upgrades after redirect; rewrite `identityKey` once. |
| Delete | Local cascade history+alerts; enqueue tombstone (no-op sync today). |
| Clock skew | Store UTC; display local. X-axis from timestamps. |
| Duplicate point ids after sync | Insert ignore. |
| Two devices, same SKU | One product; union of points. |
| Downsample vs min | Stats from raw; line from downsampled. Don’t let LTTB hide the true low. |
| Target line off-chart | If target &lt; min or &gt; max, expand Y padding 8%. |
| Paise | `double` + `formatInr`. Never integer rupees. |
| Empty scrape | Engine fail path; don’t write 0. |
| Background isolate | Own DB connection; don’t share UI Drift. |
| Quiet hours | History still writes; tray skipped. |
| Range with 1 point | Disable that chip or fall back to ALL. |

---

## 13. Definition of done (Phase 1)

- Adding a product immediately shows a detail graph state (1 point).
- After two accepted checks, the line is interactive (scrub + tooltip).
- Min / avg / max match raw points in the selected range.
- Pending/fail never add a vertex.
- Chart widget has no repository/Dio imports.
- `history_series_test.dart` covers downsample, range slice, stats, 0/1-point.
- Existing engine tests still pass.
- No Flipshope API. No fake MRP.

---

## 14. Mapping to current files (do not throw away)

Nexus Watch is already the monitor. This architecture **wraps** it:

- `WatchEngine` stays the only scraper orchestrator.
- `WatchRepository` becomes the Drift adapter behind `WatchStore`.
- `watch_screen.dart` `_WatchDetailSheet` LineChart (lines ~502–525) is replaced by `PriceHistoryChart`.
- Expense `LineTouchData` / Cloud `live_sparkline.dart` are **visual references**, not dependencies. Watch chart lives in the Watch feature folder so it can use price-specific tooltips and target/base lines.

Cloud Hub already has a durable outbox. When you turn Watch sync on, `entityType` values `watch_product` / `watch_point` join that queue. Do not sync Watch through Drive or the files API.

---

*Local-first, identity-keyed, append-only history, graph as a pure widget, sync as a replaceable port. That is the architecture. Implement Phase 1 graph next; leave HTTP sync as `NoopWatchSync` until you want multi-device.*
