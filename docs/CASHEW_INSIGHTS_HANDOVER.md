# Cashew → AI Nexus expense handover

**Audience:** any developer implementing Cashew-grade analytics, budgets, recurring bills, charts, and tracking on top of the existing Nexus expense module.  
**Cashew dump:** JADX of `com.budget.tracker_app` **6.6.11** (`versionCode` 510) at `C:\Users\Beast\Downloads\Cashew`.  
**Cashew public source (algorithms):** `jameskokoska/Cashew` `budget/lib` (clone analysed: **5.4.3+416**, schemaVersion **46**). The APK is newer than that tag and adds Intelligence, mailbox, notification-scanner templates, and local deep links — those extra strings are taken from the APK `en.json`.  
**Nexus home today:** Flutter `ai_nexus/lib/presentation/screens/expense/` + `core/services/expense_*` + Drift `expenses` / `budget_entries` / `salary_entries`. Production API is `ainexus/api/src/index.js`, **not** the legacy SQLite demo in `ainexus/routes/expenses.js`.

Read this as an **implementation spec**, not a clone brief.

Cashew is **GPL-3.0**. Do **not** copy Cashew Dart, widgets, assets, or SQL. Re-implement the *ideas and formulas* in our architecture (Riverpod, Drift, local-first, tombstones, Telegram `TLog`, grounded AI). If a sentence below describes Cashew internals, it is so you can reproduce behaviour independently.

---

## 0. One-screen truth

| Surface | Cashew | Nexus today | Verdict |
|---|---|---|---|
| Ledger | Signed amounts on **wallets**. Expense negative, income positive. Transfers are paired balance-correction rows. | Unsigned **spend** rows. Bank is a **label**. Salary is a sidecar, not a transaction. | Take wallet/transfer *ideas* later. Do **not** flip our amount sign without a migration plan. |
| Budget | Many budgets, cycles, category limits (% or ₹), added-only vs all-transactions, savings vs expense polarity | **One** global monthly number + append-only history | **Take** category limits + period history. Keep one primary “lifestyle” budget. |
| Recurring | Upcoming / subscription / repetitive with pay, skip, auto-pay, overdue | Subscription is only a **category name** | **Take** — highest missing value for India bills |
| Income | First-class transactions | Salary one-row-per-month only. SMS **drops credits**. | **Take** income rows; keep salary as the in-hand forecast input |
| Accounts | Real balances, FX via USD pivot | HDFC/ICICI/AXIS/SCAPIA/CASH labels + CC statement/due config | Keep our **CC forecast** (Cashew has none). Add balances only if we introduce wallets. |
| Charts | Cumulative/per-day line, GitHub heatmap, pie with tap-to-filter, budget pace overlay, period history | Pace, month heat, pies, trend line, weekday bars, merchants, 3/6/12 month bars | **Take** cumulative vs per-day, budget pace line, period history. Unify our broken period chips first. |
| Insights | Totals + averages over **completed** periods (skip zeros, skip current) | Grounded AI tokens + range facts + salary/CC | Keep AI. Steal Cashew’s *average-of-completed-periods* rule. |
| Capture | NL Intelligence, receipt photo, notification templates, CSV, Google Sheet mailbox | SMS India banks, voice STT gateway, scan/PDF, smartParse | **Keep ours.** Do not replace SMS with Cashew’s generic notification parser. |
| Sync | Firebase + Google Drive backups | Local-first PG + tombstones + NAS | Keep ours. **Add durable expense outbox** (salary already has it). |

**You already have the hard India-specific product:** SMS debit parse, salary day 28 vs CC due, Investment/Loan excluded from lifestyle spend, grounded AI that cannot invent rupees. Cashew’s product is a **general ledger + period engine + recurring lifecycle**. Steal that. Do not steal theme packs, IAP, Drive mailbox, or GPL code.

---

## 1. Recommended build order (do this, in this order)

Each step is independently shippable. Stop after any step and Expense still works.

### Step 0 — Fix waste in *our* setup (no Cashew UI required)

Do this **before** adding features. Otherwise new charts inherit the bugs.

1. **One period engine** used by Tracker, Insights, Trend modal, timeframe, widget, web.  
2. **One at-risk threshold** (pick **75%**; ring currently uses 70%).  
3. **One remaining-days rule** (include today; salary `safeToSpendPerDay` currently excludes it).  
4. **Strip Investment/Loan** from 9 PM recap and CC monthly totals (they currently leak in).  
5. **Durable expense outbox** on the existing `sync_queue` (salary already drains it).  
6. **SMS `bankFrom`** must not map SBI → HDFC.

Until Step 0 ships, do not add a second budget type or a new chart that takes a period chip.

### Step A — Shared `PeriodRange` (Cashew `CycleType`)

Cashew stores a period **per surface** (`""`, `"PieChart"`, `"NetWorth"`, `"AllSpendingSummary"`, `"OverdueUpcoming"`). We need one type, many stored keys.

```dart
enum PeriodKind { allTime, calendarMonth, rollingDays, dateRange, nextMonth }

class PeriodRange {
  final PeriodKind kind;
  final DateTime? start; // inclusive, local date 00:00
  final DateTime? end;   // exclusive, or null = open
  final int? rollingDays;
  final String label;    // 'Today' | '7D' | 'Month' | ...
}
```

Canonical windows (local, `now` date-only):

| Label | Kind | Start | End |
|---|---|---|---|
| Today | dateRange | today 00:00 | tomorrow 00:00 |
| 7D | rollingDays 7 | today−6 | tomorrow 00:00 |
| Month | **calendarMonth** | 1st of this month | 1st of next month |
| 3M | calendarMonth×3 | 1st of (month−2) | 1st of next month |
| 6M | calendarMonth×6 | 1st of (month−5) | 1st of next month |
| All | allTime | epoch | null (includes future) |
| NT | nextMonth | 1st of next month | 1st of month after |

**Today is the last day of every bounded window except All/NT.** Future-dated rows belong in All and NT only.

Replace:

