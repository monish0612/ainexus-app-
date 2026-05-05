# AI NEXUS — Updated Design Addendum (v2)

> **Purpose**: This document supplements the main ARCHITECTURE.md with the updated 12-screen design.
> Feed this to Cursor alongside the original ARCHITECTURE.md.
> The new designs are in docs/designs_v2/ (screenshots) and docs/html_reference_v2/ (HTML code).

---

## UPDATED APP STRUCTURE — 12 Screens

The app has expanded from 6 to 12 screens. Here is the complete screen map:

### Bottom Navigation Tabs (5 tabs)
```
HOME        ANALYTICS     DISCOVER      AI COACH      CLOUD HUB
  │            │              │              │              │
  ▼            ▼              ▼              ▼              ▼
Dashboard   Analytics     Discover      AI Coach Hub   Cloud Hub
             ├─Insights    ├─Saved        ├─LexiAI       ├─Sync History
             └─Trends      └─Article      └─Saved Words
                             Summary
```

### Screen List with Design Files

| # | Screen | Screenshot | HTML Reference | Description |
|---|--------|-----------|----------------|-------------|
| 1 | Landing/Onboarding | landing_page_screen.png | landing_page_code.html | Splash + "Get Started" CTA |
| 2 | Dashboard Home | dashboard_home_screen.png | dashboard_home_code.html | Balance, spending chart, activity, smart tips |
| 3 | Analytics Main | analytics_page_screen.png | analytics_page_code.html | Spending overview with area chart |
| 4 | Analytics Insights | analystics_insights_page_screen.png | analystics_insights_page_code.html | AI-powered spending insights |
| 5 | Analytics Trends | analytics_trends_page_screen.png | analytics_trends_page_code.html | Historical trend charts |
| 6 | Discover (RSS News) | ai_discover_page_screen.png | ai_discover_page_code.html | AI-summarized news feed |
| 7 | Discover Saved | discover_saved_page_screen.png | discover_saved_page_code.html | Bookmarked articles |
| 8 | Article Summary | ai_article_summary_view_screen.png | ai_article_summary_view_code.html | Full article with AI summary |
| 9 | AI Coach Hub | AI_Coach_Hub_page_screen.png | AI_Coach_Hub_page_code.html | Text/voice input, corrections, platform variations |
| 10 | LexiAI / Saved Words | LexiAI_Saved_Words_page_screen.png | LexiAI_Saved_Words_page_code.html | Vocabulary builder, saved corrections |
| 11 | Cloud Hub | cloud_hub_page_screen.png | cloud_hub_page_code.html | Cloud sync dashboard, storage overview |
| 12 | Cloud Hub Sync History | cloud_hub_sync_history_page_screen.png | cloud_hub_sync_history_page_code.html | Sync log, conflict resolution |

---

## NEW SCREENS — Specifications

