# Flipshope price-tracker handover (for AI Nexus)

**Audience:** whoever implements Flipshope-style tracking on top of the existing Nexus Watch module.  
**Dump analysed:** JADX of Flipshope `com.flipshopeApp` `2.1.445` (`versionCode` 445), folder `C:\Users\Beast\Downloads\Flipshope-+AI+Price`.  
**Nexus home today:** `ai_nexus/lib/data/services/price_watch/` + `presentation/screens/watch/`.

Read this as an implementation spec, not a clone brief. Flipshope’s Dart (`libapp.so`) is **not** in the dump. Everything below is recovered from native Kotlin, Flutter plugins, `AssetManifest.bin`, and the public API the widget actually calls. Where Dart is inferred from assets, it is labelled **inferred**.

---

## 0. One-screen truth

| | Flipshope | Nexus Watch today |
|---|---|---|
| History graph | **Server** has years of prices for a store+SKU | **Local** points from your own scrapes |
| Live price | Their API + in-app WebView of the retailer | HTTP scrape of Amazon / Flipkart / Myntra / Swiggy |
| Add product | Search, share URL, WebView browse, widgets | Paste/share product URL |
| Alerts | Push from their backend + local Awesome Notifications | WorkManager 15 min + local notifications |
| Deals feed | Separate product (`getrecentpricedrop`) | Not built |
| In-app shop | Full WebView of Flipkart/Amazon/… | Opens the store in the browser |
| Extra stores | 13+ on widgets; more in Flutter assets | 4 stores |

You already have the hard part of *live* tracking (scrape, confirm-on-jump, history table, alerts, share-to-watch). Flipshope’s *product* is:

1. A **historical price API** keyed by `(storeId, productId)`.
2. An **in-app WebView shop** with a graph overlay.
3. A **deals widget + FCM** for “what dropped recently” (not the user’s watchlist).
4. UX: how-it-works tour, target-price alert, Pro upsell, more storefronts.

Do **not** copy their widget fake-MRP, ANDROID_ID usage, or `₹null` FCM formatting. Those are bugs / dark patterns, documented in §8 so you do not reproduce them.

---

## 1. Recommended build order (do this, in this order)

Each step is independently shippable. Stop after any step and Watch still works.

### Step A — Keep Nexus Watch as the source of truth

Do not replace `WatchEngine` / `WatchRepository` / Drift tables. Flipshope logic **adds** surfaces and storefronts. It does not replace `decideCheck` / `decideAlerts`.

### Step B — Identity: `(store, productId)` everywhere

Flipshope’s native deal row is `(sid, pid)` composite PK. Nexus already has `WatchStore` + `productId` + unique `canonicalUrl`. When adding stores, **always** extract a stable SKU (Flipkart `pid`, Amazon ASIN, Myntra style id). Never key history on a messy URL.

### Step C — Price-history graph UX (you have data; match their screen)

Nexus already writes `watch_price_history`. Flipshope’s graph screen (from assets) shows:

- Current price
- Lowest / average / highest over the series
- Fullscreen vs minimize
- “Add alert” (target price)
- Empty / expired / store-not-supported / no-internet states

Wire `WatchScreen` detail to those four stats from local history. No Flipshope API required.

### Step D — Share / WebView “track this” overlay

Flipshope: share a product link → `ShareActivity` → Dart `mainShare` → lookup + track.  
Nexus: `ACTION_SEND` already seeds `pendingWatchUrlProvider` → `WatchScreen` → `showAddWatchSheet`.

Gap: they keep you **inside** a WebView while shopping. If you want that: InAppWebView of `canonicalUrl`, overlay graph + “Set alert”, do not leave the app. Scrape still uses `WatchHttpFetcher`, not their API.

### Step E — More store adapters (only if you want their store list)

Widget store ids are in §5. Add one adapter + `canonicalizeWatchUrl` branch per store. Start with Ajio / Nykaa if you expand; skip ShopClues/Paytm Mall unless you have a working scrape.

### Step F — Optional: deals rail (Flipshope widget, not watchlist)

Separate feature. Their endpoint is:

```http
POST https://flipshope.com/api/prices/getrecentpricedrop?version=2.1.445&platform=android_widget
```

Response: `{ "data": [ { "Store": int, "PID": string, "title": string, "imgurl": string, "price": int } ] }`

