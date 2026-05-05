# AI NEXUS — Figma-to-Flutter Conversion Master Plan
# Based on Deep Analysis of 15,413 Lines of React/TypeScript Source Code

---

## CRITICAL FINDING

Your Figma Make prototype is a **fully working React app** — not just static screens.
It has complete business logic, state management, AI categorization, theme switching,
and animations. This is your **definitive spec**. The earlier HTML mockups are obsolete.

---

## 1. WHAT THE FIGMA PROTOTYPE ACTUALLY CONTAINS

### App Structure (4 Bottom Nav Tabs + Settings Sheet)

```
📱 AI NEXUS App
├── 🏠 Expense (Home) — Tab 1
│   ├── Tracker Sub-tab
│   │   ├── Budget Ring (animated SVG donut)
│   │   ├── Balance Card (gradient, adapts to budget status)
│   │   ├── Category Pie Chart (recharts)
│   │   ├── Expense List (swipe to edit/delete)
│   │   ├── Analysis Section (5 periods, bar charts)
│   │   └── Trend Modal (full-screen chart)
│   ├── Insights Sub-tab
│   │   ├── Period Selector (Today/7D/1M/6M/All)
│   │   ├── Area Chart (spending trend)
│   │   ├── Category Breakdown (bar chart)
│   │   ├── AI Smart Analysis Card
│   │   ├── Search + Filter
│   │   └── Anomaly Detection
│   └── Modals:
│       ├── Add Expense (AI Scan + Manual, bank/card selector)
│       ├── Edit Expense
│       ├── Set Budget
│       ├── Budget History
│       └── Success Animation (confetti)
│
├── 📰 News (Discover) — Tab 2
│   ├── For You Sub-tab
│   │   ├── Featured Card (hero, 400px tall)
│   │   ├── Category Filters (horizontal scroll)
│   │   ├── News Cards (image + excerpt)
│   │   ├── Pull-to-Refresh
│   │   └── Notification Panel
│   ├── Saved Sub-tab
│   │   ├── Search Saved Articles
│   │   └── Saved Article Grid
│   └── Article Detail Modal
│       ├── AI Summary Section
│       ├── Reading Progress Bar
│       ├── Content Blocks (paragraph, heading, quote, stat)
│       └── Action Buttons (share, bookmark, read)
│
├── 🎓 AI Coach (Tutor) — Tab 3
│   ├── Rephrase Sub-tab
│   │   ├── Text Input (500 char limit)
│   │   ├── Voice Recording Button
│   │   ├── Platform Selector (7 platforms: Email Long/Short, Slack, WhatsApp, Twitter, LinkedIn, Teams)
│   │   ├── Platform Results with "Why It Works" + Techniques
│   │   └── Copy-to-Clipboard
│   ├── Coach Sub-tab
│   │   ├── Text Input (300 char limit)
│   │   ├── Corrected Text with Highlights
│   │   ├── Platform × Tone Matrix (5 platforms × 3 tones)
│   │   └── Pro-tip Card
│   └── Dictionary Sub-tab (LexiAI)
│       ├── Word Search
│       ├── Definition + Pronunciation + Example
│       ├── Save to Vocabulary
│       └── Saved Words Library
│
├── ☁️ Cloud — Tab 4
│   ├── Files Sub-tab
│   │   ├── Featured File Card
│   │   ├── File List (with star, delete, download)
│   │   ├── Upload Flow (progress, speed, ETA)
│   │   └── File Details
│   └── History Sub-tab
│       ├── Sync History Timeline
│       └── Transfer Details
│
└── ⚙️ Settings (Bottom Sheet Modal — not a tab)
    ├── Profile Avatar (gradient ring + edit)
    ├── Name + Email
    ├── AMOLED/White Theme Toggle
    ├── Bank Accounts CRUD (add/delete)
    ├── AI Preferences
    ├── Security
    ├── Notifications
    ├── About
    └── Sign Out
```

### Key Technical Details from Source Code

