# MoneySplit → AI Nexus expense handover

**Audience:** whoever implements MoneySplit-grade personal-finance tracking on top of the existing Nexus Expense module.  
**Dump analysed:** JADX of MoneySplit `com.thegreatdanton.moneysplit.money_split` **1.5.0** (`versionCode` 33684634), folder `C:\Users\Beast\Downloads\MoneySplit`. Play **base APK only** — `libapp.so` / kernel / isolate snapshots live in the missing ABI split, so Dart class names are recovered from help targets, JSON configs, native Kotlin, widgets, and release notes. Where Dart is inferred, it is labelled **inferred**.  
**Nexus home today:** `ai_nexus/lib/presentation/screens/expense/` + `lib/data/repositories/expense_repository.dart` + `lib/core/services/expense_*.dart` + `lib/data/services/sms_auto_expense/` + `android/.../sms/`.

Read this as an **implementation spec**, not a clone brief. MoneySplit is a full offline-first ledger (accounts, transfers, subscriptions, bills, loans, merchants, budgets-by-category, upcoming, Smart Scan). Nexus is a **consumption tracker** with salary, CC forecast, grounded AI, and India SMS auto-log. The job is to take their **clean, informative logic** and graft it onto Nexus without throwing away what we already do better.

Do **not** copy their RevenueCat gating, ads / `AD_ID`, `getAndroidId`, clone protection, telemetry push, Play Integrity wrap, or fake-premium dark patterns. Those are documented in §20 so you do not reproduce them.

---

## 0. One-screen truth

| Surface | MoneySplit 1.5.0 | Nexus Expense today | Verdict |
|---|---|---|---|
| Identity of money | First-class **accounts** (bank / cash / credit / special) with last-4 matching | Flat `bank` + `cardType` (`HDFC/ICICI/AXIS/SCAPIA/CASH` × `DB/CC/Cash`) | **Upgrade accounts.** Keep existing rows; migrate `(bank, cardType)` → Account. |
| Ledger types | Expense **and** income **and** transfer (double-entry) | Expense only. Credits/OTPs/refunds discarded by SMS parser | **Add income + transfer.** Debit-only is why salary is a side table. |
| Categories | Parent → subcategory + cross-cutting **tags** | Flat 26-name list. `Investment` / `Loan` excluded from spend | Keep Investment/Loan exclusion. **Add parent/child + tags.** |
| Merchant | Canonical merchant + aliases + spend/income default categories + 6-month trend | `description` string. SMS labels + category learnings | **Add merchant entity.** Description stays as note/fallback. |
| Budget | Period object: master limit, category allocations, include/exclude tags, force-link, rollover, Sankey, badges | One monthly rupee number + history of that number + pace vs calendar | **Keep pace math.** Add category envelopes **on top**. |
| Recurring | Subscriptions, bills, loans as scheduled objects + Upcoming timeline | Categories named Subscription / Bills / Loan. No due engine | **Add objects + Upcoming.** Categories alone are waste. |
| Insights | Feed of acceleration / outliers / risks + drilldown. Rebuild after import | Grounded LLM cards + heat calendar + DoW + KPIs + range facts in one giant tab | **Keep grounding.** Split UI; add feed types we lack. |
| Charts | Income vs expense, heatmaps, category growth, merchant 6-month bars, budget Sankey | Trend line, category/bank/card bars, DoW (total/avg/txns), heat month, investment sparkline, AI search charts | **Keep ours.** Add Sankey, income-vs-expense, merchant trend, category growth. |
| Capture | SMS + **notification listener** + PDF statements + CSV/Excel + app migration + custom “tap-to-tag” rules | Bank SMS (HDFC/ICICI/AXIS/Scapia) ask/auto + review overlay + 1-min native dedupe | **Keep SMS intake policy.** Add notif listener, transfer/income parse, statement/CSV, custom rules. |
| Salary | Life-hours wage (simple + YMOYL real wage) | In-hand salary per month + hike % + CC forecast vs salary credited on day 28 | **Keep salary+CC forecast.** Add life-hours as a **badge**, not a replacement. |
| Goals | Savings pots + sinking funds + pacing strategies | None (leftover = salary − spend) | **Add goals.** Leftover is not a goal. |
| Widgets | 8 Glance widgets (budget, bills, today, quick add, dashboard, goals, calendar, life-hours) | 1 expense widget: today / month / top category | **Extend widget family.** Do not replace the existing one. |
| Help | Contextual in-app guides + screen targets | None in expense | Optional later. Specs in this file replace their help for implementers. |
| Split-with-friends | Name + `split.svg` only. **No Splitwise engine** | None | **Do not build friend-splits.** Personal ledger only. |

You already have the hard parts of *honest numbers*: spend-only vs Investment/Loan, pace vs budget, CC statement windows tied to salary day 28, SMS ask/auto/undo, last-write-wins sync with tombstones, Telegram logs, and an LLM that **cannot invent rupees**. MoneySplit’s product is:

1. A **real ledger** (accounts, types, links) instead of a tagged expense list.
2. **Obligations with dates** (subs / bills / loans) feeding one Upcoming surface.
3. **Budget as a period with category math**, not a single ring.
4. **Capture that reviews before it pollutes analytics** (pending review, transfer linking, merchant aliases).
5. **Analytics that explain a number**, then drill to the rows that made it.

---

## 1. Recommended build order (do this, in this order)

Each step is independently shippable. Stop after any step and Expense still works. Existing `expenses` rows must remain readable.

### Step A — Keep Nexus as the source of truth

Do **not** replace `ExpenseRepository`, `ExpenseInsightEngine`, `InsightGrounding`, `ExpensePaceMetrics`, `CreditCardForecastEngine`, `SmsIntakePolicy`, or the Investment/Loan spend split.

MoneySplit logic **adds tables and screens**. It does not rewrite `monthPace` or grounding.

### Step B — Accounts + transaction type (the foundation)

Without this, every later feature (transfers, CC repayments, SMS matching, budgets-by-account) lies.

Migrate: each distinct `(bank, cardType)` the user already has → one `Account`. Stamp every existing expense `type = expense`, `accountId = that account`. `CASH`/`Cash` → type `cash`. `CC` → type `credit`. `DB` → type `bank`.

### Step C — Income + transfer (double-entry)

Salary credits, refunds, and “paid the HDFC card from HDFC savings” stop being missing or double-counted. This is the single biggest data-quality jump.

### Step D — Merchant entity + alias merge

SMS `Zomato*Rest` / `ZOMATO` become one merchant. Category defaults stop depending on a raw description string. 6-month merchant bar chart becomes possible.

### Step E — Category parent/child + tags

Do not flatten Investment/Loan. Add optional `parentId` and a `tags` table. Budget envelopes and Sage-quality answers need this.

### Step F — Budget periods + category allocations + badges

Keep the existing monthly master number as the default “Monthly / all spend accounts” period. Add envelopes, Near/Over/Spent badges, include/exclude tags, force-link, rollover, Quick Budget + 1-tap undo.

### Step G — Subscriptions, bills, loans as objects + Upcoming

Upcoming is the product. Objects without Upcoming are admin screens nobody opens.

### Step H — Smart Scan upgrades (transfer linking, income, notification listener, custom rules)

Reuse `BankSmsParser` + `SmsIntakePolicy`. Add pipeline_config windows. Notification listener is Android-only, off by default, same review modes we already have (`ask` / `auto`).

### Step I — Insights feed + charts we lack (Sankey, income vs expense, category growth, merchant trend)

Compose **facts in code** (same contract as `InsightFacts`). LLM only phrases. Rebuild after import / recategorize / period finalize.

### Step J — Savings goals + life-hours badge

Goals use leftover and sinking-fund links. Life-hours uses salary we already store. Do not replace `SalaryScreen`.

### Step K — Widgets / deep links / receipts / CSV / PDF (optional)

Ship only after the ledger is trustworthy. A dashboard widget on dirty data is worse than no widget.

---

## 2. What Nexus already does better (do not regress)

Copying MoneySplit blindly would **delete** these. Treat them as invariants.

