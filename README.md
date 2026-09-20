# Nexus AI — Android app

Flutter client for Nexus AI (offline-first expense tracker, news, tutor, cloud, and home-screen widgets). Current version: **1.0.50+51**.

This repository is only the Android / Flutter app. Web and the Node API live in their own GitHub repos. Clone all three if you need the full setup.

## Repositories

| Piece | GitHub | Notes |
| --- | --- | --- |
| **Android (this repo)** | https://github.com/monish0612/ainexus-app- | Flutter, Drift SQLite, Riverpod |
| **Backend API** | https://github.com/monish0612/ainexus | Express + Postgres + LiteLLM |
| **Web** | https://github.com/monish0612/ainexus-web | React + Vite, `https://monishlabs.com/nexusai` |
| Narration (TTS) | https://github.com/monish0612/narrator | Article audio pipeline |
| Speech-to-text | https://github.com/monish0612/stt-gateway | Voice input gateway |

Production API base: `https://monishlabs.com/nexusai/api/v1`.

## Local run

```bash
flutter pub get
flutter test
flutter run
# release APK: flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

Requires Flutter ≥ 3.24 and Dart ≥ 3.4. Do not commit `android/key.properties`, keystores, `.env`, or `secrets/`.

## App layout

- `lib/presentation/` — screens (expense, news, tutor, cloud, settings, watch)
- `lib/data/` — Drift DB, repositories, SMS auto-expense, sync
- `lib/core/` — router, auth, merge/sync policy, widgets, share sheets
- `android/` — native widgets, SMS bridge, launcher / splash
- `docs/` — architecture and feature handovers (`ARCHITECTURE.md`, `WATCH_ARCHITECTURE.md`, merge-related tests under `test/`)

## Expense merge (Tracker)

Long-press a row to enter multi-select. Merge is available with 2+ selected rows. The merge sheet asks for description, category, bank, payment type, and optional comments. Date/time come from the latest selected row. Originals are removed locally and on the cloud; only the merged expense remains. Swipe-back exits checkbox mode without jumping the list.

## Docs for other agents

Start with `docs/ARCHITECTURE.md`, then `docs/WATCH_ARCHITECTURE.md` and `docs/CURSOR_SETUP_GUIDE.md`. Narration implementation notes: `.cursor/rules/article-audio-narration.mdc`.
