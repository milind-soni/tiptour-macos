# TipTour - Agent Instructions

<!-- This is the single source of truth for all AI coding agents. CLAUDE.md is a symlink to this file. -->
<!-- AGENTS.md spec: https://github.com/agentsmd/agents.md — supported by Claude Code, Cursor, Copilot, Gemini CLI, and others. -->

## Overview

macOS menu bar voice companion. Lives entirely in the macOS status bar (no dock icon, no main window). Clicking the menu bar icon opens a custom floating panel. Voice uses one realtime Gemini Live path by default. Ctrl+K text commands can route to Hermes or Claude for one-action planning through the same TipTour grounding/action engine.

Source builds require the user to paste their own provider keys into the visible panel fields; keys are stored in macOS Keychain. Distributed builds can optionally configure a Cloudflare Worker proxy via `TipTourWorkerBaseURL`, but the maintainer's Worker URL must never be hardcoded into the open-source app.

## Architecture

- **App Type**: Menu bar-only (`LSUIElement=true`), no dock icon or main window.
- **Framework**: SwiftUI (macOS native) with AppKit bridging for menu bar panel and cursor overlay.
- **Pattern**: MVVM with `@StateObject` / `@Published` state management.
- **Source Layout**: TipTour source is grouped by responsibility: `App/` for lifecycle and `CompanionManager`, `Core/` for the stable `TipTourEngine` facade, `Actions/` for action-driver boundaries, `Workflow/` for single-action plans and grounding, `Perception/` for screen/AX/DOM/OCR/local detection, `ImageEditing/` for file-aware highlighted image edit preparation/execution, `FollowAlong/` for tutorial transcript-to-actions experiments, `Harnesses/` for local external transports, `Plugins/` for connection metadata, `Skills/` for portable markdown app skills plus tiny runtime hints, `UI/` for panel/overlay views, `Voice/` for Gemini Live plus planner/orchestrator clients, `Recording/` for walkthrough capture, and `Utilities/` for cross-cutting helpers. Keep general agent/source-map docs outside `TipTour/`; markdown under `TipTour/Skills/**/SKILL.md` is intentionally bundled as app-skill content.
- **Voice Mode**: Voice is a single Gemini Live realtime path: bidirectional WebSocket voice, optional screenshots, and at most one tool call per user turn. Gemini can call `submit_workflow_plan(goal, app, steps)` for one local computer/text action or `edit_highlighted_image(prompt, ...)` for a highlighted image edit. The Screenshots toggle applies to remote visual context and image-edit execution; local accurate grounding can still run without sending screenshots. Provider API keys come from local Keychain fields in source builds. The legacy `point_at_element` path is disabled and no longer declared to Gemini.
- **TipTour Engine Facade**: `TipTourEngine` is the small core-facing facade for callers that should not know about `CompanionManager`. It exposes observe, local target listing with stable marks/IDs, grounded one-step planning/execution through the shared `PointerActionRequest` shape, recent action history, and single-action workflow submission; future `ground`, `act`, `record`, and `replay` APIs should grow here first instead of expanding transport/UI classes. It also enforces user connection toggles before accepting external action requests.
- **Local Harness Server**: TipTour also exposes a localhost-only HTTP harness (`TipTourHarnessServer`) on `127.0.0.1:19474` for external orchestrators such as Hermes. This keeps Hermes/OpenClaw/Composio outside the macOS app while letting them call TipTour as the local perception/action engine. Hermes should use its own tools for web search, browser automation, downloads, files, terminal commands, memory, skills, and long-horizon planning; TipTour should enter when the local Mac needs visual context, GUI grounding/action, or visual validation. The harness exposes health/capabilities/observe, the canonical agent contract (`GET /v1/agent-contract`), brokered visual context (`POST /v1/visual-context`), highlighted file/URL/text source resolution (`POST /v1/resolve-highlight-source`), file-aware highlighted image edit preparation/execution (`POST /v1/image-edit`), loaded markdown skills (`GET /v1/skills` and `GET /v1/skills/active`), compact target grounding (`POST /v1/ground-target`), debug local YOLO/OCR targets (`GET /v1/targets`), grounded one-step planning/execution (`POST /v1/act` and `POST /v1/plan-next-action`), recent validation history (`GET /v1/action-history`), plus raw single-action workflow submission (`POST /v1/workflow-plan`). Long-horizon prompt planning belongs to Hermes or another external orchestrator, which should loop over observe/visual-context/ground-target/act/action-history instead of asking TipTour to own task planning. Every accepted one-action path carries a `trace_id` through logs and harness responses so grounding, execution, validation, and latency can be debugged together. `plan-next-action` refreshes local perception, chooses one real target, executes one action through `WorkflowRunner`, waits for completion/pause/failure, refreshes perception once more, and reports validation. Raw workflow submission still clamps external requests to one step and routes through `TipTourEngine` + `WorkflowRunner` so Autopilot permissions, grounding, overlay flight, app-switch pauses, and CUA execution remain the single enforcement path.
- **Screen Capture**: ScreenCaptureKit (macOS 14.2+), multi-monitor support. The cursor screen is captured at native display pixel resolution for Gemini coordinate accuracy; secondary screens are downscaled to keep latency reasonable.
- **Voice Input**: Gemini Live captures mic audio and streams it directly over the WebSocket. The hotkey is a listen-only CGEvent tap so modifier-only shortcuts (Ctrl+Option) work reliably in the background.
- **Text Command Input**: Ctrl+K opens a tiny cursor-following input bar (`TextCommandPanelManager` + `TextCommandPanelView`). It is intentionally an alternate non-voice input mode. Submitted text flows through `PointerPromptRouter`: obvious pointer commands stay local through `TipTourEngine`, one-step prompts ask Claude for one `WorkflowPlan` step, and longer prompts route to local Hermes Agent at `127.0.0.1:8642` only when Hermes Auto is ON. TipTour streams planner/tool progress into the command bubble as a neutral sliding ticker while keeping pointer animation and desktop action execution in the shared engine.
- **Radial Input Switcher**: Holding Ctrl+Option+Command opens a tiny overlay-rendered radial switcher around the cursor. It offers three input modes: Speak, Type, and Highlight. Moving the mouse toward an option highlights it, and releasing the shortcut selects it. This is only an input chooser: Speak enters the existing voice path, Type opens the existing Ctrl+K text command panel, and Highlight points the user at the existing Ctrl+Shift focus highlight gesture.
- **Markdown App Skills**: App-specific quirks belong in portable Claude/Codex-style markdown skills, not in `TipTourEngine` or `ActionExecutor`. `MarkdownAppSkillRegistry` loads skills in simple precedence order: user overrides from `~/.tiptour/skills`, then project skills from `.claude/skills`, `.agents/skills`, `.openhands/skills`, and `.openhands/microagents`, then bundled/source skills from `TipTour/Skills`. It reads the human instructions for planner prompts and parses only a small fenced `tiptour-runtime-hints` JSON block for deterministic behavior such as command aliases, modal input policy, and target disambiguation. The initial `blender` skill owns Blender-specific commands (`G`/`S`/axis/confirm), numeric modal typing policy, and menu-region target preference.
- **Focus Highlight Context**: Holding Ctrl+Shift activates a listen-only freeform highlight trail. `GlobalHighlightShortcutMonitor` records the mouse path, `OverlayWindow` renders the same blue cursor streak used by the Ctrl+Option voice trail, and the committed trail lingers briefly then fades out; no visual box is drawn. The committed context remains active until the next highlight begins. `CompanionManager` sends Gemini a `FocusHighlightContext` with the global rect, last painted hover point, topmost CUA window intersecting the painted region, AX element under the highlight, active selected text when it belongs to the highlighted element/window, and normalized screenshot `box_2d` when available. Ctrl+K Claude planning and Hermes prompts receive the same focus-highlight context block, with screenshot-relative `box_2d` when screenshots are enabled. If the highlight intersects a text element but the user did not make a native macOS selection, TipTour asks AX for `AXRangeForPosition` at sampled painted points and expands the result to the highlighted word/range. The preferred tool-call shape is now generic: Gemini/Claude mark edit steps with `targetContext: "currentHighlight"` or `targetContext: "currentSelection"`, and `CompanionManager` binds that context to the available resolver (AX text range today, other target resolvers later). The intersected app is also pinned as the target app for follow-up workflows so commands like "rewrite this" or "change this area" stay inside the app/window the user highlighted instead of typing into whatever is frontmost later.
- **Action Grounding**: Gemini calls `submit_workflow_plan`; click-like steps are grounded by `ElementResolver`, which resolves exact local `target_id`/`target_mark` first when present, then falls back to the step `label` via a local-first lookup. Gemini may provide `point_2d` (`[y, x]`, normalized to 0-1000) and/or `box_2d` (`[y1, x1, y2, x2]`). TipTour prefers deterministic local geometry when available and only falls back to Gemini coordinates after local resolvers miss.
    1. **macOS Accessibility tree** — pixel-perfect, ~30ms. Works on Apple-native Mac apps, most Cocoa third-party apps, and Electron apps that respect `AXManualAccessibility` (set on every app focus — see below). Uses batched `AXUIElementCopyMultipleAttributeValues` reads for ~3-10× speedup over per-attribute reads on large trees (Xcode, Electron).
    2. **Browser DOM/CDP coordinates** — Chromium page geometry through CUA Driver Core's CDP client when a remote-debugging page target is available. This gives browser-web controls a deterministic DOM-rect fallback before vision coordinates.
    3. **Local perception cache (experimental branch only)** — the native overlay publishes the latest CoreML UI detections plus Apple Vision OCR into `LocalPerceptionTargetCache`. This lets labels such as "Add" resolve without screenshot streaming or Gemini `box_2d`.
    4. **Native detector refinement (experimental branch only)** — local CoreML UI detections plus Apple Vision OCR refine Gemini's rough `box_2d` point for canvas/no-AX apps such as Blender. The detector uses the warm overlay cache when available and can run one fresh pass from the latest screenshot when the cache is cold.
    5. **Raw LLM coordinates from `box_2d`** — Gemini's own spatial grounding. Used only after AX, browser DOM, and native detector refinement miss.
    Blender is an exception on the experimental branch: it skips AX/CDP but still allows the native detector/OCR cache to refine a visible label before falling back to Gemini `box_2d`. WorkflowRunner also skips AX polling and AX-fingerprint post-click validation for Blender/no-AX apps because their AX tree does not reflect canvas UI changes.