| Invariant | Where | Rule |
|---|---|---|
| Investment is not spend | `isInvestmentCategory` / `spendOnly` | Never in budget, widget, pace, memory rollup, charts. Own Insights card + cumulative sparkline. |
| Loan repayment is not spend | `isLoanCategory` | Same exclusion. Own Insights card. When loans become objects, *link* the repayment txn; do not also count it as Food. |
| Pace math | `ExpensePaceMetrics.monthPace` | `expectedByNow = budget * (dayOfMonth / lengthOfMonth)`; `safeDaily = max(0, leftover) / remainingDays`; ahead-of-pace iff `monthSpent - expected > max(budget * 0.08, ₹100)`. |
| Range-fact floors | `rupeeFloor = 100`, `pctFloor = 0.05` | Do not surface “₹12 more than last week”. |
| Heat calendar | `heatMonth` | Intensity vs hottest day this month; future days 0; tap opens that day. |
| CC × salary | `CreditCardForecastEngine` + `kSalaryCreditDay = 28` | Statement close / due / which salary month pays it. User-configured per CC bank. |
| Grounded AI | `InsightFacts` → composer → `InsightGrounding` | LLM never originates a number. Bare digits → template fallback. No raw rows sent. |
| Memory rollup | `expense_monthly_category` | Constant-cost facts regardless of row count. Rebuildable. Local-only. |
| SMS intake | `SmsIntakePolicy` | `auto` + Dart alive → silent save; engine dead → disk queue; ask + UI visible → in-app review; else tray Approve/Reject. Undo only if category/description untouched. |
| SMS date safety | `expenseDay` | If parsed bank day is >1 calendar day from received, use received day (dd/mm vs mm/dd). |
| SMS privacy | `ParsedSmsDebit.rawBody` | Never on the expense row, never in `toJson` logs, never to the composer. |
| Native SMS dedupe | `SmsDeduper` | `sender|amount|minuteBucket`, retain 7 days. |
| Save retry | SMS save loop + `ExpenseRepository._syncPostWithRetry` | 3 attempts, 400ms × attempt. Unique constraint → treat as success (already saved). |
| Widget retry | `ExpenseWidgetService` | 3 tries, 500ms → 1s → 2s. Midnight AlarmManager. Debounce 300ms. |
| Sync | last-write-wins `updatedAt` (server clock) + tombstone watermark | Local insert always succeeds; cloud is eventual. Telegram on final failure. |
| Insights periods | `expensesInInsightPeriod` | Week/30d/90d/6M end **end-of-today**. Future-dated bills go to **NT** and All, never leak into Week. |

MoneySplit Sage also refuses to send transaction rows / SMS / PDFs to cloud. Keep that. Their cloud fallback *does* send locale, currency, sanitized account labels, upcoming count, subscription count. Nexus composer already sends only tokens — **stricter. Keep stricter.**

---

## 3. What in *our* setup is waste (and what MoneySplit does instead)

These are not bugs. They are the wrong *shape* for the job, which is why they feel noisy but not informative.

| Nexus today | Why it is waste | MoneySplit shape to adopt |
|---|---|---|
| `Subscription` / `Bills` / `Loan` as **categories** | A Netflix charge and a one-off “subscription to a magazine” look the same. No next due, no “inactive but still charging”, no mark-paid. | Recurring **objects** with cadence + due + link to a txn. Category is still “Entertainment” / “Utilities”. |
| One budget rupee for the whole month | Ring says “₹8,400 left” while Food is already blown and Rent is untouched. | Master limit **plus** category envelopes + Near/Over badges. Pace ring stays as the master. |
| `description` = merchant | `Zomato*Rest`, `ZOMATO`, `Swiggy` never group. Top merchants in Insights is a string split. | Canonical merchant + aliases. Description is a note. |
| Five hard-coded banks | Adding Kotak means a code change. No last-4, no opening balance, no liability vs cash. | Account records. Settings bank pills become **account presets**, not the schema. |
| Debit-only SMS | Card payment looks like a ₹40,000 “expense”. Salary never lands in the ledger. Net worth is fiction. | Parse credit + debit; auto-link equal-and-opposite within windows; CC payment is a **transfer**, not Food. |
| Insights tab as one 5k-line widget | Every chart fights for space. High-priority signal is buried under DoW. | Dashboard (health + smart actions) / Analytics (charts) / Insights feed (cards with drilldown). Reuse the same engines. |
| Leftover = salary − spend | Useful, but it is not “emergency fund in 8 months”. | Salary leftover **and** named goals with a pace. |
| Widget: today + month + top cat | Fine, but no “what is due”, no burn rate, no remaining. | Keep this widget. Add a **Dashboard** widget (spent/limit/remaining/days left/burn) and a **Bills** widget. |

---

## 4. Dump limitations (so implementers do not invent Dart we did not see)

**Recovered with high confidence**

- Help corpus (every field, badge, include/exclude rule, notification mode).
- `pipeline_config.json` (dedup 15 min, transfer 30 min, CC 120 h ±₹25, personalization thresholds).
- `plan_policy.json`, `feature_flags.json`, `parsing_config.json` v6, subscription catalog v1 (113 providers).
- Native: 8 Glance widgets + prefs keys, NLS AES-GCM queue, Wear Data Layer keys, deep links, life-hours minutes formula.
- Release notes through v1.5.0 (notes hub, parent ceiling, tap-to-tag SMS, savings goals, amortization UI, widgets).

**Not in this dump (`libapp.so` missing)**

- Exact SQLite `CREATE TABLE` list beyond `financial_notes` / `note_tags` (schema v99) and `explicitAssigned` (v92).
- Exact EMI amortization kernel (UI exists; use standard reducing-balance PMT below and test against bank examples).
- Exact “Growing” merchant % and dormant 30-vs-90 choice (help says 30–90 from historical baseline).
- Sankey visual encoding (screen exists: `budget/budget_sankey_screen`).
- Export “Tier 1/2/3 analytics” meaning.
- App-lock timeout / failed-attempt policy.
- Exact reminder offsets for bills.

Where a number is missing, this spec **picks a Nexus default** and marks it **Nexus default**. Do not bikeshed — ship the default, make it a named constant.

---

## 5. Data model (Drift) — additive, migratable

All new tables are local-first. Sync later using the same `updatedAt` + tombstone pattern as expenses. Until a backend exists, writes succeed locally and queue via `SyncQueue` (`entityType` new values). Memory rollup stays derived from **spend expenses only**.

### 5.1 Existing tables (keep)

```
expenses (id, amount, description, category, bank, cardType, date, isManualCategory, comments, updatedAt)
budget_entries (id, amount, setAt)          -- history of the master monthly number
salary_entries (id, month PK 'YYYY-MM', amount, setAt)
expense_monthly_category (month, category, total, count)
category_learnings (keyword, category)
```

### 5.2 New columns on `expenses` (nullable → backfill)

| Column | Type | Backfill |
|---|---|---|
| `type` | text `expense\|income\|transfer` | `'expense'` |
| `accountId` | text | mapped from `(bank, cardType)` |
| `counterAccountId` | text null | transfer destination |
| `transferGroupId` | text null | shared by both legs |
| `merchantId` | text null | matched or created from `description` |
| `status` | text `posted\|pending\|rejected` | `'posted'` |
| `source` | text `manual\|voice\|sms\|notification\|csv\|pdf\|migrate` | `'sms'` if id starts `sms-` else `'manual'` |
| `externalRef` | text null | SMS `referenceId` |
| `linkedSubscriptionId` / `linkedBillId` / `linkedLoanId` / `linkedBudgetId` | text null | |
| `forceLinkedBudget` | bool default 0 | |
| `excludeFromBudget` | bool default 0 | do **not** use this for Investment/Loan — those stay category-based |
| `receiptPath` | text null | |

**Do not drop `bank` / `cardType`.** They remain denormalized for the widget and old queries until every reader uses `accountId`. Write both on every new row.

### 5.3 `accounts`

```
id text PK
name text                  -- "HDFC 1234", "Cash"
type text                  -- bank | cash | credit | special
currency text default 'INR'
openingBalance real default 0
maskDigits text null       -- last 3–5 digits only. NEVER full PAN
institutionKey text null   -- 'HDFC' for brand color / SMS match
cardKind text null         -- DB | CC | Cash (compat)
statementDay int null      -- CC only
dueDay int null            -- CC only
archivedAt text null
updatedAt text
```