- Tracker `1M` (already calendar month)  
- Insights `Month` (currently last **30 days**)  
- Trend modal `Month` (calendar) vs `3M/6M` that currently overshoot into **next** month  
- Web Tracker `1m` (rolling ~30 days)

**Tests:** `expense_period_range_test.dart` with a frozen `now`. Cover month-end (31 Jan), IST offset, future CC bill, NT.

### Step B — Recurring bills (Cashew upcoming / subscription / repetitive)

This is the largest missing *idea*. India users have rent, SIPs, Netflix, EMIs. Today those are either forgotten or logged as one-off spend.

### Step C — Budget remaining copy + pace line + ghost unpaid + today marker

We already compute `MonthPace`. Cashew’s UI is clearer. Add category limits on the **existing** monthly budget before inventing multiple budgets.

### Step D — All-spending summary + cumulative graph + completed-period averages

One page: income, expense, net, overdue, investments, loans. History tab of past calendar months.

### Step E — Associated titles + pin/duplicate

We have `category_learnings` (word → category). Cashew has **title → category** with recency order. Pin last-2-months frequent merchants on long-press `+`.

### Step F — Optional wallets + transfers

Only after A–E. Bank labels plus CC forecast already cover 90% of Indian card use. Wallets are for “what is my cash + bank balance”.

### Step G — Do not take

Listed in §11.

---

## 2. What Nexus already does better (do not replace)

| Nexus feature | Why it stays |
|---|---|
| SMS auto-expense (`sms_auto_expense_service.dart` + Kotlin `BankSmsParser`) | Cashew’s notification templates are generic; ours know HDFC T1–T8, Axis, ICICI, Scapia, UPI. On-device. |
| Voice STT gateway (`stt-gateway` + `HoldToSpeakController`) | Cashew Intelligence sends text to Gemini. We already have on-device STT + Groq Whisper + domain vocab. |
| `smartParse` + learnings | NL add already exists. |
| Salary + `CreditCardForecastEngine` | Cashew has **zero** statement-day / due-day / salary-credit-day 28 logic. |
| `isNonSpendCategory` (Investment, Loan) | Cashew uses filters to drop loans from “income/expense only”. We have a single source of truth. |
| Grounded AI (`ExpenseInsightEngine` + `insight_grounding.dart` + `expense-insight.js`) | LLM may only phrase `{{tokens}}`. Cashew Intelligence can hallucinate amounts. |
| Memory rollup `expense_monthly_category` | O(1) facts regardless of row count. |
| Tombstones + LWW `updatedAt` | Cashew Firebase sync is a different model. |
| Pace floors ₹100 / 5% / 8% | Prevents noisy “you spent ₹12 more” facts. |

---

## 3. Waste in our setup that Cashew would not ship

These make *our* analytics less informative even before we add Cashew ideas.

### 3.1 Period chips do not mean the same thing

| Surface | “Month” | File |
|---|---|---|
| Tracker analysis `1M` | This **calendar** month | `tracker_tab.dart` |
| Insights `Month` | Last **30 days** | `insights_tab.dart` `expensesInInsightPeriod` |
| Trend modal `Month` | Calendar month | `expense_trend_modal.dart` |
| Trend `3M`/`6M` | Starts at month-start of −2/−5, **ends last day of next month** | same |
| Web Tracker spend | Rolling `1m` | `ainexus-web` `inPeriod` |
| Widget / ring / pace / heat / salary | Calendar month | various |

**Fix:** Step A. One helper. Every chip calls it.

### 3.2 At-risk colour is not one number

| Surface | Green | Amber | Red |
|---|---|---|---|
| Budget ring | `< 70%` | `≥ 70%` | `≥ 100%` |
| Tracker card | else | `> 75%` | over |
| Insights strip | else | `> 75%` | over |

**Fix:** `kBudgetAtRiskRatio = 0.75` in `expense_pace_metrics.dart`. Ring, card, strip, widget all import it.

### 3.3 Remaining days disagree

```
Pace remainingDays = max(1, lengthOfMonth − dayOfMonth + 1)  // includes today
Salary daysRemaining = daysInMonth − dayOfMonth              // excludes today; 0 on last day → treated as 1
Widget per-day     = balance / (daysLeftMonth + 1)           // includes today
Cashew remainingDays = (periodEnd.date − today.date).inDays + 1
```

**Fix:** one `remainingDaysInclusive(today, periodEnd)` used by pace, salary safe/day, widget, Cashew-style copy.

### 3.4 Non-spend leaks

`isNonSpendCategory` is skipped in spend charts, but:

- 9 PM recap (`notification_service.dart`) sums **all** of today’s rows  
- CC monthly totals (`watchMonthlyCardSpendTotals`) filter `cardType == 'CC'` only, so a CC SIP still hits the bill forecast  

**Product decision (implement this):**

- Recap: spend-only. Mention investments/loans in a second line if present.  
- CC forecast: **include** Investment/Loan on CC. A SIP charged to the card **is** a bill against salary. Document it. Do not strip.

### 3.5 Expense writes have no durable outbox

`ExpenseRepository._syncPostWithRetry`: 3 attempts, `400ms * attempt`, then snackbar **“Sync failed — saved locally”**. Next launch **pulls** and does **not** push leftover local-only rows. An offline add is trapped on that phone until the user edits it.

Salary already queues on `sync_queue`.

**Fix:** after 3 POST failures, insert `sync_queue` entity `expense` with the full JSON. On open (after remote-nuke check, before `syncFromServer`): `drainSyncQueue()` like salary. Same for DELETE (queue the id). Idempotent: server upsert-by-id.

Retry policy (copy salary, do not invent a fourth):

| Attempt | Delay | Transient (timeout, 5xx, 429) | Permanent (401, 404, 422) |
|---|---|---|---|
| 1 | 0 | retry | fail + `TLog.e`, do not queue 401 |
| 2 | 400 ms | retry | — |
| 3 | 800 ms | queue + `TLog.e` | — |

Telegram: `TLog.e` on final failure (flush). `TLog.w` on attempt 1–2. Never throw into the UI.