Calling *their* production API from Nexus is not something this handover authorises. Replicate the **shape** on your own backend, or skip deals.

### Step G — Optional: home-screen widgets

Only after Watch and deals exist locally. Copy **behaviour**, not their fake strikethrough MRP.

---

## 2. What Nexus already implements (do not rebuild)

| File | Job |
|---|---|
| `price_models.dart` | `WatchItem`, `WatchPricePoint`, `WatchAlert`, `ScrapeHit`, alert reasons |
| `store_url.dart` | Canonicalise Amazon / Flipkart / Myntra / Swiggy; reject search/category URLs |
| `watch_http_fetcher.dart` | Isolated Dio, Chrome 141 UA, cookie jar, 3 retries, mobile/desktop UA flip |
| `adapters/*.dart` | Store-specific HTML harvest |
| `page_harvest.dart` / `price_parse.dart` | og:title, JSON-LD, INR parse |
| `watch_policy.dart` | ≥35% jump → pending 10 min confirm; score &lt; 50 → pending; quiet hours |
| `watch_repository.dart` | Drift insert, history, alerts, due-item selection, duplicate-on-canonicalUrl |
| `watch_engine.dart` | addFromUrl, check, checkDue (1.2s gap between items) |
| `watch_scheduler.dart` | WorkManager unique task `app.ainexus.price_watch`, ≥15 min, network required |
| `watch_notifier.dart` | Channel `nexus_price_alerts`, payload `watch:<id>` |
| `watch_prefs.dart` | enabled, interval 15–43200 min, decrease/increase/target, quiet 22–08 |
| `watch_screen.dart` / `add_watch_sheet.dart` | List, graph, add sheet, share seed URL |

**Nexus edge cases already handled (keep them):**

- Duplicate `canonicalUrl` → `WatchDuplicateException`.
- Paused items never due.
- `pendingPrice` due only after `kConfirmDelay` (10 min).
- Failures 1..`kMaxRetries` retry after 5 min; then normal interval.
- Quiet hours skip the tray but history/alerts still persist.
- Confirm disagree &gt; 8% vs parked price → fail, **keep last accepted**, no notify.
- Interval clamped 15..43200.
- Background isolate opens `AppDatabase.background()`, closes in `finally`.
- Share text: first http(s) URL extracted; tracking params stripped per store.

---

## 3. Flipshope product, end-to-end (user steps)

### 3.1 First launch **(inferred from assets + plugins)**

1. Splash (`splash.lottie` / birthday splash variant).
2. Login: Google and/or phone OTP (`sms_autofill`, `phone_number_hint`).
3. Optional country/city (`csc_picker_plus`).
4. Optional “How price tracker works” tour (6 stills + search illustration + success Lottie).
5. Optional notification permission (Awesome Notifications + FCM).
6. Home with bottom nav: Home / Search / Deals / Shop.

Launcher icon can later switch to Festival / Pro / Birthday via `flutter_icon_dynamic` (three `activity-alias` entries, all start `enabled=false`).

### 3.2 Track a product **(inferred + native share/search)**

Four entry points, all converge on `(sid, pid)`:

1. **Search** — in-app search (shortcut “Product Search”, widget search bar → `HomeSearchActivity` / Dart `mainHomeSearch`).
2. **Share** — `ShareActivity` / Dart `mainShare`. `ACTION_SEND * /*`. Invalid URI → clear intent and `finish()` (no crash).
3. **WebView shop** — browse retailer; overlay “track / graph” (`redirect_webview`, `webview_loading` Lottie, wakelock).
4. **Deals / widget** — tap deal → `https://flipshope.com/widget/deal_widget?sid=&pid=` into `MainActivity`.

After identity is known they show graph (low / avg / high), set target alert, optional wishlist.

### 3.3 Shop without leaving the app **(inferred)**

InAppWebView of the retailer. Back button SVGs, empty-webview state, “store not supported” art, expired badge. Checkout likely keeps screen awake (`wakelock_plus`).

### 3.4 Deals (native, fully recovered)

Not the user’s watchlist. A global “recent drops” list:

1. Widget or Flutter calls `addNewDeal` / FCM `type=deal` / REST refresh.
2. Room table `deals`, max 12, newest `ROWID` first.
3. Tap opens Flipshope which then opens the product.