**Balance (inferred, Nexus default):**

```
cash_or_bank_balance = openingBalance + sum(income) - sum(expense) + sum(transfer_in) - sum(transfer_out)
credit_outstanding   = openingBalance + sum(card_spend) - sum(card_repayments)
```

Card spend **increases liability**, not “available cash”. A repayment is a **transfer** (bank → credit), never a spend category.

**SMS matching:** store only last 3–5 digits (`HDFC - 1234`). If two accounts share the same last-4, do not auto-match — send to pending review.

**Delete:** archive by default. Hard-delete only if zero transactions, or reassign txns first (MoneySplit: robust cleanup of related items).

### 5.4 `merchants`

```
id, canonicalName, createdAt, firstSeenAt, lastSeenAt
defaultExpenseCategory, defaultExpenseSubcategory
defaultIncomeCategory, defaultIncomeSubcategory
customRuleLocked bool     -- Resync must not override
```

`merchant_aliases (merchantId, alias, matchType contains|exact, source sms|csv|user)`

`merchant_category_rules` — same as defaults; `Update Past Transactions` is an explicit bulk write with a confirmation sheet. No undo → require typed confirm if count > 20.

### 5.5 Categories / tags

```
categories (id, name, parentId null, kind spend|income|transfer|system, icon, archived)
tags (id, name, archived)
transaction_tags (txnId, tagId)
```

Seed from `expenseCategories`. `Investment` and `Loan` are `kind=system` and **cannot be deleted**. Subcategory examples to offer (not force): Food → Groceries, Dining Out; Transport → Fuel, Cabs, Transit.

**Assignment order:** category → subcategory if needed → tag only if cross-cutting (trip, project).

**Import path matching:** full `Parent/Child`. Reuse parent; create missing child under it. Never create a category from a numeric ID.

### 5.6 Budgets

```
budget_periods (
  id, name,
  kind monthly|paycheck|custom|open_tagged,
  startDate, endDate null,          -- open_tagged has null end
  masterLimit real,
  status active|finalized,
  accountScope all|selected,
  rolloverEnabled bool,
  createdAt, finalizedAt null,
  explicitAssigned bool             -- v92: parent ceiling is explicit
)
budget_accounts (periodId, accountId)
budget_tag_filters (periodId, tagId, mode include|exclude)
budget_category_alloc (periodId, categoryId, assigned real)
budget_links (periodId, txnId, force bool)
```

Keep writing `budget_entries` whenever the **active monthly master** changes so Salary/Insights/widget stay compatible.

### 5.7 Obligations

```
subscriptions (id, name, amount, currency, cadence monthly|yearly|customDays,
               nextDue, accountId, merchantId, providerKey null, status active|paused|cancelled,
               notes, trialEndsOn null, promoEndsOn null)
bills (id, name, amountExpected, cadence, nextDue, accountId, merchantId, reminderOffsetDays default 2, status)
loans (id, name, originalPrincipal null, currentBalance, emi, annualRatePct,
       rateType fixed|floating, nextDue, frequency monthly,
       startDate, alreadyRunning bool, lateFeeAmount null, autoLateFee bool, status active|closed)
loan_rate_changes (loanId, effectiveDate, annualRatePct)   -- user-entered, not RBI sync
loan_charges (loanId, date, amount, kind processing|late|other, inEmi bool, txnId null)
savings_goals (id, name, targetAmount, targetDate null, strategy date|refill|builder,
               monthlyBuilderAmount null, currentSaved, linkedCategoryId null, periodId null)
```

### 5.8 Capture / review

```
scan_batches (id, source sms|notification|pdf|csv|migrate, startedAt, finalizedAt, accepted, rejected)
pending_transactions (...parsed fields..., batchId, confidence, reason)
custom_sms_rules (id, name, senderPattern, bodyPattern, enabled, fieldMapJson)
notification_selected_apps (packageName, profileKey, certSha256)
```

Nexus already has a native JSON queue (`sms_auto_expense_queue.json`, max 40). Keep it for SMS. Notification listener gets its **own** encrypted queue (see §12).

---

## 6. Transaction rules (every writer must obey)

1. **One real-world event = one posted transaction** unless the user explicitly splits.
2. Do not create compensating entries to “fix” a wrong row. Edit the source row.
3. **Pending never hits** Dashboard totals, budget usage, Insights, or the widget.
4. Confirm before post: account, **direction** (income vs expense), category/tag, not a duplicate.
5. Card repayments are **transfers**, not spend.
6. Self-transfers (wallet → bank, CRED → card) are transfers; intermediaries listed in §12.5 are auto-promoted then deduped against the card posting.
7. Investment and Loan categories remain non-spend even if the account is a spending account.
8. Linking is 1 payment ↔ 1 obligation. Duplicate linkage is rejected.
9. Mark-as-paid on Upcoming **does not create a txn** (MoneySplit “Manual Marker”). It advances `nextDue` and records an acted-on flag. If the user already has a bank txn, **link** it instead.
10. Edit the **source** (subscription/bill/loan), then Upcoming re-derives. Do not edit the same due in two places.

---

## 7. Feature specs

### 7.1 Dashboard (new top of Tracker, or first Insights page)

**Purpose:** decision screen on open, not a chart dump.

**Always-visible (Nexus mapping):**

| Block | Source | Action |
|---|---|---|
| Health | `MonthPace.status` + leftover + salary saved % | tap → Tracker ring / Salary |
| Budget status | active period remaining + worst category badge | tap → Budget detail |
| High-priority cards | Insights feed severity ≥ warning | tap → that insight |
| Upcoming cluster | next 7 days sum + overdue count | tap → Upcoming |
| Recent activity | last 8 posted txns | swipe recategorize / open details |
| Smart actions | computed, max 3 | one tap into the workflow |

**Smart-action ranking (Nexus default):**

1. `pending_review_count > 0` → “Review {n} imported items”
2. `overdue_count > 0` → “{n} overdue”
3. Any category `Over` → “Cover overspending in {cat}”
4. Pace `overPlan` → “Month is over plan”
5. Pace `aheadOfPace` → “Spending ahead of pace”
6. Duplicate suspicion (same merchant+amount < 15 min) → “Possible duplicate”
7. Uncategorized / `Others` share ≥ 20% this month → “Fix categories”
8. Else hide the row

After a Smart Action, return here and **recompute** (same as their “verify impact”).

**Do not** put the DoW chart on Dashboard. That stays in Analytics.

### 7.2 Accounts

**Screens:** list, details (txns for that account only), add/edit.

**Add/edit fields:** name, type, opening/baseline, `maskDigits` (3–5), institution preset, CC statementDay/dueDay (reuse Settings bank cycle — **move** that config onto the account so it is not a parallel map).

**Checklist:** names still meaningful in a year; type accurate; no duplicate accounts for the same real source; rename instead of clone.

**Credit-card behaviors (must implement):**

- Spend on a credit account increases **outstanding**, not cash.
- Payment entries reduce dues (transfer from a bank/cash account).
- Statement/due-cycle drives Upcoming “card bill” rows (you already compute this in `CreditCardForecastEngine` — **surface those as Upcoming items** of type `credit_card_statement`).
- Reconcile the card often, not only at month-end.
- Never file a card payment under Food/Shopping.

**Account details use:** inflow/outflow, unusual spikes, linked card spending. Reconcile **one account at a time**.

### 7.3 Transactions

**History:** search merchant / amount / date. Weekly habit: uncategorized, duplicates, missing salary/rent.

**Add/edit field order:** account → amount → type → category/sub → tags → date/time → notes.

**Details — Link menu (exact actions):**

- Link credit-card payment
- Link self transfer
- Link subscription payment
- Link bill payment
- Link budget (force-link)
- Link loan payment (EMI or extra principal) — **do not** also create a manual loan-payment record

**Find-link screen:** from a txn, search candidate obligations/txns in a date window (default ±5 days, amount ±₹25 or 2%, whichever larger — **Nexus default**, matches CC tolerance).