| Aspect | React Implementation | Flutter Equivalent |
|--------|---------------------|-------------------|
| Font | Plus Jakarta Sans (400-700) | `google_fonts` or bundled TTF |
| Theme | `palette.ts` with createPalette(dark/white) | `ThemeData` + `ThemeExtension<AppColors>` |
| State | React Context (SettingsProvider) | Riverpod `StateNotifier` |
| Navigation | react-router (4 routes) | GoRouter `ShellRoute` + `IndexedStack` |
| Charts | recharts (AreaChart, BarChart, PieChart) | `fl_chart` |
| Animations | motion/react (framer-motion) | `AnimationController` + `Hero` |
| Icons | lucide-react (48+ icons used) | `lucide_icons` or Material Icons |
| Storage | localStorage | `shared_preferences` + Drift (SQLite) |
| Currency | INR (₹) with en-IN formatting | `intl` package NumberFormat |
| AI Categorize | Rule-based keyword matching (local) | Dart service + LiteLLM for real AI |
| Bottom Nav | 4 icons, white dot indicator, spring animation | Custom `BottomNavigationBar` |
| Settings | DraggableScrollableSheet (bottom sheet) | `showModalBottomSheet` + `DraggableScrollableSheet` |
| Swipe | Touch gestures on expense items | `Dismissible` widget |
| Header | 52px compact, emoji avatar, centered title | `PreferredSizeWidget` 52px |

### Color System (from palette.ts)

```
AMOLED DARK:                      WHITE THEME:
bg:      #000000                  bg:      #FFFFFF
bg1:     #060608                  bg1:     #F8FAFC
bg2:     rgba(255,255,255,0.05)   bg2:     rgba(0,0,0,0.04)
bg3:     rgba(255,255,255,0.08)   bg3:     rgba(0,0,0,0.06)
bg4:     rgba(255,255,255,0.12)   bg4:     rgba(0,0,0,0.09)
text:    #F1F5F9                  text:    #0F172A
text2:   #94A3B8                  text2:   #475569
text3:   rgba(255,255,255,0.42)   text3:   rgba(0,0,0,0.55)
text4:   rgba(255,255,255,0.28)   text4:   rgba(0,0,0,0.38)
text5:   rgba(255,255,255,0.18)   text5:   rgba(0,0,0,0.25)
border:  rgba(255,255,255,0.08)   border:  rgba(0,0,0,0.09)
border2: rgba(255,255,255,0.05)   border2: rgba(0,0,0,0.06)
headerBg:#000000                  headerBg:#FFFFFF
navBg:   rgba(0,0,0,0.97)        navBg:   rgba(255,255,255,0.97)

Category Colors:
Food: #FF6B6B  |  Grocery: #51CF66  |  Transport: #339AF0
Entertainment: #CC5DE8  |  Shopping: #FF922B  |  Bills: #FCC419
Health: #F06595  |  Others: #868E96

Accent: #0D59F2 (Blue — used in settings, buttons)
```

---

## 2. THE APPROACH — TWO PARALLEL WORKSTREAMS

### Workstream A: Give Cursor the React Source as Spec (Primary)

Instead of screenshots, we give Cursor the **actual React source files** as the specification.
Cursor's AI can read React/TypeScript and produce equivalent Flutter/Dart code.

### Workstream B: Use Stitch Screenshots for Visual QA

The 13 stitch PNG screenshots serve as visual reference to verify pixel accuracy.

---

