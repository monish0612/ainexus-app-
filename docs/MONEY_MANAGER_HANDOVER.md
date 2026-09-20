# Money Manager → AI Nexus expense handover

**Audience:** whoever adds missing Money Manager *ideas* (stats, charts, tracking, budgets, edge-case math) on top of the existing Nexus Expense Tracker.  
**Dump analysed:** JADX of Realbyte **Money Manager Free** `com.realbyteapps.moneymanagerfree` **4.12.12 GF** (`versionCode` 1203), folder `C:\Users\Beast\Downloads\Money Manager`.  
**Nexus home today:** `ai_nexus/lib/presentation/screens/expense/` + `lib/data/repositories/expense_repository.dart` + `lib/core/services/expense_pace_metrics.dart` + `lib/core/services/expense_insight_engine.dart`.  
**Related prior work:** voice STT gateway already lives in `stt-gateway/` and is wired through `HoldToSpeakController` / `SttGatewayService` (see the exported analysis in `C:\Users\Beast\Downloads\cursor_codebase_analysis_and_voice_logi.md`). Do **not** rebuild voice. Steal MM’s *orderless field list* for the expense parser vocabulary only.

Read this as an **implementation spec**, not a clone brief. Java under `sources/defpackage` is R8 junk. The real app is `sources/com/realbyte/money/`. Chart HTML is live Highcharts under `resources/assets/chart/`. Strings are in `resources/res/values/strings.xml`.

Where a field name is recovered from SQL/strings, it is labelled **recovered**. Where UI copy implies behaviour but the method body is obfuscated, it is labelled **inferred**. Do not treat inferred as a unit-test oracle. Schema/formulas were cross-checked against `DBHelper`, `DBQuery.d`, `BudgetService.c`, `BudgetUtil`, `TxRepository.f`, and `AssetRepository`; if those disagree with strings, **prefer the Java**.

---

## 0. One-screen truth

| Surface | Money Manager | Nexus Expense today |
|---|---|---|
| Product type | Double-entry **household ledger** (accounts with balances) | **Spend diary** (amount + category + bank label + card type) |
| Transaction kinds | Income, Expense, Transfer-In, Transfer-Out, Income/Expense Balance, fees, installments | Expense only. Investment / Loan are *excluded* from spend, not first-class types |
| Accounts | Real assets/liabilities with groups, currency, SMS join-string, include-in-totals, hidden, deleted-restore | `bank` is a string (`HDFC`/`ICICI`/`AXIS`/`SCAPIA`/`CASH`) with **no balance** |
| Credit cards | Settlement date, payment date, payable vs outstanding, lump-sum vs at-time, usage hurdle, Pay button, prepayment tag | `cardType` `CC`/`DB`/`Cash`. Settings `Bank` already has `statementDay`/`dueDay` (HDFC 18/9, AXIS 24/13, SCAPIA 26/15). `credit_card_forecast_engine.dart` posts salary on day **28**. CC Food still hits **this** month’s budget |
| Budget | Per-category (and subcategory) **tree**, default + per-month override, remaining/used/excess, budget-vs-actual overlay chart | **One** latest `BudgetEntries` amount (not month-keyed). Past months get a budget via “last `setAt` not after that month’s end” |
| Periods | Fiscal month start day + weekend shift; Daily / Calendar / Weekly / Monthly / Annually / Total / custom Period | **Three overlapping chip sets** (Tracker Today/7D/1M/6M/All, Insights Week/Month/3M/6M/All/NT, Trend Week/Month/3M/6M/AllTime) |
| Stats | Dedicated Stats tab: Income\|Expense toggle, pie + ranked list, tap → category history line + txn list | Insights kitchen-sink + Tracker pie + Trend modal + timeframe bars |
| MoM | `Compared Expenses` index (100 = same as last fiscal month) on Trans **Total** page | `momDelta` / `momPct` in `ExpenseInsightEngine` + `RangeFact.vsPrevious` |
| Cash vs card | Cash / debit-card / credit-card / transfer-expense split on Total | Bank + cardType breakdowns exist; not shown as a *cash-flow composition* |
| Recurring | Repeat types 0–17 + installment `10001` | None (future-dated rows only) |
| SMS | Inbox staging, macros, join-strings, notification-listener (KR banks), duplicate by `SMS_RDATE` | India `BankSmsParser` + review overlay. No join-string, no inbox ledger |
| AI | None (autocomplete + macros) | Grounded AI ask, insight tokens, category learning, voice smart-parse |
| Salary | None | First-class `SalaryEntries` + hike / runway |
| Charts | Highcharts pie, line, column, budget line+column; spiderweb HTML unused | `fl_chart` pie / line / bar / heat / DOW / historic months |
| Sync | uid + `isSynced` + `syncTime` + `syncVersion` + soft `IS_DEL` | `updatedAt` last-write-wins + tombstones. Keep this |

Nexus already has the hard parts Money Manager never built: **AI that cannot hallucinate numbers**, salary, pace vs budget, heat calendar, weekday mix, merchant rollup, investment/loan exclusion, India SMS, voice+STT retry, home widget.

Money Manager’s *product* is:

1. A **period engine** (one fiscal calendar everywhere).
2. A **transaction type engine** (income / expense / transfer, with transfer-as-expense).
3. A **category tree + per-period budget** (not one number).
4. A **Stats drill path**: pie → category → time series + transactions.
5. A **Total page** that answers “where did this month’s money go?” in four buckets (cash, card, credit-card, transfer-expense) plus MoM.
6. Credit-card **cycle math** (usage date vs payment date).

Do **not** copy ads, 15-account cap, Korean notification-listener for 200+ bank packages, CalcBox, share-codes, or their Google API keys from `strings.xml`.

---

## 1. Recommended build order (do this, in this order)

Each step is independently shippable. Stop after any step and Expense still works. **Do not start a second Expense tab until Step A is done** — adding more chips on top of three period systems is how the current UI became noisy.

### Step A — One period engine (fix waste first)

**Problem:** three incompatible clocks (verified in code, not inferred):

| Surface | “Week” | “Month” / `1M` | Extra leak |
|---|---|---|---|
| Tracker analysis | last 7 days, `[today−6, tomorrow)` | **calendar** 1st → next 1st | `All` includes **future** |
| Insights | last 7 days to EOD today | **rolling 30 days** | `All` no upper bound; NT = next calendar month |
| Trend modal | **Sunday-start calendar week** | calendar month | 3M/6M **end** = last day of **next** month (`DateTime(y, month+2, 0)`) |
| Heat / pace / salary / budget ring | — | calendar `YYYY-MM` | Widget month spent: `date >= monthStart` **with no upper bound** (future rows inflate it) |

Salary `safeToSpendPerDay` uses `daysRemaining` **excluding today**; Tracker `remainingDays` **includes today**. Same “₹/day left” can differ by one day. Budget ring AT RISK is **≥70%**; Tracker balance card AT RISK is **>75%**.

**Do this:** introduce `ExpensePeriodEngine` (pure Dart, no I/O) as the only function that turns `(now, settings)` into a range.

```dart
class FiscalSettings {
  /// 1–28. 1 = calendar month. Salary day 25 → 25.
  final int monthStartDay; // default 1
  /// none | previousFriday | followingMonday
  final WeekendShift weekendShift; // default none
  final int weekStartWeekday; // DateTime.monday default
}

class PeriodRange {
  final DateTime startInclusive; // local date, time 00:00
  final DateTime endInclusive;    // local date, time 23:59:59.999
  final String label;             // "Sep 2026" / "1–7 Sep"
  final String key;               // "2026-09" or "2026-W36"
}
```

Wire **every** existing chip, heat month, salary month, widget, and SQL `date` filter through this. Until then, new charts will lie.

MM weekend shift (`DateUtil.q`, `Calendar.DAY_OF_WEEK` 7=Sat, 1=Sun), recovered:

```text
type 0 none
type 1 previous Friday: Sat → −1d, Sun → −2d
type 2 following Monday: Sat → +2d, Sun → +1d
```

Month start day ≥28 clamps to that month’s length.

**Tests first:** `test/core/services/expense_period_engine_test.dart` — monthStartDay=25, weekend=Friday, 31 Jan, leap year, NT (next fiscal month), future-dated rows, Sat/Sun start.

Keep Nexus `isNonSpendCategory` as the spend filter. MM does not have Investment/Loan exclusion; we must keep it.