**Receipts (optional Step K):** camera or gallery; `.jpg/.jpeg/.png`; copy into app docs `receipts/{uuid}.jpg`; full-screen zoom; remove **deletes file, no undo**. `isReceiptScanningEnabled` is **false** in MoneySplit 1.5.0 — do **not** promise OCR.

**Filter presets (Settings):** type All/Expenses/Income/Transfers; included accounts; excluded accounts; **one Active** preset auto-applies when opening History. Examples from their help: credit-card expense audit; everyday ledger hiding savings; transfers-only; cash-only.

### 7.4 Budget (the important math)

Keep `ExpensePaceMetrics` on the **master limit**. Category math is additional.

#### Period kinds

| Kind | Date rule | Include-tag rule |
|---|---|---|
| **Monthly** | calendar month (or user start-day later) | in range **OR** has include-tag |
| **Paycheck** | bounded range (salary date → next) | same as Monthly |
| **Custom** | bounded range | in range **AND** has include-tag |
| **Open-tagged** | no end | has include-tag |
| No include tags set | — | normal date-range only |

Then **exclude tags** remove matches. Then **account scope**. Then **force-link override:** force-linked rows **always count** and always appear in View All, even with an exclude tag.

If the same tag is in both lists, keep it in **one** list (last write wins, UI should prevent both).

Tag filters are **editable only while `status=active`**. After finalize **or** `now > endDate`, filters are read-only.

**View All from a budget must use the exact same predicate as the totals.** If the list and the ring disagree, that is a P0 bug.

#### Usage of a category

```
usage(cat) = sum(posted spend txns matching period predicate
                 AND category is cat or a child of cat
                 AND NOT isNonSpendCategory)
assigned(cat) = budget_category_alloc.assigned
remaining(cat) = assigned - usage
usagePct = assigned == 0 ? 0 : usage / assigned
```

#### Parent / child envelopes (v1.4.1)

- Parent assigned = **ceiling envelope**.
- Child assigned draws from the parent pool **without shrinking** the parent.
- If `sum(child.assigned) > parent.assigned`, **auto-expand** parent to the sum (`explicitAssigned` stays true so restore/backup keeps the expanded value).
- `+ Add Subcategory` on an expanded parent card opens category create with `parentId` prefilled.

#### Badges (exact)

Currency display uses existing `formatCurrency`.

| Badge | Condition |
|---|---|
| Unbudgeted | `assigned == 0` |
| Over (red) | `remaining < 0` |
| Spent (outline) | `remaining == 0 && usagePct >= 1` |
| Near (orange) | `0.85 <= usagePct < 1` |
| Underfunded (amber) | linked savings goal and `remaining < goal.target` (envelope left cannot fund the goal) |
| Healthy (green) | not Over/Near/Spent/Unbudgeted, and any linked goal funded |

#### Period close

Finalize is deliberate:

1. Freeze tag filters.
2. Compute `rollover = max(0, masterLimit - periodSpend)` if enabled.
3. Next period master = user input, optionally `+ rollover`.
4. Rebuild Insights (`ExpenseMemoryService.recompute` + feed rebuild).
5. Historical analysis uses the frozen period, not “whatever the live filters are”.

#### Quick Budget (power tools)

| Action | Behavior |
|---|---|
| Fill Unbudgeted Only | For `assigned==0` cats, copy previous period assigned; **do not** touch manual non-zero |
| Fund Underfunded Goals | `assigned += max(0, goal.target - remaining)` for linked cats |
| Use last month / avg 3 months | copy allocation template |
| Reset all | all assigned → 0 |
| Cover Overspending | top chip: `assigned = usage` for Over cats (clears deficit) |

**1-tap undo:** keep a `QuickBudgetSnapshot` of all `assigned` values in memory + a Snackbar/notification action for 8 seconds. This is the **only** budget undo they document. Implement it.

#### Sankey (`budget_sankey_screen`) — **inferred** visual, Nexus default

Three columns:

1. **Source:** Income this period (posted income in scope) and/or Master limit (toggle).
2. **Categories:** assigned (or actual spend — default **actual spend** so it is a true flow).
3. **Outcome:** Spent vs Remaining vs Overspend (overspend as a red sink).

Library: `fl_chart` cannot do Sankey well. Use a simple custom `CustomPainter` flow (or `sankey_chart` if you add a dep). Empty state if `< 2` categories or total < ₹100.

Cap nodes at 8 categories + “Other”. Same floor as range facts.

### 7.5 Subscriptions

**Why:** silent monthly leakage. Category `Subscription` cannot answer “is this still on?”.

**Fields:** exact service name, amount, cadence monthly/yearly/custom, next due, likely account, notes, optional `providerKey` from catalog.

**Catalog (optional, high value for India):** `assets/config/subscription_catalog` has 113 providers with `merchantAliases` (`contains` match), brand color, plans, cancellation URL. Ship **IN.json** first (Netflix, Spotify, YouTube, Hotstar, Swiggy One, Zomato Gold, ChatGPT, …). Matching:

```
if merchant.canonical or alias contains provider.merchantAlias (casefold)
  suggest providerId + default plan amount for country IN
```

Do **not** auto-create 113 rows. Suggest on SMS/merchant: “Looks like Netflix — track as subscription?”

**Link payments:** amount match or known variance (tax / plan / intro ended); date window; merchant; no duplicate link. If mismatch: check account, aliases, amount change; link only at high confidence.

**Upcoming:** `nextDue` is the schedule. After Smart Scan finalize, reconcile flagged subs.

**Edit:** update the same row; do not duplicate identity.

### 7.6 Bills

Same skeleton as subscriptions but **variable amount is normal** (electricity). Store `amountExpected` as baseline; actual linked txn may differ. Reminder: **Nexus default** `nextDue - 2 days`, user editable 0–14. Settings already has notification permission.

Overdue: `now > nextDue && not marked paid && no linked txn in window`.

No match: expand date range slightly → check merchant variation → different account → keep unlinked.

### 7.7 Loans & EMI

**Offline-first:** rates are user-typed. No bank/RBI sync.

**Fields:** name (bank + purpose), current balance, EMI, annual rate %, next due, frequency, fixed vs floating, `alreadyRunning`.

**Already-running (critical):**

- Tracks from **today’s balance**, current EMI, current rate.
- Original principal **optional**. If unknown, progress = paid since add-date, **not** lifetime payoff %.
- Cannot recreate old EMI history, total interest already paid, old rate changes, old prepayments.

**One active record per real loan.** Refinance → close old, open new.

**Link:** from the bank txn, Link loan. Extra principal = same link with `kind=prepay`.

**Late fees:** manual, or auto-add `lateFeeAmount` if `now > nextDue + grace` (**Nexus default grace = 0**).

**Plan EMI simulator (does not mutate the loan until Save):**

Standard reducing-balance (Nexus default, kernel not recovered):

```
r = annualRatePct / 100 / 12          # monthly
if r == 0: emi = principal / n
else:      emi = P * r * (1+r)^n / ((1+r)^n - 1)

For month k:
  interest_k = balance * r
  principal_k = emi - interest_k
  balance    = balance - principal_k
```

Simulator inputs: new rate, new EMI, extra monthly principal. Outputs: new tenure, total interest, interest saved vs current. Render amortization table (month, emi, interest, principal, balance).

**Floating:** store `loan_rate_changes`. Future schedule uses the latest rate as of each month. User must enter rate changes; never invent them.

**Nexus overlap:** keep `Loan` category exclusion for repayments. When a txn is linked to a loan, auto-set category `Loan` so it stays out of the budget. Do not double-count EMI as both a loan object payment and Food.

### 7.8 Upcoming (the timeline)

**Sources (union):**

- Subscription `nextDue` (active)
- Bill `nextDue` (active)
- Loan EMI `nextDue` (active)
- CC statement due from `CreditCardForecastEngine` (you already have this)
- Budget period end (optional, low priority)
- Goal target dates (optional)

**Groups:**

1. Overdue (`date < today`)
2. Due soon (`today .. today+7`) **Nexus default**
3. Later

Sort inside group by date, then amount desc.

**Per item actions:** Mark paid (manual marker — no txn), Open source, Link existing txn.

**Before mark paid:** confirm money actually moved. If unsure, reconcile first.

**Policy:** edit source → reopen Upcoming to verify. No duplicate edits.

