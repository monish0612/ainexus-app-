# AI NEXUS — Complete Architecture & Implementation Blueprint

> **Purpose**: This document is the single source of truth for building the AI NEXUS Android app.
> Feed this to the Cursor IDE agent along with the design screenshots for pixel-perfect implementation.

---

## 1. PROJECT OVERVIEW

**AI NEXUS** is an AI-powered personal finance + communication coaching Android app.

### Core Features
- **Home Dashboard**: Balance overview, spending donut chart, activity tracking, AI smart tips
- **Insights/Analytics**: Time-filtered spending charts, category breakdowns, area chart
- **Discover (RSS News)**: AI-summarized news feed with category filters (Tech, Finance, AI Labs)
- **AI Coach**: Text/voice input → grammar correction → platform-specific variations (Zoom, Slack, WhatsApp)
- **Settings**: Profile, AMOLED Dark/Light toggle, AI preferences, security, notifications

### Non-Negotiable Requirements
- **Offline-first**: All writes go to local SQLite first, sync when online
- **Ultra-fast**: 60fps animations, <800ms cold start, <5ms local writes
- **Modular LLM via LiteLLM Gateway**: Single unified API for all LLM providers with auto-fallback, caching, cost tracking
- **AMOLED Dark**: True black (#000000) background, #4725F4 primary accent

---

## 2. TECH STACK (Use Exactly These)

| Layer | Package / Service | Version / Notes |
|---|---|---|
| Framework | Flutter | ≥3.24 |
| State Management | flutter_riverpod | ^2.5.1 |
| Code Gen | riverpod_annotation + riverpod_generator | ^2.3.5 / ^2.4.0 |
| Navigation | go_router | ^14.2.0 |
| HTTP Client | dio | ^5.4.3+1 |
| Connectivity | connectivity_plus | ^6.0.3 |
| Local Database | drift + sqlite3_flutter_libs | ^2.18.0 |
| Preferences | shared_preferences | ^2.2.3 |
| Secure Storage | flutter_secure_storage | ^9.2.2 |
| Biometrics | local_auth | ^2.2.0 |
| Charts | fl_chart | ^0.68.0 |
| Fonts | google_fonts | ^6.2.1 |
| Images | cached_network_image | ^3.3.1 |
| Loading | shimmer | ^3.0.0 |
| Animations | lottie | ^3.1.2 |
| SVG | flutter_svg | ^2.0.10+1 |
| Background Sync | workmanager | ^0.5.2 |
| Notifications | flutter_local_notifications | ^17.2.1+1 |
| Audio | record + just_audio | ^5.1.0 / ^0.9.38 |
| Utilities | freezed_annotation, json_annotation, uuid, logger, equatable, intl, path_provider, path |
| Dev | build_runner, freezed, json_serializable, drift_dev, go_router_builder |
| **LLM Gateway** | **LiteLLM Proxy** | Deployed on Coolify (same VPS) — unified OpenAI-compatible API |
| Backend API | Node.js Express | On Coolify |
| Database | PostgreSQL 16 | On Coolify |
| Cache | Redis 7 | Shared by LiteLLM + backend |
| Reverse Proxy | Nginx | SSL + rate limiting |

---

## 3. INFRASTRUCTURE OVERVIEW — THE LiteLLM ARCHITECTURE

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     HOSTINGER VPS KVM 2 (Mumbai)                         │
│                     Managed by Coolify                                   │
│                                                                          │
│   ┌──────────┐     ┌──────────────┐     ┌────────────────────────┐      │
│   │  Nginx   │────▶│  Node.js API │────▶│  LiteLLM Proxy         │      │
│   │  :80/443 │     │  :3000       │     │  :4000                 │      │
│   └──────────┘     └──────┬───────┘     │                        │      │
│                           │             │  ┌──────────────────┐  │      │
│                           │             │  │ Virtual Keys     │  │      │
│                           ▼             │  │ Rate Limiting    │  │      │
│                    ┌──────────────┐     │  │ Response Caching │  │      │
│                    │ PostgreSQL   │     │  │ Cost Tracking    │  │      │
│                    │ :5432        │     │  │ Auto Fallbacks   │  │      │
│                    └──────────────┘     │  │ Load Balancing   │  │      │
│                                         │  └──────────────────┘  │      │
│                    ┌──────────────┐     │         │               │      │
│                    │ Redis        │◀────│─────────┘               │      │
│                    │ :6379        │     └─────────┬───────────────┘      │
│                    └──────────────┘               │                      │
│                                                   ▼                      │
│                                    ┌──────────────────────────┐          │
│                                    │  External LLM Providers  │          │
│                                    │  OpenAI  │  Anthropic    │          │
│                                    │  Groq    │  Google       │          │
│                                    │  Mistral │  DeepSeek     │          │
│                                    │  xAI     │  Azure        │          │
│                                    └──────────────────────────┘          │
└──────────────────────────────────────────────────────────────────────────┘

FLOW:
Android App ──HTTPS──▶ Nginx ──▶ Node.js API ──▶ LiteLLM ──▶ LLM Provider
                                     │
                                     ▼
                                 PostgreSQL
```

### Why LiteLLM is the Core of Our LLM Strategy

1. **Unified API**: Your backend always calls `http://litellm:4000/v1/chat/completions` in OpenAI format. Want to switch from GPT-4o to Claude Sonnet to Groq Llama? Change it in the LiteLLM config — zero code changes anywhere.

2. **Auto Fallback**: If OpenAI is slow/down, LiteLLM automatically tries the next provider (e.g., OpenAI → Anthropic → Groq). Your app never fails.

3. **Response Caching (Redis)**: Repeated queries are answered instantly from cache. Makes the app feel snappy and saves money.

4. **Virtual Keys**: Create API keys with budget limits for your app. The real provider keys never leave the server.

5. **Cost Dashboard**: See exactly what each model/user costs. Set monthly budgets.

6. **<10ms internal latency**: LiteLLM runs on the same VPS as your API — no external network hop.

---

## 4. FOLDER STRUCTURE (Create Exactly This)

```
lib/
├── main.dart
├── app.dart
│
├── core/
│   ├── constants/
│   │   └── app_constants.dart
│   ├── di/
│   │   └── injection.dart
│   ├── network/
│   │   ├── api_client.dart
│   │   ├── api_endpoints.dart
│   │   └── network_info.dart
│   ├── router/
│   │   └── app_router.dart
│   ├── theme/
│   │   ├── app_colors.dart
│   │   └── app_theme.dart
│   └── utils/
│       └── extensions.dart
│
├── data/
│   ├── local/
│   │   ├── database/
│   │   │   ├── app_database.dart
│   │   │   ├── tables/
│   │   │   │   ├── users_table.dart
│   │   │   │   ├── transactions_table.dart
│   │   │   │   ├── categories_table.dart
│   │   │   │   ├── news_articles_table.dart
│   │   │   │   ├── ai_conversations_table.dart
│   │   │   │   └── sync_queue_table.dart
│   │   │   └── daos/
│   │   │       ├── transaction_dao.dart
│   │   │       ├── news_dao.dart
│   │   │       └── sync_dao.dart
│   │   └── preferences/
│   │       └── app_preferences.dart
│   ├── remote/
│   │   ├── auth_remote_source.dart
│   │   ├── finance_remote_source.dart
│   │   ├── news_remote_source.dart
│   │   └── llm_remote_source.dart
│   ├── models/
│   │   ├── user_model.dart
│   │   ├── transaction_model.dart
│   │   ├── category_model.dart
│   │   ├── news_article_model.dart
│   │   ├── correction_model.dart
│   │   └── sync_item_model.dart
│   ├── repositories/
│   │   ├── auth_repository_impl.dart
│   │   ├── finance_repository_impl.dart
│   │   ├── news_repository_impl.dart
│   │   └── ai_coach_repository_impl.dart
│   └── sync/
│       └── sync_engine.dart
│
├── domain/
│   ├── entities/
│   │   ├── user_entity.dart
│   │   ├── transaction_entity.dart
│   │   ├── category_entity.dart
│   │   ├── balance_entity.dart
│   │   ├── spending_entity.dart
│   │   ├── news_article_entity.dart
│   │   └── correction_entity.dart
│   ├── repositories/
│   │   ├── auth_repository.dart
│   │   ├── finance_repository.dart
│   │   ├── news_repository.dart
│   │   └── ai_coach_repository.dart
│   └── usecases/
│       ├── auth/
│       │   ├── login_usecase.dart
│       │   └── register_usecase.dart
│       ├── finance/
│       │   ├── get_balance_usecase.dart
│       │   ├── get_spending_usecase.dart
│       │   ├── add_transaction_usecase.dart
│       │   └── get_categories_usecase.dart
│       ├── news/
│       │   ├── get_articles_usecase.dart
│       │   └── refresh_articles_usecase.dart
│       └── ai_coach/
│           ├── correct_text_usecase.dart
│           └── get_saved_corrections_usecase.dart
│
├── services/
│   ├── llm/
│   │   ├── litellm_client.dart          ← NEW: Direct LiteLLM client
│   │   ├── llm_service.dart             ← Abstract interface
│   │   ├── llm_registry.dart            ← Registry (routes to LiteLLM)
│   │   ├── models/
│   │   │   ├── llm_request.dart
│   │   │   ├── llm_response.dart
│   │   │   └── llm_model_config.dart
│   │   └── langchain/
│   │       ├── chain_manager.dart
│   │       ├── memory_store.dart
│   │       └── tool_registry.dart
│   └── sync/
│       └── background_sync_service.dart
│
└── presentation/
    ├── screens/
    │   ├── launch/
    │   │   └── launch_screen.dart
    │   ├── home/
    │   │   ├── home_screen.dart
    │   │   ├── home_controller.dart
    │   │   └── widgets/
    │   │       ├── balance_card.dart
    │   │       ├── spending_donut_chart.dart
    │   │       ├── activity_tracking_section.dart
    │   │       └── smart_tip_card.dart
    │   ├── insights/
    │   │   ├── insights_screen.dart
    │   │   ├── insights_controller.dart
    │   │   └── widgets/
    │   │       ├── spending_area_chart.dart
    │   │       ├── category_donut.dart
    │   │       └── category_grid_card.dart
    │   ├── discover/
    │   │   ├── discover_screen.dart
    │   │   ├── discover_controller.dart
    │   │   └── widgets/
    │   │       └── news_article_card.dart
    │   ├── ai_coach/
    │   │   ├── ai_coach_screen.dart
    │   │   ├── ai_coach_controller.dart
    │   │   └── widgets/
    │   │       ├── correction_card.dart
    │   │       ├── platform_variation_section.dart
    │   │       └── voice_record_button.dart
    │   └── settings/
    │       ├── settings_screen.dart
    │       └── widgets/
    │           ├── profile_header.dart
    │           └── settings_tile.dart
    └── widgets/
        ├── app_shell.dart
        ├── glass_card.dart
        ├── gradient_card.dart
        ├── filter_chip_row.dart
        ├── segmented_toggle.dart
        ├── category_icon.dart
        ├── ai_badge.dart
        └── shimmer_loading.dart
```

Backend folder:
```
backend/
├── docker-compose.yml          ← Includes LiteLLM service
├── .env.example
├── litellm/
│   ├── litellm_config.yaml     ← Model routing, fallbacks, caching
│   └── Dockerfile              ← Optional custom build
├── api/
│   ├── package.json
│   ├── Dockerfile
│   └── src/
│       └── index.js            ← Express API (calls LiteLLM internally)
├── database/
│   └── init.sql                ← PostgreSQL schema
└── nginx/
    └── nginx.conf
```

---

## 5. DESIGN SYSTEM

### 5.1 Colors

```dart
// BRAND
primary = #4725F4       // Purple accent — buttons, active states, charts
primaryLight = #7C3AED  // Lighter purple — gradients
primaryDark = #3318B0   // Darker purple
accentBlue = #00F2FF    // Cyan — AI Coach glow, pro-tip accent
accentCyan = #2DD4BF    // Teal

// BACKGROUNDS
backgroundDark = #000000   // AMOLED true black — scaffold
backgroundLight = #F6F5F8  // Light mode scaffold
surfaceDark = #0A0A0A      // Slightly lifted surfaces
cardDark = rgba(255,255,255,0.03)  // Glass card fill — 3% white
cardBorder = rgba(255,255,255,0.08) // Glass card border — 8% white

// TEXT
textPrimary = #F1F5F9   // slate-100 — headings, main text
textSecondary = #94A3B8  // slate-400 — body, descriptions
textTertiary = #64748B   // slate-500 — timestamps, hints
textMuted = #475569      // slate-600 — placeholders

// SEMANTIC
success = #10B981  // emerald-500
error = #F43F5E    // rose-500
warning = #EAB308  // yellow-500
info = #0EA5E9     // sky-500

// CATEGORY COLORS (for spending charts)
food = #4725F4       // primary purple
transport = #0EA5E9  // sky blue
shopping = #F43F5E   // rose
rent = #F59E0B       // amber
others = #10B981     // emerald

// CHART ACCENTS
chartPink = #EC4899
chartEmerald = #10B981
chartAmber = #F59E0B

// GLASS EFFECTS
glassBackground = rgba(255,255,255,0.03)
glassBorder = rgba(255,255,255,0.08)
primaryGlass = rgba(71,37,244,0.05)
primaryGlassBorder = rgba(71,37,244,0.15)

// GRADIENT DEFINITIONS
gradientCard = [#4725F4, #7C3AED]           // Balance card
gradientOrb = [#4725F4, #7C3AED, #3B82F6]   // Launch screen orb
gradientButton = [#4725F4, #A855F7]          // CTA buttons
```

### 5.2 Typography

```
Font Family: Manrope (primary for everything)
Font Family: Space Grotesk (display text — "AI NEXUS" logo only)
Font Family: JetBrains Mono (digital clock / monospace numbers)

Weight Scale: 200 (ExtraLight), 300 (Light), 400 (Regular), 500 (Medium), 600 (SemiBold), 700 (Bold), 800 (ExtraBold)

Size Scale:
- 48px: Display (AI NEXUS logo) — Space Grotesk Bold, letter-spacing: -2
- 36px: Hero numbers ($3,482.90) — Manrope ExtraBold, tracking: -1
- 32px: Balance amount — Manrope ExtraBold, tracking: -1
- 26px: Discover title — Manrope ExtraBold, tracking: -0.5
- 24px: User name in settings — Manrope Bold
- 20px: Section headers, article titles — Manrope Bold
- 18px: AppBar titles — Manrope Bold, tracking: -0.3
- 17px: Tagline text — Manrope Light, height: 1.6
- 16px: Body text — Manrope Regular, height: 1.5
- 14px: Card labels, descriptions — Manrope Regular
- 13px: Segmented toggle labels, filter chips — Manrope SemiBold
- 12px: Timestamps, meta text, subtitles — Manrope Regular
- 11px: System status text — Manrope Medium, tracking: 2
- 10px: Nav labels, AI badge text — Manrope Bold, tracking: 1.5
- 9px: Category label, chart legend values — Manrope Bold, tracking: 1.5
```

### 5.3 Component Patterns

**Glass Card**: bg rgba(255,255,255,0.03), border 1px rgba(255,255,255,0.08), radius 16px, blur 12px, padding 16-24px
**Gradient Card**: gradient(135deg, #4725F4, #7C3AED), radius 16px, shadow 0 10px 30px rgba(71,37,244,0.5), padding 24px
**Filter Chip active**: bg #4725F4, text white 13px SemiBold, radius 24px
**Filter Chip inactive**: bg glass, border glass, text slate-400 13px SemiBold, radius 24px
**Segmented Toggle**: container primaryGlass radius 12 h48, active segment #4725F4 white radius 8, animate 250ms
**Bottom Nav**: bg #000000 95% + blur, border-top 0.5px primaryGlass. Active: #4725F4 + indicator bar + glow. Inactive: #64748B
**AI Badge**: bg primaryGlass, border primaryGlassBorder, radius 20, icon auto_awesome 12px, text 9px Bold primary 80% UPPERCASE

---

## 6. SCREEN-BY-SCREEN SPECIFICATION

### 6.1 Launch Screen
- Full black background with decorative purple blur circles (top-left, bottom-right)
- Centered glowing orb: 140px circle, gradient border (primary → purple → blue), black fill, blur_on icon
- Orb has pulsing animation (scale 0.95↔1.05, 3s loop)
- Below orb: "AI" in white + "NEXUS" in gradient text, Space Grotesk 48px Bold
- Tagline: "Harnessing the power of the next generation." in slate-400, Manrope 17px Light
- Bottom: Full-width gradient CTA button "Get Started →", radius 16px, height 60px
- Page indicators: 28px active purple bar + 2× 8px inactive gray dots
- Top bar: "SYSTEM ONLINE" text left + signal icon right, 40% opacity

### 6.2 Home Screen
- **Header**: Avatar (42px, primary border) + "Welcome back," / "Alex Rivera" + notification bell (red dot)
- **Search bar**: Glass card with search icon + "Universal Search..." + pulsing AI badge
- **Balance card**: Gradient card. "Total Balance" / "$12,450.80" 32px ExtraBold / Income +$4,200 / Outcome -$1,150 / "Analytics" pill
- **Spending Analysis**: Glass card. "Spending Analysis" + "This Month" badge. CustomPaint donut chart 180×180 (food 40%, transport 25%, shopping 20%, others 15%). Center "$1,200" + "TOTAL SPENT". 2×2 legend grid
- **Activity Tracking**: Header + "Details >" link. 2-column glass cards with mini bar charts. "Today" primary bars, "Yesterday" gray bars
- **Smart Tip**: Glass card. magic icon + "Smart Tip" + "You spent 15% more on Dining Out..."
- **FAB**: 60px primary circle, glow shadow, bottom-right above nav

### 6.3 Insights Screen
- Back button + "Insights" + calendar icon. SegmentedToggle (Today/7 Days/Month/6 Months)
- "TOTAL SPENDING" → "$3,482.90" 36px ExtraBold + green "14.2%"
- CustomPaint area chart: cubic bezier path + gradient fill + 3 data dots. Mon-Sun labels
- Category donut section: 110px donut (70%/25%/5%) + center "70% FOOD" + legend
- 2×2 grid: Dining $1,240 / Shopping $870 / Transport $420 / Rent $2,800 with progress bars

### 6.4 Discover Screen
- Sticky header: "Discover" 26px + search/bell buttons. FilterChipRow: All News, Tech, Finance, AI Labs
- Article cards: 16:9 image, category label, AI badge, title 20px, summary 2-line, "Read Full Story →"

### 6.5 AI Coach Screen
- Header: Menu + "AI Coach Hub" + bell. Tabs: Coach / LexiAI / Saved
- Glass textarea (5 lines, 500 chars). Voice button (64px primary, cyan glow)
- Corrections card: "PERFECTED" green badge, corrected text 17px, tone tags, divider, platform buttons (Zoom/Slack/WhatsApp), variation preview with left border
- Pro-tip card: lightbulb icon in cyan bg + tip text

### 6.6 Settings Screen
- Profile: 120px avatar with gradient ring + glow + edit button. "Alex Rivera" + "AI PREMIUM" badge
- Appearance toggle: "AMOLED Dark" / "Amoled White"
- Preferences: 4 glass tiles (AI Preferences, Security, Notifications, About) with icons + chevrons
- Sign Out: red outlined button

---

## 7. LiteLLM GATEWAY — COMPLETE SETUP

### 7.1 LiteLLM Config File (`backend/litellm/litellm_config.yaml`)

This is the heart of the LLM routing. Create this file exactly:

```yaml
# ═══════════════════════════════════════════════════════
# AI NEXUS — LiteLLM Proxy Configuration
# Deployed via Coolify on Hostinger KVM 2
# ═══════════════════════════════════════════════════════

model_list:
  # ── PRIMARY: OpenAI GPT-4o-mini (fast + cheap for most tasks) ──
  - model_name: "gpt-4o-mini"
    litellm_params:
      model: "openai/gpt-4o-mini"
      api_key: "os.environ/OPENAI_API_KEY"
      max_tokens: 4096
      temperature: 0.7

  # ── PRIMARY: GPT-4o (for complex tasks) ──
  - model_name: "gpt-4o"
    litellm_params:
      model: "openai/gpt-4o"
      api_key: "os.environ/OPENAI_API_KEY"
      max_tokens: 4096

  # ── FALLBACK: Anthropic Claude Sonnet ──
  - model_name: "claude-sonnet"
    litellm_params:
      model: "anthropic/claude-sonnet-4-20250514"
      api_key: "os.environ/ANTHROPIC_API_KEY"
      max_tokens: 4096

  # ── FAST: Groq Llama (ultra-low latency, free tier) ──
  - model_name: "groq-llama"
    litellm_params:
      model: "groq/llama-3.1-70b-versatile"
      api_key: "os.environ/GROQ_API_KEY"
      max_tokens: 4096

  # ── CHEAP: DeepSeek (budget option) ──
  - model_name: "deepseek"
    litellm_params:
      model: "deepseek/deepseek-chat"
      api_key: "os.environ/DEEPSEEK_API_KEY"
      max_tokens: 4096

  # ── Google Gemini (optional) ──
  - model_name: "gemini-flash"
    litellm_params:
      model: "gemini/gemini-2.0-flash"
      api_key: "os.environ/GOOGLE_API_KEY"
      max_tokens: 4096

# ── ROUTER SETTINGS ─────────────────────────────────
router_settings:
  routing_strategy: "latency-based-routing"   # Pick fastest available
  num_retries: 3                               # Retry on failure
  timeout: 60                                  # Max seconds per request
  allowed_fails: 2                             # Failures before model is marked unhealthy
  cooldown_time: 30                            # Seconds before retrying failed model

  # ── FALLBACK CHAIN ──
  # If primary model fails, try these in order
  fallbacks:
    - "gpt-4o-mini": ["groq-llama", "claude-sonnet", "deepseek"]
    - "gpt-4o": ["claude-sonnet", "gpt-4o-mini"]
    - "claude-sonnet": ["gpt-4o", "gpt-4o-mini"]

# ── CACHING (Redis) ─────────────────────────────────
# Identical requests return instantly from cache
litellm_settings:
  cache: true
  cache_params:
    type: "redis"
    host: "redis"
    port: 6379
    ttl: 3600            # Cache responses for 1 hour

  # ── COST TRACKING ──
  success_callback: ["langfuse"]    # Optional: detailed analytics
  max_budget: 100.0                  # Monthly budget cap in USD
  budget_duration: "30d"

  # ── RATE LIMITING ──
  max_parallel_requests: 50
  tpm_limit: 100000                  # Tokens per minute
  rpm_limit: 500                     # Requests per minute

# ── DATABASE (for key management + spend tracking) ──
general_settings:
  master_key: "os.environ/LITELLM_MASTER_KEY"
  database_url: "os.environ/DATABASE_URL"
  store_model_in_db: true
```

### 7.2 How the Backend Calls LiteLLM

The Node.js API calls LiteLLM using **standard OpenAI format**. The URL is internal (same Docker network = <10ms):

```javascript
// In your Node.js backend — this is ALL the LLM code you need
const LITELLM_URL = 'http://litellm:4000';
const LITELLM_KEY = process.env.LITELLM_VIRTUAL_KEY; // Virtual key, not real provider key

// Generic completion — works for ANY model
async function llmComplete(prompt, systemPrompt, model = 'gpt-4o-mini') {
  const response = await fetch(`${LITELLM_URL}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LITELLM_KEY}`,
    },
    body: JSON.stringify({
      model: model,  // "gpt-4o-mini", "claude-sonnet", "groq-llama", etc.
      messages: [
        ...(systemPrompt ? [{ role: 'system', content: systemPrompt }] : []),
        { role: 'user', content: prompt },
      ],
      max_tokens: 2048,
      temperature: 0.7,
    }),
  });
  const data = await response.json();
  return data.choices[0]?.message?.content || '';
}

// That's it. Same code for OpenAI, Anthropic, Groq, DeepSeek, Gemini.
// To switch models: just change the "model" string parameter.
// Fallbacks happen automatically via litellm_config.yaml.
```

### 7.3 Model Selection Strategy for the App

| Feature | Default Model | Why | Fallback Chain |
|---|---|---|---|
| AI Coach (grammar correction) | `gpt-4o-mini` | Fast, cheap, great at grammar | → groq-llama → claude-sonnet |
| News Summarization | `groq-llama` | Ultra-fast, good enough for summaries | → gpt-4o-mini → deepseek |
| Smart Tips (spending analysis) | `gpt-4o-mini` | Quick financial insights | → deepseek → groq-llama |
| Complex Analysis (if added later) | `gpt-4o` | Best reasoning | → claude-sonnet → gpt-4o-mini |
| Conversation/Chat (if added later) | `claude-sonnet` | Best at natural conversation | → gpt-4o → gpt-4o-mini |

---

## 8. OFFLINE-FIRST SYNC ARCHITECTURE

```
USER ACTION
    │
    ▼
┌─────────────────────────┐
│  Repository.write()     │
│  1. Write to Drift DB   │ ← INSTANT (< 5ms)
│  2. Insert SyncQueue    │
│  3. Return to UI        │
└─────────────────────────┘
    │
    ▼ (background)
┌─────────────────────────┐
│  SyncEngine             │
│  Triggers:              │
│  - Connectivity change  │
│  - Every 5 minutes      │
│  - Manual pull-refresh  │
│                         │
│  Process:               │
│  1. Check isConnected   │
│  2. Read SyncQueue FIFO │
│  3. POST each to API    │
│  4. On success: delete  │
│  5. On fail: retry++    │
│  6. Pull remote changes │
│  7. Merge into local DB │
└─────────────────────────┘
```

### Drift Database Tables

```
USERS: id, name, email, avatarUrl, membershipTier, memberSince, updatedAt
TRANSACTIONS: id, userId, amount, currency, categoryId, description, type(income|expense), transactionDate, isSynced, createdAt, updatedAt
CATEGORIES: id, name, icon, color, sortOrder
NEWS_ARTICLES: id, title, summary, content, imageUrl, sourceUrl, sourceName, category, isAiSummarized, isRead, isBookmarked, publishedAt, cachedAt
AI_CONVERSATIONS: id, userId, inputText, correctedText, platform, platformVariation, tone, modelUsed, createdAt, isSynced
SYNC_QUEUE: id(autoIncrement), tableName, recordId, operation(insert|update|delete), payload(JSON), retryCount, createdAt, lastAttemptAt
```

---

## 9. LLM SERVICE LAYER (Flutter Side)

### Key Change from Direct Providers → LiteLLM

Previously, the Flutter app's LLM code needed separate provider implementations (OpenAI, Anthropic, Custom). With LiteLLM, the Flutter LLM service is **much simpler** because ALL providers use the same OpenAI-compatible format through your backend:

```dart
// ── services/llm/litellm_client.dart ──
// This is the ONLY LLM client you need on the Flutter side.
// It calls YOUR backend API, which internally calls LiteLLM.
// All providers, fallbacks, caching happen server-side.

class LiteLLMClient {
  final ApiClient _api;

  LiteLLMClient(this._api);

  /// Complete a prompt using any model routed through LiteLLM
  /// Model names: "gpt-4o-mini", "claude-sonnet", "groq-llama", "deepseek", "gemini-flash"
  /// If model is null, backend picks the default for the task type
  Future<String> complete({
    required String prompt,
    String? systemPrompt,
    String? model,        // Optional: override default model
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    final response = await _api.post('/api/v1/llm/complete', data: {
      'prompt': prompt,
      'system_prompt': systemPrompt,
      'model': model,                    // LiteLLM routes this
      'temperature': temperature,
      'max_tokens': maxTokens,
    });
    return (response.data as Map<String, dynamic>)['content'] as String? ?? '';
  }

  /// Stream completion (token by token)
  Stream<String> completeStream({
    required String prompt,
    String? systemPrompt,
    String? model,
  }) async* {
    // For v1, use non-streaming and simulate
    // For v2, implement SSE streaming from backend
    final result = await complete(prompt: prompt, systemPrompt: systemPrompt, model: model);
    final words = result.split(' ');
    for (int i = 0; i < words.length; i++) {
      yield '${words[i]}${i < words.length - 1 ? ' ' : ''}';
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Summarize text (uses fast model by default)
  Future<String> summarize({required String text, int maxLength = 200}) async {
    final response = await _api.post('/api/v1/llm/summarize', data: {
      'text': text,
      'max_length': maxLength,
    });
    return (response.data as Map<String, dynamic>)['summary'] as String? ?? text;
  }

  /// Correct grammar + generate platform variations
  Future<CorrectionResult> correct({
    required String text,
    String? targetTone,
    List<String> platforms = const ['zoom', 'slack', 'whatsapp'],
  }) async {
    final response = await _api.post('/api/v1/llm/correct', data: {
      'text': text,
      'target_tone': targetTone ?? 'professional',
      'platforms': platforms,
    });
    final data = response.data as Map<String, dynamic>;
    return CorrectionResult(
      originalText: text,
      correctedText: data['corrected'] ?? text,
      toneLabels: List<String>.from(data['tone_labels'] ?? []),
      platformVariations: Map<String, String>.from(data['variations'] ?? {}),
      proTip: data['pro_tip'],
    );
  }

  /// Check which models are available
  Future<List<String>> getAvailableModels() async {
    final response = await _api.get('/api/v1/llm/models');
    return List<String>.from((response.data as Map<String, dynamic>)['models'] ?? []);
  }
}
```

### Abstract LLM Service (Still Useful for Testing/Offline)

Keep the abstract interface for dependency injection and testing, but the primary implementation is `LiteLLMClient`:

```dart
abstract class LLMService {
  Future<String> complete({required String prompt, String? systemPrompt, String? model});
  Future<String> summarize({required String text, int maxLength});
  Future<CorrectionResult> correct({required String text, String? targetTone, List<String> platforms});
  Stream<String> completeStream({required String prompt, String? systemPrompt, String? model});
  void dispose();
}

// LiteLLMClient implements LLMService
// OfflineLLMService implements LLMService (returns cached/fallback responses when offline)
```

### LangChain Future Integration

The LangChain scaffold remains the same (ChainManager, ToolRegistry, MemoryStore). When you add LangChain:
- ChainManager calls `LiteLLMClient.complete()` as its LLM backend
- LiteLLM handles model routing — LangChain doesn't need to know which provider is being used
- You can add tools (web search, DB query, calculator) via ToolRegistry without changing LLM code

---

## 10. BACKEND API — UPDATED WITH LiteLLM

### API Endpoints

```
# Health
GET  /health → {status: "ok", timestamp: "...", litellm: "ok"}

# Auth
POST /api/v1/auth/register → {email, name, password} → {user, token}
POST /api/v1/auth/login    → {email, password} → {user, token}
GET  /api/v1/auth/profile  → {id, name, email, ...}

# Finance
GET  /api/v1/finance/balance      → {total_balance, income, outcome}
GET  /api/v1/finance/transactions → [{id, amount, category_id, type, ...}]
POST /api/v1/finance/transactions → {amount, category_id, type, date} → {transaction}
GET  /api/v1/finance/spending     → {total, by_category: [...], percent_change}
GET  /api/v1/finance/categories   → [{id, name, icon, color}]

# News
GET  /api/v1/news/articles → [{id, title, summary, imageUrl, category, ...}]

# LLM (ALL go through LiteLLM — backend picks the model)
GET  /api/v1/llm/health    → {status, available_models: ["gpt-4o-mini", "claude-sonnet", ...]}
GET  /api/v1/llm/models    → {models: ["gpt-4o-mini", "gpt-4o", "claude-sonnet", "groq-llama", ...]}
POST /api/v1/llm/complete  → {prompt, system_prompt, model?, temperature} → {content, model_used, cached}
POST /api/v1/llm/summarize → {text, max_length} → {summary, model_used}
POST /api/v1/llm/correct   → {text, target_tone, platforms} → {corrected, tone_labels, variations, pro_tip}

# Sync
POST /api/v1/sync/push → {table, record_id, operation, payload} → {status, server_timestamp}
GET  /api/v1/sync/pull  → {since: ISO8601} → {changes: [...], server_timestamp}
```

### Backend LLM Routes (Call LiteLLM Internally)

```javascript
// ═══════ KEY CHANGE: All LLM routes use LiteLLM ═══════
const LITELLM_URL = process.env.LITELLM_URL || 'http://litellm:4000';
const LITELLM_KEY = process.env.LITELLM_VIRTUAL_KEY;

// Helper: call LiteLLM (OpenAI-compatible format)
async function callLiteLLM({ messages, model = 'gpt-4o-mini', temperature = 0.7, maxTokens = 2048, responseFormat = null }) {
  const body = {
    model,
    messages,
    max_tokens: maxTokens,
    temperature,
  };
  if (responseFormat) body.response_format = responseFormat;

  const response = await fetch(`${LITELLM_URL}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LITELLM_KEY}`,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) throw new Error(`LiteLLM error: ${response.status}`);
  const data = await response.json();
  return {
    content: data.choices?.[0]?.message?.content || '',
    model_used: data.model || model,
    cached: data._cache_hit || false,
    usage: data.usage || {},
  };
}

// POST /api/v1/llm/complete
app.post('/api/v1/llm/complete', authenticate, async (req, res) => {
  const { prompt, system_prompt, model, temperature, max_tokens } = req.body;
  const result = await callLiteLLM({
    messages: [
      ...(system_prompt ? [{ role: 'system', content: system_prompt }] : []),
      { role: 'user', content: prompt },
    ],
    model: model || 'gpt-4o-mini',
    temperature: temperature || 0.7,
    maxTokens: max_tokens || 2048,
  });
  // Log to DB
  await pool.query(
    'INSERT INTO ai_conversations (user_id, input_text, corrected_text, model_used) VALUES ($1, $2, $3, $4)',
    [req.userId, prompt, result.content, result.model_used]
  );
  res.json(result);
});

// POST /api/v1/llm/summarize — uses fast model
app.post('/api/v1/llm/summarize', authenticate, async (req, res) => {
  const { text, max_length = 200 } = req.body;
  const result = await callLiteLLM({
    messages: [{ role: 'user', content: `Summarize in under ${max_length} chars:\n\n${text}` }],
    model: 'groq-llama',  // Ultra-fast for summaries
    temperature: 0.3,
    maxTokens: 300,
  });
  res.json({ summary: result.content, model_used: result.model_used, cached: result.cached });
});

// POST /api/v1/llm/correct — uses gpt-4o-mini with JSON output
app.post('/api/v1/llm/correct', authenticate, async (req, res) => {
  const { text, target_tone = 'professional', platforms = ['zoom', 'slack', 'whatsapp'] } = req.body;
  const result = await callLiteLLM({
    messages: [
      { role: 'system', content: `You are an expert communication coach. Return JSON: {"corrected":"...","tone_labels":[...],"variations":{"platform":"text"},"pro_tip":"..."}` },
      { role: 'user', content: `Tone: ${target_tone}\nPlatforms: ${platforms.join(', ')}\nText: "${text}"` },
    ],
    model: 'gpt-4o-mini',
    temperature: 0.5,
    responseFormat: { type: 'json_object' },
  });
  const parsed = JSON.parse(result.content);
  res.json({ ...parsed, model_used: result.model_used, cached: result.cached });
});

// GET /api/v1/llm/models — list available models from LiteLLM
app.get('/api/v1/llm/models', authenticate, async (req, res) => {
  const response = await fetch(`${LITELLM_URL}/v1/models`, {
    headers: { 'Authorization': `Bearer ${LITELLM_KEY}` },
  });
  const data = await response.json();
  const models = data.data?.map(m => m.id) || [];
  res.json({ models });
});
```