### 3.6 Insights tab is a second app

`insights_tab.dart` is thousands of lines: salary, investments, loans, range facts, KPI carousel, budget strip, trend, weekday, category/bank/card, merchants, high/low, remaining list. Tracker already has pie, heat, historic bars, trend entry.

**Cashew pattern:** home is **composable widgets** the user can hide. Default-on is small.

**Fix (Step D UX):** Insights default = salary + 2 range facts + category breakdown + Ask AI. Move weekday / merchants / high-low behind “More stats” or the All-spending page. Do not delete the engines; hide the chrome.

### 3.7 Widget calendar bars are clock, not money

Native widget draws month/year **elapsed time** bars. Cashew’s home widgets are money. Either bind those bars to spend intensity or remove them so they stop looking like a heat chart.

### 3.8 Budget is not month-keyed

`currentBudget = latest budget_entries.amount`. Changing April’s budget in May rewrites how April is judged.

Cashew budgets have `startDate` + recurrence, so January and February are different periods of the **same** budget object.

**Fix (with Step C):** when the user sets a budget, write `{id, amount, setAt, month: 'YYYY-MM'}`. Lookup: this calendar month, else most recent previous month (carry-forward). History modal already lists `setAt`; add the month column. API: extend budget JSON, default `month` from `setAt` for old rows.

### 3.9 Hardcoded banks vs Settings banks

Constants: `HDFC, ICICI, AXIS, SCAPIA, CASH`. Settings can add banks. SMS `bankFrom` still snaps unknowns (and **SBI**) to HDFC.

**Fix:** SMS maps using configured bank names (substring, case-insensitive). Unknown → `CASH` or a new `OTHER`, never silently HDFC. SBI stays SBI if configured, else OTHER.

---

## 4. Cashew data model (ideas only)

Do **not** recreate Cashew’s 20-table Firebase schema. Map onto Drift incrementally.

### 4.1 Transaction lifecycle (the important part)

Cashew amount is **signed**. Nexus amount is **always positive spend** (or investment/loan). Keep our sign. Add a `kind` enum instead:

```text
ExpenseKind:
  spend        // default, counts in lifestyle totals
  income       // salary extra / refund / freelance; NOT the salary sidecar
  transfer     // later, Step F
  investment   // existing category, kind can be derived
  loan         // existing category
  recurring    // template / occurrence — see §5
```

Until Step F, do **not** add transfer.

Cashew `paid` / `skipPaid` matter for recurring:

| State | Counts in spend / budget / net? |
|---|---|
| Normal spend (our current row) | Yes |
| Recurring occurrence, unpaid | **No** |
| Recurring occurrence, skipped | **No** |
| Recurring occurrence, paid | **Yes**, date = pay day (or original due if setting on) |
| Income occurrence, unpaid | No |
| Income occurrence, deposited | Yes |

That is the whole overdue/upcoming trick: **unpaid scheduled rows are visible but not money**.

### 4.2 What Cashew stores that we should *not* copy yet

- Shared-budget Firebase members  
- `transactionOwnerEmail`  
- Multi-currency `currencyFunctions` (USD pivot). We are INR.  
- `ScannerTemplates` (we have SMS templates)  
- `AppSettings` JSON blob — use existing SettingsController  

---

## 5. Feature specs (implement these)

Each spec: **why**, **data**, **algorithm**, **edge cases**, **retry**, **tests**, **UI**, **files**.

---

### Spec 1 — Recurring bills (Step B)

**Why:** Rent, SIPs, Netflix, insurance. Cashew’s subscriptions page answers “what hits me this month” with monthly/yearly/total annualization. We have a Subscription **category** and no calendar.

#### Data (Drift `recurring_rules` + occurrences as expenses)

Prefer **one rule + generated occurrences**, not Cashew’s “pay mutates the row and inserts a child”.

```text
recurring_rules
  id            TEXT PK
  title         TEXT           // 'Netflix'
  amount        REAL           // always positive
  kind          TEXT           // spend | income
  category      TEXT
  bank          TEXT
  cardType      TEXT           // DB | CC | Cash
  comments      TEXT
  periodUnit    TEXT           // daily | weekly | monthly | yearly
  periodLength  INT            // 1 = every month, 2 = biweekly if weekly, etc.
  startDate     TEXT           // 'YYYY-MM-DD' first due
  endDate       TEXT?          // null = forever
  autoPay       BOOL           // default false for Nexus (Cashew defaults true — too aggressive for us)
  notify        BOOL           // default true
  nextDue       TEXT           // cached next unpaid due date
  createdAt / updatedAt
```

On due (or on app open): ensure an **occurrence expense** exists:

```text
Expense.id        = 'recurring:{ruleId}:{dueDate}'   // idempotent
Expense.date      = dueDate (local noon, same as SMS policy)
Expense.amount    = rule.amount
Expense.category  = rule.category
+ new fields:
  status          = unpaid | paid | skipped     // default paid for normal rows
  recurringRuleId = ruleId
  dueDate         = dueDate                     // original due, survives pay-date shift
```

Migration: existing expenses `status = paid`, `recurringRuleId = null`. Spend aggregations: `status == paid` AND NOT `isNonSpendCategory`. Unpaid/skipped never enter memory rollup.

#### Pay / skip / deposit

| Action | Write | Next occurrence |
|---|---|---|
| Pay (spend) | `status=paid`. Optional: set `date` to today unless `payOnOriginalDay` | Insert/ensure next due `unpaid` |
| Skip | `status=skipped`, do not count | Same next due |
| Unpay | `status=unpaid`, remove from totals | Do **not** delete the already-created next row |
| Deposit | Same as pay for `kind=income` | Same |

**Pay date default:** stamp **today** (Cashew default). Overdue rent paid on the 12th hits this month’s budget — that is what users feel. Setting `payOnOriginalDay` keeps the due month (needed for “I paid April rent on May 2 but it is April’s bill”).

#### Auto-pay

Cashew defaults **on** and loops up to **50** children so a spawned overdue child is also paid. That silently inflates spend when someone opens the app after a vacation.