### 3.5 Pro / campaigns **(inferred, skip unless you want them)**

Play Billing, Google Pay art, birthday spin wheel, refer-and-earn, leaderboard. Unrelated to core tracking.

---

## 4. Flipshope native architecture (what the dump actually contains)

```
FlipshopeApplication
  ├─ FlutterLoader
  ├─ WebView.setDataDirectorySuffix(processName)  // API 28+, non-main process
  └─ FacebookSdk.fullyInitialize() on main looper

Cached engines
  ├─ main_engine        / Dart main              / MainActivity
  ├─ share_engine        / Dart mainShare         / ShareActivity
  └─ search_engine      / Dart mainHomeSearch    / HomeSearchActivity

Method channel  com.flipshopeApp/launch_info
  (all three activities)

Room  flipshope_database  (widget only)
  └─ deals(sid, pid, title, subtitle, imgurl)  PK (pid, sid)

Retrofit  https://flipshope.com/
  └─ POST api/prices/getrecentpricedrop

FCM
  ├─ FlutterFirebaseMessagingService     // Dart alerts
  └─ MyFirebaseMessagingService           // type=deal → Room
```

Manifest extras that affect tracker UX:

- `usesCleartextTraffic=true` (HTTP allowed).
- `allowBackup=false`.
- `largeHeap=true`.
- `flutter_deeplinking_enabled=false` — they handle links in native + `app_links`.
- Deep links: `https://flipshope.com`, AppsFlyer `flipshope.onelink.me/v4X7`, `myapp://widget.flipshopeApp.com`.
- Default FCM channel id `recent_deals`.
- Two widgets, 24 h system period (manual refresh is the real update).

**MainActivity crash filter (do not copy blindly):** if the stack contains IME `ViewRootImpl.mWindowAttributes` NPE, or InAppWebView “view not a child of…”, they `Looper.loop()` instead of dying. That hides bugs. Nexus should keep Crashlytics/TLog.

---

## 5. Store identity map (copy this)

Flipshope **integer** `sid` is the store. Native widget list (complete):

| sid | Store | Asset | Notes |
|---:|---|---|---|
| 1 | Flipkart | `flipkart.png` | Also match URL/title `flipkart` or **`flixcart`** (CDN typo) |
| 2 | Amazon | `amazon.png` | Also `media-amazon` in image URL |
| 4 | Snapdeal | `snapdeal.png` | |
| 5 | JioMart | `jiomart.png` | |
| 6 | TataCliq | `tata_cliq.png` | URL/title contains `tata` |
| 7 | Myntra | `myntra.png` | |
| 8 | Nykaa | `nykaa.png` | |
| 9 | Ajio | `ajio.png` | |
| 10 | PepperFry | `pepperfry.png` | |
| 11 | FirstCry | `firstcry.png` | |
| 12 | NykaaFashion | `nykaa_fashion.png` | |
| 13 | Croma | `croma.png` | |
| 16 | Purplle | `purple.png` | filename is `purple`, not purplle |

**Unused in native:** 3, 14, 15.  
**Flutter assets only (no widget sid):** Meesho, Shopsy, ShopClues, Paytm Mall, Reliance Digital, WhatsApp.

Nexus mapping if you add stores: extend `WatchStore` with a stable **string** id (`ajio`, `nykaa`, …) and, if you ever talk to a Flipshope-shaped API, keep a sidecar `int? flipshopeSid`.

Special widget sids (not stores):

| sid | Meaning |
|---:|---|
| 9998 | Dead: “search” click handler exists, no cell is created |
| 9999 | Show All / Show Less toggle on AIO widget |

---

## 6. Data models (Flipshope)

### 6.1 Widget deal (Room + Flutter channel)

```text
DealEntity / ModelDealData
  sid:      Int     // store
  pid:      String  // SKU, required, non-empty
  title:    String
  subtitle: String  // display price, usually "₹" + rupees
  imgurl:   String
PK (pid, sid)
```

SQL actually used:

```sql
SELECT * FROM deals ORDER BY ROWID DESC;
SELECT COUNT(pid) FROM deals;
SELECT pid FROM deals ORDER BY ROWID ASC LIMIT 1;   -- oldest
DELETE FROM deals WHERE pid = ?;
DELETE FROM deals;
INSERT … DealEntity
```