**Sage/count:** upcoming pending count is the only obligation number MoneySplit sends to cloud. We should not send it unless we add a cloud composer path; local Upcoming does not need it.

### 7.9 Merchants & rules

**Directory filters:**

| Filter | Definition (Nexus default where help is vague) |
|---|---|
| All | All merchants, order by **this calendar month** spend desc |
| Active this month | `lastSeen` in current month |
| High spend | top **25%** of this month’s merchant totals (min 4 merchants or skip) |
| Growing | MoM spend `meetsFloor` **and** ≥ **+25%** vs previous month |
| Dormant | no spend for **60 days**, but had spend in the 180 days before that |

**Badges:** Spike (count or spend ≥ 2× last month and meetsFloor); New (first txn ever); Recurring (txn in ≥ 3 successive months).

**Detail snapshot:** total spend, lifetime count, average size, first/last date.

**Charts:** spend by parent category (progress list); spend by account (progress list); **6-month bar** of monthly totals (reuse `historicCalendarBars`).

**Combine similar names:** suggested aliases from scanner; checkbox; Link Selected; Unlink later. Future scans map to canonical.

**Resync Rules:** rebuild *automated* category mappings from history. **`customRuleLocked` never overridden.**

**Cleanup Rules:** delete orphan aliases / duplicate mappings. Confirm count.

### 7.10 Savings goals & sinking funds

| Strategy | Math |
|---|---|
| Target date | `monthlyPace = max(0, target - saved) / max(1, monthsLeft)` linear |
| Flexible refill | each period, `shortfall = max(0, target - saved)`; prompt to fill |
| Monthly builder | add `flat` every month regardless of spends |

**Status:** ahead / on track / behind — compare `saved` to `expectedSaved` (linear from start). Threshold: 8% of target or ₹100, same spirit as pace.

**Category targets:** budgeting that category auto-contributes (when user allocates) toward the goal. Swipe-to-delete target (confirm). Tap → that budget period.

**Deposit/Withdraw:** adjust `currentSaved` via action sheet; optional linked transfer txn.

**Quick Budget “Fund Underfunded Goals”** uses these targets (see §7.4).

Widget/Wear already expect `goal_percent = saved/target`, `monthly_pace`, `next_milestone`.

### 7.11 Life-hours (badge, not a new religion)

**Do not replace** `SalaryScreen` / hike / CC forecast.

**Simple rate (help):**

```
hourly = monthlyNet / (weeklyHours * 4.333)
```

**Nexus default inputs:** `monthlyNet = current salary_entries.amount`; `weeklyHours` default **40**, user editable.

**Real wage (YMOYL):**

```
real = (monthlyNet - commuteCost - workMeals - jobOverhead)
       / (weeklyHours * 4.333 + monthlyCommuteHours)
```

Guard: if denominator ≤ 0 or rate ≤ 0, hide badge.

**Display (exact native formula):**

```
minutes = round(amount / hourlyRate * 60)
hours = minutes ~/ 60
mins  = minutes % 60
text  = hours>0 && mins>0 ? "${hours}h ${mins}m"
      : hours>0 ? "${hours}h"
      : "${mins}m"
badge = "⏱ ≈ $text of work"
```

Show **under the amount field** in add/edit expense when enabled. Standalone calculator = Settings app-bar + optional widget chips `+10 / +50 / +100 / RESET`.

Widget prefs: `widget_life_hours_hourly_rate`, `widget_life_hours_today`, `widget_life_hours_week`, `widget_calc_amount`, `widget_calc_time_result`.

### 7.12 Insights feed (new) vs existing Insights tab

Keep the existing tab as **Analytics** (charts). Add a **feed** of cards.

**Card types to implement (facts in code, copy optional LLM via same grounding pipeline):**

| Id | Trigger (Nexus default) | Drilldown |
|---|---|---|
| `pace_over` | `PaceStatus.overPlan` | Tracker |
| `pace_ahead` | `aheadOfPace` | Tracker |
| `mom_up` / `mom_down` | existing `momDelta` + `meetsFloor` | Trend modal |
| `category_outlier` | a category’s MoM `meetsFloor` (reuse `_categoryShift`) | filtered txns |
| `top_share` | top category ≥ 50% (you already warn in `_tone`) | category timeframe |
| `top3_concentration` | top 3 ≥ 70% | Analytics |
| `six_month_high/low` | existing `_sixMonthExtreme` | Trend |
| `dow_peak` | existing DoW peak copy | Analytics DoW |
| `cc_due` | open statement due within 7 days | Salary / Upcoming |
| `salary_short` | `SalaryMonthForecast.isShort` | Salary |
| `sub_leak` | active subs sum ≥ 15% of salary | Subscriptions |
| `merchant_spike` | Spike badge | Merchant detail |
| `pending_review` | pending > 0 | Review |
| `uncategorized` | Others ≥ 20% of month | History filter |
| `goal_behind` | goal status behind | Goals |

**Lifecycle:**

- Rebuild after: large import, category/tag cleanup, budget finalize, merchant merge.
- User can dismiss (store `dismissedInsightId+periodKey`). Do not rebuild dismissed until next period.
- Never act from a card without drilldown for money-moving decisions (same as their help).

**Composer:** reuse `ExpenseInsightService` + `InsightGrounding`. Add tokens; do not send rows.

### 7.13 Sage / AI Ask

Nexus already has `expense_ai_ask_sheet` + `ExpenseAiSearchService` (list or chart). MoneySplit Sage extras worth taking:

- Prompt chips: “top categories this month”, “what changed vs last month”, “reduce recurring”, “add 500 lunch from last account”, “open upcoming”.
- Voice: we already have STT gateway. Keep on-device instant + gateway replace-if-untouched.
- Confirmation in **source screens** for any write (“add 500…”) — parse intent, open `AddExpenseModal` prefilled, do not silent-write from chat.
- Privacy: still no SMS bodies, no PDFs, no full account numbers, no OTP.

Do **not** add “user pastes Gemini key in Settings” unless product asks. We have a backend composer.

### 7.14 Settings extras worth taking

| Item | Take? | Notes |
|---|---|---|
| Biometric/PIN app lock | Optional | `local_auth` already on device for other apps; expense data is sensitive |
| Backup accounts+txns+presets | Yes, later | We have Google Drive in Cloud; do not store raw notification text |
| Reset transactions keep accounts/categories | Yes | Distinct from nuke easter egg |
| Export Excel | Optional | We are not a reporting suite first |
| FX cache | Skip until multi-currency accounts exist | |
| Floating pill nav / handedness / 0.5–3s auto-hide | Skip | Different shell (`AppShell`) |
| Premium palettes / RevenueCat | **No** | |
| Help hub | Optional | This handover is the implementer guide |

---

## 8. Charts & analytics catalog

### 8.1 Keep (already in Nexus)

| Chart | File | Logic |
|---|---|---|
| Budget ring + leftover + safe daily | `tracker_tab` + `budget_ring` | `MonthPace` |
| Heat month | `tracker_tab` | `heatMonth` |
| Historic month bars 6/12 | `tracker_tab` | `historicCalendarBars` |
| Trend line + period compare | `expense_trend_modal` | spend-only |
| Category / bank / card breakdown bars | `insights_tab` | period chips Week/Month/3M/6M/All/NT |
| Day-of-week total / avg / txns | `insights_tab` | `_DowViewMode` |
| Investment cumulative sparkline | `investmentCumulativeMonthlySeries` | running sum by YYYY-MM |
| Salary spent vs left bar | `salary_insights_card` | salary − spend |
| AI search category pie / daily / monthly bars | `expense_timeframe_screen` | `ExpenseChart` |
| Top merchants list | `ExpensePaceMetrics.topMerchants` | by description string — **replace source with merchantId** once Step D lands |

### 8.2 Add (MoneySplit-grade, missing or weak)