**Nexus default: OFF.** If user enables per-rule `autoPay`:

- Only if `dueDate < today 00:00 + 1 minute`  
- Only if occurrence is still `unpaid` (never auto-pay a skipped or user-unpaid row — store `autoPayLocked=true` after manual unpay)  
- Loop at most **12** times per rule per session (a yearly bill should not spawn 50)  
- `TLog.i` each auto-pay; `TLog.w` if loop hits cap  

#### Overdue vs upcoming (lists, not money)

```
overdue  = status==unpaid && dueDate < today && kind spend|income
upcoming = status==unpaid && dueDate >= today
```

Homepage/widget numbers for overdue/upcoming **sum unpaid amounts**. They do **not** enter the budget ring.

Period filter on those boxes: optional. Default **all unpaid** (Cashew’s list page ignores homepage cycle; the homepage box *can* follow a cycle). For Nexus v1: **all unpaid**, always. Simpler, matches “bills I still owe”.

#### Subscriptions math (Cashew `getTotalSubscriptions`)

For the Recurring page header, one number with Monthly / Yearly / Total:

Let `L = periodLength` (skip if `L == 0`). `daysInMonth` / `daysInYear` of **current** calendar.

**Monthly equivalent:**

- daily: `amount * daysInMonth / L`  
- weekly: `amount * (daysInMonth / 7) / L`  
- monthly: `amount / L`  
- yearly: `amount / 12 / L`  

**Yearly equivalent:**

- daily: `amount * daysInYear / L`  
- weekly: `amount * (daysInYear / 7) / L`  
- monthly: `amount * 12 / L`  
- yearly: `amount / L`  

**Total:** raw `amount` (no annualizing).

Use **absolute** rupees. Income rules subtract on the header if we show net; v1 show two numbers (to pay / to receive).

#### Edge cases

| Case | Behaviour |
|---|---|
| Amount 0 | Reject save |
| `periodLength <= 0` | Coerce to 1 |
| Feb 31 start | Clamp due day to last day of that month every occurrence (`DateTime(y, m+ n, d)` in Dart already overflows — **do not** use that). Helper: `addMonthsClamped(date, n)` using `min(day, lastDayOfTargetMonth)`. |
| End date | Next due after `endDate` is not created |
| Duplicate id | Unique constraint on `recurring:{ruleId}:{dueDate}` = success (like SMS `sms-{id}`) |
| Delete rule | Occurrences already **paid** stay (history). Unpaid/skipped occurrences deleted. Confirm copy: “Paid history is kept.” |
| Edit amount | Future unpaid occurrences update; paid do not |
| Offline pay | Local status paid immediately; queue expense upsert |
| Remote nuke | Rules table wiped with expenses (extend `expense_nuke_service`) |
| Investment SIP as recurring | Category Investment → occurrence is non-spend; still shows on Recurring page; does not eat budget |
| CC recurring | `cardType=CC` → occurrence included in CC forecast **when paid** (or when unpaid if we decide unpaid card bills should forecast — v1: only paid, plus a “upcoming CC” line on salary card) |

#### Retry / sync

- New tables sync: `GET/PUT /api/v1/recurring` with LWW `updatedAt`.  
- Occurrences are normal expenses (existing upsert + tombstones).  
- Rule delete: tombstone `deleted_recurring`.  
- Drain: rules queue entity `recurring` + existing expense queue.  
- 3 attempts, 400ms × attempt, then durable queue. `TLog.e` on final.  
- Idempotent occurrence ids make double-open / double-sync safe.

#### Tests

`recurring_engine_test.dart`: clamp months, skip vs pay totals, auto-pay cap 12, unpay lock, investment category excluded from spend, unique id, endDate, yearly annualization numbers with a fixed 31-day month.

#### UI

- Tracker: compact **Overdue (n) · ₹X** chip if `n>0`, tap → Recurring page.  
- Recurring page: list grouped Overdue / This week / Later. Swipe pay / skip.  
- Add expense: toggle “Repeat” → unit + length + end.  
- Widget: optional overdue count (do not drop today spend).  
- 9 PM recap: if overdue unpaid, mention count (spend-only recap still excludes them from ₹ total).

#### Files

New: `lib/core/services/recurring_engine.dart` (pure), `lib/data/repositories/recurring_repository.dart`, Drift tables, `lib/presentation/screens/expense/recurring_page.dart`.  
API: `ainexus/api/src/index.js` recurring routes mirroring expenses.  
Web: later.

---

### Spec 2 — Budget remaining sentence + today marker + ghost bar + pace line (Step C)

**Why:** We already have `MonthPace` (`expectedByNow`, `safeDaily`, `aheadOfPace`). Cashew’s sentence is what users quote: *“You can spend ₹420/day for 11 more days.”* Our banner is vaguer.

#### Copy (expense budget, under budget)

```
You can spend {format(safeDaily)}/day for {remainingDays} more day(s)
```

Cashew keys: `spending-tracking` + amount + `/day` + `for N more days`.

Over budget:

```
{format(monthSpent − budget)} over {format(budget)} for {remainingDays} more day(s)
```

Out of range (should not happen for calendar-month budget): show nothing.

Savings-style (if we add a savings budget later): `You should save ₹X/day…`.

#### Today marker on the ring / bar

Cashew: `todayPercent = (now − start) / (end − start + 1 day) * 100`.

```
lengthMs = (periodEndExclusive − periodStart)   // already exclusive end in our PeriodRange
todayPercent = (today 00:00 − start) / lengthMs
```

Draw a tick on the budget bar at `todayPercent`. If spend percent >> today percent → ahead of pace (same as `MonthPace` threshold). If today is outside 0–1, hide the tick (past months).

#### Ghost bar (unpaid recurring in this period)

```
ghost = sum(amount) of recurring occurrences in this calendar month with status==unpaid
```

Draw a lighter extension of the spent bar. **Do not** add ghost to `monthSpent`. Tooltip: “₹X in unpaid bills this month”.