Room is a **singleton**, `allowMainThreadQueries = true` (do not copy that; keep Nexus Drift on background connections).

### 6.2 REST product

```text
ProductData
  Store:  Int
  PID:    String
  title:  String
  imgurl: String
  price:  Int     // rupees, integer — no paise
```

Envelope: `{ "data": ProductData[] }`. kotlinx.serialization with two flags on (lenient / ignore-unknown style). Extra JSON fields will not crash the widget.

### 6.3 FCM data payload (`type=deal`)

| Key | Native field |
|---|---|
| `type` | must equal `deal` or ignore |
| `Store` | sid |
| `PID` | pid |
| `title` | title |
| `price` | subtitle = `"₹" + value` |
| `imgurl` | imgurl |

Empty data map → native service ignores (notification-only goes to Flutter / system tray).

---

## 7. Flipshope logic, function by function

### 7.1 Method channel `com.flipshopeApp/launch_info`

| Method | Returns / does |
|---|---|
| `getAndroidID` | `Settings.Secure.ANDROID_ID` (Kotlin non-null assert) |
| `getLaunchedActivityName` | `"MainActivity"` / `"ShareActivity"` / `"HomeSearchActivity"` |
| `isDealsWidgetRegistered` | any `NewDealsWidget` ids |
| `isAIOWidgetRegistered` | any `AllInOneShoping` ids |
| `canRequestDealsWidgetPin` | `SDK_INT >= 26` only |
| `canRequestAIOWidgetPin` | same |
| `requestDealsWidgetPin` | `requestPinAppWidget(NewDealsWidget)` if API 26+ else false |
| `requestAIOWidgetPin` | same for AIO |
| unknown | `notImplemented()` |

**`addNewDeal` — copy the validation, not the “always success” bug.**

1. If args is not a `Map` → Flutter `error("INVALID_ARGS", "Arguments cannot be null")`.
2. `sid`: `Number` or numeric `String` → int; else **0**.
3. `pid`: must be `String` and `length > 0`. Else log `"Missing required field: pid"` / `"PID cannot be empty"`, **do not insert**, but they still `success(true)`.
4. `title`: else `"Untitled Deal"`.
5. `subtitle`: else `"Price not available"`.
6. `imgurl`: else `""`.
7. Any parse exception → log `"Parse error: …"`, skip insert, still `success(true)`.
8. IO dispatcher: `saveDeal` then Main dispatcher refresh all `NewDealsWidget` ids. If no widgets: log `"No widget instances found to refresh"`. Save errors: `"Error saving deal: "`.

**Nexus equivalent:** `WatchEngine.addFromUrl` already returns a real `WatchItem` or throws. Keep throwing. If you add a widget, refresh widgets only after a successful insert.

### 7.2 `DealRepository.saveDeal` (FIFO 12)

```
count = SELECT COUNT(pid)
if count >= 12:
    oldestPid = SELECT pid ORDER BY ROWID ASC LIMIT 1
    if oldestPid != null:
        DELETE FROM deals WHERE pid = ?
insert DealEntity
```

**Edge case:** delete is `WHERE pid = ?` **without sid**. If the same `pid` exists on two stores, **both rows are deleted**. Copy as: delete the oldest **row** (`ROWID` or `id`), not all rows sharing the sku.

Cap 12 is only for the **widget carousel**, not the user’s watchlist. Nexus must not cap `watch_products` at 12.

Failures → Crashlytics, swallow.

### 7.3 `refreshAllDealsFromApiSync`

1. POST `api/prices/getrecentpricedrop` with query `version=2.1.445`, `platform=android_widget`.
2. Map each `ProductData` → `ModelDealData(store, pid, title, "₹"+price, imgurl)`.
3. `DELETE FROM deals`.
4. Insert list **reversed** so API[0] gets the highest `ROWID` (shown first with `ORDER BY ROWID DESC`).
5. Exception → Crashlytics; old rows already gone if delete succeeded.

**Do not copy the delete-before-insert without a transaction.** Nexus: wrap wipe+insert in one Drift transaction.

Triggered by: widget `onEnabled`, refresh button, `MainActivity.onStart` (all deal widgets).

Interceptor: only those two query params. No auth header on this call.

