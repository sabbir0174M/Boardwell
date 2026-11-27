# Boardwell

**Boardwell** is a 100% free, offline-first chess playing and hybrid multi-coach learning Android app built with Flutter. It is engineered for universal Android compatibility — from low-end 32-bit Android 7.0 (`minSdk 24`) phones to modern 64-bit Android 15/16/17+ (`targetSdk 36`) devices with mandatory 16 KB ELF page alignment, Edge-to-Edge layouts, and Predictive Back gestures.

## Key Capabilities

- **Universal Android Compatibility & Auto-Tuning**
  - `minSdk 24` through `compileSdk 36` / `targetSdk 36` with NDK r28+ and `useLegacyPackaging = false` for 16 KB page-size alignment.
  - Native `DeviceCapabilityService` reads RAM, CPU ABI (`armeabi-v7a`, `arm64-v8a`, `x86_64`), and Android API level on startup:
    - **Low-Memory Profile (< 3.5 GB RAM or 32-bit):** Stockfish tuned to `Threads=1`, `Hash=16`, depth `10`, lightweight board animations, instant zero-RAM `RuleBasedCoach` offline.
    - **Standard/High Profile (64-bit, 4 GB+ RAM):** Stockfish tuned to `Threads=2`, `Hash=32`, depth `14`, full on-device LLM support.
  - **Zero Dangerous Permissions:** Declares only `INTERNET` and `ACCESS_NETWORK_STATE`. All JSON backups and local `.task`/`.bin` model imports use Android's Storage Access Framework (`file_picker` / `share_plus`).
- **Offline Chess Core**
  - Interactive `chessground` (^10.3.0) board + `dartchess` (^0.14.0) rules, FEN/PGN, undo/redo, and promotion.
  - Local `stockfish_flutter_plus` (^1.0.1) engine (Skill Level 0–20), live evaluation bar, move quality badges (Best, Good, Inaccuracy, Mistake, Blunder), 30 bundled ECO openings, and 20 offline tactical puzzles.
- **Hybrid Multi-Coach System & Direct AI Opponent**
  - Unlimited custom `CoachProfile` entries across three engines:
    1. **Rule-Based Coach** (instant, 0 MB RAM, always offline).
    2. **On-Device LLM Coach** via `flutter_edge_ai` + `flutter_edge_ai_mediapipe` (`.task` / `.bin` models, download progress, local file import, strict single-model-in-RAM lifecycle, auto-release on background pause).
    3. **Cloud AI API Coach (BYOK)** via universal streaming OpenAI-compatible `/chat/completions` client with editable presets (OpenRouter, Google AI Studio, OpenAI, Groq, Custom URL) and API keys stored exclusively in `flutter_secure_storage`.
  - **Anti-Hallucination Pipeline:** Every AI coaching request runs local Stockfish first to ground the prompt with verified FEN, evaluation delta, best move, and top 3-move PV line.
  - **Hybrid Auto-Fallback & Side-by-Side Compare Mode:** Automatically falls back to the configured offline coach when `connectivity_plus` detects no network, and lets you compare two coaches side by side on any move.
  - **Direct AI Model Opponent:** Play directly against any configured on-device or cloud coach model with `dartchess` legal-move validation, up to 3 automatic retries on illegal moves, and Stockfish fallback.
- **User-Owned Local Storage**
  - SQLite (`sqflite`) for saved games, puzzle progress, and Coach Profiles, plus JSON Export/Import backup (raw API keys are never exported).

## Automated APK Builds (GitHub Actions)

Push to `main` or trigger **Actions → Build Boardwell Android APKs** to build and download:
1. `Boardwell-universal-release.apk` (Universal Multi-ABI: `armeabi-v7a`, `arm64-v8a`, `x86_64`)
2. Per-ABI Split APKs (`Boardwell-armeabi-v7a-release.apk`, `Boardwell-arm64-v8a-release.apk`, `Boardwell-x86_64-release.apk`)

## Local Development

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Developer Credit

Developed by **Md. Sabbir Mia**  
GitHub: [https://github.com/sabbir404M](https://github.com/sabbir404M)