### Step B — Stats composition on data we already have (no new tables)

Money Manager’s Stats tab is three widgets stacked:

1. **Income | Expense toggle** with the *total in the button label* (`Income  ₹x` / `Expenses  ₹y`).
Slice `y` = share; tooltip `amount` = formatted rupees. **Pie drill is not Highcharts drilldown** (`allowPointSelect` only). Tap is the **Android list** under the pie → `StatsDetail` (line + tx list). Sub-pie = `CategoryRepository.h` `GROUP BY SUB_CATE_ID` when a parent is open.
3. **Ranked list** under the pie: name, amount, % . Tap a row → `StatsDetail`: line chart of that category across months (`line.html`) + transaction list for the selected month.

Nexus already has the pie (`tracker_tab.dart`) and a timeframe drill (`expense_timeframe_screen.dart`). What is missing:

- Pie slice / legend row **opens** timeframe filtered to that category (today it is mostly decorative).
- Dual **Income vs Expense** is N/A until Step E. Until income exists, keep Expense-only but add the **Total composition strip** from Step C.
- Category **history line** (last 6/12 fiscal months for one category). `ExpenseMonthlyCategory` already stores `(month, category, total, count)` — this is a SQL read, not a new table.

Ship: `StatsCategoryDetailSheet` on top of `ExpenseTimeframeScreen` + a 6-month line from `watchMonthlySpendTotals` filtered by category.

Empty / error: `popup_message22` = “No data available.” Retry = pull-to-refresh recomputes from Drift. Never block UI on a chart WebView (we use `fl_chart`, keep it).

### Step C — Total-page composition strip (the most informative MM screen we lack)

On MM Trans → **Total** (`MainBudgetFragment` header, data from `BudgetService.c`):

| Field (recovered) | Meaning | Formula |
|---|---|---|
| Income | `SummaryVo.g` | `TOTAL_IN` |
| Expenses | `SummaryVo.h` | `TOTAL_OUT` |
| Compared Expenses | `SummaryVo.a` | see §5.3 |
| Cash expenses | `SummaryVo.b` | `AG_TYPE in (1, 11)` |
| Card expenses | `SummaryVo.c` | `AG_TYPE in (3)` |
| Credit-card out / in | `SummaryVo.d` / `e` | `AG_TYPE in (2)` |
| Transfer-expense | `SummaryVo.f` | transfer-out from cash/bank to non-liquid |

**Nexus mapping without accounts (Step C v1):**

Until we have real accounts, approximate with **existing** `cardType`:

| MM bucket | Nexus v1 |
|---|---|
| Cash expenses | `cardType == 'Cash'` spend-only |
| Card (debit) expenses | `cardType == 'DB'` spend-only |
| Credit-card | `cardType == 'CC'` spend-only (this is *usage*, not the bill) |
| Transfer-expense | `category ∈ {Investment, Loan, Insurance}` **shown separately**, not in spend. We already exclude Investment+Loan from spend; **surface them here** as “moved to wealth/debt” instead of hiding them only on Insights KPI cards |
| Compared Expenses | fiscal-month spend vs previous fiscal month, index 100 = flat |

Put this strip at the **top of Tracker** under the budget ring, replacing the overlapping “analysis carousel” KPIs that repeat Insights. That is the “waste in our setup, good in theirs” change: MM’s Total page is one glance; our Tracker+Insights both try to be that glance.

### Step D — Budget vs actual overlay (keep one global budget, add category rows)

Do **not** replace `BudgetEntries`. Add:

```text
budget_lines
  id TEXT PK
  category TEXT          -- '' = total/global (mirrors today's single budget)
  amount REAL
  period_key TEXT        -- '0' = default; '202609' = fiscal YYYYMM
  updated_at TEXT
```

Rules recovered from MM (`budget_monthly_help`, `BudgetService.b`, `BudgetUtil`, `BUDGET_AMOUNT`):

1. Changing the **default** budget applies **starting next fiscal month**. Current month keeps the amount already snapshotted.
2. `BUDGET_AMOUNT.uid = budgetUid + "_" + period`. Lookup: `AMOUNT` where `budgetUid = ? AND BUDGET_PERIOD <= currentPeriod` take `MAX(BUDGET_PERIOD)`.
3. If a **main** category budget is `0`, display the **sum of subcategory budgets** (`budget_monthly_help_sub_rule`). Orphan children (no parent budget row) get a **synthetic parent** `uid="-2"`.
4. `IS_TOTAL=1` with amount `0` displays the **sum of category budgets** (same rollup at the top).
5. Used % = `used / budget * 100`. If `budget == 0` then `used > 0 ? 100 : 0` (`BudgetUtil.a`).
6. Remaining = `budget - used`. Excess when `used > budget` (`main_summary_list_lable4`).
7. Chart: `budgetLineBar.html` — **column = used (expenses)**, **line = budget**, click category → that month’s Budget Detail. `selectChart(index)` highlights the selected month.
8. `BUDGET.uid` recipe: `targetUid + "_" + doType + "_" + isTotal + "_" + transferType + "_" + periodType`.

Nexus v1 (no subcategories yet):

- Keep global budget as the line with `category = ''`.
- Optional per-category caps for the user’s top 5 spend categories.
- Overlay last 6 fiscal months: bars = spend, line = budget in force that month.
- Reuse `budget_history_modal.dart` chart; do not add a fourth chart widget.

### Step E — Transaction type: Income + Transfer (only after A–D)

MM `DO_TYPE` (**recovered** from strings + `DBQuery`):

| `DO_TYPE` | UI | Effect on totals |
|---|---|---|
| `0` | Income | `TOTAL_IN` / `TOTAL_ORI_IN` |
| `1` | Expense | `TOTAL_OUT` / `TOTAL_ORI_EX` |
| `3` | Transfer-Out | See transfer-as-expense |
| `4` | Transfer-In | Pair of `3` |
| `7` | Income Balance | Opening / reconcile up |
| `8` | Expense Balance | Opening / reconcile down |

Nexus today has no `type` column. Add `Expense.type` with default `'expense'` so every existing row stays valid.

**Do not** implement full double-entry accounts in this step. A transfer can be two linked rows (`transfer_group_id`) with `from_bank` / `to_bank` using the existing bank list. Investment/Loan logging stays as today (single expense row, excluded from spend) **or** becomes a transfer to a virtual “Investment” / “Loan” pocket — pick one in code, do not keep both.

### Step F — Credit-card cycle (India-shaped)

MM credit card account fields (**recovered**): `CARD_DAY_FIN` (settlement / statement start), `CARD_DAY_PAY` (payment date), `IS_CARD_AUTO_PAY`, usage hurdle type (previous month / 3-month average), amount.

Settings `config_setting_list8`:

- **A. At the time** — CC spend hits the month you swiped.
- **B. Lump sum** — CC spend is hidden from monthly expense until payment date, then posted as one payment. When `Globals.b == "1"`, `DBQuery.d` **drops** `AG_TYPE == 2` from `TOTAL_OUT` and treats the payment transfer as the expense.

Nexus already forecasts “this month’s CC spend = next month’s bill” in salary. Step F is:

1. Setting: `ccPosting = usageDate | paymentDate` (default `usageDate`, matches today).
2. **Do not add a `bank_cycle` table.** `settings_controller.dart` `Bank.statementDay` / `dueDay` already exist and are edited in Settings. Wire Step F to that.
3. `watchMonthlyCardSpendTotals('CC')` **includes** Investment/Loan on a CC (the bank still bills you). Spend pies must still exclude those categories. Tested in `expense_investment_savings_test.dart`.
4. Forecast engine: `kSalaryCreditDay = 28` — salary[M] is treated as credited on the 28th of M−1. Do not invent a second salary-credit day.

Do **not** build MM’s “Pay” button that posts a transfer from bank → card unless Step E exists.

### Step G — Recurring + installments

MM `repeat_string` (**exact**):

| id | Label | Next date (`RepeatService.a`) |
|---|---|---|
| 0 | Nothing | — |
| 5 | Every Day | +1 day |
| 9 | Weekdays | +1 day, skip Sat/Sun |
| 10 | Weekend | jump to next Saturday |
| 6 | Every Week | +7 |
| 7 | Every 2 weeks | +14 |
| 15 | Every 4 weeks | +28 |
| 1 | Every Month | +1 month |
| 8 | The end of the month | next last-day |
| 2 / 3 / 4 / 16 | Every 2 / 3 / 4 / 6 Month | +N months |
| 17 | Annually | +1 year |
| 10001 | Installment (N months) — not in the array; special-cased in `RepeatTypeList` |