### Cloud Hub (NEW — replaces Settings as 5th tab)
**Design System**: "The Ethereal Vault" — uses a different color palette from the rest of the app.
- **Color scheme**: Cyan (#00E6E6, #C1FFFE) + Electric Purple (#D575FF, #9800D0) on AMOLED black
- **Font**: Space Grotesk for display numbers, Manrope for body
- **Design philosophy**: "No-Line Rule" — no 1px borders, use background color shifts instead
- **Surface hierarchy**: Level 0 (#000000) → Level 1 (#0E0E0E) → Level 2 (#1F1F1F) → Level 3 (glass overlays)
- **Features**: Storage overview, sync status, backup management, data encryption status
- See `cloud_hub_page_DESIGN.md` for the complete design system specification

### Cloud Hub Sync History (NEW)
- Detailed sync log showing push/pull operations
- Conflict resolution UI
- Uses same Ethereal Vault design system as Cloud Hub
- See `cloud_hub_sync_history_page_DESIGN.md`

### Analytics Insights (NEW sub-screen)
- AI-generated spending insights and recommendations
- Displayed as cards with trend indicators
- Accessible from Analytics main screen

### Analytics Trends (NEW sub-screen)
- Historical spending trends with multiple chart types
- Period comparison (this month vs last month)
- Category breakdown over time

### Discover Saved (NEW sub-screen)
- Bookmarked/saved articles grid
- Accessible from Discover screen via tab or filter

### Article Summary View (NEW)
- Full article view with AI-generated summary at top
- Reading progress indicator
- "Save" and "Share" actions

### LexiAI / Saved Words (NEW sub-screen)
- Vocabulary builder tied to AI Coach
- Saved corrections and word improvements
- Accessible from AI Coach Hub via tab

---

## UPDATED FOLDER STRUCTURE

```
lib/presentation/screens/
├── launch/
│   └── launch_screen.dart
├── home/
│   ├── home_screen.dart
│   ├── home_controller.dart
│   └── widgets/
│       ├── balance_card.dart
│       ├── spending_donut_chart.dart
│       ├── activity_tracking_section.dart
│       └── smart_tip_card.dart
├── analytics/                          ← EXPANDED (was "insights")
│   ├── analytics_screen.dart           ← Main analytics with tab bar
│   ├── analytics_controller.dart
│   ├── insights/
│   │   └── analytics_insights_screen.dart    ← NEW
│   ├── trends/
│   │   └── analytics_trends_screen.dart      ← NEW
│   └── widgets/
│       ├── spending_area_chart.dart
│       ├── category_donut.dart
│       ├── trend_chart.dart                   ← NEW
│       └── insight_card.dart                  ← NEW
├── discover/                           ← EXPANDED
│   ├── discover_screen.dart
│   ├── discover_controller.dart
│   ├── saved/
│   │   └── discover_saved_screen.dart         ← NEW
│   ├── article/
│   │   └── article_summary_screen.dart        ← NEW
│   └── widgets/
│       ├── news_article_card.dart
│       └── article_summary_header.dart        ← NEW
├── ai_coach/                           ← EXPANDED
│   ├── ai_coach_screen.dart
│   ├── ai_coach_controller.dart
│   ├── lexiai/
│   │   └── lexiai_saved_words_screen.dart      ← NEW
│   └── widgets/
│       ├── correction_card.dart
│       ├── platform_variation_section.dart
│       ├── voice_record_button.dart
│       └── saved_word_card.dart                ← NEW
└── cloud_hub/                          ← NEW (replaces settings)
    ├── cloud_hub_screen.dart
    ├── cloud_hub_controller.dart
    ├── sync_history/
    │   └── sync_history_screen.dart
    └── widgets/
        ├── storage_overview_card.dart
        ├── sync_status_indicator.dart
        └── sync_history_item.dart
```

---

## UPDATED NAVIGATION (GoRouter)

```dart
GoRouter(
  initialLocation: '/launch',
  routes: [
    GoRoute(path: '/launch', builder: LaunchScreen),
    ShellRoute(
      builder: AppShell,  // Bottom nav with 5 tabs
      routes: [
        // Tab 1: Home
        GoRoute(path: '/home', builder: HomeScreen),

        // Tab 2: Analytics (with sub-routes)
        GoRoute(
          path: '/analytics',
          builder: AnalyticsScreen,
          routes: [
            GoRoute(path: 'insights', builder: AnalyticsInsightsScreen),
            GoRoute(path: 'trends', builder: AnalyticsTrendsScreen),
          ],
        ),

        // Tab 3: Discover (with sub-routes)
        GoRoute(
          path: '/discover',
          builder: DiscoverScreen,
          routes: [
            GoRoute(path: 'saved', builder: DiscoverSavedScreen),
            GoRoute(path: 'article/:id', builder: ArticleSummaryScreen),
          ],
        ),

        // Tab 4: AI Coach (with sub-routes)
        GoRoute(
          path: '/ai-coach',
          builder: AiCoachScreen,
          routes: [
            GoRoute(path: 'lexiai', builder: LexiAISavedWordsScreen),
          ],
        ),

        // Tab 5: Cloud Hub (with sub-routes)
        GoRoute(
          path: '/cloud-hub',
          builder: CloudHubScreen,
          routes: [
            GoRoute(path: 'sync-history', builder: SyncHistoryScreen),
          ],
        ),
      ],
    ),
  ],
)
```

---

## UPDATED BOTTOM NAVIGATION

| Position | Icon | Label | Route |
|----------|------|-------|-------|
| 1 | home | Home | /home |
| 2 | analytics | Analytics | /analytics |
| 3 | explore | Discover | /discover |
| 4 | smart_toy | AI Coach | /ai-coach |
| 5 | cloud | Cloud Hub | /cloud-hub |

Note: Settings is now accessible from Cloud Hub or profile, NOT a separate bottom tab.

---

## CLOUD HUB DESIGN SYSTEM (Different from rest of app)

The Cloud Hub screens use a distinct "Ethereal Vault" design system:

### Colors (Cloud Hub only)
```dart
// These override AppColors ONLY within Cloud Hub screens
surfaceContainerLowest = #000000  // Level 0 - The Void
surface = #0E0E0E                  // Level 1 - The Bed
surfaceContainerHigh = #1F1F1F     // Level 2 - The Module
surfaceVariant = #262626           // Level 3 - Glass overlays

primary = #C1FFFE                  // Cyan light
primaryDim = #00E6E6               // Cyan
primaryContainer = #00FFFF         // Cyan bright
onPrimary = #006767                // Cyan dark (text on primary)

secondary = #D575FF                // Electric purple
secondaryContainer = #9800D0       // Deep purple
secondaryDim = #B90AFC             // Vibrant purple

tertiary = #63BAFF                 // Info blue
error = #FF716C                    // Coral red

outline = #757575
outlineVariant = #484848           // Ghost borders (15% opacity only)
onSurface = #FFFFFF                // Headlines
onSurfaceVariant = #ABABAB         // Body text
```

### Cloud Hub Rules
- NO 1px borders — use background color shifts only
- Glassmorphism: backdrop-filter blur(12px) on floating panels
- Luminous shadows using 4% cyan glow, not dark shadows
- Space Grotesk for data display numbers (storage "1.2 TB")
- Manrope for all other text
- 80% of screen should be #000000 (AMOLED power saving)

---

## UPDATED BUILD ORDER FOR CURSOR

When building screens, use the v2 designs:

Phase 7 (Screens) becomes:
1. Landing Screen → docs/designs_v2/landing_page_screen.png
2. Dashboard Home → docs/designs_v2/dashboard_home_screen.png
3. Analytics Main → docs/designs_v2/analytics_page_screen.png
4. Analytics Insights → docs/designs_v2/analystics_insights_page_screen.png
5. Analytics Trends → docs/designs_v2/analytics_trends_page_screen.png
6. Discover → docs/designs_v2/ai_discover_page_screen.png
7. Discover Saved → docs/designs_v2/discover_saved_page_screen.png
8. Article Summary → docs/designs_v2/ai_article_summary_view_screen.png
9. AI Coach Hub → docs/designs_v2/AI_Coach_Hub_page_screen.png
10. LexiAI Saved Words → docs/designs_v2/LexiAI_Saved_Words_page_screen.png
11. Cloud Hub → docs/designs_v2/cloud_hub_page_screen.png
12. Cloud Hub Sync History → docs/designs_v2/cloud_hub_sync_history_page_screen.png

For each screen, ALWAYS reference:
- The screenshot (pixel-match the layout)
- The HTML code file (extract exact colors, spacing, fonts, component styles)
- The DESIGN.md if available (Cloud Hub screens)
