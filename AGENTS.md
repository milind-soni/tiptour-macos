# TipTour - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar companion app. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel with companion voice controls. Uses push-to-talk (ctrl+option) to capture voice input, transcribes it via AssemblyAI streaming, and sends the transcript + a screenshot of the user's screen to Claude. Claude responds with text (streamed via SSE) and voice (ElevenLabs TTS). A blue cursor overlay can fly to and point at UI elements Claude references on any connected monitor.

All API keys live on a Cloudflare Worker proxy — nothing sensitive ships in the app.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay
- **Pattern**: MVVM with `@StateObject` / `@Published` state management
- **Voice Mode**: User-selectable — `geminiLive` (primary, single-model realtime WebSocket with tool calls) or `claudeAndElevenLabs` (legacy 3-stage pipeline)
- **Gemini Live mode (primary)**: Single WebSocket to `gemini-2.5-flash-native-audio-preview-12-2025` — bidirectional voice (PCM16 16kHz in, PCM16 24kHz out), vision (JPEG screenshots), text transcription, AND tool calling all in one streaming connection. Two tools exposed: `point_at_element(label)` for single-click asks, `submit_workflow_plan(goal, app, steps)` for multi-step walkthroughs. Gemini produces workflow plans itself inside its tool call — no separate planner model. API key fetched from Worker's `/gemini-live-key` endpoint.
- **Claude mode (legacy)**: Apple Speech STT → Claude (Sonnet/Opus) via Worker `/chat` → ElevenLabs TTS via Worker `/tts`. Kept for comparison; no AssemblyAI dependency.
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support
- **Voice Input**: Gemini Live mode streams mic audio directly over the WebSocket. Claude mode uses Apple Speech on-device STT. Hotkey is a listen-only CGEvent tap so modifier-only shortcuts (ctrl+opt) work reliably in background.
- **Element Pointing**: The LLM calls one of two tools. `ElementResolver` resolves the `label` argument to pixel positions via a three-tier lookup:
    1. **macOS Accessibility tree** — pixel-perfect, ~30ms. Works on native Mac apps, most Electron apps, and anywhere a well-formed AX tree is exposed.
    2. **YOLO + OCR visual detection** — fallback for apps without good AX support (Blender, games, some web content). Uses step 1's optional `x,y` hint as proximity anchor.
    3. **Raw LLM coordinates** — absolute last resort.
- **Element Detection**: On-device via `NativeElementDetector.swift` — CoreML YOLO model (`UIElementDetector.mlpackage`) for UI element bounding boxes + Apple Vision framework (`VNRecognizeTextRequest`, accurate mode) for OCR text detection. No external server, no Python, no OmniParser dependency.
- **Accessibility Tree**: `AccessibilityTreeResolver.swift` walks the user's target app's AX tree via `ApplicationServices`, matches elements by title/description/value, returns exact pixel frames in global AppKit coordinates. Uses a snapshot of `NSWorkspace.frontmostApplication` taken at hotkey press time so the query targets the app the user was actually looking at, not TipTour's own menu bar.
- **Concurrency**: `@MainActor` isolation, async/await throughout
- **Analytics**: PostHog via `TipTourAnalytics.swift`

### API Proxy (Cloudflare Worker)