Reflection setting:

- **On the date** — post on the calendar day.
- **On the first day of every month** — all of that month’s repeats are posted on fiscal month start (`config_repeat_save_first_day_left` warns that dates up to `%1$s` are reflected in advance).

Installment: `CARDDIVIDMONTH` + `cardDivideUid` + `CARD_DIVIDE_MONTH_STR` (`(i/n)`). UI: “Monthly installment plan”, “Total: %1$s”. Recovered: `floor(total/n)` with **remainder on the first** slice; `IN_ZMONEY` holds the original total. Day-list **zeros** installment amounts when `0 < CARDDIVIDMONTH < 10001` so only the current slice counts. Must complete inside one calendar month (`inout_edit_message6`) for the *plan*, then copies land on later `WDATE`s. `1903911` was an iPhone repeat sentinel — skip.

MM `RepeatService.h` runs **once per device day**. Transfer templates write paired `DO_TYPE` 3/4 with swapped accounts (`RepeatService.e`).

Nexus: `recurring_rules` table + a WorkManager / app-resume job that inserts missing occurrences up to `today` using `NEXT_DATE` cursor. **Idempotent** on `(rule_id, occurrence_date)`. Never generate into the future except the current fiscal month. Same once-per-day gate.

### Step H — Real accounts / net worth (optional, largest product change)

Only if the owner wants a ledger, not a diary. MM Accounts tab: Assets, Liabilities, Balance, credit-card payable vs outstanding, hidden accounts, deleted-account restore, “include in totals”, loan as **negative** opening balance, overdraft as negative, debit-card **no carry-over**.

Nexus should **not** clone this unless we are willing to replace `bank: String` with `account_id`. That is a migration of every expense, SMS parser, widget, and AI token. Prefer Step C+F first.

---

## 2. What NOT to copy

| MM thing | Why skip |
|---|---|
| AdMob / AppLovin / AdFit / Coupang | Not a product idea |
| `accountRestrict` 15 accounts | Free-tier dark pattern |
| Notification listener for 200+ Korean bank/pay packages (manifest `<queries>`) | We have India SMS. Do not request Notification Listener for every Indian bank app |
| `SmsParserKRW` / country parsers | We have `BankSmsParser` for IN |
| CalcBox, share-code points, PC Manager, multi-book (Korean-only strings) | Other products |
| Highcharts WebView | Use existing `fl_chart`. Port *data shapes*, not the WebView |
| `spiderweb.html` | Present in assets, **zero Java references** in this APK. Nice for “this month vs last month category shape”; add only after Step B if 4+ categories |
| `pie_sub.html` | Unused Highcharts demo (nested pie). Our drilldown is a **second screen**, which is cleaner |
| Passcode / fingerprint as a clone | Nexus already has app auth |
| Google Drive backup as a clone | Nexus already has cloud sync + Drive for other features |
| Their `google_api_key` / Firebase ids in `strings.xml` | Secrets from a third-party dump. Never paste into Nexus |

---

## 3. Money Manager product surface (recovered)

Bottom / main destinations (from `main_title`, `assets_title`, `config_title`, `Main.java` fragment tags):

1. **Trans.** — Daily list, Calendar, Weekly, Monthly, **Total**, Annually. `+` Input, Inbox, Bookmark.
2. **Stats** — Income / Expense pies, period pager, drill to `StatsDetail`.
3. **Budget** — expandable category list + used/remaining; tap → `BudgetDetail` overlay chart.
4. **Accounts** — groups, balances, card payable, Stats per account (daily/monthly/yearly line+column).
5. **Notes** — dated memos on calendar (not transactions).
6. **Settings** — categories, subcategories, budget, repeat, SMS, backup, currency, carry-over, transfer-expense, card posting, month start, weekend, widgets.

Input form fields (`inout_edit_lable*`): Date, Account, Category, Amount, Note, From, To, Installment, Months, Payment, Tag, Fees, photos (up to 3 strings: first/second/third photo), location `lat/lng`.

Voice (MM): `voicePanelTitle` = “Date, Account, Category, Amount, Contents (Orderless)”. Region-gated (`voiceNotSupportMsg`). Nexus should pass those field names into STT `vocabulary` (already done for banks+categories in Add Expense).

Widgets (xml providers): 4x1 tx, 4x2 tx, 4x1/2x1/2x2 quick-add (dark + white), 4x2 **card usage**, mic shortcut. Theme + opacity. Nexus already has a stronger expense widget (budget ring + add). Steal only **card-usage hurdle** if Step F ships.

---

## 4. Recovered schema (SQLite)

Source: `com.realbyte.money.database.database.DBHelper.onCreate`. Soft-delete is `IS_DEL`; sync columns on almost every table: `isSynced`, `syncTime`, `syncVersion`. **Nexus already has a better merge (`updatedAt`) — keep it.** When adding tables, add `updated_at` + `deleted_at`, not MM’s `isSynced` integer.

### 4.1 `INOUTCOME` (transactions)

`AID` PK, `uid` UNIQUE, `assetUid`, `toAssetUid`, `ctgUid`, `DO_TYPE`, `ZMONEY` (amount as VARCHAR — **do not copy that; use REAL**), `IN_ZMONEY`, `AMOUNT_ACCOUNT`, `ZCONTENT` (payee/merchant), `ZDATA` (memo), `ZDATE` (epoch-ish), `WDATE` (working date `YYYY-MM-DD` — **this is what totals filter on**), `wtime`, `paid`, `CARDDIVIDMONTH`, `cardDivideUid`, `CARD_DIVIDE_MONTH_STR`, `txUidTrans` (link to the other side of a transfer), `txUidFee`, `SMS_RDATE`, `SMS_ORIGIN`, `SMS_PARSE_CONTENT`, `MARK` (bookmark), `currencyUid`, `lat`, `lng`, `gstd`, `IS_DEL`, `UTIME`.

Indexes: `DO_TYPE`, `ZDATE`, `WDATE`, `SMS_RDATE`, `UTIME`, `assetUid`, `ctgUid`, `currencyUid`.

### 4.2 `ASSETS` / `ASSETGROUP`

Account: name `NIC_NAME`, group `groupUid`, currency, SMS `SMS_TEL` + `SMS_STRING` (join words, `;`-separated), `IS_TRANS_EXPENSE`, `IS_CARD_AUTO_PAY`, `CARD_DAY_FIN`, `CARD_DAY_PAY`, hurdle type/start/amount, `cardAssetUid` (debit/credit → funding account), `APP_PACKAGE` / `APP_NAME` (notification listener).

`ASSETS.ZDATA` lifecycle (**recovered**): `0` active, `1` deleted, `2` hidden-from-lists, `3` eye-slash. Lists: `ZDATA not in (1,2)` (cards also exclude `3`). Deleted accounts with `DATA_COUNT>0` still appear in period stats.

`ASSETS.ZDATA2` = include-in-totals: unchecked ⇒ `'1'`. Net worth omits those uids (`ZDATA2 is null or ZDATA2 <> '1'`).

Default groups (`arrays.xml` `assets_group` `uid;name;A|L`) — `ASSETGROUP.TYPE` **is this uid**:

| `AG_TYPE` | Name | A/L | Role in totals |
|---|---|---|---|
| `1` | Accounts | A | Bank. With `11`, “Cash Expenses” (`SummaryVo.b`) |
| `2` | Card | L | Credit. Excluded from expense when posting = lump-sum |
| `3` | Debit Card | L | “Card Expenses”. **No own carry**; folded into `cardAssetUid` |
| `4` | Savings | A | Transfer-expense target |
| `5` | Loan | L | Shown **negative** |
| `6` | Top-Up/Prepaid | A | |
| `7` | Others | A | |
| `8` | Investments | A | Transfer-expense target |
| `9` | Overdrafts | L | Shown **negative** |
| `10` | Insurance | A | Transfer-expense target |
| `11` | Cash | A | With `1`, “Cash Expenses” |

**Do not swap 1 and 11.** Earlier notes that called `1` Cash were wrong. `cashOut = AG_TYPE IN (1, 11)` is bank+cash.

Debit cards: **no carry-over** (`config_button_text1_help_desc3`). They are a payment rail (`cardAssetUid` → funding account), not a balance. Must share parent currency.

