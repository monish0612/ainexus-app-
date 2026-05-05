# CURSOR AGENT PROMPT — Setup Guide

## What To Do Before Starting

### Step 1: Create Flutter project
```bash
flutter create --org app.ainexus --project-name ai_nexus --platforms android .
```

### Step 2: Place these files in the project

| File | Location | Purpose |
|---|---|---|
| `.cursorrules` | Project root `/ai_nexus/.cursorrules` | Agent coding rules |
| `ARCHITECTURE.md` | `/ai_nexus/docs/ARCHITECTURE.md` | Master blueprint |
| `DESIGN_MAPPING.md` | `/ai_nexus/docs/DESIGN_MAPPING.md` | HTML→Flutter mapping |
| `pubspec.yaml` | Replace `/ai_nexus/pubspec.yaml` | Dependencies |

### Step 3: Add design reference files
- Put 6 screenshots → `/ai_nexus/docs/designs/`
- Put 6 HTML files → `/ai_nexus/docs/html_reference/`

### Step 4: Download fonts
Download from Google Fonts and place in `/ai_nexus/assets/fonts/`:
- Manrope (all weights: ExtraLight, Light, Regular, Medium, SemiBold, Bold, ExtraBold)
- Space Grotesk (Light, Regular, Medium, Bold)
- JetBrains Mono (Medium)

Also create empty folders: `assets/images/`, `assets/lottie/`, `assets/icons/`

### Step 5: Set up local backend (for testing LLM features)
```bash
# You need Docker installed locally
mkdir -p backend/litellm backend/api/src backend/database backend/nginx

# Copy the docker-compose.yml from ARCHITECTURE.md Section 11
# Copy litellm_config.yaml from ARCHITECTURE.md Section 7.1
# Copy init.sql, nginx.conf, api/src/index.js from ARCHITECTURE.md

cd backend
cp .env.example .env
# Edit .env — add at least OPENAI_API_KEY and LITELLM_MASTER_KEY

docker-compose up -d

# Verify LiteLLM is running:
curl http://localhost:4000/health
# → {"status":"healthy"}

# Generate a virtual key for the app:
curl -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer YOUR_LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"max_budget": 10, "duration": "30d", "key_alias": "ainexus-dev"}'
# Put the returned key in .env as LITELLM_VIRTUAL_KEY

# Access LiteLLM dashboard at http://localhost:4000/ui
```

### Step 6: Open Cursor Agent and paste the prompt below

---

## PROMPT TO PASTE INTO CURSOR AGENT