#### Pace line on the trend / timeframe monthly chart

Cashew budget graph: horizontal expected spend `budget * (t − start) / (end − start)` for an in-progress period; full `budget` for completed periods.

On `expense_trend_modal` and timeframe monthly bars, overlay a dashed **expected** series. Hide if budget is 0.

Optional: previous 2 months at 40% opacity (`showPastSpendingTrajectory`). Nice, not v1.

#### Category spending limits

Cashew: per (budget, category) limit as **percent of budget** or **absolute ₹**. Over if `|spent| > limit`.

Nexus v1: attach to the **single** monthly budget.

```text
category_budget_limits
  category TEXT PK
  kind     TEXT   // percent | amount
  value    REAL   // 0–100 or rupees
  updatedAt
```

Display on Insights category rows and Tracker pie legend: spent / limit, colour at 100%. Subcategories: not in v1 (we have no subs).

**Defaults off.** Empty table = current behaviour.

Smart tip that mentions “sub-limit” today is lying — wire it to this table or delete the copy.

#### Past budget periods + averages

Cashew history: load 8 periods, “view more” adds 3/5. Average = `(sum of category across loaded periods) / (count of periods whose total ≠ 0)`. **Current incomplete period excluded. Zero periods excluded.**

Use calendar months, spend-only, budget-for-that-month from Spec 3.8 carry-forward.

```
avgMonthly = sum(monthTotals where month < current AND total >= rupeeFloor) 
           / count of those months
```

Show on Insights under historic bars. This is more honest than `lifetimeTotal / monthsTracked` (which includes the in-progress month and zeros).

Keep `MemoryFacts.avgMonthlyTotal` for AI or switch the token to this definition — **do switch**, and update `expense_insight_engine_test`.

#### Edge cases

| Case | Behaviour |
|---|---|
| Budget 0 | No sentence, no pace line, no today tick required, ring stays “SET BUDGET” |
| remainingDays computed 0 | Cashew adds 1. We already `max(1, …)`. Keep. |
| Ghost > leftover | Bar can exceed 100% visually; spent number does not |
| Category limit 0 | Treat as unset, not “zero allowed” |
| Percent limit > 100 | Clamp 100 on save |
| Absolute limit > budget | Allowed (e.g. Food 15k on 10k budget is a user error — warn, don’t block) |

#### Retry

Limits: same 3-try POST `/api/v1/budget/category-limits` + queue entity `budget_limits`. Budget month key: extend existing budget payload.

#### Tests

Extend `expense_pace_metrics_test.dart` with copy-string golden tests (no UI). `todayPercent` at start of month ≈ 0, last day ≈ 1. Averages skip current and zeros.

#### UI

Tracker under the ring: the sentence. Ring: today tick. Insights category rows: limit bar if set. Set-budget modal: “Category limits” expander.

---

### Spec 3 — Graphs: cumulative vs per-day, heatmap, pie tap (Step D)

#### 3a Cumulative vs per-period line

Cashew `calculatePoints`:

1. Bucket paid amounts by calendar day.  
2. Optional **starting level** = sum of everything **before** graph start (`getTotalBeforeStartDate…`). Debug flag can zero this.  
3. **Cumulative (default):** running sum.  
4. **Per-day:** that day’s sum only (heatmap uses this).  
5. If distinct days > ~500, downsample.  
6. Hide graph if **only one point** (`hideIfOnlyOneEntry`) or all zeros (`showIfNone: false`).

Nexus `expense_trend_modal` is per-bucket, not cumulative. Add a toggle **Running total | Each day**. Default running total for 3M/6M/All; each day for Week/Month.

Starting level for All: 0. For Month: 0 (month is self-contained). For 6M: 0 unless we want lifetime context — v1 start at 0 so the line matches the period total.

Polarity: our amounts are positive spend. Line goes **up** as you spend (Cashew inverts signed expenses). Do not import their invert flag.

#### 3b Heatmap (GitHub style)

We have a **current-month** heat calendar (`ExpensePaceMetrics.heatMonth`). Cashew shows **5 months** (phone) / **10** (tablet), expense red vs income green, 4 opacity bands, tap → day sheet.

**Take:** extend heat to last 5 calendar months, scroll to load +1. Intensity: 4 bands between min and max **spend** (we have no daily income yet; when income rows exist, split scales).

```
band = 1..4 from equal-width [minPositive, max]
opacity ≈ 0.5 + 0.125 * band
zero days = muted gray
future = empty
padding week cells = transparent
```

First weekday: Settings (Cashew `firstDayOfWeek`). India default **Monday**.

Tap: already opens timeframe for that day (`onOpenDay`). Keep.

Do not include Investment/Loan. Do not include unpaid recurring.

#### 3c Pie tap-to-filter

Cashew home pie: tap slice → select category, % of total, tap row → search filtered to that category + pie period. Subcategory remainder = parent − children (we have no subs). Strip zero-total cats so touch indexes stay correct. Legend top 3 (or 5 if width > 320).

Nexus Tracker pie is top-5 already. **Add:** tap slice → `onOpenTimeframe` **pre-filtered to that category** (timeframe screen already has category chips — pass `initialCategory`).

Empty copy: “No spend in this period” + period chip, not a blank chart frame.

#### 3d All-spending summary page

Cashew `WalletDetailsPage(wallet: null)`:

| Row | What | Nexus mapping |
|---|---|---|
| Net | paid income − paid expense + corrections | `income − spend` (v1 no corrections) |
| Expense | paid spend excluding loans/corrections | our spend-only |
| Income | paid income | salary **plus** income rows when Spec 4 exists; until then show **Salary this month** as income |
| Balance correction | category `"0"` | skip until wallets |
| Lent / borrowed | P2P loans | skip or map to Loan category card we already have |
| Upcoming / Overdue | unpaid scheduled | Spec 1 |

History tab: one card per past calendar month: net, expense, income. Graph: **per-period** two lines or **cumulative** net. Zero months hidden until “view more”. Average footnote: completed periods only (§ Spec 2).

