# Voice AI Mac App Research

Date: 2026-05-25

## Question

Pipecat is not working reliably as TipTour's local voice sidecar. We need a grounded look at open-source Mac voice AI apps and decide what TipTour should do next.

## Executive Take

TipTour should keep Gemini Live as the default speech-to-speech path, but stop treating Pipecat as the main alternative voice runtime.

The best open-source Mac voice apps converge on a simpler pattern:

1. Native macOS shell in Swift/SwiftUI.
2. Local speech-to-text through WhisperKit/Core ML, Apple Speech, or whisper.cpp.
3. Optional text cleanup/planning after transcription.
4. Paste or route the final transcript into the app's existing command engine.

That maps cleanly to TipTour: build a native local dictation/command mode that sends the transcript into `PointerPromptRouter` and `TipTourEngine`. Use provider-native realtime APIs for full speech-to-speech. Keep Pipecat only as an experimental harness for transport/provider experiments.

## Current Local Pipecat Status

The sidecar is currently reachable on `127.0.0.1:7860`.

Observed health:

- `service`: `tiptour-pipecat-voice`
- `active`: `false`
- TipTour harness reachable at `127.0.0.1:19474`
- Pipecat import ready: `true`
- Pipecat version: `1.2.1`
- local audio ready: `true`
- last error: `Missing GOOGLE_API_KEY/GEMINI_API_KEY for Pipecat Gemini Live.`

That means the current problem is not simply "Pipecat is not installed." The next likely failure points are app-to-sidecar key handoff, sidecar lifecycle, Gemini Live service API drift, local audio session ownership, or the complexity of asking a Python voice framework to sit in the middle of a native Mac app that already has a working Gemini Live path.

## Best Open-Source Mac App References

### Pindrop

Source: https://github.com/watzon/pindrop

Why it matters:

- Native macOS menu bar app.
- Swift/SwiftUI, not Electron/Tauri.
- Uses WhisperKit for local on-device transcription.
- Supports global hotkeys and push-to-talk/toggle behavior.

Takeaway for TipTour:

This is the closest architectural reference for a local native voice-input path. The important idea is not the full app, it is the small loop: hotkey -> record -> local STT -> insert or route text.

### VoiceInk

Source: https://tryvoiceink.com/

Why it matters:

- Mac-first dictation UX.
- Local transcription by default.
- Optional cloud enhancement sends text, not raw audio.
- Stores keys locally and emphasizes privacy.

Takeaway for TipTour:

Good reference for user-facing trust language and settings structure: local by default, optional provider keys, clear boundary between voice audio and post-transcription text processing.

### Cadence

Source: https://www.cadencevoice.ai/

Why it matters:

- Voice input for agent control on macOS.
- On-device Whisper transcription.
- Routes spoken commands into Claude agents.
- Uses app context such as active app and selected text.

Takeaway for TipTour:

This is conceptually close to TipTour's Ctrl+K and focus-highlight flow. The useful pattern is "voice becomes contextual command text," not "voice framework owns the desktop."

### OpenWhispr

Source: https://github.com/OpenWhispr/openwhispr

Why it matters:

- Feature-rich open-source dictation, notes, meeting transcription, AI actions.
- Cross-platform stack: Electron, React, whisper.cpp, sherpa-onnx.
- Public API and MCP mentioned in the project docs.

Takeaway for TipTour:

Good reference for a broader voice workspace, but too heavy for TipTour's native menu-bar core. Useful for API/MCP patterns, not for the in-app voice hotkey path.

### Buzz

Source: https://buzzcaptions.com/ and https://github.com/chidiwilliams/buzz

Why it matters:

- Mature open-source Whisper GUI.
- Good batch/file/live transcription reference.
- Cross-platform and MIT licensed.

Takeaway for TipTour:

Useful for transcription UX and export workflows, but not directly relevant to realtime desktop action. It is more "transcribe media" than "control the Mac."

### McClaw

Source: https://mcclaw.app/

Why it matters:

- Native SwiftUI AI assistant shell for multiple AI CLIs.
- Voice mode, Keychain/auth separation, native Mac positioning.
- Strong "native shell around existing engines" philosophy.

Takeaway for TipTour:

Good validation that TipTour should stay native and delegate heavy AI work to well-defined provider/CLI/localhost boundaries, not turn the Mac app into an embedded agent server.

## Voice Runtime / Framework Research

### WhisperKit / Argmax OSS Swift

Source: https://github.com/argmaxinc/argmax-oss-swift

Fit for TipTour: high.

Why:

- Swift package.
- macOS 14+.
- Includes WhisperKit for speech-to-text.
- Includes TTSKit and SpeakerKit in the same OSS SDK.
- CLI supports microphone streaming for testing.
- Local server exists for OpenAI-compatible transcription experiments.

Recommended use:

Use WhisperKit as the first local voice command path:

1. Capture audio with `AVAudioEngine`.
2. Transcribe locally with WhisperKit.
3. Feed final text into `PointerPromptRouter`.
4. Let existing TipTour routing decide local one-step action, Claude one-step planning, or Hermes delegation.

Do not start by building a full speech-to-speech replacement. Start with reliable push-to-talk speech-to-command.

### Apple Speech

Source: Apple native framework, no new service dependency.

Fit for TipTour: medium to high.

Why:

- Native and low-friction.
- Good fallback where WhisperKit model download/performance is an issue.
- No Python, no sidecar, no provider key.