Loan / overdraft: opening amount **must** be entered negative or it is treated as an asset.

### 4.3 `ZCATEGORY`

`uid`, `NAME`, `TYPE` (income vs expense), `STATUS` (**2 = this row is a subcategory**; parent `pUid`), `C_IS_DEL`, `ORDERSEQ`.

Special category ids in SQL:

- `ctgUid == '-4'` → keep as main `-4` (uncategorized / special).
- empty / null subcategory → main `'-2'` (“None”).
- `STATUS == 2` → the row is a child; `MAIN_CATE_ID = pUid`, `SUB_CATE_ID = uid`.

### 4.4 `BUDGET` / `BUDGET_AMOUNT`

`BUDGET`: `uid`, `targetUid` (category or account), `DO_TYPE`, `PERIOD_TYPE` (**6 = monthly** in every query we found), `IS_TOTAL` (1 = overall budget), `TRANSFER_TYPE`, `ORDER_SEQ`, `IS_DEL`.

`BUDGET_AMOUNT`: `budgetUid`, `AMOUNT`, `BUDGET_PERIOD`. `BudgetUtil.b` is `year * 100 + Calendar.MONTH + 1` → **YYYYMM** (Sep 2026 = `202609`). Live code **always writes `PERIOD_TYPE = 6`** (monthly). Amount for a month = latest row with `BUDGET_PERIOD <= that month` (forward-fill). Snapshot per month so history does not rewrite.

### 4.5 Other tables worth the idea, not the names

| Table | Idea for Nexus |
|---|---|
| `REPEATTRANSACTION` | `NEXT_DATE` cursor, `REPEAT_TYPE`, `END_DATE` |
| `FAVTRANSACTION` | Bookmarks / templates (we have category learning instead; optional) |
| `SMS_RAW_READ` | Inbox staging **before** it becomes an expense. We have review overlay — persist unreviewed SMS here conceptually |
| `MESSAGEMACRO2` | Per-sender parse macros + `conAssetUid` |
| `TAG` / `TX_TAG` | User tags + **system** tags `system_prepayment`, `system_card_usage_exception` |
| `PHOTO` | Receipts. Optional |
| `MEMO` | Calendar notes. Skip; Nexus comments field is enough |
| `CURRENCY` | Multi-currency. Skip for IN rupee app unless asked |
| `CODE_DATA` / `CODE_LINK` | Share-code. Skip |

### 4.6 MM calculation settings (`ZETC`, recovered)

These are the flags that change totals. Port as a small `expense_settings` row (or SharedPreferences), not 20 tables.

| `dataTypeKey` | Default | Meaning |
|---|---|---|
| `start_day` (`ZDATATYPE -23459`) | `"1"` | Monthly start date 1–31 (clamp ≥28) |
| `carry_over` (`-5457`) | `"0"` | Previous month net into this Total |
| `card_accounting_type` (`-30009`) | `"0"` | A = at swipe, `"1"` = lump-sum on payment date |
| `use_sub_category` (`19810`) | `"0"` | Subcategories off (`"1"` show children) |
| `week_start_day` (`10002`) | `"0"` | `0`–`6` Sun–Sat |
| `month_start_weekend_type` (`10008`) | `"0"` | `0` none, `1` previous Friday, `2` following Monday |
| `repeat_reflect_type` (`10009`) | `"0"` | `"0"` on the date, `"1"` on first day of period |
| `default_period_type` (`2123`) | `"6"` | Monthly |
| transfer-income hide (`Globals.O`, `10012`) | not `"2"` | `"2"` → never treat source-side transfers as income |
| `sms_auto_save_to_tx` | `"0"` | Auto-save parsed SMS |
| `sms_search_day` | `"30"` | SMS lookback (cap 10000) |

Transfer fee is a **linked sibling transaction** (`txUidFee`), not a field on the parent. If we add fees, use a child row with `parent_id`, do not overload `comments`.

MM ships **no** split-among-categories UI, **no** named Net Worth report (Accounts Balance = Assets − Liabilities), **no** savings-goal entity. Do not invent those while copying Stats.

Default income cats: Allowance, Salary, Petty cash, Bonus, Other. Default expense tree is Food (+ Lunch/Dinner/…), Social Life, Transport, … Nexus already has a 26-category India list — **keep ours**, do not import MM’s Korean defaults.

---

## 5. Formulas (copy these into tests)

All money rounding in MM: `round(x * 10^decimalPlaces) / 10^decimalPlaces` via `CurrencyRepository`. Amount column in totals is `ZMONEY` (main FX) unless the account currency differs, then `AMOUNT_ACCOUNT`. Soft-delete: `IS_DEL=1` when cloud sync is on, otherwise hard `DELETE` (same for photos/tags). Nexus already tombstones — keep that; do not copy the dual path.

`Schema.java` / `SchemaAdd.java` / `SchemaMigration.java` in the dump are **empty stubs** — ignore them.

Nexus: keep integer rupees in UI via `formatCurrency`; compute in `double` like today. Add rupee-floor `100` already in `ExpensePaceMetrics.rupeeFloor` — keep it so tiny noise does not become a “insight”.

### 5.1 Spend vs non-spend (Nexus, keep)

```text
isSpend = category ∉ {Investment, Loan}     // isNonSpendCategory
monthSpent = Σ amount of isSpend in fiscal month
```

Insurance is **spend** in Nexus today and **transfer-expense** in MM. Step C v1: keep Insurance as spend, show Investment+Loan in the “moved” bucket. Do not silently exclude Insurance without a product decision.

### 5.2 Income / expense / transfer (MM `DBQuery.d`)

Let `cardLumpSum = (posting mode == B)`  → MM `Globals.b == "1"`.  
Let `hideTransferAsExpenseFromIncomeSide = MM Globals.O` (`ZETC 10012 == "2"`: never treat source-side transfers as income).

**Default posting (at the time), transfer-as-expense ON:**

```text
TOTAL_IN  = DO_TYPE=0
          OR (DO_TYPE=3 AND IS_TRANS_EXPENSE=1
              AND (TO_IS_TRANS_EXPENSE≠1 OR NULL))
              -- money leaving a "savings/investment/loan" account back to liquid
              -- counted as income when the FROM account is marked transfer-expense

TOTAL_OUT = DO_TYPE=1
          OR (DO_TYPE=3 AND (IS_TRANS_EXPENSE≠1 OR NULL) AND TO_IS_TRANS_EXPENSE=1)
              -- transfer INTO a transfer-expense account counts as an expense
```

**Card lump-sum ON** (`card_accounting_type = "1"`): drop credit-card (`AG_TYPE=2`) spend from expense; paying the card (transfer **to** a card) **is** expense:

```text
IN:  DO_TYPE='0'
     OR (DO_TYPE='3' AND IS_TRANS_EXPENSE=1
         AND (TO_IS_TRANS_EXPENSE!=1 OR null) AND TO_AG_TYPE!=2)
OUT: (DO_TYPE='1' AND AG_TYPE!=2)
     OR (DO_TYPE='3' AND AG_TYPE!=2 AND (IS_TRANS_EXPENSE!=1 OR null)
         AND (TO_IS_TRANS_EXPENSE=1 OR TO_AG_TYPE==2))
```

**Transfer-expense OFF (`Globals.O` true):** `TOTAL_IN` is pure `DO_TYPE=0`; `TOTAL_OUT` stays as in the matching posting mode, without source-side transfer-income.

**Nexus v1 (no accounts):** do not implement the SQL above until Step E. Use §1 Step C mapping.

**Account balance (all time, Step H):** `(DO_TYPE in 0,4,7) − (1,3,8)` (`AssetRepository.a`). Debit cards excluded as standalones then folded into `cardAssetUid`.

**Credit-card payable** (`AssetRepository.i`, cycle start = `CARD_DAY_FIN`): waterfall old outflow vs old inflow, leftover vs future inflow. Returns `{current_due, upcoming, overdue}` **all negative**. Prepayment tag `system_prepayment` splits paid vs outstanding. `WDATE` is **not** auto-shifted to `CARD_DAY_PAY`.

**Original vs adjusted (always computed in the same SELECT):**