### 7.4 Recent-deals widget (`NewDealsWidget`)

Prefs per instance: `widget_prefs_<appWidgetId>` → `widget_layout_mode` int, default `0`.

| mode | Adapter URI | Adapter view | Empty view |
|---|---|---|---|
| 0 grid | `widget://grid/<id>/<nowMs>` | `R.id.widget_list` | `R.id.empty_view` |
| 1 list | `widget://list/<id>/<nowMs>` | `R.id.widget_list_vertical` | same |

Timestamp in URI forces `RemoteViewsService` to reload.

- Header tap / item template: launcher component (`getLaunchIntentForPackage` else `MainActivity`), `ACTION_VIEW`. Fill-in: `https://flipshope.com/widget/deal_widget?sid=<sid>&pid=<pid>`.
- Refresh: `ACTION_REFRESH_WIDGET` + `appWidgetIds`. Hide icon, show spinner, API refresh, rebuild, notify adapter.
- Toggle: `ACTION_TOGGLE_LAYOUT`, requestCode `id + 10000`. **In this APK the toggle ImageView is `gone` and 0×0.** Code still flips 0↔1 in prefs.
- `onReceive` uses `goAsync()` + IO coroutine; always `pendingResult.finish()`.
- `MY_PACKAGE_REPLACED`: rebuild all instances.
- `onDeleted`: `prefs.clear()` for those ids.
- `onEnabled`: analytics `realtime_deal_widget_install`; subscribe FCM `widget_deals_topic` and `widget_deals_topic_<versionName>`; API refresh.
- `onDisabled`: only if **zero** instances left → `realtime_deal_widget_uninstall` + unsubscribe both topics.
- `MainActivity.onStart`: refresh both widget types; exceptions swallowed.
- PendingIntent flags: `167772160` = `FLAG_UPDATE_CURRENT | FLAG_MUTABLE` (API 31+).
- System `updatePeriodMillis`: 86400000 (24h).
- Analytics names are snake_case as above.

**Grid cell (`layout_mode == 0`) — do not copy the MRP math:**

```
show subtitle as current price
digits = subtitle.replace("[^0-9]", "")
if digits.parseInt != null:
    fakeMrp = digits + 1000
else:
    fakeMrp = "₹5200"
show Html.fromHtml("<s>₹{fakeMrp}</s>")
```

List mode (`layout_mode == 1`): real title + real subtitle, no strikethrough.

**Logo resolution order:**

1. `sid` switch (1,2,4,5,6,7,8,9,10,11,11,12,13,16).
2. Else lowercase `imgurl` and `title` contains store tokens (`flipkart` / `flixcart`, `amazon` / `media-amazon`, `myntra`, `ajio`, `nykaa`, `jiomart`, `snapdeal`, `tata`, `firstcry`).
3. Else Croma / Nykaa Fashion / Pepperfry / Purplle assets if matched.
4. Else `search.png`.

**Product image:**

- If `imgurl` starts with `http://` or `https://`: Glide GET with  
  `User-Agent: Mozilla/5.0 (Android Widget)`  
  `Accept: image/webp,image/apng,image/*,*/*;q=0.8`
- Else load as local file URI / android_asset.
- Copy bitmap (`config ?: ARGB_8888`, immutable) before `RemoteViews.setImageViewBitmap`.
- Failure: transparent (`android.R.color.transparent`) on deals widget.
- Glide target size 100×150.
- Out-of-range index: empty grid layout, no crash.
- `getViewTypeCount() = 2`.
- `hasStableIds = true` but `getItemId` is the **index**, not pid.

Empty copy: `"No deals found. Tap refresh button."`

### 7.5 All-in-one store widget (`AllInOneShoping`)

Prefs: `com.flipshopeApp.AllInOneShoping` / `show_all_items` boolean, default false. **One pref for all instances** (not per widget id).

`onDataSetChanged` (the list the user sees):

```
stores = hardcoded 13 (order in §5)
if show_all_items: use all
else: take first 5   // Flipkart, Amazon, Myntra, Ajio, Snapdeal
if stores.size > 5 OR show_all_items:
    append WidgetItem(9999, "Show All"|"Show Less", arrow_down|arrow_up)
```