**New month tip** (Cashew string `new-month-tip`): on first open of a new calendar month, snackbar “A new month has started — open Insights for trends.” Once per month, SharedPreferences `lastNewMonthTip=YYYY-MM`.

#### Edge cases

| Case | Behaviour |
|---|---|
| One data point | Hide line graph; keep the number |  
| All zeros | Hide graph, show empty copy |  
| 500+ day All | Downsample to ≤ 500 points, keep endpoints |  
| Heat max = 0 | All intensity 0 |  
| Pie of one category 100% | Still tappable |  
| Period All + future bills | Line includes future days only in All; heat never paints future |

---

### Spec 4 — Income as first-class rows (after recurring)

Salary stays the **in-hand** number for CC forecast (`kSalaryCreditDay = 28`). Extra income (freelance, refund, cash gift) must not overwrite salary.

```text
Expense.kind = income
Expense.amount > 0
NOT counted in spend, ring, pace, heat-spend
Counted in All-spending Income box and net
```

SMS: continue **dropping credits** unless we add an explicit “log this credit” on the review sheet (ask-mode). Do not auto-log salary SMS as income **and** salary sidecar (double count).

Refunds: user logs income, category original (Food refund) or a Refund category. Net for that category = spend − refunds in All-spending; lifestyle ring stays spend-only unless we add “include income in budget” (Cashew `includeIncome`, default **off**). **Keep off.**

---

### Spec 5 — Associated titles + pin / duplicate

**Learnings today:** words length > 3 from description → category, fire-and-forget sync.

Cashew titles: substring match `LIKE %title%`, order by recency, then complete last word, then category name. Duplicate exact title for same category is **moved to top**, not duplicated. `isExactMatch` is stored and **unused** — do not copy that dead field.

**Upgrade:**

```text
category_learnings: keyword PK, category, hits INT, updatedAt
```

On save: store **full description** (trimmed, casefold) as well as tokens. Lookup: exact description first, then `contains`, then token map. Cap 500 rows, LRU by `updatedAt`.

**Pin / duplicate (Cashew long-press +):**

- Frequent = last 60 days, spend-only, group by `(description, category, amount)` count ≥ 2, top 8.  
- Pin table `pinned_expenses(id, expenseSnapshot JSON, order)`.  
- Tap pin → `addExpense` new id, **today’s date**, same amount/category/bank.  
- Long-press FAB → sheet of pins + frequents.

SMS merchants with `@` already write `sms_merchant_labels` (device-local). On pin, offer to promote that VPA into learnings (synced).

Retry: learnings already POST per word (noisy). Batch: debounce 1s, one POST of the map. 3 tries + queue entity `learnings` (we already retry pending **clear**; add pending **put**).

---

### Spec 6 — Activity log (undo delete)

Cashew: recently deleted/modified transactions; restore if category still exists.

We have server **tombstones** (`deleted_expenses`) but the UI cannot restore.

**v1:** on local delete, keep a `deleted_expense_log` row (full JSON + `deletedAt`) for 30 days, max 100. Snackbar “Undo” 5s already? If not, add it. Restore = upsert original id (clears tombstone on server — existing behaviour).

If category was a user category we don’t have (future): block restore with Cashew’s copy “The original category has been deleted”.

---

### Spec 7 — Bulk edit + exclude from budget

Cashew: multi-select change category / account / date; `budgetFksExclude` so a txn can exist in the wallet but not in a budget (list still shows it with `paid` forced false **in memory** — DB paid unchanged).

Nexus v1 without multi-budget:

- Timeframe screen: enter select mode → Change category / Delete.  
- `excludeFromBudget BOOL` on expense. Spend aggregations skip it. Row still lists with a mute tag “Excluded”. Memory rollup skips it.

Do not fake `paid=false` in memory like Cashew — that bug is easy to leak into sync. Use an explicit flag.

---

### Spec 8 — CSV import (bank statements)

Cashew: column mapper (date, amount, title, note, account, category), custom date format, template download. Warns CSV is **not** a backup (budgets missing).

Nexus: Indian bank CSV / Excel. Reuse `smartParse` for category. Idempotent id = `csv:{sha1(date|amount|description|bank)}`. Preview screen: N rows, errors list, “Import M valid”. Backup reminder snackbar before commit. 3-try bulk POST (chunks of 100). Failed chunk queued.

Do not import into Investment unless category maps. SMS duplicates: if `sms-*` already has same day+amount+merchant, skip and count as duplicate.

---

### Spec 9 — Deep links / share

Cashew app links (from APK manifest): `https://cashewapp.web.app/addTransaction`, `addTransactionRoute`, `addTransferRoute`, `correctTotalBalance`, …

Nexus already: `ACTION_SEND` / `PROCESS_TEXT` for expenses. Add:

```
ainexus://expense/add?amount=120&description=Tea&category=Food&date=2026-09-11
```

Missing category → open add modal with fields filled, do not save. Amount parse fail → toast, open empty modal. Auth missing → login then consume the intent (store in `pendingExpenseLinkProvider`, same pattern as watch URLs).

---

### Spec 10 — Notifications (smarter than 9 PM only)

Cashew reminder types:

- If the app was **not opened today**  
- 24 hours from last open  
- Everyday  

Copy pool of ~26 “add today’s transactions” strings.

Nexus: keep 9 PM recap (spend-only after Step 0). Add:

- If overdue unpaid count > 0 at 9 PM, extra line.  
- If `today spend count == 0` AND app not opened today AND not a skip-day setting, fire.  
- Upcoming 08:00: occurrences due today.

Respect notification permission. Battery: one `WorkManager` / existing alarm, not a 5-second `TimerBuilder` like Cashew’s overdue homepage widget.

---

## 6. Formulas cheat sheet (copy into code comments)

### Spend filter (already exists — keep)

```
isSpend(e) = !isNonSpendCategory(e.category) && e.status != unpaid && e.status != skipped
             && e.excludeFromBudget != true && e.kind != income
```

Introduce `status`/`kind`/`excludeFromBudget` with defaults so old rows stay spend.