---

## 11. DOCKER COMPOSE — WITH LiteLLM

```yaml
version: "3.8"

services:
  # ── API Server ────────────────────────────────────
  api:
    build: ./api
    container_name: ainexus-api
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - DATABASE_URL=postgresql://ainexus:${DB_PASSWORD}@postgres:5432/ainexus
      - LITELLM_URL=http://litellm:4000
      - LITELLM_VIRTUAL_KEY=${LITELLM_VIRTUAL_KEY}
      - JWT_SECRET=${JWT_SECRET}
      - CORS_ORIGIN=*
    depends_on:
      postgres:
        condition: service_healthy
      litellm:
        condition: service_healthy
    networks:
      - ainexus-network

  # ── LiteLLM Proxy (THE LLM GATEWAY) ──────────────
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ainexus-litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    volumes:
      - ./litellm/litellm_config.yaml:/app/config.yaml
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://ainexus:${DB_PASSWORD}@postgres:5432/ainexus
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - GROQ_API_KEY=${GROQ_API_KEY}
      - DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}
    command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - ainexus-network

  # ── PostgreSQL 16 ─────────────────────────────────
  postgres:
    image: postgres:16-alpine
    container_name: ainexus-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ainexus
      POSTGRES_USER: ainexus
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ainexus"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - ainexus-network

  # ── Redis (Cache for LiteLLM + Rate Limiting) ────
  redis:
    image: redis:7-alpine
    container_name: ainexus-redis
    restart: unless-stopped
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - ainexus-network

  # ── Nginx ─────────────────────────────────────────
  nginx:
    image: nginx:alpine
    container_name: ainexus-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api
      - litellm
    networks:
      - ainexus-network

volumes:
  postgres_data:
  redis_data:

networks:
  ainexus-network:
    driver: bridge
```

