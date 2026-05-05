# Nexus AI — Web Deployment Guide

This document walks through deploying the Flutter Web build of Nexus AI to the
existing Coolify VPS at **`72.60.219.97`**, alongside the already-running
backend API (`monish0612/ainexus:main`) and LiteLLM gateway (`ainexus-litellm`).

The Android app is **completely unaffected** by this deployment. It continues
to ship from `android/` and talk to the same API. The web build is purely
additive.

---

## Architecture

```
                           ┌─────────────────────────────┐
                           │   Coolify @ 72.60.219.97    │
                           ├─────────────────────────────┤
  Android user ──────────► │  monish0612/ainexus:main    │ :3000  ◄─── REST API
                           │  ainexus-litellm            │ :4000  ◄─── LLM gateway
                           │  postgresql-database        │
                           │  redis-database             │
  Web user ──────────────► │  ainexus-web   (NEW)        │ :80    ◄─── Flutter web
                           └─────────────────────────────┘
```

The new `ainexus-web` container is a **single Caddy 2** instance serving the
compiled `flutter build web` bundle as static files. It calls the existing
API over HTTP using the public IP (or the Coolify-assigned `*.sslip.io` host).

---

## What's in the repo

| File | Purpose |
| --- | --- |
| `Dockerfile.web` | 3-stage image: Flutter SDK → Drift assets → Caddy |
| `deploy/Caddyfile` | Production Caddy config (SPA fallback, COOP/COEP, CSP, gzip) |
| `web/index.html` | Custom shell with splash screen + meta tags |
| `web/manifest.json` | PWA manifest (installable on desktop + mobile) |
| `docker-compose.web.yml` | Standalone compose for the web frontend |
| `.dockerignore` | Trims build context (excludes Android, backend, etc.) |
| `lib/core/platform/` | Cross-platform abstractions (kIsWeb, io stubs, OCR stubs) |

---

## Step-by-step deployment in Coolify

### 1. Create the application

1. Open Coolify → project **"ai nexus app"** → **+ New Resource** → **Application**.
2. **Source**: connect this repository (the same one already serving the API).
3. **Build pack**: `Dockerfile`.
4. **Branch**: whichever branch holds this commit (usually `main`).
5. **Base directory**: `.` (project root).
6. **Dockerfile location**: `Dockerfile.web`.
7. **Ports**: `80` (Coolify will expose this through its own reverse-proxy on
   ports 80/443).

### 2. Build arguments

Under **"Build → Build args"** add:

| Name | Value |
| --- | --- |
| `API_BASE_URL` | `http://72.60.219.97:3000` *(or your custom domain)* |
| `LITELLM_URL` | *(leave empty — the Flutter web build never calls LiteLLM directly)* |
| `SQLITE3_WASM_VERSION` | `2.9.4` *(only override if you bump `sqlite3` in pubspec.lock)* |
| `DRIFT_WORKER_VERSION` | `2.28.2` *(only override if you bump `drift` in pubspec.lock)* |

### 3. Domain

- Click **"Generate Domain"** in Coolify → it will return something like
  `nxsweb-xyz.72.60.219.97.sslip.io`.
- This sslip.io host resolves automatically to the VPS, and Coolify
  terminates HTTPS via Let's Encrypt.
- Optionally, point your own domain (`nexus.example.com` etc.) at the VPS and
  add it as a custom domain in Coolify.

### 4. Backend CORS

The backend already has `CORS_ORIGIN=*` in `backend/.env` and
`backend/docker-compose.yml`, so the new web origin is accepted out of the box.

If you later want to lock CORS down to a specific origin, edit the API's
environment in Coolify and set:

```
CORS_ORIGIN=https://nxsweb-xyz.72.60.219.97.sslip.io
```

then restart the API container.

### 5. Deploy

Click **"Deploy"** in Coolify. The build will:

1. Pull the `ghcr.io/cirruslabs/flutter:3.41.3` image.
2. `flutter pub get` → `flutter build web --release --dart-define=API_BASE_URL=…`.
3. Download the matching `sqlite3.wasm` and `drift_worker.dart.js` assets
   from GitHub releases.
4. Bake everything into a tiny `caddy:2.8-alpine` image.

First build takes ~6–8 minutes; subsequent builds (with Docker layer cache) ~90s.

### 6. Verify