### Month pace (already exists — keep numbers)

```
expectedByNow = budget * (dayOfMonth / lengthOfMonth)
leftover      = budget − monthSpent
remainingDays = max(1, lengthOfMonth − dayOfMonth + 1)
safeDaily     = max(0, leftover) / remainingDays
threshold     = max(budget * 0.08, 100)
overPlan      if monthSpent > budget
aheadOfPace   if (monthSpent − expectedByNow) > threshold
else onTrack
```

### Cashew today marker

```
todayPercent = (now − start) / (end − start + 1 day)
hide if todayPercent not in [0, 1]
```

### Cashew remaining-days copy

```
remainingDays = (periodEnd.date − today.date).inDays + 1
safeDaily     = (budget − spent) / remainingDays     // under
overDaily     = (spent − budget) / remainingDays     // over, for the “over for N days” sentence
blank if today not in [start, end]
```

### Completed-period average

```
months = calendar months strictly before current, total >= 100
avg    = sum(totals) / months.length     // 0 if empty
```

### Subscription annualization — see Spec 1.

### Range facts (already exist)

Keep order: vsPrevious → topCategoryShare → top3Concentration → categoryShift → sixMonthExtreme. Floors ₹100 and 5%.

### Net (once income exists)

```
net = incomePaid − spendPaid     // investments/loans listed separately, not in net lifestyle
```

Cashew net worth **includes** open lent/borrowed and balance corrections and **excludes** unpaid. Do not call our number “net worth” until wallets exist. Label **“Net this period”**.

---

## 7. Edge-case register (do not skip)

| # | Case | Required behaviour |
|---|---|---|
| 1 | Empty period | 0, empty copy, **no** empty chart frame |
| 2 | Future-dated CC bill | All + NT only; not Today/7D/Month |
| 3 | Month length 28–31 | `addMonthsClamped`; pace uses `daysInMonth` |
| 4 | DST / IST | Store dates as local calendar strings `YYYY-MM-DD` / ISO without UTC shift; SMS already noon-local |
| 5 | Amount NaN / inf / > 1e12 | Reject (Cashew clamps ±999999999999) |
| 6 | Duplicate SMS + recurring same day | Two rows allowed if ids differ; merge UI hint if same merchant+amount+day |
| 7 | Pay recurring twice | Unique occurrence id → second pay is no-op |
| 8 | Unpay after auto-pay | `autoPayLocked`; next opens must not re-pay |
| 9 | Offline 3 failed POSTs | Queue; UI success; drain on next open **after** remote nuke |
| 10 | Remote nuke then drain | Existing order: nuke first (already in `expense_screen.dart`) — extend to recurring rules |
| 11 | Tombstone vs newer local edit | Keep local (existing LWW) |
| 12 | Server empty `updatedAt` | Never clobber local (existing) |
| 13 | Budget change mid-month | Month-keyed row; past months keep old amount |
| 14 | Category limit on Investment | Allowed but does not affect lifestyle ring |
| 15 | Skip last occurrence before endDate | No extra child |
| 16 | Clock back 1 day | Recurring ensure is idempotent; do not unpay |
| 17 | Heat tap future day | No-op |
| 18 | Pie touch index after filtering zeros | Rebuild sections after strip |
| 19 | One-point line | Hide chart |
| 20 | Web vs Flutter period | Same `PeriodRange` contract in TS (`ainexus-web/src/features/expense/periods.ts`) |
| 21 | Widget stale date | Existing midnight redraw; add overdue badge only if snapshot includes it |
| 22 | 9 PM recap + overdue | Two lines; spend-only ₹ |
| 23 | Salary 0, budget set | Pace still works; salary card hides |
| 24 | Exclude from budget + Insights search | Row visible when searching comments; totals skip |
| 25 | CSV date `dd/mm` vs `mm/dd` | Require format picker; default `dd/MM/yyyy` for India |
| 26 | Restore deleted after 30 days | Log pruned; “no longer available” |
| 27 | Goal “until reached” | Cashew’s stop-check is **buggy** (sums loan fk for goals). If we add installments, stop when `sum(paid toward goal) >= target` using the **goal** fk. |
| 28 | Transfer pair edit | Step F only: update both or confirm; never leave unpaired correction |
| 29 | Primary currency | INR only; do not add USD pivot |
| 30 | Demo / preview random data | Do **not** add Cashew preview demo (data-loss trap) |

---

## 8. Retry, accuracy, Telegram — standard for every new write path

Copy this. Do not invent per-feature networking.

```text
1. Write Drift in a transaction. UI streams immediately.
2. POST/PUT/DELETE with 3 attempts, delay 400ms * attempt.
3. Transient: timeout, connection error, 408, 429, 5xx → retry.
4. Permanent: 401, 403, 404, 413, 422 → no retry, TLog.e, surface a specific snackbar.
5. After 3 transient failures: insert sync_queue (entity type + json + op).
6. On launch: applyRemoteResetIfNeeded → drainSyncQueue → pull sync → retryPendingClears.
7. Adopt server updatedAt on success (existing _adoptServerUpdatedAt).
8. Idempotent ids for generated rows (recurring, csv, sms).
9. TLog.w attempt failures; TLog.e final (flush). Never log payloads that include tokens.
10. Memory rollup applyDelta in the same local transaction; recompute after pull.
```

Accuracy:

- All money math in **pure** functions (`expense_pace_metrics.dart` style), unit-tested with frozen `now`.  
- UI only formats.  
- AI composer still **cannot** emit bare digits (`insight_grounding.dart`). New tokens (`overdueCount`, `safeDaily`, `avgCompletedMonthly`) are added to `ExpenseInsightEngine` the same way.  
- Floors: do not emit facts under ₹100 or 5%.  

---

## 9. Suggested Drift / API additions (minimal)