### Environment Variables (`.env`)

```env
# Database
DB_PASSWORD=your_strong_password_here

# Auth
JWT_SECRET=your_jwt_secret_32_chars_minimum

# LiteLLM
LITELLM_MASTER_KEY=sk-litellm-master-key-change-this
LITELLM_VIRTUAL_KEY=sk-litellm-app-key-change-this

# LLM Provider API Keys (add the ones you use)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GROQ_API_KEY=gsk_...
DEEPSEEK_API_KEY=sk-...
GOOGLE_API_KEY=AIza...
```

---

## 12. LOCAL DEVELOPMENT SETUP

### Quick Start (Dev Machine)

```bash
# 1. Start backend stack locally
cd backend
cp .env.example .env
# Edit .env with your API keys

docker-compose up -d

# 2. Verify everything is running
curl http://localhost:3000/health       # API
curl http://localhost:4000/health       # LiteLLM
curl http://localhost:4000/v1/models    # Available models

# 3. Create a virtual key in LiteLLM (for the app to use)
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer sk-litellm-master-key-change-this" \
  -H "Content-Type: application/json" \
  -d '{"max_budget": 10, "duration": "30d", "key_alias": "ainexus-dev"}'
# → Returns a virtual key. Put it in .env as LITELLM_VIRTUAL_KEY

# 4. Test LLM through your API
curl -X POST http://localhost:3000/api/v1/llm/complete \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"prompt": "Hello, who are you?", "model": "gpt-4o-mini"}'

# 5. Access LiteLLM dashboard
open http://localhost:4000/ui
# Login with LITELLM_MASTER_KEY

# 6. Run Flutter app
cd ../  # Back to Flutter project root
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --debug
```