- `curl https://<your-domain>/healthz` → should return `ok`.
- Open the domain in a browser → splash → app loads.
- DevTools → Application → Service workers → confirm `flutter_service_worker.js`
  is registered.
- DevTools → Application → IndexedDB or OPFS → confirm `ai_nexus` database is
  created (after first DB write).

---

## Local development

### Just preview the web build

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

Drift's WASM assets are auto-fetched by `flutter run` in dev mode.

### Build the production Docker image locally

```powershell
docker build -f Dockerfile.web `
  --build-arg API_BASE_URL=http://72.60.219.97:3000 `
  -t ainexus-web .

docker run --rm -p 8080:80 ainexus-web
# open http://localhost:8080
```

### Run via compose

```powershell
docker compose -f docker-compose.web.yml up --build
```

---

## Feature parity matrix

The web build is a **strict subset** of the Android build. The following
table lists every feature and its web availability.

| Feature | Android | Web | Notes |
| --- | --- | --- | --- |
| Login (HMAC-SHA256) | ✅ | ✅ | Same flow; secure storage uses webStorage |
| Expense Tracker | ✅ | ✅ | Manual entry only on web |
| Receipt OCR (ML Kit) | ✅ | ❌ | Hidden tab — Google ML Kit is Android-only |
| Voice expense entry | ✅ | ✅ | Uses Web Speech API; HTTPS + permission required |
| Insights / charts | ✅ | ✅ | fl_chart works fully on web |
| Budget management | ✅ | ✅ | |
| News feed | ✅ | ✅ | RSS + AI summarisation served from API |
| Article AI follow-up chat | ✅ | ✅ | |
| News notifications | ✅ | ❌ | Workmanager + flutter_local_notifications no-op on web |
| Dictionary lookup | ✅ | ✅ | |
| Rephrase | ✅ | ✅ | |
| Coach (correct grammar) | ✅ | ✅ | |
| Search lookup | ✅ | ✅ | |
| Deep research | ✅ | ✅ | |
| URL summarizer | ✅ | ✅ | |
| Article TTS | ✅ | ⚠️ | Web uses browser SpeechSynthesis; quality varies |
| Cloud Hub (Google Drive) | ✅ | ❌ | Drive integration uses dart:io File ops; shows "Coming soon on web" snackbar |
| Drift offline DB | ✅ (SQLite) | ✅ (sqlite3.wasm + OPFS) | |
| Sync queue | ✅ | ✅ | |
| Saved words | ✅ | ✅ | |
| PROCESS_TEXT integration | ✅ | ❌ | Android-only intent surface |
| Home-screen widget | ✅ | ❌ | AppWidgetProvider is Android-only |
| Background expense recap | ✅ | ❌ | Workmanager unavailable on web |
| Settings (theme, banks, model) | ✅ | ✅ | Full parity |
| PWA install (Add to Home) | n/a | ✅ | Manifest + service worker generated |
| Offline mode | ✅ | ✅ | Drift WASM + service worker |

---

## Troubleshooting

### "Missing browser features" warning in console

This appears when the browser doesn't support the OPFS API. Drift will
fall back to IndexedDB and your app continues to work — persistence is just
slightly slower. Modern Chrome/Edge/Firefox/Safari all support OPFS with
COOP/COEP headers (set in our Caddyfile).

### `sqlite3.wasm` returns 404

The Dockerfile pins versions matching `pubspec.lock`. If you upgrade `drift` or
`sqlite3` in pubspec, also bump the build args:

```
DRIFT_WORKER_VERSION=<your drift version>
SQLITE3_WASM_VERSION=<your sqlite3 version>
```

### CORS errors in DevTools

Confirm the backend is running and `CORS_ORIGIN` includes your web origin (or
is `*`). Check `backend/.env` and the deployed environment variables in
Coolify's API application.

### Service worker keeps serving old version

Hard-refresh (Ctrl+Shift+R) once after each deploy. Caddy serves
`flutter_service_worker.js` with `Cache-Control: no-cache` so subsequent loads
will pick up the new bundle automatically.

### Web build very slow on cold cache

The first build downloads ~300MB of Flutter SDK and pub deps. Subsequent
Coolify builds re-use layers and complete in ~90s.

---

## Updating the web app

Any push to the configured branch triggers a Coolify rebuild. Zero-downtime
rolling deploys are handled by Coolify's reverse-proxy.

The Android app is **untouched** by this pipeline — it continues to be built
and shipped from `android/` as before.