```
Read the entire ARCHITECTURE.md file in the docs/ folder. This is the complete blueprint for building the AI NEXUS Android app. Also read the .cursorrules file in the project root — follow those coding rules strictly.

I have uploaded 6 design screenshots in docs/designs/ and their corresponding HTML source code in docs/html_reference/. The HTML files contain the exact colors, spacing, fonts, and component structures to replicate.

CRITICAL CONTEXT — LLM Architecture:
This app uses LiteLLM as a unified LLM gateway. The Flutter app NEVER calls LLM providers (OpenAI, Anthropic, etc.) directly. Instead:
- Flutter app → calls Node.js backend API (/api/v1/llm/* endpoints)
- Node.js API → calls LiteLLM proxy (http://litellm:4000, internal Docker network)
- LiteLLM → routes to the actual LLM provider (OpenAI, Anthropic, Groq, DeepSeek, etc.)
- LiteLLM handles: auto-fallbacks, Redis caching, cost tracking, rate limiting
- All LLM calls use standard OpenAI-compatible JSON format regardless of actual provider
- The Flutter LLM client (services/llm/litellm_client.dart) is a simple Dio wrapper calling the backend
- Model selection is a string parameter: "gpt-4o-mini", "claude-sonnet", "groq-llama", etc.

Build the complete working AI NEXUS Flutter Android app following the ARCHITECTURE.md exactly. Here is the build order:

**PHASE 1 — Core Infrastructure:**
1. Replace pubspec.yaml with all dependencies listed in ARCHITECTURE.md Section 2
2. Create the exact folder structure from ARCHITECTURE.md Section 4
3. Implement lib/core/theme/app_colors.dart with all color constants from Section 5.1
4. Implement lib/core/theme/app_theme.dart with AMOLED dark + light ThemeData
5. Implement lib/core/constants/app_constants.dart (use http://10.0.2.2:3000 for local dev API URL)
6. Implement lib/core/network/ (NetworkInfo, ApiEndpoints, ApiClient with interceptors)
7. Implement lib/core/router/app_router.dart (GoRouter with ShellRoute)
8. Implement lib/core/utils/extensions.dart
9. Implement lib/main.dart + lib/app.dart

**PHASE 2 — Data Layer:**
10. Create all Drift table definitions in data/local/database/tables/
11. Create DAOs in data/local/database/daos/
12. Implement data/local/database/app_database.dart with all tables, migrations, seed data
13. Implement data/local/preferences/app_preferences.dart
14. Create all data models in data/models/ using freezed + json_serializable
15. Implement remote data sources in data/remote/
16. Implement data/sync/sync_engine.dart (offline queue processor)
17. Implement all repository implementations in data/repositories/

**PHASE 3 — Domain Layer:**
18. Create all entities in domain/entities/
19. Create all repository interfaces in domain/repositories/
20. Create all use cases in domain/usecases/

**PHASE 4 — Service Layer (LiteLLM-based):**
21. Implement services/llm/litellm_client.dart — the PRIMARY LLM client. This calls YOUR backend /api/v1/llm/* endpoints using Dio. It does NOT call LiteLLM or any LLM provider directly. See ARCHITECTURE.md Section 9 for exact implementation.
22. Implement services/llm/llm_service.dart — abstract interface for DI/testing
23. Implement services/llm/llm_registry.dart — simple registry wrapping LiteLLMClient
24. Implement services/llm/models/ — request/response DTOs
25. Implement services/llm/langchain/ scaffold (chain_manager, memory_store, tool_registry)
26. Implement services/sync/background_sync_service.dart (WorkManager)

**PHASE 5 — DI + Wiring:**
27. Implement core/di/injection.dart with ALL Riverpod providers

**PHASE 6 — Shared UI Widgets:**
28. Build all shared widgets in presentation/widgets/

**PHASE 7 — Screens (pixel-match the design screenshots):**
29. Launch screen — match docs/designs/Launch_screen.png
30. Home screen — match docs/designs/homepage_screen.png (CustomPainter donut chart)
31. Insights screen — match docs/designs/analytics_screen.png (CustomPainter area chart)
32. Discover screen — match docs/designs/rss_feed_news_screen.png
33. AI Coach screen — match docs/designs/AI_Coach_screen.png
34. Settings screen — match docs/designs/settings_screen.png

**PHASE 8 — Backend + LiteLLM:**
35. Create backend/litellm/litellm_config.yaml — exact content from ARCHITECTURE.md Section 7.1
36. Create backend/docker-compose.yml — exact content from ARCHITECTURE.md Section 11 (includes LiteLLM, PostgreSQL, Redis, Nginx)
37. Create backend/.env.example with all required env vars
38. Create backend/api/ — Node.js Express server that calls LiteLLM internally (ARCHITECTURE.md Section 10)
39. Create backend/database/init.sql — PostgreSQL schema
40. Create backend/nginx/nginx.conf — reverse proxy with rate limiting

After each phase, run `flutter analyze` and fix issues. After Phase 2, run `dart run build_runner build --delete-conflicting-outputs`.

IMPORTANT RULES:
- Follow .cursorrules strictly
- LLM calls: Flutter → Backend API → LiteLLM → Provider. NEVER skip LiteLLM.
- Use EXACTLY the colors, fonts, spacing from ARCHITECTURE.md Section 5
- All writes: local-first then sync-queue (Section 8)
- Riverpod StateNotifier pattern (Section 13)
- Look at HTML reference files for exact pixel values
```

---

## After the Agent Finishes Building

### Run the app
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --debug
```

### Start the backend
```bash
cd backend
docker-compose up -d

# Check everything:
docker ps  # Should show: api, litellm, postgres, redis, nginx
curl http://localhost:4000/health  # LiteLLM healthy
curl http://localhost:3000/health  # API healthy
```

### Deploy to Hostinger VPS (Coolify)
1. SSH into VPS → install Coolify
2. In Coolify dashboard → New Project → Docker Compose
3. Upload the `backend/` folder
4. Set environment variables in Coolify UI
5. Deploy
6. Update `app_constants.dart` with production URL
7. `flutter build apk --release`