### Flutter Local Development Config

In `lib/core/constants/app_constants.dart`, use these for local dev:

```dart
abstract final class AppConstants {
  // LOCAL DEV — change to production URL before release
  static const apiBaseUrl = 'http://10.0.2.2:3000';  // Android emulator → host
  // static const apiBaseUrl = 'https://api.ainexus.app';  // PRODUCTION

  // LiteLLM is internal to backend — app never calls it directly
  // The app only talks to apiBaseUrl, which proxies to LiteLLM
}
```

### Testing the Full LLM Flow Locally

```
Flutter App (emulator)
    │
    │ POST http://10.0.2.2:3000/api/v1/llm/correct
    │ Body: {"text": "i goes to store", "target_tone": "professional"}
    ▼
Node.js API (localhost:3000)
    │
    │ POST http://litellm:4000/v1/chat/completions
    │ Body: {model: "gpt-4o-mini", messages: [...]}
    ▼
LiteLLM (localhost:4000)
    │
    │ Check Redis cache → miss → call OpenAI
    │ Cache response for next time
    ▼
OpenAI API
    │
    │ Returns corrected text
    ▼
Response flows back:
OpenAI → LiteLLM (caches) → Node.js (logs to DB) → Flutter (displays)
```

---

## 13. STATE MANAGEMENT PATTERN

