# TipTour macOS

AI-powered software teacher that lives next to your cursor. It can see your screen, listen to you, talk back, and point at exactly what you need to click — across any app on your Mac.

Built on top of [Clicky](https://github.com/farzaa/clicky) (open source, by [@farzatv](https://x.com/farzatv)).

## What it does

- **Hold Control+Option** → speak your question
- **Sees your screen** via ScreenCaptureKit
- **AI responds** with text + voice (Claude + ElevenLabs)
- **Points at UI elements** — cursor flies to exactly what you need to click
- **Multi-step guidance** — walks you through workflows step by step

## What we're adding (beyond Clicky)

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
ANTHROPIC_API_KEY=your-key
ASSEMBLYAI_API_KEY=your-key
ELEVENLABS_API_KEY=your-key
ELEVENLABS_VOICE_ID=your-voice-id
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

```
User holds Control+Option
  → AVAudioEngine captures mic
  → PCM16 streamed via WebSocket to AssemblyAI (real-time)
  → Live transcription on screen

User releases
  → Screenshot captured (ScreenCaptureKit)
  → Transcript + screenshot → Claude (via Cloudflare Worker)
  → Claude responds with text + [POINT:x,y:label] tags
  → ElevenLabs speaks the response
  → Cursor flies along bezier arc to each target element
```

## Video-to-Guide Pipeline

Generate interactive guides from YouTube tutorials:

```bash
cd scripts
python3 quick-guide.py "https://youtube.com/watch?v=VIDEO_ID"
```

Extracts timestamped steps from video transcripts using Gemini AI. Output is a JSON guide that can sync with video playback — pause at each step, point at the element, wait for user action, resume.

## Credits

- [Clicky](https://github.com/farzaa/clicky) by Farza — the foundation
- Claude by Anthropic — AI vision + reasoning
- AssemblyAI — real-time speech transcription
- ElevenLabs — text-to-speech