```text
TOTAL_ORI_IN       = Σ DO_TYPE=0
TOTAL_ORI_EX       = Σ DO_TYPE=1
TOTAL_TRANSFER_OUT = Σ DO_TYPE=3
TOTAL_TRANSFER_IN  = Σ DO_TYPE=4
TOTAL_LEFT_IN      = Σ DO_TYPE=7
TOTAL_LEFT_OUT     = Σ DO_TYPE=8
```

MM UI “Total” on Trans is **Income − Expenses** after the transfer-as-expense rewrite, not `ORI_IN − ORI_EX`. Carry-over (previous month surplus/deficit) is added on Daily/Total when carry-over is ON (`main_day_list_draw_text`, `config_setting_list2_move_next_desc`). Negative leftover = expense; surplus = asset. Debit-card group excluded.

### 5.3 Compared Expenses (MoM index)

From `BudgetService.c`:

```text
thisOut = TOTAL_OUT(this fiscal month)
lastOut = TOTAL_OUT(previous fiscal month)
if lastOut == 0:
  index = 100          # displayed as "100%"
else:
  index = round((thisOut - lastOut) * 100 / lastOut) + 100
```

`100` = same as last month. `130` = 30% more. `70` = 30% less. This is **better UX than our raw Δ rupees** for a header chip because it is comparable across income levels.

Nexus: add `momIndex` next to `momPct` in `ExpenseInsightEngine`. Show it on Tracker Total strip. Keep `momPct` for the AI tokens (the LLM already knows `%`).

**Previous fiscal month range:** `DateUtil.r(calendar, monthStartDay, weekendShift, -1)` then `z`/`L` for start/end. Port via `ExpensePeriodEngine.previous(range)`.

### 5.4 Cash / card / CC / transfer-expense split

From `BudgetService.c` (same `WDATE` range, `IS_DEL` not 1):

```text
cashOut   = TOTAL_OUT where AG_TYPE IN (1, 11)   # bank + cash
cardOut   = TOTAL_OUT where AG_TYPE IN (3)      # debit
# Credit on this header is NAIVE (not the transfer-expense rewrite):
ccOut     = Σ DO_TYPE in (1, 3) where AG_TYPE=2
ccIn      = Σ DO_TYPE in (0, 4) where AG_TYPE=2
xferExp   = Σ ZMONEY where DO_TYPE=3
            AND AG_TYPE IN (1, 11)
            AND TO_AG_TYPE NOT IN (1, 2, 3, 11)
```

Do **not** reuse `TOTAL_OUT` for the CC row on this strip — `SummaryVo.d`/`e` ignore lump-sum / transfer-expense CASE.

Nexus v1:

```text
cashOut = Σ spend where cardType=='Cash'
debitOut = Σ spend where cardType=='DB'
ccOut    = Σ spend where cardType=='CC'
xferExp  = Σ amount where category in {Investment, Loan}   # not spend
```

### 5.5 Category rollup (MM SQL, port the CASE)

```sql
MAIN_CATE_ID = CASE
  WHEN ctgUid = '-4' THEN '-4'
  WHEN subCtg.STATUS = 2 THEN subCtg.pUid
  ELSE CASE WHEN subCtg.uid IS NULL OR subCtg.uid = '' THEN '-2' ELSE subCtg.uid END
END
MAIN_CATE_NAME = CASE WHEN subCtg.STATUS = 2 THEN mainCtg.NAME ELSE subCtg.NAME END
SUB_CATE_ID   = CASE WHEN subCtg.STATUS = 2 THEN subCtg.uid ELSE '' END
SUB_CATE_NAME = CASE WHEN subCtg.STATUS = 2 THEN subCtg.NAME ELSE '' END
```

Pie uses **main** category. StatsDetail can switch to **sub** list (`stats_detail_sub_list_item`). Nexus has a flat category list — pie of `category`, tap → list. When we add subcategories, reuse this CASE in Drift, do not compute in the widget.

### 5.6 Budget remaining / pace (Nexus, keep and align period)

Already in `ExpensePaceMetrics.monthPace`:

```text
expectedByNow = budget * (dayOfMonth / lengthOfMonth)
leftover      = budget - monthSpent
safeDaily     = max(0, leftover) / max(1, remainingDays)
threshold     = max(budget * 0.08, 100)
status        = monthSpent > budget → overPlan
                monthSpent - expectedByNow > threshold → aheadOfPace
                else onTrack
```

**Change:** `dayOfMonth` / `lengthOfMonth` must be **fiscal** after Step A (if month starts on the 25th, day 1 of the period is the 25th). Until Step A, do not add a second pace widget.

### 5.7 Budget % used (MM)

```text
pct = budget == 0 ? (used > 0 ? 100 : 0) : (int) (used / budget * 100)
```

If main budget is 0, `used` still paints against **sum of child budgets**.

### 5.8 Card usage hurdle (MM)

`AssetService.a` + `AssetsDetail`. Spend in `[monthStart, nextMonth)` on `DO_TYPE 1|3`, excluding tag `system_card_usage_exception`. Installment groups (`cardDivideUid`) count **full TOTAL_MONEY** only if this period contains the **first** slice; otherwise `PERIOD_MONEY`. Cycle month-start is `CARD_DAY_FIN` (`weekendType=0`).

- `CARD_USAGE_HURDLE_TYPE==1` (default / previous-month style): remaining = `hurdle − thisMonth`
- `==2` (3-month average): remaining = `hurdle * 3 − (this + prev2 months)`

KR default hurdle `300000`. Widget shows used vs hurdle.

Nexus: optional per-bank `hurdleAmount` + `hurdleKind` on existing `Bank`. Source spend = `watchMonthlyCardSpendTotals` for that bank. Do not auto-exclude transfers until we have them.

### 5.9 Duplicate SMS

MM: `SELECT * FROM INOUTCOME WHERE SMS_RDATE = ? AND (IS_DEL != 1 OR IS_DEL IS NULL)` → `sms_already_exist`.

Nexus: persist `sms_fingerprint` (sender + date + amount + last-4) on the expense. Unique index. Review overlay already exists — if fingerprint matches, show “Already logged” and skip insert. Retry of SMS broadcast must not create a second row.

Search filters (live in `Search.java` `U()`, **not** `SearchService.java` which is empty): text on payee **or** memo (optional `SMS_ORIGIN`); amount min/max; tags via `TX_TAG`; accounts include transfer `toAssetUid`; categories by `MAIN_CATE_ID`/`SUB_CATE_ID`; period codes **differ from Stats** (Search `B`: 5 all, 1 month, 2 year, 3 week, 4 custom. Stats `u`: 2 month, 3 year, 4 week, 5 custom).

Fee: sibling `DO_TYPE=1` with same `txUidFee`, payee = `input_transfer_fee`. Already inside expense — do not add it again.

### 5.10 Carry-over vs opening balance (do not mix)

**Opening / reconcile** is persisted: `DO_TYPE` 7 / 8, `ctgUid='-4'`, strings Income/Expense Balance.

**Carry-over ON** (`ZETC -5457`): `TxRepository.f` builds a first-day row labelled `Rollover_Carryover` / `main_day_list_draw_text`.

```text
net = TOTAL_IN − TOTAL_OUT  from 0000-00-00 through yesterday
if net > 0 → income carry
if net < 0 → expense carry, amount = abs(net)
```

Debit (`AG_TYPE=3`) is excluded as a standalone then folded into `cardAssetUid`. Widgets and Excel skip carry rows when listing recent txs.

One dump pass described this as persisted `DO_TYPE` 7/8; `TxRepository.f` instead synthesizes `DO_TYPE` 0/1 with `MAIN_CATE_ID='Rollover_Carryover'`. **Re-read that method before coding.** Nexus should not persist phantom expenses either way.

Nexus: skip until we have income. Safer UX: `nextMonthBudgetHint = leftover` if `leftover > 0` — display only, do not rewrite `BudgetEntries`.

---

## 6. Charts — data shapes to implement (not Highcharts)

All MM charts: WebView loads HTML → `window.androidActivity.drawChart()` → Java builds a Map → `javascript:drawChart(json)`. **Port the JSON, render with `fl_chart`.** Empty: `nodata` = “No data available.”

### 6.1 Category pie (Stats / Tracker)

From `StatsExpensesFragment.a()` / `StatsIncomeFragment`:

```json
{
  "pieBackgroundColor": "#FFFFFF",
  "pieTextColor": "#000000",
  "pieTextSize": 12,
  "pieBorderColor": "#FFFFFF",
  "colors": ["#…", "…11 rotating…"],
  "nodata": "No data available.",
  "series": [{
    "name": " ",
    "type": "pie",
    "data": [
      { "name": "Food", "y": 42.5, "amount": "₹12,480" }
    ]
  }]
}
```