`onCreate` builds **all** stores and never adds 9999. The system then calls `onDataSetChanged`, which clears and rebuilds. Dead path; ignore.

Clicks (`WIDGET_ITEM_CLICK`, fill-in `widget-item://item/<sid>?widgetId=<id>`):

- last path `9998` → `storewidget_searchstore` + `HomeSearchActivity` `NEW_TASK`. **No 9998 cell exists.**
- `9999` → flip `show_all_items`, notify, `onUpdate`. If `widgetId` missing/0 → **no-op**.
- else → `storewidget_clickstore` + MainActivity `VIEW`  
  `https://flipshope.com/widget/aio_widget?sid=<sid>`  
  flags `872415232` = `NEW_TASK | CLEAR_TOP | SINGLE_TOP`. `startActivity` exceptions swallowed.

Search **bar** is a separate PendingIntent to `HomeSearchActivity` (does not use 9998).

Image: Glide, size `48 * density`. Fail → `ic_default_icon` **except** sid 9999 has no catch (local asset).  
`getItemId` = sid (or index if null).  
`hasStableIds = true`.  
API 31+ mutable pending intents; older `FLAG_UPDATE_CURRENT` only.

Analytics: `storewidget_install` / `storewidget_uninstall` / `storewidget_searchstore` / `storewidget_clickstore`.

### 7.6 FCM native `MyFirebaseMessagingService`

```
super.onMessageReceived
data = remoteMessage.data
if data.isEmpty: return
if data["type"] != "deal": return
sid    = parseInt(Store) else 0
pid    = PID as String else skip
title  = title as String else skip-if-null path same as addNewDeal
subtitle = "₹" + data["price"]     // null → literal "₹null"
imgurl = imgurl as String else ""
saveDeal + refresh widgets
```

Empty notification-only messages are left to Flutter FCM / tray (`recent_deals`).

**Copy:** data-only “broadcast deal” vs per-user watch alert as two channels.  
**Do not copy:** `"₹" + nullable` without checking.

Nexus already notifies per `WatchItem`. A Flipshope-style *global* deals topic would be a new FCM topic, not `nexus_price_alerts`.

### 7.7 Flutter → widget after Dart tracks something

`addNewDeal` is how Dart pushes a row into the **deals widget**, not into a personal watchlist. Personal watchlist lives in Dart/sqflite (not in this dump).

Nexus: if you add a deals widget, push from `WatchEngine` only if you *want* the user’s own drops on the home screen. Otherwise keep widget = global deals, Watch = personal list.

---

## 8. Every small edge case (checklist)

Use this as a QA list when you implement. **Skip / fix** items are marked.