| Chart | Placement | Exact series |
|---|---|---|
| **Income vs expense** side-by-side bars | Analytics, period chips | per month: `sum(income)` vs `sum(spendOnly)`. Net line optional. |
| **Category growth** | Analytics | last 6 months, top 5 cats, grouped or small-multiples bars. Hide if `meetsFloor` fails for all. |
| **Merchant 6-month** | Merchant detail | `historicCalendarBars` filtered `merchantId` |
| **Budget Sankey** | Budget detail | §7.4 |
| **Spend by account** progress | Merchant detail + Analytics | percent of merchant/period |
| **Balance trend** | Dashboard health | cash+bank balances over 6 months (needs accounts). Credit shown separately as liability, never summed into “net cash” without a label. |
| **Velocity / burn** | Dashboard widget + budget hero | `burnRate = monthSpent / dayOfMonth`; `projectedMonth = burnRate * length`; `daysLeft`; status = pace status. |

**AI Summary screen** (`dashboard/ai_summary_screen`): this is our grounded recommendation, not a new model. Put the existing `AiRecommendationCard` on Dashboard **and** on the timeframe AI card. Do not run two composers.

**Explainability rule (theirs + ours):** Analytics = numbers; AI = narrative over those numbers. User must be able to tap a chart → filtered rows (`expense_timeframe_screen`).

---

## 9. Smart Scan / SMS / notifications (logic + retry)

### 9.1 What to keep from Nexus SMS

- Templates T1–T8 HDFC, Axis, ICICI, Scapia; discard E-Mandate / OTP / credits **until Step C**, then parse credits as income.
- `SmsIntakePolicy` arrival kinds and undo rules.
- Native minute-bucket deduper + queue max 40.
- `suggestSmsCategory` + learnings + VPA labels.
- Raw body never on the row.
- Save: 3 attempts, unique → success, Telegram on final fail.
- Dual parser: Kotlin `BankSmsParser` must stay in lockstep with Dart (existing tests).

### 9.2 Pipeline to add (`pipeline_config.json` — copy constants, not their file into git if it is huge; re-express in Dart)

```dart
class ScanPipelineConfig {
  static const sameTypeDedupWindow = Duration(minutes: 15);
  static const bankToBankWindow = Duration(minutes: 30);
  static const ccPaymentWindow = Duration(hours: 120);
  static const ccAmountToleranceInr = 25.0;
  static const intermediaryAutoPromoteToTransfer = true;
  static const manualScanChunk = 200;
  static const isolateMaxChunk = 500;
  static const backgroundLinkingScope = Duration(hours: 72);
  static const anchorMaxAge = Duration(days: 90);
  static const onlyUpdateAnchorIfNewer = true;
}
```

**Dedup (posted + pending):** same `accountId` + amount within 15 minutes **or** same `externalRef` (IMPS/NEFT/RTGS/UPI/RRN) — **reference wins**. Also keep native 1-minute sender+amount bucket as a first line of defence.

**Last-4 collision:** `6308` vs `308` — MoneySplit release notes mention digit merge. **Nexus default:** match if one suffix equals the other (length 3–5). If still ambiguous, pending review.

**Transfer linking:**

1. Expense and income, same amount, different accounts, ≤ 30 min → propose transfer (or auto if both high-confidence SMS).
2. Credit-account debit (spend) vs bank debit to an **intermediary**, then credit-account **payment** within 120 h, amount ±₹25 → keep **one** card spend + **one** repayment transfer; drop the intermediary duplicate.
3. Intermediaries (India-first): Paytm, PhonePe, Google Pay, GPay, CRED, CRED Club, CheQ, PayZapp, MobiKwik, Freecharge, BharatPe, Razorpay, Simpl, LazyPay, Slice, Uni Card, Jupiter, Fi Money.

**Fast-fail:** before full parse, require a financial hint (`debited|credited|spent|UPI|Rs|INR|₹|…`). OTP / declined / reversed / failed → ignore (MoneySplit `ignore` / `otp` keys).

**Personalization (on-device category ML — Nexus default, no cloud):**

```
minReviewedSupport = 3        // user-confirmed rows for that merchant
dominanceThreshold = 0.70     // one category ≥ 70% of those
suggestConfidence  = 0.50     // show suggestion
autoApplyConfidence = 0.75    // auto-apply only in auto mode
entropyThreshold   = 1.2      // if category distribution too mixed, do not auto
recencyHorizonDays = 365
shadowMode = false            // true = suggest only
```

Never override `isManualCategory == true`. Never override `customRuleLocked` merchant rules.

**Anchor engine:** SMS balance / due amount updates the account **only if** the SMS date is newer than the last anchor and not older than 3 months.

### 9.3 Notification listener (Android)

MoneySplit: off by default; Notification Access; **allowlist of packages**; reject unselected apps **before reading title/text**; same parse/dedup/transfer pipeline as SMS; SMS+notif of the same txn → **one** row; raw text **not** stored as note, log, analytics, or backup.

**Modes (map to our SMS modes):**

| MoneySplit | Nexus |
|---|---|
| Ask me first | `ask` — tray / overlay, no row yet |
| Add to Pending Review | pending `status=pending` (new) |
| Auto add | `auto` — high confidence only; else pending |

**Queue (copy their robustness, not their package names):**

- File: encrypted (AES-GCM). Max **100** events, **1 MB**, TTL **24 h**.
- Headless Flutter/engine: if queue leftover after drain, **retry in 60 s**.
- Identity: `packageName + profileKey + signingCertSha256` (anti-spoof).
- Pigeon-style MethodChannel is fine (`app.ainexus.ai_nexus/notif_expense`).

**India allowlist seed** (`notification_app_catalog.json`): GPay, PhonePe, Paytm, HDFC Now, ICICI iMobile, YONO SBI, BHIM. User can add more from “observed apps”.

**Capability states to surface in Settings:** Unsupported / Not granted / Granted disconnected / Granted connected / Restricted.

**Clear data:** wipes queued ciphertext + processing metadata. System Notification Access may stay on until the user revokes it — show that sentence in UI.

**Do not** enable this in the same PR as SMS. Ship SMS transfer-linking first.

### 9.4 Custom SMS rules (“Tap-to-Tag”)

For unrecognized senders: user highlights amount / merchant / card digits in a sample SMS (no regex required in the UI). Store as a rule `{senderPattern, fieldMap}`. Test against the sample before enabling. Enable/disable/swipe-delete. **Nexus default cap: unlimited** (they gated at 3 on free — ignore).

If a rule starts producing junk: disable, do not delete, keep history.

### 9.5 PDF / CSV / migration (Step K)

**CSV/Excel columns to confirm:** date, amount, account, category, subcategory. Empty description stays empty — **never** write “imported from …” into description.

**PDF statements:** password optional; debit/credit direction; pause + re-run rather than import garbage. India parsers they ship (do not port blindly; treat as a checklist of banks): Axis/HDFC/ICICI/SBI/Kotak/IDFC/HSBC/IndusInd/OneCard/BoM/Equitas CC line formats.

**Import lock:** while one import runs, block SMS history import, PDF, CSV, migration (prevents duplicates). Show progress on Smart Scan home. Prefer keep-app-open.

**Money Manager migrate (only if we ever support it):** Transfer-Out = transfer from Account column to Category column when both accounts exist; recheck after account setup; ignore icons; do not create categories from numeric IDs.

### 9.6 Review flow (all sources)

1. Account mapping first  
2. High-value next  
3. Category/tag mismatches  
4. **Reject uncertain** rather than force-import  
5. Finalize → spot-check History → reconcile subs/bills/loans → rebuild Insights/Dashboard  

Statement extraction wrong → Pause → fix mapping → Re-run.

---

## 10. Widgets & deep links

### 10.1 Keep existing Nexus expense widget

Today total/count, month spent/count, top category. Midnight stamp, 3× retry. Tests: `ExpenseWidgetLogicTest`.

### 10.2 Add (MoneySplit Glance family — pick 2 first)

| Priority | Widget | Prefs / payload | Tap |
|---|---|---|---|
| 1 | **Dashboard / Budget hero** 4×2 | `spent, limit, remaining, days_left, burn_rate, status`, category JSON, recent tx JSON | `ainexus://expense/budget` |
| 2 | **Bills & subs** 4×2 | list `{id, name, amount, due, type, isTrial, isPromo, status}` pending count | `ainexus://expense/upcoming` |
| 3 | Today 2×2 | spent vs daily budget, today income, invested, life-hours | today timeframe |
| 4 | Quick actions 4×1 | Expense / Income / Transfer / Scan | add modal with type |
| 5 | Goals 2×2 | saved/target/pace | goals |
| 6 | Calendar 4×4 | per-day spent + due dots | day drilldown (we already have `onOpenDay`) |
| 7 | Life hours 2×2 | rate, today/week hours, +10/50/100 calc | calculator |