- `y` = **percentage of period total** (Highcharts pie uses `y` as slice size).
- Tooltip shows formatted `amount`, not `%` only.
- Labels: `name` + `percentage:.1f %`.
- Click / legend: navigate to category detail. Do **not** explode slices as the only interaction.

Nexus Tracker pie already has touch-to-highlight. **Add** `onSliceTap → ExpenseTimeframeScreen(category: name, range: currentPeriod)`.

Group slices below 3% into **Other** (`stats_list_etc`) so a 20-category pie stays readable. MM does this in the list (“Other”); do it in both pie and list.

### 6.2 Category history line (StatsDetail)

`line.html`:

```json
{
  "categories": ["2026/04", "05", "06", "07", "08", "09"],
  "series": [{ "name": "Food", "data": [1000, 3000, 12000, 200000, 100000, 15000] }],
  "colors": ["#7cb5ec"],
  "xAxisVisible": true,
  "valuePrefix": "₹",
  "valueSuffix": "",
  "nodata": "No data available."
}
```

Source: `ExpenseMonthlyCategory` where `category = ?`, last 12 fiscal keys, pad zeros (`ExpensePaceMetrics.historicCalendarBars` already pads).

### 6.3 Account / Total column + line (AssetsAllStats)

`column.html` + `line.html` on the same page: Income vs Expense columns (highlight colours `inColorHighlight` / `outColorHighlight`) and a balance line. Click category on column is **not** wired in budgetLineBar’s tooltip (tooltip disabled); click calls `callAndroid(this.category)` on the budget combo chart.

Nexus: skip account charts until Step H. For Total strip, a **stacked bar** Cash | Debit | CC | Moved is more informative than another pie.

### 6.4 Budget vs actual (BudgetDetail)

`budgetLineBar.html` series:

1. `type: "column"`, name = “Expenses”, `pointPadding: 0.2` — used amount per month.
2. `type: "line"`, name = “Budget” — budget in force that month.

Click month → load that month’s category budget list. `selectChart(index)` selects the line point.

Nexus: implement in `budget_history_modal.dart` (already has line + grouped bars). Add the **budget line** on the spend bars. One chart, not two.

### 6.5 Heat calendar (Nexus, keep)

`ExpensePaceMetrics.heatMonth`: intensity = daySpend / hottestDayThisMonth. Future days 0. Tap day → timeframe for that day (`onOpenDay`). MM Calendar shows per-day income/expense numbers + memos. We should add **day total in the cell** (we have `HeatDay.spent`) — currently intensity-only is pretty but not informative. That is a one-line UX steal.

### 6.6 Weekday mix (Nexus, keep)

Insights DOW bar with Total / Avg/day / Txns + weekend share. MM does **not** have this. **Do not replace it** with a spiderweb. It is already more advanced.

### 6.7 Spiderweb (optional later)

`spiderweb.html`: polar line, `categories` = category names, one series this month, optionally a second series last month (commented sample is one series). Use only when `categories.length >= 4` and both months have data. Otherwise it is a scribble.

---

## 7. Insights / stats Nexus already has (do not rebuild)

Implementers keep these; MM has no equivalent.

| Feature | Where | Keep? |
|---|---|---|
| Pace vs budget, safe daily, ahead/over | `ExpensePaceMetrics.monthPace` | Yes; fiscal-align in Step A |
| Range facts (vs previous, top share, top3 ≥70%, category shift, 6-month high/low) | `ExpensePaceMetrics.rangeFacts` | Yes |
| Grounded AI (`{{tokens}}`, no hallucinated numbers) | `ExpenseInsightEngine` + `expense_insight_service.dart` | Yes |
| AI ask sheet | `expense_ai_ask_sheet.dart` | Yes |
| Category learning | `learningsProvider` | Yes |
| Salary + hike + CC forecast | `salary_screen.dart` | Yes |
| Investment cumulative sparkline + loan KPI | `insights_tab.dart` | Yes; also surface in Step C strip |
| Merchant top-N | `topMerchants` | Yes |
| Heat calendar | Tracker | Yes; show ₹ on cell |
| Voice STT retry + Telegram | `SttGatewayService` | Yes |
| Widget budget ring | Android `ExpenseWidgetLogic` | Yes |
| SMS India parser + review | `sms_auto_expense/` | Yes; add fingerprint |
| Memory rollup `ExpenseMonthlyCategory` | Drift | **This is the Stats backend.** All new charts read it |

---

## 8. Waste in Nexus that MM does better (and how to retire it)

This is the “our setup is waste, theirs is informative” list. Each item is a removal or merge, not a new feature.

| Waste | Why it is weak | MM equivalent | What to do |
|---|---|---|---|
| Three period chip sets | Same user question, three answers | One fiscal pager on every tab | Step A; Insights chips become aliases of Tracker periods |
| Insights tab ~5k lines | KPI carousel + trend + DOW + merchants + search + salary + AI | Stats is pie+list; Total is composition; Budget is tree | Insights becomes: Salary card + AI + DOW + merchants. Move pie/trend to Tracker/Stats |
| Analysis carousel on Tracker (Today/7D/1M/6M/All pages) | Swiping pages of the same pie | Horizontal period on one page | One pie, period chips, composition strip |
| Trend modal **and** Insights line **and** historic month bars | Three spend-over-time charts | One line on StatsDetail; one budget overlay | Keep historic bars on Tracker (6/12 month). Delete or deep-link Trend modal from the bar tap |
| `bank` as a label | Cannot answer “what is my HDFC balance?” | Accounts | Do not pretend; either Step H or stop showing bank pie as if it were a balance |
| Single budget vs 25 categories | “₹50k left” with Food at 80% is a lie | Category budgets | Step D |
| Pie without drilldown | Pretty, not a tool | Pie → list → month line → txns | Step B |
| Heat without numbers | Colour-only | Calendar with ± per day | Print `HeatDay.spent` |
| Insights `Month` = 30 rolling days vs Salary = calendar month | AI talks about “this month” using the wrong window | One `WDATE` range everywhere | Step A |
| NT (next month) hidden as a chip | Useful for rent logged early | MM just uses the date | Keep NT but label “Scheduled / next fiscal month” |
| Duplicate empty states | Each chart invents copy | One `No data available.` | Shared `ExpenseEmptyChart` |
| Tracker tip uses **all-time** top category | Advises this month from lifetime Food | Total page is period-scoped | Tip must use **current fiscal month** top cat |
| Two AT RISK cutoffs (ring 70%, card 75%) | Same budget, two colours | One % used | One constant |
| Salary vs Tracker remaining-days | ₹/day disagrees mid-month | One formula | Include today (Tracker) everywhere |
| Widget month unbounded | Future rent inflates “this month” | `WDATE between start and end` | Clamp to fiscal month |
| Insights `watchExpenses()` in RAM | Will not scale | SQL aggregates | New views use `rangeSummary` / memory rollup |
| `AppConstants.categories` (8) vs `expenseCategories` (26) | Dead constants | One list | Delete the 8-item list |
| Epoch-ms expense ids | Collision if two saves in 1ms | `uid` UNIQUE | UUID |
| SMS `SBI` → HDFC | Wrong bank | Join-string / own bank | Stop the alias |
| `clear all` vs nuke | Salary survives `clear all` | Reset contents vs complete reset | Copy must say so |

---

## 9. Missing ideas worth taking (priority)

P0 = do next. P1 = after P0. P2 = only if we want a ledger.

### P0 — Informative without new concepts

1. **Period engine** (Step A).
2. **Composition strip** Cash / Debit / CC / Moved + MoM index (Step C).
3. **Pie → category timeframe** (Step B).
4. **Category 6/12-month line** from `ExpenseMonthlyCategory`.
5. **₹ on heat cells**.
6. **Budget line on historic bars**.
7. **SMS fingerprint** unique index + “already logged”.
8. **Other** bucket for <3% pie slices.
9. Shared empty/error/retry for every chart.

### P1 — Tracking MM got right