## 3. UPDATED FOLDER STRUCTURE

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── theme/
│   │   ├── app_colors.dart           ← from palette.ts
│   │   ├── app_theme.dart            ← ThemeData dark + white
│   │   └── app_text_styles.dart      ← Plus Jakarta Sans
│   ├── constants/
│   │   └── app_constants.dart
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── api_endpoints.dart
│   │   └── network_info.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── utils/
│   │   ├── extensions.dart
│   │   └── currency_formatter.dart   ← INR formatting
│   └── di/
│       └── injection.dart
│
├── data/
│   ├── local/
│   │   ├── database/
│   │   │   ├── app_database.dart
│   │   │   └── tables/ (expenses, categories, news, cloud_files, ai_conversations, sync_queue)
│   │   └── preferences/
│   │       └── app_preferences.dart
│   ├── remote/ (auth, finance, news, llm, cloud)
│   ├── models/ (freezed DTOs)
│   ├── repositories/ (implementations)
│   └── sync/
│       └── sync_engine.dart
│
├── domain/
│   ├── entities/
│   │   ├── expense_entity.dart       ← from expense.ts types
│   │   ├── category_entity.dart
│   │   ├── news_article_entity.dart  ← from NewsData.ts types
│   │   ├── cloud_file_entity.dart    ← from CloudPage types
│   │   ├── correction_entity.dart    ← from TutorPage types
│   │   └── bank_entity.dart          ← from settingsContext
│   ├── repositories/ (interfaces)
│   └── usecases/
│
├── services/
│   ├── llm/
│   │   ├── litellm_client.dart
│   │   └── ai_categorize_service.dart  ← from aiCategorize.ts (enhanced with real LLM)
│   └── sync/
│       └── background_sync_service.dart
│
└── presentation/
    ├── screens/
    │   ├── landing/
    │   │   └── landing_screen.dart        ← stitch_landing_page
    │   ├── expense/
    │   │   ├── expense_screen.dart         ← ExpensePage.tsx
    │   │   ├── expense_controller.dart
    │   │   └── widgets/
    │   │       ├── budget_ring.dart         ← BudgetRing.tsx
    │   │       ├── tracker_tab.dart         ← TrackerTab.tsx
    │   │       ├── insights_tab.dart        ← InsightsTab.tsx
    │   │       ├── expense_item.dart        ← ExpenseItem.tsx (swipeable)
    │   │       ├── add_expense_modal.dart   ← AddExpenseModal.tsx
    │   │       ├── edit_expense_modal.dart  ← EditExpenseModal.tsx
    │   │       ├── set_budget_modal.dart    ← SetBudgetModal.tsx
    │   │       ├── budget_history_modal.dart
    │   │       ├── expense_trend_modal.dart
    │   │       └── expense_success_modal.dart
    │   ├── news/
    │   │   ├── news_screen.dart            ← NewsPage.tsx
    │   │   ├── news_controller.dart
    │   │   └── widgets/
    │   │       ├── featured_card.dart
    │   │       ├── news_card.dart
    │   │       ├── article_detail_modal.dart ← ArticleDetailModal.tsx
    │   │       └── notification_panel.dart
    │   ├── tutor/
    │   │   ├── tutor_screen.dart           ← TutorPage.tsx
    │   │   ├── tutor_controller.dart
    │   │   └── widgets/
    │   │       ├── rephrase_tab.dart
    │   │       ├── coach_tab.dart
    │   │       ├── dictionary_tab.dart
    │   │       ├── platform_result_card.dart
    │   │       └── voice_record_button.dart
    │   ├── cloud/
    │   │   ├── cloud_screen.dart           ← CloudPage.tsx
    │   │   ├── cloud_controller.dart
    │   │   └── widgets/
    │   │       ├── file_card.dart
    │   │       ├── upload_progress.dart
    │   │       └── sync_history_item.dart
    │   └── settings/
    │       └── settings_modal.dart          ← SettingsModal.tsx (bottom sheet)
    └── widgets/
        ├── app_shell.dart                  ← RootLayout.tsx
        ├── bottom_nav.dart                 ← BottomNav.tsx
        ├── compact_header.dart             ← 52px header pattern
        └── themed_card.dart