- **Accurate Grounding + Native Detection Overlay**: The visible panel has an "Accurate Grounding" toggle that silently runs the restored native CoreML detector plus Apple Vision OCR and feeds `LocalPerceptionTargetCache`, so action grounding can resolve visible labels from local detections even when screenshot streaming to Gemini is off. The green/blue detection boxes are controlled separately by the Dev-only "Show Detection Overlay" toggle. Detection refreshes on enable, app activation, CUA action events, screen changes, voice-session start, and a second post-action settle pass instead of polling YOLO continuously.
- **Highlighted Source Resolution and Image Editing**: `TipTourHighlightSourceResolver` uses the latest focus highlight to resolve a local file, browser URL, selected text, or screenshot-only source, then returns suggested tool capabilities such as image edit, text edit, selected text edit, open source, or visual context. `TipTourImageEditService` builds on that resolver for image files, writing highlighted screenshot/crop artifacts under `~/Library/Application Support/TipTour/image-edits/<trace_id>/`. Optional execution uses the local Gemini key and saves a copy only; originals are never overwritten automatically. Voice can call this directly through `edit_highlighted_image` for demos without Hermes.
- **Accessibility Tree**: `AccessibilityTreeResolver.swift` walks the user's target app's AX tree via `ApplicationServices`, matches elements by title/description/value, returns exact pixel frames in global AppKit coordinates. Uses the app/window under the mouse at hotkey press time, with frontmost app as fallback, so the query targets the app the user was actually pointing at, not TipTour's own menu bar. Highlight hit-testing uses CUA Driver Core's `WindowEnumerator.visibleWindows()` and `AXInput.elementAt(...)` to identify the topmost intersected app/window and element. **Pre-warmed on hotkey press** via `CompanionManager.prefetchAccessibilityTreeForTargetApp` — the AX walk overlaps the user's first words and Gemini's session setup, so the first CUA click/action step resolves against warm data.
- **AX hardening for Electron**: On every app activation (`NSWorkspace.didActivateApplicationNotification`), `CompanionManager.enableManualAccessibilityIfNeeded` sets `AXManualAccessibility=true` on the activated app's AX element. Electron apps (Framer, VS Code, Slack, Discord, Cursor, Notion, Figma desktop) honor this attribute and populate their full webpage AX tree; non-Electron apps return `kAXErrorAttributeUnsupported` which we silently ignore. Without this, Electron apps return ~0 candidates from AX walks. A `0.4s` `AXUIElementSetMessagingTimeout` is also applied at app launch on the system-wide element + per-app on activation, capping any single AX query from hanging the resolver longer than 400ms.
- **Single-action workflows**: `WorkflowRunner` consumes one step at a time. In Autopilot mode it drives that one action through CUA, then stops; Gemini's tool calls are limited to one step per turn and harness requests are defensively clamped to one accepted step. Each action is stamped with a fresh `operationToken` (UUID) so callbacks from a stale run can't mutate the current one after a rapid restart. The runner pauses automatically when the user Cmd-Tabs to an unrelated app, when an `AXSheet`/`AXDialog` modal appears mid-workflow, or when the post-click AX-tree fingerprint stays unchanged through a 350ms settle window for steps that depend on visible UI state changing.
- **Two operating modes — Autopilot (default) vs Teaching**: A compact state button in `CompanionPanelView` flips TipTour between "do it for me" (autopilot, default — TipTour clicks/types/presses keys for the user) and "show me how" (teaching — TipTour points at one click target, the user clicks). When Autopilot is ON, `WorkflowRunner` schedules an `ActionExecutor` click ~650ms after each cursor flight, and non-click step types (`.keyboardShortcut`, `.type`) are actionable for the single accepted step. State persisted to `UserDefaults` under `isAutopilotEnabled`. The pause-on-app-switch + modal + post-click-validator safety net applies to autopilot the same way it does to user-driven flows — autopilot rides the rails, doesn't bypass them.
- **Connection Toggles**: The menu bar panel has a small "Connections" section for user-controlled plugin-like integrations. `CUA Driver` defaults ON and gates all desktop action execution through `ActionExecutor`; when OFF, TipTour can still observe/ground but action plans are rejected before execution. `Hermes Auto` defaults OFF; when ON, only long-running Ctrl+K prompts are delegated to the local Hermes API server while simple pointer actions and Claude one-step planning remain available.
- **Action execution** (Autopilot only): `ActionExecutor.swift` is the stable TipTour action facade; concrete delivery lives behind the `TipTourActionDriver` protocol. The default `CuaActionDriver` uses CUA Driver Core (`CuaDriverCore`) for low-level macOS input delivery. It supports app/URL launch, left/right/double clicks, keyboard shortcuts, single-key presses, typing, focused AX value setting, and keyboard-backed scrolling. Each successful CUA action posts a UI-action notification so accurate grounding can refresh YOLO/OCR after the target app changes. Typing first tries direct AX selected-text insertion, then uses a clipboard-staged Cmd+V fallback for rich web editors like Google Docs. For focus-highlight text edits, it first applies the armed `AXSelectedTextRange` and refuses blind key-event fallback if that range cannot be restored, preventing highlighted-word edits from pasting into the wrong insertion point. TipTour still owns target selection, cursor visuals, Gemini/Hermes harness handling, and workflow safety checks.
- **Walkthrough recording**: `ScreenRecorder.swift` saves the user's walkthrough as an `.mov` to `~/Library/Application Support/TipTour/recordings/`. ScreenCaptureKit + AVAssetWriter, H.264 primary with HEVC fallback, 16-aligned dimensions for codec compatibility, serial sample-buffer queue to preserve FIFO ordering through the writer.
- **Concurrency**: `@MainActor` isolation, async/await throughout.
- **Analytics**: PostHog via `TipTourAnalytics.swift`.

