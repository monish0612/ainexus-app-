# THE CURSOR PROMPT — Paste This Into Cursor Agent (Ctrl+I)

---

## PROMPT START — Copy everything below this line:

```
Read ALL of these documents in order before writing any code:

1. docs/ARCHITECTURE.md — Master architecture blueprint
2. docs/ARCHITECTURE_ADDENDUM.md — Updated 12-screen design (overrides the 6-screen spec)
3. docs/DEVELOPER_SPEC.md — Final app specification with all features and user flows
4. docs/PERFORMANCE_RULES.md — Mandatory performance optimization rules for every file
5. docs/DESIGN_MAPPING.md — HTML-to-Flutter component mapping
6. .cursorrules — Coding rules (already in project root)

CRITICAL CONTEXT:
- This app uses LiteLLM as a unified LLM gateway on a remote VPS (72.60.219.97)
- The Flutter app calls a local Node.js backend → which calls LiteLLM → which routes to Groq/Gemini
- The app has 12 screens (not 6) — use docs/designs_v2/ screenshots and docs/html_reference_v2/ HTML files
- Every single widget MUST follow docs/PERFORMANCE_RULES.md — const everything, ListView.builder, RepaintBoundary on charts, dispose all controllers

APP OVERVIEW (from DEVELOPER_SPEC.md):
- Name: AI NEXUS — AI Expense, Linguistic Coach & Cloud Vault
- Theme: AMOLED Black (#000000) with neon cyan/purple gradients
- 5 bottom tabs: Home | Analytics | Discover | AI Coach | Cloud Hub
- Offline-first with Drift SQLite + background sync
- All LLM calls go through backend API → LiteLLM (never direct)

THE 12 SCREENS TO BUILD (match the v2 design screenshots exactly):

Tab 1 — HOME:
  Screen 1: Landing Page → docs/designs_v2/landing_page_screen.png
  Screen 2: Dashboard Home → docs/designs_v2/dashboard_home_screen.png
    - Balance card, spending donut chart (CustomPaint + RepaintBoundary), activity bars, smart tips
    - Floating "+" FAB button

Tab 2 — ANALYTICS:
  Screen 3: Analytics Main → docs/designs_v2/analytics_page_screen.png
    - Area chart (CustomPaint + RepaintBoundary), timeframe toggle, category breakdown
  Screen 4: Analytics Insights → docs/designs_v2/analystics_insights_page_screen.png
    - AI-powered spending insights cards
  Screen 5: Analytics Trends → docs/designs_v2/analytics_trends_page_screen.png
    - Historical trend charts, period comparison

Tab 3 — DISCOVER:
  Screen 6: Discover Feed → docs/designs_v2/ai_discover_page_screen.png
    - RSS news cards with AI badges, category filter chips, pull-to-refresh
  Screen 7: Discover Saved → docs/designs_v2/discover_saved_page_screen.png
    - Bookmarked articles grid
  Screen 8: Article Summary → docs/designs_v2/ai_article_summary_view_screen.png
    - Full article with AI summary header, reading progress bar

Tab 4 — AI COACH:
  Screen 9: AI Coach Hub → docs/designs_v2/AI_Coach_Hub_page_screen.png
    - Text/voice input, grammar correction, platform variations (Zoom/Slack/WhatsApp)
  Screen 10: LexiAI Saved Words → docs/designs_v2/LexiAI_Saved_Words_page_screen.png
    - Vocabulary builder, saved corrections library

Tab 5 — CLOUD HUB:
  Screen 11: Cloud Hub → docs/designs_v2/cloud_hub_page_screen.png
    - DIFFERENT design system ("Ethereal Vault" — cyan #00E6E6 + purple #D575FF)
    - Read docs/html_reference_v2/cloud_hub_page_DESIGN.md for full design rules
    - No 1px borders, use background color shifts only
  Screen 12: Sync History → docs/designs_v2/cloud_hub_sync_history_page_screen.png
    - Sync log with push/pull operations

BUILD ORDER:

PHASE 1 — Core Infrastructure:
1. pubspec.yaml with all dependencies
2. Exact folder structure from ARCHITECTURE_ADDENDUM.md (12-screen structure)
3. lib/core/theme/ (AppColors + AppTheme with AMOLED dark)
4. lib/core/constants/ (AppConstants — apiBaseUrl = 'http://10.0.2.2:3000')
5. lib/core/network/ (Dio ApiClient with interceptors, NetworkInfo, ApiEndpoints)
6. lib/core/router/ (GoRouter with ShellRoute — 12 screens, see ARCHITECTURE_ADDENDUM.md routing)
7. lib/core/utils/ (extensions)
8. main.dart + app.dart

PHASE 2 — Data Layer:
9. Drift tables (users, transactions, categories, news_articles, ai_conversations, sync_queue)
10. DAOs with .watch() streams for reactive UI
11. AppDatabase with migrations + seed categories
12. AppPreferences (SharedPreferences wrapper)
13. Data models with freezed + json_serializable
14. Remote data sources (auth, finance, news, LLM)
15. SyncEngine (offline queue processor)
16. Repository implementations (offline-first pattern: write local → queue sync)

PHASE 3 — Domain Layer:
17. Entities (pure Dart objects)
18. Repository interfaces
19. Use cases

PHASE 4 — LLM Service (LiteLLM-based):
20. services/llm/litellm_client.dart — calls backend /api/v1/llm/* endpoints via Dio
21. services/llm/llm_service.dart — abstract interface
22. services/llm/llm_registry.dart
23. services/llm/langchain/ scaffold
24. services/sync/background_sync_service.dart (WorkManager)

PHASE 5 — DI:
25. core/di/injection.dart — ALL Riverpod providers

PHASE 6 — Shared Widgets:
26. glass_card, gradient_card, filter_chip_row, segmented_toggle, category_icon, ai_badge, shimmer_loading, app_shell (bottom nav with 5 tabs)

PHASE 7 — ALL 12 Screens:
27-38. Build each screen pixel-matching the v2 screenshots
    - For EVERY screen: open the screenshot AND the HTML code file side by side
    - Extract exact colors, spacing, font sizes, border radius from the HTML
    - Follow PERFORMANCE_RULES.md strictly: const widgets, ListView.builder, RepaintBoundary on CustomPaint, dispose controllers, shimmer loading states

PHASE 8 — Backend:
39. Node.js Express API with routes for auth, finance, news, LLM (calling LiteLLM at http://72.60.219.97:4000)
40. PostgreSQL init.sql schema

PERFORMANCE RULES (from PERFORMANCE_RULES.md — MANDATORY):
- const on EVERY widget/style/padding/radius where values are compile-time known
- ListView.builder for ALL lists (never Column with .map())
- RepaintBoundary wrapping ALL CustomPaint widgets and list items
- dispose() ALL controllers (Animation, Scroll, Text, Focus)
- CachedNetworkImage for all images (never Image.network)
- Shimmer placeholders for all loading states (never blank screens)
- CustomScrollView + Slivers for all scrollable screens (never nested ScrollViews)
- Curves.easeOutCubic for all animations, 250ms for transitions
- TextScaler.noScaling in MaterialApp builder
- Max 150 lines per widget file — split large widgets into sub-widget files
- Isolate (compute()) for heavy data processing

After each phase: run `flutter analyze` and fix all issues.
After Phase 2: run `dart run build_runner build --delete-conflicting-outputs`
After Phase 7: run `flutter run --profile` on a device and check for jank.
```

## PROMPT END