`updatePeriodMillis = 0` — Dart pushes prefs, then requests update (same as now).

Period switch D/W/M on the summary widget: store `widget_summary_period` and recompute on action.

### 10.3 Deep links (theirs → ours)

Use `ainexus://` (or existing scheme). Support:

```
/expense
/expense/add?type=expense|income|transfer
/expense/scan
/expense/txns?type=&from=&to=
/expense/budget
/expense/analytics?tab=categories
/expense/upcoming
/expense/goals
/expense/salary
```

Home-widget launch already exists for Search; reuse the pattern.

Wear OS Data Layer (`/money_split/wear_tile_data`) is **out of scope** unless we ship a watch face. The key list is a **payload checklist** for a future compact summary (pacing_*, goal_*, life_hours_*, upcoming_bills_json).

---

## 11. Retry, queues, and failure contract (implement every write this way)

Copy the **spirit** of ExpenseRepository / SMS / widget / STT — not a new framework.

| Path | Attempts | Backoff | Permanent (do not retry) | User sees | Log |
|---|---|---|---|---|---|
| Local Drift write | 1 | — | schema errors | error sheet | `TLog.e` |
| Cloud sync POST/DELETE | 3 | 400ms × n | 401/403 | local success, later banner | `TLog.w` then `TLog.e` |
| SMS save | 3 | 400ms × n | unique constraint = success | toast / review error | `TLog.e` after 3 |
| SMS native queue | durable file, max 40 | drain on resume | — | waitingCount | — |
| Notif queue | AES file, max 100, TTL 24h | engine retry **60s** if leftover | malformed drop | pending review | — |
| Widget refresh | 3 | 500ms doubling | missing channel | stale until next | `TLog.d` |
| Transfer linker | 1 per batch + 72h background pass | — | amount mismatch | stays unlinked | — |
| Quick Budget | snapshot undo 8s | — | — | snackbar Undo | — |
| Insight compose | 1 | — | any HTTP fail | **template** (already) | `TLog.e` |
| PDF/CSV import | chunks of 200 | pause/resume | bad mapping | progress + retry chunk | — |
| Merchant “update past” | one transaction | — | user cancel | progress count | — |

**Overlapping imports:** mutex. Second start → toast “Import already running”.

**Headless SMS/notif:** if Dart is dead, queue; never drop a high-confidence debit. On process death mid-save, unique id (`sms-{id}`) + unique constraint makes retry safe.

**Telegram:** final failures `TLog.e` (flush). Transient retry `TLog.w`. Never log raw SMS, PAN, OTP, notif body, or backup tokens.

---

## 12. Edge cases (do not skip)

1. Future-dated expense → Insights NT, not Week. Budget monthly: belongs to the month of `date`, not “today”.
2. Timezone: parse to local like `expensesInInsightPeriod`.
3. Month length: statementDay 31 in February → clamp (already in CC engine).
4. `remainingDays` at least 1 (already in `monthPace`).
5. Transfer delete: confirm and delete **both legs** (`transferGroupId`).
6. Account delete with txns: block or reassign.
7. Two SMS + one GPay notif for the same UPI ref → one row (ref priority).
8. CRED pays a card, then the bank posts the card settlement → intermediary skip.
9. Salary credit SMS (once we parse income) must **not** hit the budget.
10. Refund (`credited`) → income, optionally suggest linking to original expense by amount+merchant ≤ 14 days (**Nexus default**).
11. Split bills with friends: **out of scope**.
12. Force-linked + exclude tag: still in budget (override).
13. Parent envelope auto-expand must not shrink later when a child is reduced below — **inferred:** shrinking parent only if `explicitAssigned` was false; if user typed the parent, keep max(parent, sum(children)).
14. Finalize then edit a txn date into that period: period is frozen — either block or show “re-open period”. **Nexus default:** allow the txn edit, **do not** change frozen totals; show a note. (Avoid silent history rewrite.)
15. Widget midnight: zero today; if month rolled, zero month metrics (already).
16. `alreadyRunning` loan without original principal: progress ring labelled “since {addDate}”, never “72% paid off”.
17. Life-hours with salary 0: hide badge, do not divide by zero.
18. Merchant merge: move aliases; rewrite `merchantId` on txns; rebuild memory.
19. Custom SMS rule too broad (`.*`) → validation reject.
20. Notification from an unselected app: drop **before** parsing.
21. Queue TTL 24h: expired events die; user can re-scan SMS history if we add it.
22. `Others` category: valid but Insights flags share ≥ 20%.
23. Voice add + SMS auto for the same spend: 15-min same amount+account dedup should catch; if descriptions differ, pending not silent-drop.
24. Investment purchase via CC: category Investment still non-spend; liability still rises on the card (outstanding ≠ budget). Show both facts in details.
25. Nuke easter egg: remains expenses+budget; **do not** silently wipe accounts/goals without the same confirmation path.

---

## 13. Suggested Drift / Dart file map (where to put code)

Do not dump 5k more lines into `insights_tab.dart`.

| Module | Path |
|---|---|
| Account entity + repo | `lib/domain/entities/account.dart`, `lib/data/repositories/account_repository.dart` |
| Merchant | `lib/data/repositories/merchant_repository.dart` |
| Budget period math (pure) | `lib/core/services/budget_period_engine.dart` **unit-test like pace** |
| Upcoming union | `lib/core/services/upcoming_engine.dart` |
| Transfer linker | `lib/core/services/transfer_link_engine.dart` |
| Scan pipeline config | `lib/data/services/sms_auto_expense/scan_pipeline_config.dart` |
| Insight feed facts | `lib/core/services/expense_insight_feed.dart` (pure) |
| Life hours | `lib/core/services/life_hours.dart` |
| Loan PMT | `lib/core/services/loan_amortization.dart` |
| Goal pace | `lib/core/services/savings_goal_engine.dart` |
| Tables | `app_database.dart` migrations, one version bump per Step |
| UI | `presentation/screens/expense/accounts/`, `budget/`, `upcoming/`, `obligations/`, `merchants/`, `scan/` |
| Widgets | extend `expense_widget_service.dart` + new Kotlin providers **or** Glance later |

Pure engines: no I/O, no Flutter. Tests next to `test/core/services/expense_pace_metrics` style.

---

## 14. Test plan (must exist before UI polish)

### 14.1 Pure engines

- Budget predicate: monthly OR-include, custom AND-include, exclude, force-link, account scope, View All == totals.
- Parent auto-expand / explicit ceiling.
- Badges: Unbudgeted / Over / Spent / Near / Underfunded / Healthy.
- Transfer linker: 30 min bank-bank; 120 h ±₹25 CC; intermediary list; no link across 121 h.
- Dedup: 15 min same account+amount; reference equality across 1 hour; different refs not merged.
- PMT: known trio (e.g. P=500000, 10% annual, 60 months → EMI ≈ ₹10623.52; last balance ~0).
- Life hours: ₹150 / ₹25/hr → `round(150/25*60)=360` → `6h`.
- Goal linear pace and behind/ahead with 8% or ₹100 band.
- Upcoming grouping overdue / 7-day / later.
- Insight period NT vs Week (already have `insight_period_bucketing_test` — keep).
- `monthPace` still goldens after budget-period introduction.

### 14.2 SMS / notif

- Existing `BankSmsParserTest` + Dart parser tests stay green.
- New: credit SMS → income; UPI ref shared by SMS+fake notif → one row.
- Intake policy matrix unchanged.
- Unique id retry does not duplicate.

### 14.3 Migration

- Existing expenses: every row has `accountId`, `type=expense`, widget still matches today/month totals (±₹0.01).
- Investment/Loan still excluded from ring and widget.

### 14.4 Sync

- Local add works offline; 3× POST; 401 no retry; tombstones still apply.

### 14.5 UI (if you change layout)

