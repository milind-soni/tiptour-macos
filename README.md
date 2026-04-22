# TipTour macOS

AI-powered software teacher that lives next to your cursor. It can see your screen, listen to you, talk back, and point at exactly what you need to click — across any app on your Mac.

A macOS menu bar companion that teaches you software by voice.

## What it does

- **Hold Control+Option** → speak your question
- **Sees your screen** via ScreenCaptureKit
- **AI responds** with text + voice (Claude + ElevenLabs)
- **Points at UI elements** — cursor flies to exactly what you need to click
- **Multi-step guidance** — walks you through workflows step by step

## What it does

- **Accessibility tree intelligence** — exact element positions from macOS AX API, not just screenshot guessing
- **Structured multi-step workflows** — Claude returns `guide_user` tool calls with sequential steps
- **StepRunner** — auto-advances when you perform each action (AX observer)
- **Video-synced tutorials** — YouTube tutorials that pause and wait for you to perform each action in the real app
- **Guide creation from YouTube** — AI watches tutorial videos and extracts step-by-step guides automatically

## Setup

### 1. Cloudflare Worker (API proxy)

```bash
cd worker
npm install
```

Create `worker/.dev.vars`:
```
GEMINI_API_KEY=your-key
ANTHROPIC_API_KEY=your-key       # optional — legacy Claude voice mode
ELEVENLABS_API_KEY=your-key      # optional — legacy Claude voice mode
ELEVENLABS_VOICE_ID=your-voice-id
OPENROUTER_API_KEY=your-key      # optional — tutorial pointing fallback
```

Run locally:
```bash
npx wrangler dev
```

### 2. Build the app

```bash
open leanring-buddy.xcodeproj
```

In Xcode:
1. Set your signing team (Target → Signing & Capabilities)
2. Cmd+R to build and run

The app appears in your **menu bar** (not the dock).

### Permissions needed

- **Microphone** — push-to-talk voice capture
- **Accessibility** — global keyboard shortcut + UI element reading
- **Screen Recording** — screenshots for AI context

## Architecture

Primary mode is **Gemini Live**: one bidirectional WebSocket handles voice in, vision, voice out, and tool calling in a single model. The older Claude + ElevenLabs pipeline remains selectable for comparison.

```
User presses Control+Option
  → Gemini Live WebSocket opens (voice in + vision)
  → User speaks; Gemini hears streaming audio
  → Gemini sees periodic screenshot frames
  → Gemini picks one of two tools:
      - point_at_element(label)         single-click ask
      - submit_workflow_plan(goal,app,steps)  multi-step walkthrough
  → ElementResolver turns labels into pixel coords via:
      1. macOS accessibility tree (native apps — instant, pixel-perfect)
      2. on-device YOLO + Apple Vision OCR (Blender, games, canvas)
      3. raw LLM coordinates (last resort)
  → Cursor flies along a bezier arc to the target
  → Gemini narrates in sync — one model owns both speech and plan
```

## Video-to-Guide Pipeline

Generate interactive guides from YouTube tutorials:

```bash
cd scripts
python3 quick-guide.py "https://youtube.com/watch?v=VIDEO_ID"
```

Extracts timestamped steps from video transcripts using Gemini AI. Output is a JSON guide that can sync with video playback — pause at each step, point at the element, wait for user action, resume.

## Credits


- Gemini Live (Google) — realtime voice + vision + tool calling
- Claude by Anthropic — vision + reasoning in the legacy mode
- ElevenLabs — text-to-speech in the legacy mode