10. **Per-category budget** with period snapshot (Step D).
11. **Fiscal month start** (salary date 1 vs 25).
12. **CC posting mode + statement/payment day** (Step F).
13. **Recurring** rent/SIP/EMI (Step G) — EMI should post as `Loan` (non-spend) or as installment child rows.
14. **Tags**: `prepayment`, `exclude-from-card-hurdle`, plus free tags. Reuse `comments` for free text; tags are filterable.
15. **Bookmarks / templates** for “usual Swiggy 280 Food”. Low priority vs learning map.
16. **Join-string** on bank: SMS containing `9985` or `HDFC` routes to that bank (MM `SMS_STRING`, `;` separator). We already guess bank in the parser; let the user pin extra tokens per bank in Settings.
17. **Inbox persistence**: unreviewed SMS survive app kill (MM `SMS_RAW_READ`). Today the overlay is session-scoped — if the process dies, the SMS is easy to miss.
18. **Multi-edit**: MM can edit all dates / notes / categories / assets for a selection, and sum selected rows. Timeframe screen: long-press select → sum in the app bar (we have swipe-to-delete; add sum).
19. **Copy txn** with “today” vs “original date” (`copy_today` / `copy_date_at`).
20. **Daily reminder** “Have you recorded your transactions today?” (`notification_daily_check`). Optional; Nexus widget already pulls them in.

### P2 — Ledger (only with an explicit product decision)

21. Income + transfers (Step E).
22. Real accounts, net worth, carry-over, debit no-accumulate (Step H).
23. Subcategories.
24. Multi-currency / FX on the entry form (MM 4.9).
25. Photos / location.
26. Excel import/export (MM TSV). Nexus cloud already exports in other ways.
27. Spiderweb this-month vs last-month.

---

## 10. Implementation specs (developer-ready)

### 10.1 `ExpensePeriodEngine`

**File:** `lib/core/services/expense_period_engine.dart`  
**Tests:** `test/core/services/expense_period_engine_test.dart`

```text
periodOf(now, settings, kind) -> PeriodRange
  kind ∈ { day, week, fiscalMonth, last7, last30, last90, last180, all, nextFiscalMonth }

previous(range) -> PeriodRange   # same length, immediately before start
fiscalMonthKey(d, settings) -> "YYYY-MM" of the fiscal month containing d
contains(range, expenseDate) -> bool
```

**Weekend shift (MM strings):** if `monthStartDay` falls on Sat/Sun: Previous Friday / Following Monday / No changes.

**SQL:** all `date` filters use `startInclusive` ISO and `endInclusive` ISO **local**, same as `ExpenseRepository._monthBounds` does today. Do not mix UTC `updatedAt` into period math.

**Retry:** none (pure). Invalid `monthStartDay` clamp to `1..28`.

**Call sites to convert (do not leave stragglers):**

- `tracker_tab.dart` `_analysisLabels`
- `insights_tab.dart` `expensesInInsightPeriod` / `calendarMonthSpend`
- `expense_trend_modal.dart` `_rangeFor`
- `ExpensePaceMetrics.monthPace` / `heatMonth`
- `ExpenseRepository.watchMonthTotal`
- `salary_providers` month key
- `ExpenseWidgetLogic` / `expense_widget_service.dart`

### 10.2 Composition strip

**File:** `lib/core/services/expense_composition.dart` (pure)

```text
Composition {
  cash, debit, credit, moved, spend, momIndex, prevSpend
}
from(expenses, range, prevRange)
```

`moved` = Investment + Loan in range (not spend).  
UI: four labelled amounts + stacked bar (widths = share of `cash+debit+credit+moved`). Hide a segment if `< rupeeFloor`.

**Retry:** recompute from `expensesStreamProvider`. If stream errors, show last good composition + `TLog.w`.

### 10.3 Category detail

Reuse `ExpenseTimeframeScreen`. Add args:

```text
category: String?
period: PeriodRange
```

Header: total, count, avg, % of period, **line chart** of last 12 fiscal months (`ExpenseRepository.categoryMonthlySeries(category)`).

**Retry:** if the series query throws, show the txn list anyway (`TLog.e`), Retry button re-runs the series only.

### 10.4 Budget lines

Migration Drift vN:

```text
budget_lines(id, category, amount, period_key, updated_at)
```

`period_key = '0'` default; `'202609'` fiscal.  
Resolver:

```text
amountFor(category, fiscalKey) =
  latest budget_lines where category=X and (period_key=fiscalKey OR period_key='0')
  preferring exact fiscalKey, else '0'
```

When the user edits the global budget in `SetBudgetModal`:

- Write `period_key = currentFiscalKey` (this month snapshot) **and** `period_key='0'` for next months.
- MM: default change applies **next** month. Match that: `period_key='0'` is next-month-onward; current month row stays.

**Retry:** same as `setBudget` today (`TLog.e` + snackbar). Sync: include in expense sync payload when backend is ready; until then local-only is OK if documented. Do **not** fail the UI if cloud 5xx; queue like expenses.

### 10.5 SMS fingerprint + inbox

**Fingerprint:** `sha256(senderNormalized + '|' + yyyy-mm-dd + '|' + amountPaise + '|' + last4orMerchant)`.

Columns: `expenses.sms_fingerprint` nullable UNIQUE.  
Inbox table `sms_inbox(id, raw, sender, received_at, fingerprint, status=pending|accepted|rejected, last_error)`.

On `SmsDebitReceiver`:

1. Compute fingerprint.
2. If expense exists → drop (log `TLog.i` once).
3. If inbox pending with same fingerprint → replace raw, do not duplicate overlay.
4. Else insert inbox + show overlay.

**Retry overlay:** if parse fails, keep `status=pending`, `last_error`, show “Retry parse”. Transient parser exceptions: retry once after 400ms (same bound as STT). Permanent (no amount) → stay pending, never auto-create an expense.

Telegram: `TLog.e` on insert failure after 2 attempts. Never lose the SMS row.

### 10.6 Recurring job

```text
recurring_rules(id, type, amount, category, bank, card_type, repeat_code, next_date, end_date, comments)
```

On app resume + daily WorkManager:

```text
while next_date <= today (fiscal) and next_date <= end_date:
  insert expense if not exists (rule_id, next_date)
  next_date = advance(repeat_code, next_date)
```

Advance table = MM ids in §1 Step G. Installment: `n` child dates, amount `round(total/n)` with last month taking remainder (so rupees add up).

**Retry:** each occurrence insert is its own transaction. Failure on day 3 does not roll back day 1–2. `TLog.e` + retry next resume. Never generate duplicates (`UNIQUE(rule_id, occurrence_date)`).

### 10.7 Chart retry / robustness (all new charts)

Contract:

1. **Compute off the UI isolate** if > 2k points (`compute()` or SQL aggregate — prefer SQL).
2. Empty → `ExpenseEmptyChart(message: 'No data available.')`.
3. Error → last data if any, else empty + Retry.
4. `TLog.w` first failure, `TLog.e` after retry (same as `SttGatewayService`: 1 retry, 400ms, only transient).
5. No WebView. No animation longer than 300ms on first paint (MM Highcharts is 500ms; ours should stay snappy).
6. Tooltips: rupee formatted, never raw `12000.0`.
7. Accessibility: category name + amount, not colour-only.

### 10.8 Accuracy rules (do not regress)

- Every total that feeds a chart **must** use `spendOnly` unless the chart is the Investment/Loan/Moved series.
- Future-dated rows: in fiscal “this month” if their date is in range; **not** in rolling last-7/30 (Insights already documents this). After Step A, NT is `nextFiscalMonth`.
- CC lump-sum mode must not double-count payment + usage. Test both modes.
- Budget 0 with spend > 0 is 100% used, not divide-by-zero.
- MoM index with `lastOut == 0`: show “—” or `100` if `thisOut==0`, else skip % (our `meetsFloor` already hides tiny deltas). Prefer hiding over fake 100.

---

## 11. Edge-case catalogue (tests to write)

