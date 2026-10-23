# ChatHalis

An AI assistant for Android — paper, ink, and a single drop of blue.

ChatHalis is built around one principle: **so simple there is nothing left to remove**. Open the app, type a question, Halis answers. No sign-up, no configuration, no model picking — everything just works.

## Features

- **Instant chat** — streaming replies token by token, live typing on screen
- **Thinking space** — Halis' chain of thought in its own collapsible panel with thinking time
- **Beautiful Markdown** — headings, tables, lists, and dark code blocks with a copy button
- **Local history** — every conversation lives in SQLite on your device, nowhere else
- **Usage meter** — a Claude-style percentage of your hourly chat limit, right in Settings
- **Light & dark** — light by default, dark one tap away; the look follows you
- **English & Tiếng Việt** — English out of the box, Vietnamese in Settings
- **Rename / delete / regenerate answers**, stop mid-stream and keep what was written

## Usage limits

Chatting runs on an hourly budget of 200 requests, shown as a percentage — never as raw counts. Filling the budget, or the server answering 429, pins the meter at 100% and pauses new messages for 1 h 05 m. The pause is applied once per window: retrying during it never adds time.

## Requirements

| | |
|---|---|
| Android | 7.1.1 (API 25) or newer |
| Flutter | 3.47 stable |
| Dart | 3.13 |

## Build & run

```bash
flutter pub get
flutter run                 # debug on an emulator / device
flutter build apk --release # release APK
flutter test                # unit tests
```

## Architecture

```
lib/
├── core/        design tokens (light + dark), strings (en + vi), small utils
├── gateway/     Kilo Gateway client: SSE, chunk parsing, error taxonomy
├── engine/      chat turns (stream, abort, retry), app store, usage tracker
├── data/        SQLite: conversations, messages
├── prompt/      the Halis identity system prompt
└── ui/          home, chat, settings — and shared widgets
```

A chat turn passes through four layers: `ui` hands text to the `engine`, the engine calls the `gateway` with history trimmed to the token budget (`context_window.dart`), streaming events (text / thinking / done) reduce into the message, then persist via `data` when the turn ends. Usage accounting runs alongside: every send counts against the rolling hour, a 429 locks the meter at 100% for the cooldown, and the tracker survives restarts.

Each reply is capped at 32,768 output tokens; when a reply is cut by the cap, a notice shows right under the message.

## Releases

Publishing a release triggers the GitHub Action in `.github/workflows/release.yml`, which builds the APK and attaches it — plus its sha256 — to that release.

## Privacy

ChatHalis has no accounts and no server of its own. Your history stays in SQLite on the device, and you can wipe everything from Settings at any time.

---

Halis · a project by Hieu Louis