```dart
// 1. State class (immutable)
class HomeState {
  final BalanceOverview? balance;
  final SpendingSummary? spending;
  final bool isLoading;
  final String? error;
  // copyWith method
}

// 2. Controller (StateNotifier)
class HomeController extends StateNotifier<HomeState> {
  final FinanceRepository _repo;
  HomeController(this._repo) : super(const HomeState()) { _load(); }
}

// 3. Provider
final homeControllerProvider = StateNotifierProvider<HomeController, HomeState>((ref) {
  return HomeController(ref.watch(financeRepositoryProvider));
});

// 4. UI consumption (ConsumerWidget)
class HomeScreen extends ConsumerWidget {
  Widget build(context, ref) {
    final state = ref.watch(homeControllerProvider);
  }
}
```

---

## 14. ROUTING

```dart
GoRouter(
  initialLocation: '/launch',
  routes: [
    GoRoute(path: '/launch', builder: LaunchScreen),
    ShellRoute(
      builder: AppShell,
      routes: [
        GoRoute(path: '/home', builder: HomeScreen),
        GoRoute(path: '/insights', builder: InsightsScreen),
        GoRoute(path: '/discover', builder: DiscoverScreen),
        GoRoute(path: '/ai-coach', builder: AiCoachScreen),
        GoRoute(path: '/settings', builder: SettingsScreen),
      ],
    ),
  ],
)
// All transitions: FadeTransition with easeOutCubic, 250ms
```