| # | Case | Expected |
|---|---|---|
| 1 | Empty month | All charts empty copy; budget remaining = full budget; pace `none` if budget 0 |
| 2 | Budget 0, spend > 0 | % = 100; pace skipped |
| 3 | Leap 29 Feb, monthStart=1 | length=29 |
| 4 | monthStart=25, today=10 Apr | fiscal month = 25 Mar–24 Apr |
| 5 | monthStart=25 on Saturday, shift=Friday | start = 24th |
| 6 | Future rent logged | In NT / that fiscal month; not in last-7 |
| 7 | Investment 50k | Not in pie, not in pace, in Moved |
| 8 | Loan EMI 20k | Same as 7 |
| 9 | Insurance 8k | Spend (unless product says otherwise) |
| 10 | Duplicate SMS | Second insert no-op |
| 11 | SMS parse fail | Inbox pending, no expense |
| 12 | Category renamed in picker | Old rows keep old string; pie has two bars until edited — **or** migrate. Document; do not silent-merge |
| 13 | Soft-deleted expense | Tombstone; charts exclude |
| 14 | Cross-device newer `updatedAt` | Server wins (existing) |
| 15 | Recurring already posted | Unique key, skip |
| 16 | Installment 3 × 10000 | 3334, 3333, 3333 (remainder on **first**, recovered from MM) |
| 17 | Pie 12 cats, 8 below 3% | Other = sum of those 8 |
| 18 | Top3 concentration < 70% | No `top3Concentration` fact |
| 19 | Δ ₹80 vs last month | Hidden (`rupeeFloor`) |
| 20 | CC lump-sum + usage same month | Expense totals show payment only |
| 21 | Debit card (when accounts exist) | Not in carry-over |
| 22 | Main budget 0, sub Food 3k + Travel 2k | Main displays 5k |
| 23 | Default budget changed on 10th | This month old; next month new |
| 24 | Heat hottest day 0 | All intensity 0, no NaN |
| 25 | `watchMonthTotal` during write | Stream re-emits; chart not stuck |
| 26 | STT gateway down | On-device text kept (already) |
| 27 | Select 5 txns | App bar sum = spend-only sum |
| 28 | Copy with today | New id, date=today, rest cloned |
| 29 | Hidden account (Step H) | Excluded from net worth if include-in-totals off |
| 30 | `IS_DEL` category | Budget row dropped (`cIsDel != 1`) |
| 31 | Tracker `remainingDays` vs Salary `daysRemaining` | Same calendar day must produce the **same** ₹/day after Step A (pick include-today; document it) |
| 32 | Ring 70% vs card 75% AT RISK | One threshold. Prefer 70% (ring) or pace’s 8% band — not both |
| 33 | Widget `date >= monthStart` no end | Must become `>= start && < nextFiscalStart` |
| 34 | Trend 3M/6M `month+2, 0` | Must not include next month after Step A |
| 35 | CC Investment on a card | In CC bill forecast; **not** in spend pie / budget remaining |
| 36 | Budget `setAt` after month-end | That history row must **not** apply to the closed month |
| 37 | Two expenses saved same millisecond | Do not use epoch-ms ids; use UUID (existing collision risk) |
| 38 | SMS `SBI` → HDFC | Do not copy; map SBI to its own bank or `Others` |
| 39 | Insights holds `watchExpenses()` full list | New Stats views must use SQL (`rangeSummary` / memory rollup) |
| 40 | `clear all` easter egg | Does **not** wipe salary; nuke does. Document in UI copy |
| 41 | `ASSETS.ZDATA=1` with txs | Still in period stats; hidden (`2`/`3`) drop from lists |
| 42 | `ZDATA2='1'` | Excluded from net worth |
| 43 | `STATUS!=2` but `pUid` set | Row **is** the main (“subcategory-as-main”) |
| 44 | Transfer fee sibling | `DO_TYPE=1` already inside expense; do not add parent+fee |
| 45 | Budget `PERIOD_TYPE` other than 6 | MM does not persist those; UI-only. Nexus: fiscal month only |
| 46 | Search `SearchService.java` | Empty stub. Filters live in `Search.java` `U()` |

---

## 12. File map (Nexus)

| Task | Touch |
|---|---|
| Period engine | **new** `lib/core/services/expense_period_engine.dart` + test |
| Composition | **new** `lib/core/services/expense_composition.dart` + test; `tracker_tab.dart` |
| Pie drill | `tracker_tab.dart`, `expense_timeframe_screen.dart` |
| Category series | `expense_repository.dart` (`categoryMonthlySeries`), `ExpenseMonthlyCategory` |
| Budget overlay | `budget_history_modal.dart`, `set_budget_modal.dart`, Drift `budget_lines` |
| Heat ₹ | `tracker_tab.dart` heat cell |
| Unify Insights periods | `insights_tab.dart` `expensesInInsightPeriod` |
| SMS fingerprint / inbox | `app_database.dart`, `sms_auto_expense_service.dart`, Kotlin `SmsDebitReceiver` |
| Recurring | **new** table + `lib/data/services/recurring_expense_service.dart` |
| CC cycle | `lib/core/services/credit_card_forecast_engine.dart` + `Bank.statementDay`/`dueDay` in `settings_controller.dart`. **No new table** |
| Salary remaining-days | `lib/domain/entities/salary_entities.dart` — align with `ExpensePaceMetrics.monthPace` |
| Widget month clamp | `ExpenseWidgetLogic.kt` + `expense_widget_service.dart` |
| Join-string | Settings + `sms_parser.dart` |
| Empty chart | **new** `lib/presentation/screens/expense/widgets/expense_empty_chart.dart` |
| TLog retry helper | Reuse patterns in `stt_gateway_service.dart` — extract `RetryOnce.transient` if you touch 3+ services |

**Do not** rewrite `ExpenseInsightEngine` tokens except add `momIndex`, `cashOut`, `debitOut`, `ccOut`, `moved`. The AI layer stays grounded.

MM dump files to re-open if a formula is disputed:

| Topic | File |
|---|---|
| CREATE TABLE | `sources/com/realbyte/money/database/database/DBHelper.java` |
| Totals SQL | `.../database/query/DBQuery.java` |
| Total page math | `.../database/service/budget/BudgetService.java` `c()` |
| Budget % / period key | `.../database/service/budget/BudgetUtil.java` |
| Pie JSON | `.../ui/stats/StatsExpensesFragment.java` `a()` |
| Budget overlay series | `.../ui/stats/BudgetDetail.java` |
| Fiscal month | `.../utils/date/DateUtil.java` `y` / `r` / `z` |
| Repeat ids | `resources/res/values/arrays.xml` `repeat_string` |
| Chart templates | `resources/assets/chart/*.html` |
| Copy / edge strings | `resources/res/values/strings.xml` |

---

## 13. Retry, logging, accuracy (non-negotiable)

Copy the STT pattern the app already uses:

| Event | Policy |
|---|---|
| Transient (timeout, 5xx, connection) | **1 retry**, 400ms pause, fresh work each time |
| Permanent (unique-constraint duplicate SMS, 401, validation) | No retry |
| User-visible | Never block typing / scrolling on a retry |
| Logs | `TLog.w` on attempt 1 fail; `TLog.e` after exhaustion (immediate Telegram flush) |
| Idempotency | SMS fingerprint, recurring `(rule_id, date)`, budget `(category, period_key)` |
| Charts | Last-good snapshot; Retry chip; no spinner longer than 1s |
| Sync | Existing `updatedAt` LWW + tombstones. New tables follow the same |
| Money | Integer rupee display; remainder on **first** installment (MM); never `NaN`/`Infinity` in a label |

Do not add a third logger. Do not `print` amounts.

---

## 14. Suggested PR slices

1. Period engine + tests + convert Insights/Tracker/Trend/Salary/Widget (no UI redesign).
2. Composition strip + MoM index + heat ₹ + pie drill + Other bucket.
3. Category history line on timeframe.
4. Budget period snapshot + overlay on existing budget history chart.
5. SMS fingerprint + inbox persistence.
6. Category budgets (optional per cat).
7. Recurring + installments.
8. CC cycle settings.
9. Income/transfer (product call).
10. Accounts / net worth (only if explicitly asked).

Stop after 2 and the app is already more informative than today. Stop after 4 and we have MM’s Stats+Budget *ideas* without becoming a Korean ledger clone.

---

## 15. What “done” looks like

A user can, in one fiscal month:

1. See **one** period on Tracker and Insights (same rupee total).
2. See **where money went**: Cash / Debit / CC / Moved, and MoM index.
3. Tap Food on the pie → Food’s year line + those transactions.
4. See budget **line vs spend bars** for the last 6 months, and remaining that matches the ring.
5. Duplicate bank SMS does not create a second expense.
6. Charts never crash on empty / zero budget / leap day.
7. AI still only speaks tokens from `ExpenseInsightEngine` (now including composition + momIndex).

If any of those fail, the PR is not done — even if the charts look like Money Manager.