```

---

## 4. REACT → FLUTTER COMPONENT MAPPING

| React Component (source file) | Flutter Widget | Lines | Priority |
|------|------|------|------|
| `RootLayout.tsx` | `AppShell` (Scaffold + IndexedStack + BottomNav) | 80 | P0 |
| `BottomNav.tsx` | `BottomNav` (4 icons, dot indicator, spring) | 60 | P0 |
| `palette.ts` | `AppColors` ThemeExtension + `AppTheme` | 150 | P0 |
| `settingsContext.tsx` | `SettingsController` (Riverpod StateNotifier) | 80 | P0 |
| `ExpensePage.tsx` | `ExpenseScreen` (tab controller + modals) | 251 | P1 |
| `TrackerTab.tsx` | `TrackerTab` (budget ring, expense list, charts) | 796 | P1 |
| `InsightsTab.tsx` | `InsightsTab` (area chart, period selector) | 902 | P1 |
| `BudgetRing.tsx` | `BudgetRing` (CustomPainter, animated arc) | 187 | P1 |
| `ExpenseItem.tsx` | `ExpenseItem` (Dismissible, swipe actions) | 216 | P1 |
| `AddExpenseModal.tsx` | `AddExpenseModal` (AI scan + manual entry) | 913 | P1 |
| `EditExpenseModal.tsx` | `EditExpenseModal` | 261 | P2 |
| `SetBudgetModal.tsx` | `SetBudgetModal` | 130 | P2 |
| `BudgetHistoryModal.tsx` | `BudgetHistoryModal` | 646 | P3 |
| `ExpenseSuccessModal.tsx` | `ExpenseSuccessModal` (confetti) | 377 | P2 |
| `ExpenseTrendModal.tsx` | `ExpenseTrendModal` (full chart) | 911 | P3 |
| `NewsPage.tsx` | `NewsScreen` (featured + cards + saved) | 527 | P1 |
| `NewsData.ts` | `news_data.dart` (article models + mock data) | 195 | P1 |
| `ArticleDetailModal.tsx` | `ArticleDetailModal` | 335 | P2 |
| `TutorPage.tsx` | `TutorScreen` (rephrase + coach + dictionary) | 1590 | P1 |
| `CloudPage.tsx` | `CloudScreen` (files + upload + history) | 817 | P2 |
| `SettingsModal.tsx` | `SettingsModal` (DraggableScrollableSheet) | 518 | P1 |
| `aiCategorize.ts` | `AiCategorizeService` (rule-based + LiteLLM) | 120 | P1 |
| `categoryUtils.ts` | `category_utils.dart` (formatCurrency INR) | 105 | P0 |

**Total React lines to convert: ~8,500+ (excluding shadcn/ui library)**

---

## 5. WHAT CHANGES FROM PREVIOUS ARCHITECTURE

| Aspect | Previous (HTML Mockups) | New (Figma React Source) |
|--------|------------------------|--------------------------|
| Tabs | 5 (Home, Insights, Discover, AI Coach, Settings) | 4 (Expense, News, Tutor, Cloud) + Settings as modal |
| Font | Manrope + Space Grotesk | Plus Jakarta Sans |
| Currency | USD ($) | INR (₹) with en-IN locale |
| Primary Color | #4725F4 (purple) | #0D59F2 (blue) for accents, no single primary |
| Categories | Food, Transport, Shopping, Rent, Others | Food, Grocery, Transport, Entertainment, Shopping, Bills, Health, Others |
| Navigation | Purple highlight + indicator bar | White/dark icon + small dot indicator |
| Settings | Full page/tab | Bottom sheet modal |
| Header | Various per screen | Unified 52px compact header |
| AI Feature | Grammar correction only | Rephrase (7 platforms) + Coach (5×3 matrix) + Dictionary |
| Charts | Custom SVG painters | fl_chart (AreaChart, BarChart, PieChart) |
| Budget | Simple balance card | Animated ring with color-coded status |
| Cloud | Not present | Full file manager + upload + sync history |

### What STAYS THE SAME
- ✅ AMOLED dark (#000000) + white theme toggle
- ✅ Offline-first with local DB + sync
- ✅ LiteLLM gateway for all AI features
- ✅ PostgreSQL + Redis on Coolify VPS
- ✅ Clean Architecture + Riverpod
- ✅ GoRouter navigation

---

## 6. BUILD ORDER FOR CURSOR IDE

### Phase 1: Foundation (Core + Theme + Nav)
1. Update `app_colors.dart` from `palette.ts` (EXACT colors)
2. Update `app_theme.dart` with Plus Jakarta Sans font
3. Implement `app_shell.dart` from `RootLayout.tsx` (4-tab IndexedStack)
4. Implement `bottom_nav.dart` from `BottomNav.tsx` (4 icons, dot indicator)
5. Implement `compact_header.dart` (52px, emoji avatar, centered title, action icon)
6. Implement `category_utils.dart` from `categoryUtils.ts` (INR formatting)
7. Update `app_constants.dart` (INR currency, new categories)
8. Update `app_router.dart` (4 routes + landing)

### Phase 2: Expense Hub (Biggest Feature — 3,500+ lines)
9. Implement `expense_entity.dart` from `expense.ts`
10. Implement `budget_ring.dart` from `BudgetRing.tsx` (CustomPainter)
11. Implement `expense_item.dart` from `ExpenseItem.tsx` (Dismissible)
12. Implement `tracker_tab.dart` from `TrackerTab.tsx`
13. Implement `insights_tab.dart` from `InsightsTab.tsx` (fl_chart)
14. Implement `expense_screen.dart` from `ExpensePage.tsx`
15. Implement `add_expense_modal.dart` from `AddExpenseModal.tsx`
16. Implement `set_budget_modal.dart` from `SetBudgetModal.tsx`
17. Implement `expense_success_modal.dart`
18. Implement `edit_expense_modal.dart`
19. Implement `expense_trend_modal.dart`
20. Implement `budget_history_modal.dart`

### Phase 3: News Hub
21. Implement article entities from `NewsData.ts`
22. Implement `featured_card.dart` (400px hero card)
23. Implement `news_card.dart` (horizontal card)
24. Implement `news_screen.dart` from `NewsPage.tsx`
25. Implement `article_detail_modal.dart`

### Phase 4: AI Coach (Tutor) Hub
26. Implement correction entities
27. Implement `rephrase_tab.dart` (7 platform outputs)
28. Implement `coach_tab.dart` (5 platform × 3 tone matrix)
29. Implement `dictionary_tab.dart` (LexiAI)
30. Implement `tutor_screen.dart` from `TutorPage.tsx`
31. Implement `ai_categorize_service.dart` from `aiCategorize.ts`

### Phase 5: Cloud Hub
32. Implement cloud file entities
33. Implement `file_card.dart`
34. Implement `upload_progress.dart`
35. Implement `cloud_screen.dart` from `CloudPage.tsx`

### Phase 6: Settings + Landing
36. Implement `settings_modal.dart` from `SettingsModal.tsx`
37. Implement `landing_screen.dart`

### Phase 7: Data Layer + Backend Integration
38. Update Drift tables (expenses, categories, banks, cloud_files)
39. Connect to LiteLLM via backend for AI categorization
40. Connect AI Coach to LiteLLM for real grammar correction + rephrasing
41. Implement offline sync engine

---

## 7. HOW TO FEED THIS TO CURSOR

### Files to Place in Your Project

```
ai_nexus/
├── docs/
│   ├── ARCHITECTURE.md              ← UPDATE with this new plan
│   ├── FIGMA_CONVERSION_PLAN.md     ← THIS file
│   ├── figma_source/                ← ALL React source files
│   │   ├── App.tsx
│   │   ├── palette.ts
│   │   ├── settingsContext.tsx
│   │   ├── routes.ts
│   │   ├── expense.ts (types)
│   │   ├── categoryUtils.ts
│   │   ├── aiCategorize.ts
│   │   ├── RootLayout.tsx
│   │   ├── BottomNav.tsx
│   │   ├── SettingsModal.tsx
│   │   ├── ExpensePage.tsx
│   │   ├── TrackerTab.tsx
│   │   ├── InsightsTab.tsx
│   │   ├── BudgetRing.tsx
│   │   ├── ExpenseItem.tsx
│   │   ├── AddExpenseModal.tsx
│   │   ├── EditExpenseModal.tsx
│   │   ├── SetBudgetModal.tsx
│   │   ├── BudgetHistoryModal.tsx
│   │   ├── ExpenseSuccessModal.tsx
│   │   ├── ExpenseTrendModal.tsx
│   │   ├── NewsPage.tsx
│   │   ├── NewsData.ts
│   │   ├── ArticleDetailModal.tsx
│   │   ├── TutorPage.tsx
│   │   ├── CloudPage.tsx
│   │   ├── theme.css
│   │   └── white-theme.css
│   ├── stitch_screens/              ← All 13 PNG screenshots
│   │   ├── landing_page.png
│   │   ├── dashboard_home.png
│   │   ├── analytics_page.png
│   │   ├── analytics_trends_page.png
│   │   ├── analystics_insights_page.png
│   │   ├── ai_discover_page.png
│   │   ├── discover_saved_page.png
│   │   ├── ai_article_summary_view.png
│   │   ├── AI_Coach_Hub_page.png
│   │   ├── LexiAI_Saved_Words_page.png
│   │   ├── cloud_hub_page.png
│   │   └── cloud_hub_sync_history_page.png
│   └── stitch_html/                 ← All 13 HTML code files
│       └── (matching .html files)
```

### The Cursor Agent Prompt

```
Read docs/FIGMA_CONVERSION_PLAN.md and .cursorrules.