### API Proxy (Cloudflare Worker)

Source builds call Gemini directly with the user's Keychain-stored API key. A Cloudflare Worker (`worker/src/index.ts`) is optional for distribution builds that set `TipTourWorkerBaseURL` in the app bundle.

| Route | Upstream | Purpose |
|-------|----------|---------|
| `GET /gemini-live-key` | — (returns secret) | Optional distribution-build route that returns a Gemini API key so the app can open a direct WebSocket to Gemini Live. |
| `POST /match-label` | `gemini-2.5-flash-lite` | Multilingual label matcher used by `ElementResolver`'s fallback when the LLM passes a label in one language and the AX tree has it in another. |

Worker secret: `GEMINI_API_KEY`.

### Key Architecture Decisions

**Menu Bar Panel Pattern**: The companion panel uses `NSStatusItem` for the menu bar icon and `FloatingCompanionPanel`, a reusable custom borderless `NSPanel` host, for the floating control panel. This gives full control over appearance (dark, rounded corners, custom shadow) and avoids the standard macOS menu/popover chrome. The panel is non-activating so it doesn't steal focus. The reusable panel owns dynamic SwiftUI fitting-size resizing, status-item anchoring/highlighting, pin-aware outside-click dismissal, and the permission-dialog dismissal guard, while `MenuBarPanelManager` stays focused on status-item lifecycle, notifications, and opening the separate Settings window.