The app never calls external APIs directly. All requests go through a Cloudflare Worker (`worker/src/index.ts`) that holds the real API keys as secrets.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `GET /gemini-live-key` | — (returns secret) | Returns the Gemini API key so the app can open a direct WebSocket to Gemini Live. Cloudflare Workers can't proxy Gemini's WebSocket so we expose the key to trusted clients. |
| `POST /chat` | `api.anthropic.com/v1/messages` | Claude vision + streaming chat (legacy voice mode only) |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voiceId}` | ElevenLabs TTS (legacy voice mode only) |
| `POST /chat-fast` | `openrouter.ai/api/v1/chat/completions` | Fast vision model for tutorial-step fallback pointing |
| `POST /generate-guide` | `generativelanguage.googleapis.com/.../gemini-2.5-flash` | Gemini guide generation from YouTube transcripts |
| `POST /transcript` | `youtube-transcript` (npm package) | Fetches YouTube video transcripts |

Worker secrets: `GEMINI_API_KEY`, `ANTHROPIC_API_KEY` (legacy), `ELEVENLABS_API_KEY` (legacy), `OPENROUTER_API_KEY`
Worker vars: `ELEVENLABS_VOICE_ID`

Removed previously: `/plan` (Gemini now plans inside its own tool call via Gemini Live — no separate planner round-trip), `/transcribe-token` + `ASSEMBLYAI_API_KEY` (Gemini Live does STT in-stream; Claude mode now uses on-device Apple Speech).

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and a custom borderless `NSPanel` for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. A global event monitor auto-dismisses it on outside clicks.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the blue cursor companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `ctrl + option` are detected more reliably while the app is running in the background.

**Transient Cursor Mode**: When "Show TipTour" is off, pressing the hotkey fades in the cursor overlay for the duration of the interaction (recording → response → TTS → optional pointing), then fades it out automatically after 1 second of inactivity.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `TipTourApp.swift` | ~89 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. |
| `CompanionManager.swift` | ~1026 | Central state machine. Owns dictation, shortcut monitoring, screen capture, Claude API, ElevenLabs TTS, and overlay management. Tracks voice state (idle/listening/processing/responding), conversation history, model selection, and cursor visibility. Coordinates the full push-to-talk → screenshot → Claude → TTS → pointing pipeline. |
| `MenuBarPanelManager.swift` | ~243 | NSStatusItem + custom NSPanel lifecycle. Creates the menu bar icon, manages the floating companion panel (show/hide/position), installs click-outside-to-dismiss monitor. |
| `CompanionPanelView.swift` | ~761 | SwiftUI panel content for the menu bar dropdown. Shows companion status, push-to-talk instructions, model picker (Sonnet/Opus), permissions UI, DM feedback button, and quit button. Dark aesthetic using `DS` design system. |
| `OverlayWindow.swift` | ~881 | Full-screen transparent overlay hosting the blue cursor, response text, waveform, and spinner. Handles cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping, and fade-out transitions. |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display. |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk voice pipeline. Handles microphone capture via `AVAudioEngine`, provider-aware permission checks, keyboard/button dictation sessions, transcript finalization, shortcut parsing, contextual keyterms, and live audio-level reporting for waveform feedback. |
| `BuddyTranscriptionProvider.swift` | ~40 | Protocol surface. Always returns `AppleSpeechTranscriptionProvider` (only used by the legacy Claude voice mode; Gemini Live handles STT in-stream). |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | On-device transcription backed by Apple's Speech framework. Free, offline, no network key required. |
| `BuddyAudioConversionSupport.swift` | ~108 | Audio conversion helpers. Converts live mic buffers to PCM16 mono audio and builds WAV payloads for upload-based providers. |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `ClaudeAPI.swift` | ~291 | Claude vision API client with streaming (SSE) and non-streaming modes. TLS warmup optimization, image MIME detection, conversation history support. |
| `OpenAIAPI.swift` | ~142 | OpenAI GPT vision API client. |
| `ElevenLabsTTSClient.swift` | ~81 | ElevenLabs TTS client. Sends text to the Worker proxy, plays back audio via `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| `NativeElementDetector.swift` | ~270 | On-device element detection using CoreML YOLO + Apple Vision OCR. Maintains a live-fed cache for instant element lookups. Used as fallback when AX tree is unavailable. |
| `AccessibilityTreeResolver.swift` | ~250 | Walks the frontmost app's macOS Accessibility tree, looks up elements by title/description/value, returns pixel-perfect frames. Primary element-lookup path — covers native Mac apps, SwiftUI, AppKit, most Electron. |
| `ElementResolver.swift` | ~140 | Unified single-entry resolver. Given a label (and optional LLM coord hint), tries AX tree → YOLO+OCR → raw LLM coords in order. Always produces a global AppKit point so the overlay can fly the cursor directly. |
| `GeminiLiveClient.swift` | ~280 | WebSocket client for Google's Gemini Live API. Sends PCM16 audio, JPEG screenshots, and text; receives PCM16 audio chunks and transcripts. All messages are JSON over a single wss:// connection. |
| `GeminiLiveAudioPlayer.swift` | ~120 | Streaming PCM16 24kHz audio playback via AVAudioEngine + AVAudioPlayerNode. Queues incoming audio chunks from the WebSocket for gapless playback. |
| `GeminiLiveSession.swift` | ~200 | Orchestrator that ties the WebSocket client + audio player + mic capture together. Owns the Gemini Live conversation lifecycle and exposes published state (input/output transcripts, isModelSpeaking) for the UI. |
| `ElementLocationDetector.swift` | ~335 | Detects UI element locations in screenshots for cursor pointing. |
| `ClickDetector.swift` | ~150 | Global listen-only CGEventTap that fires a callback when a left-mouse-down lands within a tolerance radius of an armed target. WorkflowRunner uses it to auto-advance the tutorial checklist when the user clicks the element the cursor is pointing at. |
| `DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `TipTourAnalytics.swift` | ~121 | PostHog analytics integration for usage tracking. |
| `WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `worker/src/index.ts` | ~142 | Cloudflare Worker proxy. Three routes: `/chat` (Claude), `/tts` (ElevenLabs), `/transcribe-token` (AssemblyAI temp token). |