| # | Where | Behaviour | Nexus action |
|---|---|---|---|
| 1 | Grid MRP | Current + 1000 as strikethrough; no digits → ₹5200 | **Do not copy** |
| 2 | `addNewDeal` success | Returns true even when pid missing | Return error to Dart |
| 3 | sid parse | Non-numeric → 0 | Reject unknown store |
| 4 | FIFO delete | `DELETE WHERE pid=?` can wipe two stores | Delete by row id |
| 5 | API refresh | Delete all then insert; not transactional | Use a transaction |
| 6 | Reverse insert | API list reversed so index 0 is newest ROWID | Keep if you mimic widget |
| 7 | Price int | Widget API has no paise | Nexus uses `double` — keep paise |
| 8 | FCM `₹null` | Null price concatenated | Guard null |
| 9 | `flixcart` | Logo heuristic | Harmless if you match CDNs |
| 10 | Layout toggle | Compiled, hidden 0×0 | Omit or show a real toggle |
| 11 | AIO 9998 | Handler, no cell | Don’t implement |
| 12 | AIO prefs | `show_all_items` global, not per widget | Per-instance if you add widgets |
| 13 | AIO `widgetId=0` | Toggle no-op | Always pass widget id |
| 14 | Glide UA | `Mozilla/5.0 (Android Widget)` | Use Nexus Chrome 141 UA (already done for scrape) |
| 15 | Bitmap copy | Immutable copy into RemoteViews | Copy if you widget-ize images |
| 16 | Cleartext | HTTP allowed app-wide | Keep Nexus HTTPS-only |
| 17 | ANDROID_ID | Sent to Dart | Don’t use as account key |
| 18 | IME crash swallow | Looper.loop | Don’t copy |
| 19 | WebView process suffix | API 28+ multiprocess | Copy if you add WebView in a :plugin process |
| 20 | Share garbage URI | finish() | Keep Nexus share robust |
| 21 | Share media filters | App handles rtmp/mkv/… | Don’t add; Nexus already has SEND text/image |
| 22 | Two FCM services | Native deals + Flutter | One notifier + optional deals topic |
| 23 | Pin API | false below Oreo, no launcher check | Same, but show a snackbar |
| 24 | Room main thread | `allowMainThreadQueries` | Never |
| 25 | Widget onStart refresh | Exceptions eaten | Log with TLog |
| 26 | Composite PK | Same pid two sids = two rows | Nexus unique `canonicalUrl` already |
| 27 | Untitled / Price not available | Defaults | OK for deals rail; not for Watch items |
| 28 | Json lenient | Extra fields ignored | Keep for any new DTO |
| 29 | version query | Hardcoded `2.1.445` | Use `package_info` |
| 30 | Birthday / Pro icons | Alias enable/disable | Skip |
| 31 | NotificationListenerService | Awesome Notifications | Don’t add a listener service for Watch |
| 32 | 24h widget period | OS may batch | WorkManager 15 min already covers Watch |
| 33 | HomeSearch transparent | `background_mode=transparent` | Overlay sheet is enough |
| 34 | Deeplink Flutter off | `flutter_deeplinking_enabled=false` | Nexus already handles SEND in `MainActivity.kt` |
| 35 | Out of stock | Asset `expired.svg` | Nexus already has `availability` / `outOfStock` |
| 36 | Store not supported | Asset `storeNotSupported.png` | Map to `canonicalizeWatchUrl == null` copy you already show |
| 37 | How-it-works 6 steps | First-run tour | Optional onboarding on Watch |
| 38 | Graph stats | lowest / average / highest assets | Compute from `watch_price_history` |
| 39 | Confirm-on-jump | **Nexus only** (35%) | Flipshope dump has no equivalent; **keep Nexus** |
| 40 | WorkManager floor | **Nexus only** 15 min | Keep |

---

## 9. User journeys to implement in Nexus (concrete)

### Journey 1 — Add from URL (already shipped)

1. User pastes or shares a product URL.
2. `extractHttpUrl` → `canonicalizeWatchUrl`.
3. Reject search/category/restaurant-menu.
4. `WatchHttpFetcher.scrape` (3 attempts, UA flip).
5. `preferResolvedCanonical` after redirects (`amzn.to`, `fkrt.it`).
6. Preview in `add_watch_sheet`; optional target price.
7. `WatchRepository.insert` (unique canonicalUrl).
8. First history point written.

**Flipshope add-on:** after insert, optional snackbar “Open in app shop” → InAppWebView of `canonicalUrl`.

### Journey 2 — Periodic check (already shipped)

1. WorkManager `priceWatchCheck` every ≥15 min, network required.
2. Skip if `watch_enabled` false.
3. Due = pending confirm (10 min) OR retry (5 min, ≤2) OR interval elapsed.
4. Pause / `checkIntervalMinutes<=0` excluded (except pending).
5. 1.2 s delay between items.
6. `decideCheck` → pending / fail / accept.
7. `decideAlerts` vs item + global prefs.
8. Quiet hours: persist alert, skip tray.

**Flipshope add-on:** none required. Their dump does not show client-side polling of watchlist; that is on their server.

### Journey 3 — Graph overlay (build this)

From `watch_price_history` for `productId`:

```
points = ORDER BY checkedAt ASC
lowest  = min(price)
highest = max(price)
average = mean(price)
current = WatchItem.currentPrice
```

UI states:

- 0 points → empty graph + “Checking…”
- 1 point → flat line (they still show a graph icon)
- Store unsupported → don’t reach here (`canonicalizeWatchUrl` failed earlier)
- `consecutiveFailures` high → last error string under the graph
- `outOfStock` → expired treatment

Alert CTA: set/clear `targetPrice` (already on `WatchItem`).

### Journey 4 — In-app shop **(new, optional)**