Concern:

Quality and language/domain behavior may be less predictable than WhisperKit for technical commands.

Recommended use:

Offer as a fallback local STT engine behind the same `LocalSpeechCommandService` interface.

### whisper.cpp

Source: https://github.com/ggml-org/whisper.cpp

Fit for TipTour: medium.

Why:

- Mature C/C++ Whisper runtime.
- Has real-time microphone examples and an HTTP server with OpenAI-like API.
- Cross-platform and proven.

Concern:

Less idiomatic than WhisperKit in a SwiftUI macOS app. Model/runtime packaging is more work.

Recommended use:

Keep as a fallback or command-line benchmark, not the first native integration.

### OpenAI Realtime

Source: https://platform.openai.com/docs/guides/realtime

Fit for TipTour: medium as optional cloud speech-to-speech.

Why:

- Provider-native realtime voice with tool calls.
- Official docs recommend WebRTC for browser/mobile capture and WebSocket for server/media pipelines.
- Strong production direction for low-latency voice agents.

Concern:

TipTour already has Gemini Live. Adding another provider-native realtime path means duplicating session tooling, model configuration, and provider UX.

Recommended use:

Consider later as a provider option, not as the immediate Pipecat replacement.

### LiveKit Agents

Source: https://docs.livekit.io/agents/

Fit for TipTour: low to medium.

Why:

- Strong open-source production framework for realtime voice/video agents.
- Python and Node.js agent SDKs.
- Good for rooms, multi-participant calls, telephony, cloud scale, and production observability.

Concern:

For a single-user local Mac hotkey, LiveKit is more infrastructure than needed. It would still be a sidecar/server-style integration.

Recommended use:

Choose LiveKit only if TipTour needs multi-user sessions, phone/video, or hosted voice agent infrastructure.

### Pipecat

Sources:

- https://docs.pipecat.ai/overview/introduction
- https://github.com/pipecat-ai/pipecat

Fit for TipTour: low for the primary local Mac hotkey path, medium for experiments.

Why:

- Open-source Python framework for realtime voice and multimodal agents.
- Supports many providers and transports, including Gemini Live, OpenAI Realtime, LiveKit, Daily, WebSocket, and local transport.
- Useful for quickly testing voice-agent pipelines.

Concern:

Pipecat makes the simple path complex for TipTour:

- Python sidecar install and lifecycle.
- PortAudio/PyAudio and macOS microphone behavior outside the app.
- Provider key forwarding from Keychain to localhost.
- Fast-moving Pipecat API surface.
- Duplicate voice/session lifecycle next to TipTour's built-in Gemini Live session.
- Risk of two planners: Pipecat and Hermes both trying to own long-horizon work.

Recommended use:

Rename the UI affordance to "Pipecat Lab" or hide it behind Advanced/Dev. It should be for runtime experiments, not the product's second voice mode.

## Recommended TipTour Architecture

### Phase 1: Native Local Speech Command

Build a native local STT path:

- `LocalSpeechCommandService`
- `WhisperKitSpeechRecognizer`
- optional `AppleSpeechRecognizer`
- one shared transcript callback into `PointerPromptRouter`
- no sidecar
- no TTS required for v1

Flow:

```text
Ctrl+Option -> record audio -> local transcript -> PointerPromptRouter -> TipTourEngine -> one action
```

This gives TipTour a reliable non-cloud voice mode and reuses all existing grounding/action safety rails.

### Phase 2: Better Voice Feedback

Add short spoken responses after action validation:

- Start with `AVSpeechSynthesizer`.
- Keep the overlay bubble as the source of truth.
- Add TTSKit only if local voice quality matters.

### Phase 3: Provider Realtime Options

Keep Gemini Live as default speech-to-speech. Consider OpenAI Realtime later behind a provider enum if users want it.

Do not put Pipecat between the app and Gemini Live unless there is a specific test that requires Pipecat's pipeline abstraction.

### Phase 4: Pipecat As Dev Harness

If we keep Pipecat:

- Move it under an Advanced "Voice Lab" section.
- Show exact health: server, TipTour harness, Pipecat import, local audio, provider key present, last error.
- Add a "Copy launch command" and "Open logs" action.
- Refuse to start when no provider key is present.
- Pin Pipecat versions more tightly and test with the installed version.
- Treat `/v1/tools/*` as the stable value. The actual realtime voice pipeline can be experimental.

## Decision

Build native local speech-to-command first. It is the path most aligned with successful open-source Mac voice apps and with TipTour's architecture.

Pipecat should not be removed immediately, because its tool proxy and experiment harness are useful. But it should be demoted from "alternate voice mode" to "experimental runtime lab" until it can pass a repeatable local smoke test:

1. Sidecar starts from TipTour.
2. Key handoff works.
3. Mic input is captured.
4. Gemini Live session starts.
5. User transcript event appears.
6. One TipTour tool call succeeds.
7. Stop cleans up the audio pipeline.

## Practical Next Steps

1. Add a small `VoiceInputMode` enum: `geminiLive`, `localSpeechCommand`, `pipecatLab`.
2. Implement `LocalSpeechCommandService` with a protocol boundary before choosing WhisperKit vs Apple Speech.
3. Wire local transcript submission to the existing text command path.
4. Move Pipecat UI copy toward "Lab" and expose its concrete health checks.
5. Add a `make smoke-pipecat` or script that checks health, key presence, tool proxy calls, start, events, and stop.