I have a complete working React/TypeScript prototype in docs/figma_source/.
This is my definitive spec. Convert it to Flutter following these rules:

1. Read palette.ts → create lib/core/theme/app_colors.dart with EXACT same colors
2. Read settingsContext.tsx → create Riverpod SettingsController
3. Read RootLayout.tsx + BottomNav.tsx → create app shell with 4-tab IndexedStack
4. Read each page file (ExpensePage, NewsPage, TutorPage, CloudPage) → create matching Flutter screens
5. Read each component → create matching Flutter widget

CRITICAL RULES:
- Font: Plus Jakarta Sans (not Manrope)
- Currency: INR (₹) not USD ($)
- Bottom Nav: 4 tabs (Wallet, Newspaper, GraduationCap, Cloud), white dot indicator
- Settings: Bottom sheet modal (not a tab)
- Header: 52px compact, emoji avatar left, centered title, action icon right
- Theme: palette.ts colors EXACTLY — AMOLED #000000 dark + #FFFFFF white
- Charts: Use fl_chart package (replaces recharts)
- Animations: Use Flutter AnimationController (replaces framer-motion)
- Swipe: Use Dismissible widget (replaces touch handlers)
- AI: All LLM calls go through backend API → LiteLLM (never direct)
- Backend API: http://10.0.2.2:3000 (local dev) or https://api endpoint