Browser/device: add expense, SMS ask, budget envelope Over, mark upcoming paid without a second txn, merchant merge then chart.

---

## 15. Implementation notes per Step (retry + accuracy)

**Step B Accounts**

- Migration in Drift `onUpgrade`: distinct `(bank, cardType)` → account; backfill `accountId`.
- Settings “banks” editor writes **accounts** (keep the same UI). `statementDay`/`dueDay` live on the credit account.
- Retry: none extra. If migration throws, abort upgrade — Drift will retry on next launch; never half-write (one transaction).

**Step C Income/Transfer**

- Add-expense modal: type segmented control. Transfer UI: from account, to account, one amount, two legs same `transferGroupId`, opposite signs / types.
- SMS: lift `_credit` early-return; parse as income; then run linker.
- Accuracy: deleting a transfer deletes both legs or neither.

**Step D Merchants**

- On write: normalize description (`remove pvt/ltd/india/payment…` from `pipeline_config.merchantCleaning`), match alias, else create merchant.
- Merge is reversible via Unlink.

**Step E Categories/tags**

- `Others` remains. Subcategories optional.
- Learnings key off **merchant canonical**, not raw SMS.

**Step F Budget periods**

- First launch: create an active monthly period with `masterLimit = current budget_entries last amount`, scope all spend accounts, no tags.
- Pace ring reads that period’s master + spend-only usage.
- Quick Budget undo snapshot in RAM only (8s).

**Step G Obligations + Upcoming**

- Seed: none. Optional: “Track Netflix?” from merchant.
- CC dues from existing forecast engine — **first Upcoming rows we can ship without new user input**.

**Step H Scan**

- Feature-flag notification listener (`false` until Settings toggle).
- Custom rules behind the same SMS settings screen.

**Step I Feed + charts**

- Feed facts 100% local. Composer optional.

**Step J Goals + life-hours**

- Life-hours default off until weekly hours set once.
- Goals do not auto-move cash unless user deposits.

**Step K Widgets/CSV/PDF**

- Only after pending-review exists (otherwise CSV will trash Insights).

---

## 16. Subscription catalog (optional asset)

If you vendor a trimmed catalog:

- Schema: `id, name, categoryKey, brandColor, merchantAliases[{value, matchType, priority}], cancellation.url`
- Country file: `providers[].plans[].prices[{amount, currencyCode, billingPeriod}]`
- IN examples exist in the dump under `assets/config/subscription_catalog/v1/countries/IN.json`.
- Do **not** copy their 113-provider list as a product identity. Use it as **alias intelligence**.

---

## 17. Release-note logic worth stealing (not in help markdown)

From `RELEASE_NOTES.md` in the dump:

- **Manual marker** on Upcoming (v1.2.0) — prevents SMS users double-counting.
- **Parent explicit ceiling + auto-expand** (v1.4.1).
- **Fill Unbudgeted Only** vs overwrite-all.
- **Tap-to-tag SMS** (v1.4.0) without regex.
- **Transfer deletion both legs** (v1.3.9).
- **Amortization simulator** (v1.3.8).
- **Paycheck and open-ended budgets + Sankey** (v1.3.1).
- **Digest scheduling** daily/weekly/monthly (optional; we have Telegram already — do not spam).
- **Financial notes hub** (v1.5.0) — **defer**. Nexus already has `comments` on expenses. A second notes product is scope creep until the ledger is solid.
- **Investment tracker screens** (v1.3.8) — Nexus already has an Investment category + sparkline. Do not build a second portfolio app. Optional: dedicated timeframe we already open from the KPI card.

---

## 18. Mapping MoneySplit screens → Nexus UX (so we do not clone the chrome)

| MoneySplit | Nexus home |
|---|---|
| Dashboard | First page of Expense **or** a slim header on Tracker (health + 3 smart actions + upcoming strip) |
| Spending / category analytics | Current Insights tab, renamed Analytics |
| AI summary | Existing recommendation card (grounded) |
| Accounts | New, seeded from Settings banks |
| Transaction history | Tracker list + timeframe screen |
| Review | SMS overlay generalized to all pending |
| Budget dashboard/detail/Sankey | Tracker ring + new envelopes sheet |
| Upcoming | New sheet/tab |
| Smart Scan | Settings SMS + new Scan entry |
| Merchants | Long-press description / new directory |
| Sage | Existing AI Ask |
| Life hours | Badge in add modal + Settings |
| 8 widgets | 1 existing + 2 new |

Handedness / pill nav / gold theme / Pro upsell: **ignore**.

---

## 19. Constants cheat-sheet (copy into code)

```
WEEKS_PER_MONTH          = 4.333
LIFE_HOURS_MINUTES       = round(amount / rate * 60)
PACE_PCT                 = 0.08
RUPEE_FLOOR              = 100
PCT_FLOOR                = 0.05
NEAR_BUDGET              = 0.85
TOP3_CONCENTRATION       = 0.70
TOP_SHARE_WARN           = 0.50
OTHERS_FLAG              = 0.20
SUB_LEAK_OF_SALARY       = 0.15
DEDUP_WINDOW             = 15 min
TRANSFER_WINDOW          = 30 min
CC_PAY_WINDOW            = 120 h
CC_PAY_TOLERANCE         = ₹25
LINK_AMOUNT_TOLERANCE    = max(₹25, 2%)
LINK_DATE_WINDOW         = ±5 days
REFUND_WINDOW            = 14 days
UPCOMING_SOON            = 7 days
DORMANT_DAYS             = 60
GROWING_PCT              = 0.25
HIGH_SPEND_QUARTILE      = 0.25
PERSONALIZATION          = support 3, dominance 0.70, auto 0.75, entropy 1.2, 365d
NOTIF_QUEUE              = 100 events, 1MB, TTL 24h, retry 60s
SMS_QUEUE                = 40 (existing)
SYNC_TRIES               = 3, 400ms * n
WIDGET_TRIES             = 3, 500ms doubling
QUICK_BUDGET_UNDO        = 8s
BILL_REMINDER_DEFAULT    = 2 days
SALARY_CREDIT_DAY        = 28 (existing)
IMPORT_CHUNK             = 200
ANCHOR_MAX_AGE           = 3 months
MASK_DIGITS              = 3–5 only
RECEIPT_EXT              = jpg/jpeg/png
```

---

## 20. Do not copy

- RevenueCat `free/pro/pro_plus`, 250 auto-tx/month, 10 accounts, 8 subs, 3 custom rules — Nexus is a personal app, not a funnel.
- `AD_ID`, AdServices, Firebase Analytics as a product requirement.
- `getAndroidId` device_info channel.
- Clone protection / pairip / Play Integrity wrapper.
- `isTelemetryPushEnabled`.
- Amazon IAP.
- Storing full card numbers.
- Raw notification/SMS text in backups or Telegram.
- Friend expense-splitting (the APK name is a lie; there is no Splitwise engine).
- Receipt **OCR** (their own flag is false).
- Whisper-cloud Sage (their own help: preview, not enabled). We already have a gateway — keep our fluid on-device-first design.
- Replacing grounded tokens with “let the model look at the ledger”.
- Summing credit-card outstanding into “cash balance”.
- Mark-as-paid that inserts a duplicate expense for SMS users.
- Fake amortization if original principal is unknown.

---

## 21. Definition of done (per Step)

A Step is done when:

1. Existing tests still pass (`sms_parser`, pace, insight period, widget, salary, add-expense banks).
2. New engine has unit tests for every formula in that Step.
3. Offline write works; sync retries 3×; Telegram on final fail; no secrets in logs.
4. Investment/Loan still excluded from spend.
5. Widget today/month still correct if that Step touches writes.
6. Pending rows cannot change the budget ring.
7. You can explain every number on the new UI from a SQL predicate.

---

## 22. What this handover is not

It is not a pixel-perfect recreation of MoneySplit, not a Splitwise clone, and not permission to rip their subscription catalog into the Play listing. It is the **logic, edge cases, chart catalog, and retry contract** to make Nexus Expense as informative as a real ledger while keeping the salary/CC/pace/grounding brain we already have.

If an ABI `libapp.so` dump appears later, re-run string extraction for EMI kernel and exact SQLite schema and **patch this file** — do not silently change PMT without tests.