---

## 15. PERFORMANCE REQUIREMENTS

| Metric | Target | How |
|---|---|---|
| Cold start | <800ms | Minimal main.dart, lazy DI, no splash delay |
| Screen transition | 60fps | FadeTransition only, no heavy rebuilds |
| Local DB write | <5ms | Drift async batch writes |
| LLM response (cached) | <50ms | Redis cache in LiteLLM |
| LLM response (uncached) | <2s | Groq for fast tasks, GPT-4o-mini for others |
| List scrolling | 60fps | ListView.builder with const widgets |
| Image loading | Progressive | cached_network_image + shimmer placeholders |
| APK size | <25MB | Tree-shake, no unused assets |

---

## 16. BUILD ORDER (For the Cursor IDE Agent)

Phase 1: Core Infrastructure
1. Create Flutter project + pubspec.yaml with all dependencies
2. Create exact folder structure as specified in Section 4
3. Implement core/theme (AppColors, AppTheme)
4. Implement core/constants (AppConstants)
5. Implement core/network (ApiClient with Dio + interceptors, NetworkInfo, ApiEndpoints)
6. Implement core/router (GoRouter)
7. Implement core/utils (extensions)
8. Create main.dart + app.dart

Phase 2: Data Layer
9. Implement all Drift tables + DAOs
10. Implement AppDatabase with migrations + seed data
11. Implement AppPreferences
12. Implement data models (freezed/json_serializable)
13. Implement remote data sources
14. Implement SyncEngine