Follow the build order in FIGMA_CONVERSION_PLAN.md Phase 1-7.
Match the stitch screenshots in docs/stitch_screens/ for visual accuracy.
```

---

## 8. BACKEND API CHANGES NEEDED

The backend needs these additional endpoints for the new features:

```
# Expense Management
POST /api/v1/expenses              → add expense
GET  /api/v1/expenses              → list (with date filters)
PUT  /api/v1/expenses/:id          → update
DELETE /api/v1/expenses/:id        → delete

# Budget
GET  /api/v1/budget                → current budget
POST /api/v1/budget                → set budget
GET  /api/v1/budget/history        → budget change history

# AI Categorization (via LiteLLM)
POST /api/v1/ai/categorize         → {description} → {category, confidence, reasoning}

# AI Rephrase (via LiteLLM)
POST /api/v1/ai/rephrase           → {text, platforms[]} → {platform_results[]}

# AI Coach (via LiteLLM)
POST /api/v1/ai/correct            → {text, platforms[], tones[]} → {corrected, variations{}}

# AI Dictionary (via LiteLLM)
POST /api/v1/ai/define             → {word} → {definition, pronunciation, example}

# Cloud Files
GET  /api/v1/cloud/files           → list files
POST /api/v1/cloud/upload          → upload file
GET  /api/v1/cloud/sync-history    → sync log
```