1. Open `canonicalUrl` in InAppWebView (Android plugin you already can add).
2. Inject nothing illegal; do not scrape via JS in the retailer page if it violates ToS — Nexus already scrapes via HTTP in `WatchHttpFetcher`.
3. Overlay: current price, sparkline, “Set alert”.
4. Back button; if WebView dies with “not a child of…”, catch and pop (Flipshope globally swallows this).
5. Process suffix if you spawn a WebView in a non-default process.

### Journey 5 — More stores

For each new store:

1. Host regex + product-id extractor in `store_url.dart` (reject listing pages).
2. Adapter `scrapeX(PageHarvest)` returning `ScrapeHit` with score.
3. Register in `WatchHttpFetcher`.
4. Tests in `test/data/services/price_watch/`.
5. Optional: store logo asset.

Do **Ajio / Nykaa** before Snapdeal / ShopClues.

### Journey 6 — Deals rail **(new, optional, your backend)**

Do not call Flipshope’s API from Nexus.

Your DTO can match theirs:

```json
{ "data": [ { "store": "amazon", "productId": "B0…", "title": "…", "imageUrl": "…", "price": 12999 } ] }
```

Client rules if you also want a widget:

- Cap N (they used 12).
- Newest first.
- Tap → `WatchEngine.addFromUrl` **or** open Watch detail if already watched (`WatchDuplicateException` → open existing).
- FCM `type=deal` optional.

### Journey 7 — Home widgets **(last)**

Two widgets, like them:

1. **Watch / drops:** last N accepted price drops from `watch_alerts` (honest prices, no +1000).
2. **Stores:** first 5 + Show All; tap opens add-watch with that store’s search or a WebView homepage.

Pin from Flutter: `AppWidgetManager.requestPinAppWidget` on API 26+.

---

## 10. Suggested Nexus file map (when you code)

| Flipshope idea | Put it here |
|---|---|
| Store enum + sid | `store_url.dart` `WatchStore` |
| Canonical URL | already `canonicalizeWatchUrl` |
| Live scrape | `adapters/` + `watch_http_fetcher.dart` |
| History stats | new helper next to `watch_repository.dart` |
| Graph UI | `watch_screen.dart` (already has `fl_chart`) |
| Target alert | already `targetPrice` + `notifyOnTarget` |
| How-it-works | optional first-run in `watch_screen.dart` |
| In-app shop | new `watch_webview_page.dart` |
| Deals DTO | new `deals_models.dart` (do not mix into `WatchItem`) |
| Deals widget | `android/.../DealsWidget.kt` + Room/Drift table **separate** from `watch_products` |
| Method channel | only if a widget needs Dart → native; Nexus can keep widgets 100% Kotlin |

---

## 11. What this dump cannot tell you (do not invent)

These live only in missing `libapp.so`:

- REST paths for **personal** watchlist, graph history, login, wishlist.
- How they scrape inside the WebView (JS selectors), if they do.
- Affiliate / redirect rewrite rules.
- Alert threshold math on the server.
- Pro SKU ids and entitlement.
- Birthday spin odds.
- Exact Home / Deals / Shop widgets and navigation graph.

If you need those, extract `libapp.so` from the XAPK arm64 split and run a Dart-string dump. Until then, implement from this document + Nexus Watch.

---

## 12. Definition of done (for “Flipshope-like tracker” on Nexus)

You are done when:

1. User can share/paste a product URL and see **current + history graph** (low / avg / high).
2. Target-price and drop alerts still respect quiet hours and 35% confirm.
3. Unsupported URL shows the existing add-sheet error (Flipshope “store not supported”).
4. Out-of-stock is visible on the card.
5. Optional: InAppWebView shop with overlay, without crashing on detach.
6. Optional: extra stores with tests.
7. Optional: deals rail/widget using **your** API, honest prices, transactional refresh, per-row FIFO delete.
8. None of: fake MRP, ANDROID_ID as user id, main-thread Room, swallowed IME crashes, calling Flipshope’s `getrecentpricedrop` from the Nexus app.

---

*Source of Flipshope facts: JADX `com.flipshopeApp` (MainActivity, MethodChannelHandler, DealRepository, NewDealsWidget, NewDealFactory, AllInOneShoping, MyWidgetFactory, MyFirebaseMessagingService, RetrofitClient, ApiService, AndroidManifest, AssetManifest.bin). Nexus facts: `lib/data/services/price_watch/*` as of this handover.*