```text
expenses.status              TEXT default 'paid'     // paid|unpaid|skipped
expenses.kind                TEXT default 'spend'    // spend|income
expenses.recurringRuleId     TEXT?
expenses.dueDate             TEXT?
expenses.excludeFromBudget   BOOL default 0
expenses.autoPayLocked       BOOL default 0

budget_entries.month         TEXT?                   // 'YYYY-MM'

category_budget_limits       (category PK, kind, value, updatedAt)
recurring_rules              (see Spec 1)
pinned_expenses              (id, json, order, updatedAt)
deleted_expense_log          (id, json, deletedAt)   // local only
sync_queue                   already exists — add entity types
```

API: upsert columns ignored by old clients; old apps omit them → server defaults. Flutter reads with `?? paid` / `?? spend`.

`ainexus/routes/expenses.js` is **not** production. Do not extend it.

---

## 10. File map for implementers

| Work | Touch |
|---|---|
| Period unification | NEW `lib/core/services/expense_period_range.dart`; `tracker_tab.dart`; `insights_tab.dart`; `expense_trend_modal.dart`; `expense_timeframe_screen.dart`; web `periods.ts` |
| Recurring | NEW engine + repo + page; `app_database.dart`; `expense_entities.dart`; `expense_repository.dart` spend filter; API |
| Budget copy / tick / ghost | `expense_pace_metrics.dart`; `budget_ring.dart`; `tracker_tab.dart` |
| Category limits | NEW table; `set_budget_modal.dart`; Insights category rows |
| Month-keyed budget | `budget_entries.month`; `currentBudgetProvider`; `budget_history_modal.dart` |
| Graphs | `expense_trend_modal.dart`; heat in `tracker_tab.dart` |
| All-spending | NEW page or Insights “Summary” tab |
| Outbox | `expense_repository.dart` + `sync_queue` |
| At-risk constant | `expense_pace_metrics.dart` |
| Recap filter | `notification_service.dart` |
| SMS bank map | `sms_parser.dart` + `BankSmsParser.kt` |
| Pins | FAB in `expense_screen.dart` |
| Tests | mirror `expense_pace_metrics_test.dart` for every pure engine |

---

## 11. Do **not** take from Cashew

| Cashew thing | Why skip |
|---|---|
| GPL source / widgets / icons | License. Re-implement. |
| Signed-amount rewrite of our ledger | Breaks every total, SMS, widget, web, AI token. Use `kind` instead. |
| USD-pivot FX / 38 currencies | INR app. |
| Google Drive backup + mailbox sheet | We have NAS / Nextcloud / PG. |
| Firebase shared budgets | Single-user app-login. |
| IAP / Cashew Pro / unlock-for-free | Not our model. |
| Material You, icon packs, custom fonts, goo plasma, left-handed nav, battery-saver setting | Theme noise. We have a design system. |
| Preview demo random data | Documented data-loss risk. |
| Notification-listener SMS templates | Ours are better for Indian banks. |
| Gemini Intelligence for add-txn | We have voice + smartParse; their privacy prompt sends account names off-device. |
| Bill splitter | Niche; loans/IOU later if ever. |
| Credit-card **account type** with statement fields on the wallet | We already have `BankBillingConfig` + forecast engine. |
| 5-second homepage timer for overdue | Use app-resume + day-change (we have watch patterns). |
| `isExactMatch` titles, `getTotalTowardsObjective` loan-fk-for-goals bug, SBI→HDFC-style silent maps | Known Cashew/Nexus bugs — do not reproduce. |

---

## 12. Cashew APK extra (6.6.11, not all in GitHub 5.4.3)

Present in `en.json`, implement only if we still want them after A–E:

- **Cashew Intelligence** / receipt photo → skip (we have STT + scan).  
- **Transaction mailbox** (Google Sheet inbox/outbox) → skip.  
- **Notification scanning** user-defined templates → skip (SMS pipeline).  
- **Local link** to a transaction URL → Spec 9 is enough.  
- **Stacked bar graph**, **period history averages** copy → take the average rule (Spec 2).  
- **Export configuration without transactions** → nice for debug; not v1.  
- **Haptic** on save / nav → optional, our `HapticFeedback` already used in places.

---

## 13. Definition of done (per step)

A step is done when:

1. Pure engine has unit tests for the edge table rows that apply.  
2. `flutter test` for touched files + existing expense tests still pass.  
3. Offline: airplane mode add/pay/skip → local UI correct → online drain within one resume → server GET matches. Fail path: `TLog.e` visible, no crash.  
4. Investment/Loan still excluded from lifestyle ring.  
5. Web either matches `PeriodRange` or shows a “mobile-only” gap comment — no silent 30-day vs calendar mismatch.  
6. No Cashew files in the tree. No GPL paste.

---

## 14. What Cashew is actually good at (steal the product feeling)

1. **Unpaid is not money.** Upcoming rent does not fake-spend the ring.  
2. **Periods are first-class** and the same widget can be all-time or this cycle.  
3. **Completed-period averages** do not lie with a half-finished month.  
4. **Safe-to-spend / day** is one sentence, not a dashboard.  
5. **Today tick vs spend fill** shows pace without a lecture.  
6. **Tap a slice / a day / a month card** and you are in a filtered list — charts are doors, not posters.  
7. **Home is editable.** If a widget is noise, hide it. Our Insights dump is the anti-pattern.  
8. **Pay / skip** is an action on the row, not a delete-and-readd.  
9. **Titles remember** “Starbucks → Food” better than token bag-of-words.  
10. **Empty states tell you to change the period**, not that the app is broken.

Nexus already has the data plane (SMS, salary, CC, AI, exclusions). This handover is how to make the **money story** as clear as Cashew without becoming Cashew.

---

*Sources: Cashew APK 6.6.11 translations + AndroidManifest; Cashew `budget/lib` tables.dart, functions.dart, budgetContainer.dart, homePageLineGraph.dart, periodCyclePicker.dart, upcomingTransactionsFunctions.dart, spendingSummaryHelper.dart; Nexus expense_entities.dart, expense_pace_metrics.dart, expense_memory_service.dart, expense_repository.dart, insights_tab.dart, tracker_tab.dart, credit_card_forecast_engine.dart, expense_screen.dart.*