Phase 3: Domain Layer
15. Implement all entities
16. Implement repository interfaces
17. Implement use cases

Phase 4: Service Layer
18. Implement services/llm/litellm_client.dart (the primary LLM client)
19. Implement services/llm/llm_service.dart (abstract interface)
20. Implement services/llm/llm_registry.dart
21. Implement LangChain scaffold (ChainManager, ToolRegistry, MemoryStore)
22. Implement BackgroundSyncService (WorkManager)

Phase 5: DI + Wiring
23. Implement core/di/injection.dart with all Riverpod providers
24. Wire repositories → use cases → controllers → LiteLLMClient

Phase 6: Shared Widgets
25. Build all shared widgets (GlassCard, GradientCard, FilterChipRow, SegmentedToggle, AppShell, etc.)

Phase 7: Screens (pixel-match the designs)
26. LaunchScreen
27. HomeScreen + all sub-widgets
28. InsightsScreen + area chart + category grid
29. DiscoverScreen + article cards
30. AiCoachScreen + corrections + platform variations
31. SettingsScreen + profile + preferences

Phase 8: Backend + LiteLLM
32. Create backend/litellm/litellm_config.yaml (exact content from Section 7.1)
33. Create backend/docker-compose.yml (exact content from Section 11)
34. Create backend/.env.example
35. Set up Node.js Express API with LiteLLM integration (Section 10)
36. Create PostgreSQL schema (init.sql)
37. Create Nginx config (rate limit LLM endpoints at 5r/s)

Phase 9: Polish
38. Run `dart run build_runner build`
39. Fix all compile errors
40. Test full flow: App → API → LiteLLM → Provider → Response → Cache → Display