**Cursor Overlay**: A full-screen transparent `NSPanel` hosts the blue cursor companion. It's non-activating, joins all Spaces, and never steals focus. The cursor position, response text, waveform, and pointing animations all render in this overlay via SwiftUI through `NSHostingView`.

**Global Push-To-Talk Shortcut**: Background push-to-talk uses a listen-only `CGEvent` tap instead of an AppKit global monitor so modifier-based shortcuts like `Ctrl+Option` are detected more reliably while the app is running in the background.

**Push-to-talk semantics**: Gemini Live is toggle-based: press Ctrl+Option once to open the realtime session, press again to close it.

**Cursor Radial Switcher**: Ctrl+Option+Command is a hold-and-release input picker rendered inside `OverlayWindow`. `GlobalRadialInputShortcutMonitor` publishes begin/move/end transitions without stealing focus, `CompanionManager` maps cursor direction to the selected mode, and `RadialInputSwitcherView` keeps the visual surface compact and disposable.

## Key Files

| File | Lines | Purpose |
|------|-------|---------|
| `TipTour/App/TipTourApp.swift` | ~111 | Menu bar app entry point. Uses `@NSApplicationDelegateAdaptor` with `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager`. No main window — the app lives entirely in the status bar. |
| `TipTour/App/CompanionManager.swift` | ~2780 | Central state machine. Owns the global hotkeys, radial input switcher routing, hover/window targeting, CUA-backed focus highlight hit-testing, selected-text context/range inference, screen capture, Gemini Live session, shared pointer prompt path for Ctrl+K text, Hermes prompt delegation, screenshot streaming privacy setting, tool handlers, permissions, AX hardening, AX-tree prefetch, feature flags, grounding refresh, post-action perception refreshes, connection toggles, local perception cache publishing, harness server, engine facade, and overlay management. |
| `TipTour/Core/PointerActionRequest.swift` | ~20 | Shared one-action request shape used by voice/text/harness callers before entering `TipTourEngine` grounded action execution, including optional exact local target IDs/marks. |
| `TipTour/Core/PointerPromptRouter.swift` | ~164 | Small shared router for text/voice prompts. Keeps obvious direct pointer commands local, routes one-step prompts to Claude, and delegates long tasks to Hermes only when Hermes Auto is enabled. |
| `TipTour/Core/TipTourEngine.swift` | ~1008 | Thin engine facade for non-UI callers. Centralizes observe, skill listing, local target listing, exact target ID/mark selection, `PointerActionRequest` grounded one-step execution, action validation/history, harness payload repair/rejection, skill-backed menu-context target filtering, workflow settlement waiting, and single-action workflow submission so harnesses/plugins do not reach into `CompanionManager`; intended home for future `ground`, `act`, `record`, and `replay` API surfaces. |
| `TipTour/Core/TipTourHighlightSourceResolver.swift` | ~740 | Resolves the latest focus highlight into a local file, URL, text selection, or screenshot-only source and returns tool capability suggestions for the outer agent. |
| `TipTour/Harnesses/TipTourHarnessServer.swift` | ~364 | Localhost-only HTTP harness for Hermes and other external orchestrators. Exposes `/v1/health`, `/v1/capabilities`, `/v1/agent-contract`, `/v1/observe`, `/v1/visual-context`, `/v1/skills`, `/v1/skills/active`, `/v1/ground-target`, `/v1/targets`, `/v1/action-history`, `/v1/act`, `/v1/plan-next-action`, and `/v1/workflow-plan`, then hands accepted requests to `TipTourEngine` instead of embedding any external agent runtime in the app. |
| `TipTour/ImageEditing/TipTourImageEditService.swift` | ~780 | File-aware highlighted image edit service. Uses the shared highlight source resolver, writes highlighted screenshot/crop/request artifacts, and optionally calls Gemini/Nano Banana image editing with the local Gemini key while saving output as a copy. |
| `TipTour/Plugins/TipTourConnection.swift` | ~26 | Lightweight built-in connection model for plugin-like integrations such as CUA, Hermes, perception, and harnesses. |
| `TipTour/Skills/MarkdownAppSkill.swift` | ~350 | Portable markdown app-skill loader. Reads Claude/Codex/OpenHands-style markdown skills from user, project, and bundled/source folders, extracts frontmatter + planner instructions, deduplicates by skill name using source precedence, and parses the small `tiptour-runtime-hints` JSON block that TipTour uses for deterministic app-specific aliases and policies. |
| `TipTour/Skills/blender/SKILL.md` | ~96 | First portable app skill. Documents Blender one-action workflows and provides runtime hints for command aliases, physical-key numeric modal input, and open-menu target disambiguation. |
| `TipTour/UI/MenuBarPanelManager.swift` | ~190 | NSStatusItem lifecycle. Creates the menu bar icon, opens/hides the floating companion panel, opens Settings, and defines shared UI notifications while delegating NSPanel mechanics to `FloatingCompanionPanel`. |
| `TipTour/UI/FloatingCompanionPanel.swift` | ~172 | Reusable non-activating NSPanel host for compact SwiftUI companion surfaces. Handles status-item anchoring/highlighting, dynamic fitting-size resizing, pin-aware outside-click dismissal, and permission-dialog dismissal deferral. |
| `TipTour/UI/CompanionPanelView.swift` | ~900 | SwiftUI panel shell. Keeps the normal menu bar surface minimal and pointer-first: status header, short hotkey hint, compact state buttons, permission setup, activity, and footer actions; durable configuration opens in Settings. |
| `TipTour/UI/PointerAgentCardView.swift` | ~108 | Compact normal-state pointer-agent card with autopilot and local-grounding status plus the primary point-only/auto-click toggle. |
| `TipTour/UI/TipTourSettingsWindowManager.swift` | ~48 | Key-capable floating Settings window host for durable app configuration while keeping TipTour menu-bar only. |
| `TipTour/UI/TipTourSettingsView.swift` | ~440 | Dedicated Settings surface with Voice, Connections, Privacy, Permissions, and Advanced sections. |
| `TipTour/UI/ProviderSetupView.swift` | ~170 | Settings content for local BYOK provider key storage. |
| `TipTour/UI/TextCommandPanelManager.swift` | ~96 | Cursor-following Ctrl+K text command panel lifecycle. Positions the small input bar near the mouse while keeping it on-screen. |
| `TipTour/UI/TextCommandPanelView.swift` | ~100 | Minimal SwiftUI text command input bar. Submits typed prompts into the shared TipTour planner/action pipeline and displays subtle streamed planner/tool status as a sliding neutral ticker below the input. |
| `TipTour/UI/RadialInputSwitcherView.swift` | ~106 | Cursor-centered radial input switcher UI for Speak, Type, and Highlight modes. Highlights the hovered direction while the user holds Ctrl+Option+Command. |
| `TipTour/UI/OverlayWindow.swift` | ~1421 | Full-screen transparent overlay hosting the blue cursor, radial input switcher, focus highlight trail, optional Dev-only native detection boxes, response text, waveform, and spinner. Cursor animation, element pointing with bezier arcs, multi-monitor coordinate mapping. |
| `TipTour/UI/DetectionOverlayView.swift` | ~460 | SwiftUI Canvas overlay that renders local CoreML UI boxes, Apple Vision OCR text boxes, and a visual-only bubble cursor/flashlight lock-on for debugging target-aware cursor behavior. |
| `TipTour/UI/CompanionResponseOverlay.swift` | ~217 | SwiftUI view for the response text bubble and waveform displayed next to the cursor in the overlay. |
| `TipTour/UI/NekoCursorView.swift` | ~288 | Pixel-art cat cursor. Whimsical visual replacement for the blue triangle — toggleable, defaults off. |
| `TipTour/UI/DesignSystem.swift` | ~880 | Design system tokens — colors, corner radii, shared styles. All UI references `DS.Colors`, `DS.CornerRadius`, etc. |
| `TipTour/Workflow/WorkflowPlan.swift` | ~290 | Schema for Gemini/harness-emitted action plans, including generic `targetContext` grounding for visible elements, current highlight, current selection, and focused element. |
| `TipTour/Workflow/WorkflowRunner.swift` | ~1313 | Executes Gemini/harness-produced single-action plans. Resolves exact target IDs/marks before fuzzy lookup, arms the click detector in Teaching mode, or executes click/type/key/open/scroll actions through the action facade in Autopilot mode. |
| `TipTour/Workflow/ElementResolver.swift` | ~566 | Unified single-entry resolver. Given an exact local target or a label plus optional spatial hints, tries target mark/ID → AX tree → browser DOM/CDP coordinates → local perception cache → native detector refinement → Gemini's raw coordinates. |
| `TipTour/Actions/TipTourActionDriver.swift` | ~69 | Action-driver protocol boundary. TipTour core asks for semantic desktop actions through this shape so CUA, AX, browser DOM, AppleScript, and test/no-op drivers can be swapped without changing workflow logic. |
| `TipTour/Actions/ActionExecutor.swift` | ~941 | Autopilot action facade plus default `CuaActionDriver`. Converts TipTour's resolved screen points and workflow actions into pid-targeted CUA app launch, URL open, clicks, hotkeys, key presses, skill-directed physical modal typing, AX/clipboard typing, value setting, highlighted text replacement, and scrolling, then notifies the app that visible UI may need fresh perception. |
| `TipTour/Perception/AccessibilityTreeResolver.swift` | ~960 | Walks the frontmost app's macOS Accessibility tree, looks up elements by title/description/value, returns pixel-perfect frames. First-tier element-lookup path. |
| `TipTour/Perception/BrowserCoordinateResolver.swift` | ~215 | Chromium browser-page fallback. Uses CUA Driver Core's CDP client to match visible DOM elements by label and map viewport rects into global AppKit coordinates. |
| `TipTour/Perception/CompanionScreenCaptureUtility.swift` | ~201 | Multi-monitor screenshot capture using ScreenCaptureKit. Returns labeled image data for each connected display plus raw cursor-screen CGImage captures with the exact AppKit display frame used by local detection. |
| `TipTour/Perception/LocalPerceptionTargetCache.swift` | ~448 | Shared local target cache. Stores YOLO/OCR detections, enriches unlabeled UI boxes with OCR labels, exposes live grounding targets with stable marks/IDs to the harness, strictly matches spoken labels, and converts screenshot-pixel boxes into global AppKit coordinates. |
| `TipTour/Perception/NativeElementDetector.swift` | ~666 | Local CoreML YOLO + Apple Vision OCR detector. Used by the Dev overlay and optional resolver refinement before raw Gemini coordinates, with strict label confirmation for dense menu snaps. |
| `TipTour/Perception/ScreenshotPerceptualHash.swift` | ~96 | dHash implementation. Deduplicates similar screenshots before sending to Gemini. |
| `TipTour/Voice/GeminiLiveClient.swift` | ~643 | WebSocket client for Google's Gemini Live API. Sends PCM16 audio, JPEG screenshots, and text; receives PCM16 audio chunks, transcripts, and tool calls. |
| `TipTour/Voice/GeminiLiveAudioPlayer.swift` | ~227 | Streaming PCM16 24kHz audio playback via AVAudioEngine + AVAudioPlayerNode. |
| `TipTour/Voice/GeminiLiveSession.swift` | ~913 | Orchestrator tying the WebSocket client + audio player + mic capture together. Owns the Gemini Live conversation lifecycle, optional screenshot streaming, fresh state-sync screenshots at the start of user turns, and explicit fresh screenshot sends for committed highlight context when screenshot streaming is enabled. |
| `TipTour/Voice/ClaudeActionPlannerClient.swift` | ~256 | Anthropic Messages API client that converts Ctrl+K text prompts + screenshots + local targets + active app-skill/focus-highlight instructions into one TipTour `WorkflowPlan` step. Prompts Claude to include exact target IDs/marks when choosing from the local target list. |
| `TipTour/Voice/HermesAgentClient.swift` | ~196 | Local Hermes Agent API streaming client. Sends TipTour prompts to `127.0.0.1:8642/v1/chat/completions`, preserves Hermes session continuity, and forwards response/tool-progress chunks back to `CompanionManager`. |
| `TipTour/Voice/ProviderRequestDiagnostics.swift` | ~37 | Shared provider HTTP response validation and short response previews for planner clients. |
| `TipTour/Voice/PCM16AudioConverter.swift` | ~90 | PCM16 audio conversion helpers for Gemini Live input/output. |
| `TipTour/Recording/ScreenRecorder.swift` | ~476 | Records the main display to `.mov` via ScreenCaptureKit + AVAssetWriter. Output to `~/Library/Application Support/TipTour/recordings/`. Currently unwired — call sites can opt in. |
| `TipTour/Utilities/ClickDetector.swift` | ~217 | Global listen-only CGEventTap that fires a callback when a left-mouse-down lands within a tolerance radius of an armed target. |
| `TipTour/Utilities/FocusHighlightContext.swift` | ~77 | Spatial model for the user's freeform highlight, intersected app/window identity, intersected AX element, and selected text context. |
| `TipTour/Utilities/GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide push-to-talk monitor. Owns the listen-only `CGEvent` tap and publishes press/release transitions. |
| `TipTour/Utilities/GlobalTextCommandShortcutMonitor.swift` | ~116 | System-wide Ctrl+K monitor that opens the cursor-following text command input. |
| `TipTour/Utilities/GlobalHighlightShortcutMonitor.swift` | ~140 | System-wide Ctrl+Shift focus highlight monitor. Owns the listen-only `CGEvent` tap and publishes begin/move/end transitions. |
| `TipTour/Utilities/GlobalRadialInputShortcutMonitor.swift` | ~149 | System-wide Ctrl+Option+Command radial input monitor. Owns the listen-only `CGEvent` tap and publishes begin/move/end cursor transitions for the radial switcher. |
| `TipTour/Utilities/PushToTalkShortcut.swift` | ~40 | Encodes the single shortcut TipTour listens for (Ctrl+Option) and translates raw CGEvents into press/release transitions. |
| `TipTour/Utilities/WindowPositionManager.swift` | ~262 | Window placement logic, Screen Recording permission flow, and accessibility permission helpers. |
| `TipTour/Utilities/KeychainStore.swift` | ~113 | macOS Keychain wrapper for storing user-pasted Gemini and Claude keys. |
| `TipTour/Utilities/RetryWithExponentialBackoff.swift` | ~67 | Utility helper for retry logic. |
| `TipTour/Utilities/TipTourAnalytics.swift` | ~106 | PostHog analytics integration for usage tracking. |
| `TipTour/Utilities/AppBundleConfiguration.swift` | ~28 | Runtime configuration reader for keys stored in the app bundle Info.plist. |
| `TipTour/Utilities/TipTourDefaults.swift` | ~136 | Centralized UserDefaults facade for persisted app preferences and first-run defaults such as Autopilot, CUA, Hermes, screenshots, panel pinning, and permission memory. |
| `worker/src/index.ts` | ~140 | Cloudflare Worker proxy. Two routes: `/gemini-live-key` (Gemini Live API key) and `/match-label` (multilingual label matcher). |

## Build & Run

```bash
# Open in Xcode
open tiptour-macos.xcodeproj

# Select the TipTour scheme, set signing team, Cmd+R to build and run

# Known non-blocking warnings: Swift 6 concurrency warnings,
# deprecated onChange warning in OverlayWindow.swift. Do NOT attempt to fix these.
```

**Do NOT run `xcodebuild` from the terminal** — it invalidates TCC (Transparency, Consent, and Control) permissions and the app will need to re-request screen recording, accessibility, etc.

## Cloudflare Worker

```bash
cd worker
npm install

# Add secret
npx wrangler secret put GEMINI_API_KEY

# Deploy
npx wrangler deploy

# Local dev (create worker/.dev.vars with GEMINI_API_KEY=...)
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