## Build & Run

```bash
# Open in Xcode
open leanring-buddy.xcodeproj

# Select the TipTour scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Cloudflare Worker

```bash
cd worker
npm install

# Add secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with your keys)
npx wrangler dev
```

## Code Style & Conventions

### Variable and Method Naming

IMPORTANT: Follow these naming rules strictly. Clarity is the top priority.

- Be as clear and specific with variable and method names as possible
- **Optimize for clarity over concision.** A developer with zero context on the codebase should immediately understand what a variable or method does just from reading its name
- Use longer names when it improves clarity. Do NOT use single-character variable names
- Example: use `originalQuestionLastAnsweredDate` instead of `originalAnswered`
- When passing props or arguments to functions, keep the same names as the original variable. Do not shorten or abbreviate parameter names. If you have `currentCardData`, pass it as `currentCardData`, not `card` or `cardData`

### Code Clarity

- **Clear is better than clever.** Do not write functionality in fewer lines if it makes the code harder to understand
- Write more lines of code if additional lines improve readability and comprehension
- Make things so clear that someone with zero context would completely understand the variable names, method names, what things do, and why they exist
- When a variable or method name alone cannot fully explain something, add a comment explaining what is happening and why

### Swift/SwiftUI Conventions

- Use SwiftUI for all UI unless a feature is only supported in AppKit (e.g., `NSPanel` for floating windows)
- All UI state updates must be on `@MainActor`
- Use async/await for all asynchronous operations
- Comments should explain "why" not just "what", especially for non-obvious AppKit bridging
- AppKit `NSPanel`/`NSWindow` bridged into SwiftUI via `NSHostingView`
- All buttons must show a pointer cursor on hover
- For any interactive element, explicitly think through its hover behavior (cursor, visual feedback, and whether hover should communicate clickability)

### Do NOT

- Do not add features, refactor code, or make "improvements" beyond what was asked
- Do not add docstrings, comments, or type annotations to code you did not change
- Do not try to fix the known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
- Do not run `xcodebuild` from the terminal — it invalidates TCC permissions

## Git Workflow

- Branch naming: `feature/description` or `fix/description`
- Commit messages: imperative mood, concise, explain the "why" not the "what"
- Do not force-push to main

## Self-Update Instructions

<!-- AI agents: follow these instructions to keep this file accurate. -->

When you make changes to this project that affect the information in this file, update this file to reflect those changes. Specifically:

1. **New files**: Add new source files to the "Key Files" table with their purpose and approximate line count
2. **Deleted files**: Remove entries for files that no longer exist
3. **Architecture changes**: Update the architecture section if you introduce new patterns, frameworks, or significant structural changes
4. **Build changes**: Update build commands if the build process changes
5. **New conventions**: If the user establishes a new coding convention during a session, add it to the appropriate conventions section
6. **Line count drift**: If a file's line count changes significantly (>50 lines), update the approximate count in the Key Files table

Do NOT update this file for minor edits, bug fixes, or changes that don't affect the documented architecture or conventions.
