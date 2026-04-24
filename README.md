<div align="center">

<img src="TipTour/Assets.xcassets/AppIcon.appiconset/1024-mac.png" width="128" height="128" alt="TipTour" />

<h1>TipTour</h1>

**Ask your Mac how to do anything. Watch the cursor do it.**

A voice-powered AI teacher for your Mac. Ask TipTour something and it sees your screen, talks back, understands what you're trying to do, and flies the cursor to the exact buttons you need to click.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014+-black)](https://www.apple.com/macos)

</div>

---

## What it does

Hold **Control + Option**, ask a question naturally:

> *"How do I render an animation in Blender?"*
>
> *"Where's the File menu in Xcode?"*
>
> *"Walk me through exporting this as an MP4."*

TipTour hears you, sees your screen, and flies a cursor to the exact UI element. On multi-step workflows it walks you through every click — narrating as it goes, auto-advancing when you click the highlighted element.

Works across every Mac app: Xcode, Blender, Figma, VS Code, browsers, GarageBand, games. Native apps get pixel-perfect targeting via the macOS Accessibility tree; apps that render their own UI (Blender, Unity, canvas tools) fall back to on-device CoreML detection.

---

## Features

- 🎤 **Voice-first.** Hold a hotkey and ask — no menus, no search. One streaming connection handles voice in, vision, voice out, and tool calling.
- 🎯 **Pixel-perfect pointing.** macOS Accessibility tree for native apps (~30ms, exact). CoreML YOLO + Apple Vision OCR for everything else. Fully on-device.
- 🪜 **Multi-step walkthroughs.** "How do I X" emits a structured plan. Cursor flies to step 1, waits for your click, advances. Checklist UI shows progress with Skip/Retry controls.
- 🐱 **Neko mode.** Optional — replace the cursor with a pixel-art cat that runs across your screen, leaves paw-print footprints, and falls asleep when idle.
- 🔒 **Permissions respected.** Mic and screen capture only fire while you're holding the hotkey. Nothing runs in the background.
- 💾 **Your data stays yours.** All element grounding happens on-device. Only voice + screenshots go to Google's Gemini Live API. No telemetry beyond opt-in anonymized analytics.

---

## Install

A signed + notarized DMG is coming. Until then, build from source — it's four commands (see [below](#building-from-source)).

---

## How it works

```
         Control + Option ──┐
                            ▼
                     ┌──────────────┐
                     │ Gemini Live  │   Single WebSocket.
                     │  (3.1 Flash) │   Voice in, vision in,
                     └──────┬───────┘   voice out, tool calls.
                            │
                            ▼
           ┌────────────────────────────────┐
           │  point_at_element(label)       │
           │  submit_workflow_plan(...)     │
           └────────────────┬───────────────┘
                            ▼
           ┌────────────────────────────────┐
           │       ElementResolver          │
           │  1. macOS Accessibility tree   │  ~30ms, pixel-perfect
           │  2. CoreML YOLO + Vision OCR   │  ~200ms, on-device
           │  3. Raw LLM coordinates        │  last resort
           └────────────────┬───────────────┘
                            ▼
                   🎯 Cursor flies to target.
                      Click it → plan auto-advances.
```

A few opinionated choices worth calling out:

- **Single-model architecture.** One Gemini Live WebSocket handles everything. No STT → LLM → TTS pipeline, no separate planner model. Cuts latency and eliminates cross-component state-sync bugs.
- **Grounding is deterministic.** The LLM emits semantic labels (`"File"`, `"New"`, `"Save"`). Swift code grounds them to pixels via AX tree + YOLO + OCR. The LLM is never asked to output raw coordinates (except as a last-resort fallback) — it's slow and imprecise at that.
- **AX-empty-tree cache.** Apps that don't expose accessibility (Blender, games) are flagged on first miss and skip AX polling for 10 minutes — straight to YOLO. Saves ~2.7s per step and keeps Core Audio fed so voice stays smooth.
- **ClickDetector auto-advance.** A global `CGEventTap` listens for left-mouse-down within the resolved element's rect (not just a radius). Click the element → next step arms automatically.

See [AGENTS.md](AGENTS.md) for the deeper technical tour.

---

## Building from source

**Requires:** macOS 14+, Xcode 16+, Node 20+ (for the Worker proxy).

### 1. Get a Gemini API key

TipTour uses Google's Gemini Live API (voice + vision + tool calling in one stream). Create a free key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — click "Create API key", copy the string that starts with `AIzaSy...`. Free-tier quota is plenty for personal use; set a hard budget cap in Google Cloud if you're worried about abuse.

### 2. Open + run

```bash
open tiptour-macos.xcodeproj
```

Set your signing team in Target → Signing & Capabilities, then `Cmd+R`. TipTour appears in your menu bar — no dock icon, no main window.

### 3. Paste your Gemini key

Click the TipTour icon → expand the **Developer** section at the bottom of the panel → paste your key → **Save**. Stored in macOS Keychain, never synced.

That's it. No Node, no Cloudflare account, no Worker deployment. The app reads the key directly when opening a Gemini Live session.

> **For distribution** (shipping a signed DMG to non-technical users), see [`worker/`](worker/) — that's the API-key proxy path that lets you ship the app without asking end-users for a key. Not needed for local development.

### 4. Grant permissions

TipTour asks for four macOS permissions on first launch. Grant them in System Settings → Privacy & Security:

| Permission | Why |
|---|---|
| Microphone | Voice input while holding Control + Option |
| Accessibility | Global keyboard shortcut + reading UI element trees |
| Screen Recording | Screenshots for Gemini's visual context |
| Screen Content | ScreenCaptureKit on macOS 15+ |

---

## Roadmap

- [ ] **YouTube tutorial follow-along** — paste a YouTube URL, video plays picture-in-picture, and at each instructor action the cursor flies to the corresponding button in your real app.
- [ ] **Signed DMG + Sparkle auto-updates**
- [ ] **Step-resolution telemetry** to guide where grounding needs to improve per app

---

## Contributing

PRs welcome. For non-trivial changes, open an issue first.

Before submitting:
1. Open `tiptour-macos.xcodeproj` in Xcode → verify it builds
2. Any new permission requests need matching `NS*UsageDescription` in `Info.plist`
3. Run through the push-to-talk flow end-to-end once to catch regressions

See [AGENTS.md](AGENTS.md) for code style and conventions.

---

## Credits

- [Clicky](https://github.com/farzaa/clicky) by [@FarzaTV](https://x.com/farzatv) — the foundation
- [Gemini Live](https://ai.google.dev/gemini-api/docs/live-api) (Google) — realtime voice, vision, and tool calling
- [oneko](https://github.com/crgimenes/neko) — pixel-art cat sprites (Masayuki Koba 1989, BSD-2 port by Cesar Gimenes)

---

<div align="center">

**[MIT License](LICENSE)** · Made by [@milind-soni](https://github.com/milind-soni)

</div>
