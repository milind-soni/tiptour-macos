//
//  CompanionManager.swift
//  TipTour
//
//  Central state manager for the companion voice mode. Owns the push-to-talk
//  pipeline (dictation manager + global shortcut monitor + overlay) and
//  exposes observable voice state for the panel UI.
//

import AVFoundation
import Combine
import Foundation
import PostHog
import ScreenCaptureKit
import SwiftUI

enum CompanionVoiceState {
    case idle
    case listening
    case processing
    case responding
}

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var hasScreenRecordingPermission = false
    @Published private(set) var hasMicrophonePermission = false
    @Published private(set) var hasScreenContentPermission = false

    /// Screen location (global AppKit coords) of a detected UI element the
    /// buddy should fly to and point at. Parsed from Claude's response;
    /// observed by BlueCursorView to trigger the flight animation.
    @Published var detectedElementScreenLocation: CGPoint?
    /// The display frame (global AppKit coords) of the screen the detected
    /// element is on, so BlueCursorView knows which screen overlay should animate.
    @Published var detectedElementDisplayFrame: CGRect?
    /// Custom speech bubble text for the pointing animation. When set,
    /// BlueCursorView uses this instead of a random pointer phrase.
    @Published var detectedElementBubbleText: String?

    // MARK: - Tutorial State

    @Published var activeTutorial: TutorialGuide?
    @Published var tutorialStepIndex: Int = 0
    @Published var isTutorialActive: Bool = false
    @Published var tutorialVideoPlayer: AVPlayer?
    @Published var showTutorialVideo: Bool = false
    @Published var tutorialVideoOpacity: Double = 0.0
    /// Current tutorial action type for animation rendering (keyboard, scroll, click, etc.)
    @Published var tutorialActionType: String = ""
    /// Show YOLO detection boxes overlay — toggle from dev tools
    @Published var showDetectionOverlay: Bool = false
    /// Latest detected elements from native detector for overlay rendering
    @Published var detectedElements: [[String: Any]] = []
    /// Image size of the screenshot used for detection (for coordinate scaling)
    @Published var detectedImageSize: [Int] = [1512, 982]
    /// The element currently being highlighted (matched by voice query)
    @Published var highlightedElementLabel: String? = nil
    /// Key label to display for keyboard actions (e.g. "G", "Ctrl+Z")
    @Published var tutorialKeyLabel: String = ""
    private var tutorialTimeObserver: Any?
    private var tutorialSkipObserverUntil: Date = .distantPast

    /// Start an interactive tutorial from a generated guide
    func startTutorial(guide: TutorialGuide, videoPath: String? = nil) {
        activeTutorial = guide
        tutorialStepIndex = 0
        isTutorialActive = true

        print("[Tutorial] Starting: \(guide.title) (\(guide.steps.count) steps)")

        // Play the local video file if available
        let videoURL: URL?
        if let path = videoPath {
            videoURL = URL(fileURLWithPath: path)
            print("[Tutorial] Playing local video: \(path)")
        } else {
            videoURL = nil
            print("[Tutorial] No video file — steps only")
        }

        if let videoURL = videoURL {
            let player = AVPlayer(url: videoURL)
            player.isMuted = false
            player.volume = 1.0
            self.onboardingVideoPlayer = player
            self.showOnboardingVideo = true

            withAnimation(.easeIn(duration: 0.5)) {
                self.onboardingVideoOpacity = 1.0
            }

            player.play()
            print("[Tutorial] Video playing")

            setupTutorialTimeObserver(player: player)
        }

        // Show first step hint on the cursor
        if let firstStep = guide.steps.first {
            showTutorialStep(firstStep)
        }
    }

    /// Advance to next tutorial step — called by hotkey or auto-detection
    func advanceTutorial() {
        guard isTutorialActive, let guide = activeTutorial else { return }
        tutorialStepIndex += 1

        if tutorialStepIndex >= guide.steps.count {
            print("[Tutorial] Complete!")
            stopTutorial()
            detectedElementBubbleText = "Tutorial complete! 🎉"
            return
        }

        let step = guide.steps[tutorialStepIndex]
        print("[Tutorial] Step \(tutorialStepIndex + 1)/\(guide.steps.count): \(step.hint)")

        // Seek video to this step's timestamp — video keeps playing
        let seekTime = CMTime(seconds: step.timestamp, preferredTimescale: 600)
        onboardingVideoPlayer?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        onboardingVideoPlayer?.play()

        showTutorialStep(step)
    }

    /// Load and start the pre-built demo tutorial
    func startDemoTutorial() {
        // Load demo guide from app bundle
        guard let bundlePath = Bundle.main.path(forResource: "demo-guide", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[Tutorial] demo-guide.json not found in bundle")
            return
        }

        let title = raw["title"] as? String ?? "Demo"
        let app = raw["app"] as? String ?? "Blender"
        let rawSteps = raw["steps"] as? [[String: Any]] ?? []

        let steps: [TutorialStep] = rawSteps.enumerated().map { i, dict in
            TutorialStep(
                id: "step-\(i+1)",
                timestamp: dict["timestamp"] as? Double ?? 0,
                action: dict["action"] as? String ?? "click",
                element: dict["element"] as? String ?? "",
                elementRole: dict["element_role"] as? String,
                hint: dict["hint"] as? String ?? "",
                narration: dict["narration"] as? String
            )
        }

        let guide = TutorialGuide(title: title, app: app, steps: steps, videoURL: "https://www.youtube.com/watch?v=peSv5IT5Ve4")

        // Download video if not cached
        let videoID = "peSv5IT5Ve4"
        let videoPath = NSTemporaryDirectory() + "tiptour-\(videoID).mp4"

        if FileManager.default.fileExists(atPath: videoPath) {
            startTutorial(guide: guide, videoPath: videoPath)
        } else {
            // Download in background, start without video for now
            startTutorial(guide: guide, videoPath: nil)
            Task {
                if let downloadedPath = try? await TutorialGuideGenerator.downloadVideoPublic(videoID: videoID) {
                    print("[Demo] Video downloaded: \(downloadedPath)")
                }
            }
        }

        print("[Demo] Loaded \(steps.count) steps")
    }

    func stopTutorial() {
        isTutorialActive = false
        activeTutorial = nil
        tutorialStepIndex = 0

        if let observer = tutorialTimeObserver {
            onboardingVideoPlayer?.removeTimeObserver(observer)
            tutorialTimeObserver = nil
        }
        onboardingVideoPlayer?.pause()

        withAnimation(.easeOut(duration: 0.3)) {
            onboardingVideoOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.onboardingVideoPlayer = nil
            self.showOnboardingVideo = false
        }

        detectedElementBubbleText = nil
        onboardingPromptText = ""
        onboardingPromptOpacity = 0.0
        showOnboardingPrompt = false
        tutorialActionType = ""
        tutorialKeyLabel = ""
        clearDetectedElementLocation()
    }

    private func showTutorialStep(_ step: TutorialStep) {
        let total = activeTutorial?.steps.count ?? 0
        let stepLabel = "Step \(tutorialStepIndex + 1)/\(total): \(step.hint)"

        // Make sure overlay is visible
        if !isOverlayVisible {
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }

        print("[Tutorial] → \(step.action) \"\(step.element)\" — \(step.hint)")

        // Set action type for animation rendering
        tutorialActionType = step.action

        // Detect keyboard actions
        let isKeyboardAction = step.action == "type" || step.action == "hold"
            || step.element.lowercased().contains("key")
            || step.element.lowercased().contains("shortcut")
            || step.element.lowercased().contains("ctrl")
            || step.element.lowercased().contains("shift")
            || step.element.lowercased().contains("cmd")

        let isScrollAction = step.action == "scroll"
            || step.element.lowercased().contains("scroll")

        // Show unified step text — no separate bubble to avoid overlap
        onboardingPromptText = stepLabel
        onboardingPromptOpacity = 1.0
        showOnboardingPrompt = true
        detectedElementBubbleText = nil  // prevent overlap

        if isKeyboardAction {
            tutorialActionType = "keyboard"
            // Extract key label from element name (e.g. "G key" → "G", "Ctrl+Z" → "Ctrl+Z")
            tutorialKeyLabel = extractKeyLabel(from: step.element)
            clearDetectedElementLocation()
            print("[Tutorial] Keyboard: \(tutorialKeyLabel)")
            return
        }

        if isScrollAction {
            tutorialActionType = "scroll"
            tutorialKeyLabel = ""
            clearDetectedElementLocation()
            print("[Tutorial] Scroll action")
            return
        }

        // Click/drag actions — screenshot + point
        tutorialKeyLabel = ""
        Task {
            await pointCursorForStep(step)
        }
    }

    /// Extract the key label from an element name like "G key", "Number pad '3'", "Ctrl+Z"
    private func extractKeyLabel(from element: String) -> String {
        let el = element.trimmingCharacters(in: .whitespaces)

        // "G key" → "G"
        if el.lowercased().hasSuffix(" key") {
            return String(el.dropLast(4)).trimmingCharacters(in: .whitespaces)
        }

        // "Number pad '3'" → "3"
        if let match = el.range(of: #"'([^']+)'"#, options: .regularExpression) {
            return String(el[match]).replacingOccurrences(of: "'", with: "")
        }

        // "Ctrl+Z", "Shift+A" → as-is
        if el.contains("+") { return el }

        // "Tab key" already handled, "Delete key" etc.
        return el.replacingOccurrences(of: " key", with: "")
    }

    /// Takes a screenshot, finds the element via native detector (local) or Claude (fallback).
    private func pointCursorForStep(_ step: TutorialStep) async {
        guard let screenshots = try? await CompanionScreenCaptureUtility.captureAllScreensAsJPEG() else {
            print("[Tutorial] Screenshot failed")
            return
        }

        guard let primary = screenshots.first else { return }

        // Try native detector first (on-device, fast, no API cost)
        if let cgImage = Self.cgImage(from: primary.imageData),
           let found = await NativeElementDetector.shared.findElement(query: step.element, in: cgImage) {
            print("[Tutorial] NativeDetector found \"\(found.label)\" at (\(Int(found.center.x)),\(Int(found.center.y)))")
            await MainActor.run {
                self.pointAtScreenPixel(found.center, capture: primary, label: step.element)
            }
            return
        }

        print("[Tutorial] NativeDetector miss — falling back to Gemma")

        // Gemma needs base64 for its vision API
        let base64Image = primary.imageData.base64EncodedString()

        // Fallback: Gemma 4 via OpenRouter (fast, vision-capable)
        let tutorialContext = activeTutorial.map { "Tutorial: \($0.title) in \($0.app)" } ?? ""
        let requestBody: [String: Any] = [
            "model": "google/gemma-4-31b-it",
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": "You see a screenshot of a macOS app (\(primary.label)). \(tutorialContext). Reply with ONLY [POINT:\(step.element)] — the app has on-device element detection that will locate the element by name. Do NOT guess coordinates. If the element isn't visible, reply [POINT:none]."],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]],
                    ["type": "text", "text": "\(step.action) \"\(step.element)\". Point at it."]
                ]]
            ]
        ]

        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody)
            var request = URLRequest(url: URL(string: "\(CompanionManager.workerBaseURL)/chat-fast")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = requestData
            request.timeoutInterval = 15

            let (data, _) = try await URLSession.shared.data(for: request)

            // OpenRouter returns OpenAI format
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let fullText = message["content"] as? String else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("[Tutorial] OpenRouter parse fail: \(raw.prefix(200))")
                return
            }

            print("[Tutorial] Gemma: \(fullText)")

            let parseResult = CompanionManager.parsePointingCoordinates(from: fullText)
            if let coord = parseResult.coordinate {
                await MainActor.run {
                    self.pointAtScreenPixel(coord, capture: primary, label: parseResult.elementLabel ?? step.element)
                }
            }
        } catch {
            print("[Tutorial] Gemma error: \(error.localizedDescription)")
        }
    }

    /// Queue labels to point at sequentially — for multi-step navigation.
    /// After the current pointing animation finishes, waits 2s for the user
    /// to click, re-scans the screen, and finds the next element by label.
    private var pendingLiveSteps: [String] = []

    private func queuePendingSteps(_ labels: [String]) {
        pendingLiveSteps = labels
        print("🎯 Queued \(labels.count) live steps: \(labels)")

        // Watch for when the current pointing finishes (element location clears)
        // then trigger the next step
        Task {
            // Wait for current pointing to finish (arrow flies back)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            // Wait a moment for user to perform the click
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // Process next step
            await processNextLiveStep()
        }
    }

    private func processNextLiveStep() async {
        guard !pendingLiveSteps.isEmpty else { return }
        let nextLabel = pendingLiveSteps.removeFirst()
        print("🎯 Live step: finding \"\(nextLabel)\"...")

        // Take a fresh screenshot and try native detector
        guard let screenshots = try? await CompanionScreenCaptureUtility.captureAllScreensAsJPEG(),
              let primary = screenshots.first else { return }

        // Try native detector cache first, then full scan
        if let found = NativeElementDetector.shared.findFromCache(query: nextLabel) {
            print("🎯 Live step: cache hit \"\(nextLabel)\" at (\(Int(found.center.x)),\(Int(found.center.y)))")
            await MainActor.run {
                self.pointAtScreenPixel(found.center, capture: primary, label: nextLabel)
            }
        } else if let cgImage = Self.cgImage(from: primary.imageData),
                  let found = await NativeElementDetector.shared.findElement(query: nextLabel, in: cgImage) {
            print("🎯 Live step: found \"\(nextLabel)\" at (\(Int(found.center.x)),\(Int(found.center.y)))")
            await MainActor.run {
                self.pointAtScreenPixel(found.center, capture: primary, label: nextLabel)
            }
        } else {
            print("🎯 Live step: \"\(nextLabel)\" not found — showing text")
            await MainActor.run {
                self.detectedElementBubbleText = nextLabel
            }
        }

        // If more steps remain, queue them
        if !pendingLiveSteps.isEmpty {
            queuePendingSteps(pendingLiveSteps)
        }
    }

    /// Convert screenshot pixel coordinates to AppKit screen coords and point the cursor there.
    private func pointAtScreenPixel(_ pixel: CGPoint, capture: CompanionScreenCapture, label: String) {
        let screenshotWidth = CGFloat(capture.screenshotWidthInPixels)
        let screenshotHeight = CGFloat(capture.screenshotHeightInPixels)
        let displayWidth = CGFloat(capture.displayWidthInPoints)
        let displayHeight = CGFloat(capture.displayHeightInPoints)
        let displayFrame = capture.displayFrame

        let clampedX = max(0, min(pixel.x, screenshotWidth))
        let clampedY = max(0, min(pixel.y, screenshotHeight))

        let displayLocalX = clampedX * (displayWidth / screenshotWidth)
        let displayLocalY = clampedY * (displayHeight / screenshotHeight)
        let appKitY = displayHeight - displayLocalY

        let globalLocation = CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitY + displayFrame.origin.y
        )

        detectedElementScreenLocation = globalLocation
        detectedElementDisplayFrame = displayFrame
        detectedElementBubbleText = label
        print("[Tutorial] → screen(\(Int(globalLocation.x)),\(Int(globalLocation.y)))")
    }

    /// Fly the cursor to a resolved element. The Resolution already contains
    /// global AppKit coordinates — no further conversion needed.
    private func pointAtResolution(_ resolution: ElementResolver.Resolution) {
        detectedElementScreenLocation = resolution.globalScreenPoint
        detectedElementDisplayFrame = resolution.displayFrame
        detectedElementBubbleText = resolution.label
    }

    private func setupTutorialTimeObserver(player: AVPlayer) {
        // Check time every 0.5s to pause at step timestamps
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        tutorialTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, self.isTutorialActive, let guide = self.activeTutorial else { return }

            let currentSeconds = CMTimeGetSeconds(time)
            let currentStep = self.tutorialStepIndex

            // Look ahead: if the NEXT step's timestamp has been reached, pause
            // and show the CURRENT step (what user needs to do now)
            let nextStepIndex = currentStep + 1
            if nextStepIndex < guide.steps.count {
                let nextTimestamp = guide.steps[nextStepIndex].timestamp
                if currentSeconds >= nextTimestamp - 0.5 {
                    // Pause slightly before the next step starts
                    player.pause()
                    // Show the NEXT step — this is what the user needs to do
                    self.tutorialStepIndex = nextStepIndex
                    let step = guide.steps[nextStepIndex]
                    self.showTutorialStep(step)
                    print("[Tutorial] Paused at \(String(format: "%.1f", currentSeconds))s → Step \(nextStepIndex + 1): \(step.hint)")
                }
            }
        }
    }


    // MARK: - Onboarding Video State (shared across all screen overlays)

    // Kept under "onboardingVideoPlayer" name for now because the tutorial
    // flow reuses this property to render tutorial videos through the
    // same SwiftUI view. TODO: rename to `tutorialVideoPlayer` in a
    // dedicated cleanup pass.
    @Published var onboardingVideoPlayer: AVPlayer?
    @Published var showOnboardingVideo: Bool = false
    @Published var onboardingVideoOpacity: Double = 0.0

    // MARK: - Onboarding Hotkey-Prompt Bubble

    /// Text streamed character-by-character on the cursor when the
    /// user first completes onboarding — "press ctrl+option to talk".
    @Published var onboardingPromptText: String = ""
    @Published var onboardingPromptOpacity: Double = 0.0
    @Published var showOnboardingPrompt: Bool = false

    let buddyDictationManager = BuddyDictationManager()
    let globalPushToTalkShortcutMonitor = GlobalPushToTalkShortcutMonitor()
    let overlayWindowManager = OverlayWindowManager()
    // Response text is now displayed inline on the cursor overlay via
    // streamingResponseText, so no separate response overlay manager is needed.

    /// Base URL for the Cloudflare Worker proxy. All API requests route
    /// through this so keys never ship in the app binary.
    private static let workerBaseURL = "http://localhost:8787"

    private lazy var claudeAPI: ClaudeAPI = {
        return ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: selectedModel)
    }()

    private lazy var elevenLabsTTSClient: ElevenLabsTTSClient = {
        return ElevenLabsTTSClient(proxyURL: "\(Self.workerBaseURL)/tts")
    }()

    /// Conversation history so Claude remembers prior exchanges within a session.
    /// Each entry is the user's transcript and Claude's response.
    private var conversationHistory: [(userTranscript: String, assistantResponse: String)] = []

    /// The currently running AI response task, if any. Cancelled when the user
    /// speaks again so a new response can begin immediately.
    private var currentResponseTask: Task<Void, Never>?

    private var shortcutTransitionCancellable: AnyCancellable?
    private var voiceStateCancellable: AnyCancellable?
    private var audioPowerCancellable: AnyCancellable?
    private var accessibilityCheckTimer: Timer?
    private var pendingKeyboardShortcutStartTask: Task<Void, Never>?
    /// Scheduled hide for transient cursor mode — cancelled if the user
    /// speaks again before the delay elapses.
    private var transientHideTask: Task<Void, Never>?

    /// True when all three required permissions (accessibility, screen recording,
    /// microphone) are granted. Used by the panel to show a single "all good" state.
    var allPermissionsGranted: Bool {
        hasAccessibilityPermission && hasScreenRecordingPermission && hasMicrophonePermission && hasScreenContentPermission
    }

    /// Whether the blue cursor overlay is currently visible on screen.
    /// Used by the panel to show accurate status text ("Active" vs "Ready").
    @Published private(set) var isOverlayVisible: Bool = false

    /// The Claude model used for voice responses. Persisted to UserDefaults.
    @Published var selectedModel: String = UserDefaults.standard.string(forKey: "selectedClaudeModel") ?? "claude-haiku-4-5-20251001"

    /// Which voice pipeline to use — the legacy STT→Claude→TTS chain or the
    /// new single-model Gemini Live realtime WebSocket.
    enum VoiceMode: String {
        case claudeAndElevenLabs   // Apple Speech STT → Claude → ElevenLabs TTS (legacy)
        case geminiLive            // Single Gemini Live WebSocket (voice + vision + voice)
    }

    @Published var voiceMode: VoiceMode = VoiceMode(rawValue: UserDefaults.standard.string(forKey: "voiceMode") ?? "") ?? .geminiLive

    func setVoiceMode(_ mode: VoiceMode) {
        voiceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "voiceMode")
        // Tear down any active Gemini session when switching away from it
        if mode != .geminiLive {
            geminiLiveSession.stop()
        }
    }

    /// Lazily-built Gemini Live session. Active only when voiceMode is .geminiLive.
    lazy var geminiLiveSession: GeminiLiveSession = {
        let session = GeminiLiveSession(
            apiKeyURL: "\(Self.workerBaseURL)/gemini-live-key",
            systemPrompt: Self.companionVoiceResponseSystemPrompt
        )
        // Tool-call handlers. Gemini Live decides per-utterance whether
        // the request is a single-element point or a multi-step workflow.
        // Fast path (simple): point_at_element → local AX + YOLO resolve.
        // Smart path (complex): create_workflow → Gemini Flash planner.
        session.onPointAtElement = { [weak self] id, label, screenshotJPEG in
            await self?.handleToolPointAtElement(id: id, label: label, screenshotJPEG: screenshotJPEG) ?? ["ok": false]
        }
        session.onSubmitWorkflowPlan = { [weak self] id, goal, app, steps in
            await self?.handleToolSubmitWorkflowPlan(id: id, goal: goal, app: app, steps: steps) ?? ["ok": false]
        }

        // Legacy transcript-tag parsing stays in place as a fallback if a
        // build of Gemini skips tools and falls back to [POINT:] markup.
        session.onOutputTranscript = { [weak self] fullTranscript in
            self?.handleGeminiTranscriptUpdate(fullTranscript)
        }

        // Reset the per-turn dedup flag when a NEW user utterance starts
        // (transcript was empty, now has chars). This is the right signal
        // for "user has something new to ask" — onTurnComplete is the
        // wrong signal because ambient noise / background speech / the
        // cat's audio spillover can re-trigger Gemini as a fake new turn
        // and double-fire tool calls without an actual new utterance.
        session.onInputTranscriptUpdate = { [weak self] fullInputTranscript in
            guard let self else { return }
            let isNewUtterance = fullInputTranscript.trimmingCharacters(in: .whitespacesAndNewlines).count > 0
                && self.previousInputTranscriptLength == 0
            if isNewUtterance {
                self.handledToolCallIDsThisUtterance.removeAll()
                self.planAppliedThisTurn = false
                self.lastGeminiTranscriptLength = 0
            }
            self.previousInputTranscriptLength = fullInputTranscript.count
        }

        session.onTurnComplete = { [weak self] in
            // Input transcript will reset to "" in GeminiLiveSession on
            // turnComplete; mirror that here so the next utterance looks
            // like a fresh start to our length counter.
            self?.previousInputTranscriptLength = 0
            // Intentionally NO reset of planAppliedThisTurn here — see
            // the onInputTranscriptUpdate block above.
        }
        session.onError = { error in
            print("[GeminiLive] Error: \(error.localizedDescription)")
        }
        return session
    }()

    // MARK: - Tool Handlers

    /// Handle the `point_at_element` tool call. Resolves the label via the
    /// AX tree → YOLO + OCR cascade, flies the cursor there, and returns a
    /// short dictionary describing the outcome so Gemini can narrate with
    /// confidence (e.g. "there it is on the top-right").
    @MainActor
    private func handleToolPointAtElement(id: String, label: String, screenshotJPEG: Data?) async -> [String: Any] {
        // Dedup by tool-call ID. Gemini Live occasionally emits the
        // SAME function call twice in one turn (once inline in
        // modelTurn.parts, once as a top-level toolCall envelope) —
        // both copies share the same id. Different legitimate tool
        // calls within the same utterance get different IDs and both
        // execute normally.
        if handledToolCallIDsThisUtterance.contains(id) {
            print("[Tool] ⏭️  ignoring duplicate point_at_element id=\(id)")
            return ["ok": true, "duplicate": true]
        }
        handledToolCallIDsThisUtterance.insert(id)
        print("[Tool] 🔧 point_at_element(label=\"\(label)\")")
        let startedAt = Date()
        planAppliedThisTurn = true
        let capture = geminiLiveSession.latestCapture
        let resolution = await ElementResolver.shared.resolve(
            label: label,
            llmHintInScreenshotPixels: nil,
            latestCapture: capture
        )
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard let resolution else {
            print("[Tool] ✗ point_at_element(\"\(label)\") → no match after \(elapsed)ms")
            // Force a fresh screenshot on the next periodic tick. If Gemini
            // was working from a stale frame (e.g. menu just opened, dialog
            // just appeared), the perceptual-hash dedup might otherwise
            // suppress the very frame Gemini needs to re-look at.
            geminiLiveSession.invalidateScreenshotHashCache()
            return ["ok": false, "reason": "element_not_found", "label": label]
        }
        print("[Tool] ✓ point_at_element(\"\(label)\") → \(resolution.label) via \(resolution.source) in \(elapsed)ms")
        pointAtResolution(resolution)

        // point_at_element is a single-click ask — there's no multi-step
        // flow expecting a click. Disarm any leftover ClickDetector state
        // from a previous workflow so stale armed rects don't misreport
        // later clicks as missed hits on the wrong target.
        ClickDetector.shared.disarm()

        return [
            "ok": true,
            "label": resolution.label,
            "source": String(describing: resolution.source)
        ]
    }

    /// Handle the `submit_workflow_plan` tool call. Gemini produces the
    /// plan itself via its own vision + reasoning, so this is just a
    /// conversion from the raw tool args into a WorkflowPlan + kickoff
    /// of the runner. No separate planner round-trip, no OpenRouter,
    /// no /plan endpoint, no 3-6s wait.
    @MainActor
    private func handleToolSubmitWorkflowPlan(id: String, goal: String, app: String, steps: [[String: Any]]) async -> [String: Any] {
        // Dedup by tool-call ID. Same reasoning as handleToolPointAtElement:
        // Gemini occasionally emits the SAME function call twice (inline
        // + envelope) with the same id. Different legitimate calls
        // (e.g. an earlier point_at_element that Gemini later supersedes
        // with this full workflow plan) get different IDs and both
        // execute. This handler supersedes any prior point_at_element
        // state — the workflow runner will drive the cursor from step 1.
        if handledToolCallIDsThisUtterance.contains(id) {
            print("[Tool] ⏭️  ignoring duplicate submit_workflow_plan id=\(id)")
            return ["ok": true, "duplicate": true]
        }
        handledToolCallIDsThisUtterance.insert(id)
        print("[Tool] 🔧 submit_workflow_plan(goal=\"\(goal)\", app=\"\(app)\", \(steps.count) steps)")
        planAppliedThisTurn = true

        let parsedSteps: [WorkflowStep] = steps.enumerated().map { index, raw in
            let label = raw["label"] as? String
            let hint = raw["hint"] as? String ?? ""
            let x = raw["x"] as? Int
            let y = raw["y"] as? Int
            return WorkflowStep(
                id: "step_\(index + 1)",
                type: .click,
                label: label,
                hint: hint,
                hintX: x,
                hintY: y,
                screenNumber: nil
            )
        }

        guard !parsedSteps.isEmpty else {
            print("[Tool] ✗ submit_workflow_plan — zero steps")
            return ["ok": false, "reason": "empty_steps"]
        }

        let plan = WorkflowPlan(
            goal: goal,
            app: app.isEmpty ? nil : app,
            steps: parsedSteps
        )
        let stepLabels = parsedSteps.map { $0.label ?? "<unlabeled>" }
        print("[Tool] ✓ submit_workflow_plan → \(plan.app ?? "?"): \(stepLabels)")
        startWorkflowPlan(plan)

        // Pause mic + screenshots so Gemini can narrate the plan in one
        // uninterrupted turn. Once the narration finishes we EXIT
        // narration mode — resuming mic + screenshots — but the
        // WebSocket stays open. That way the user can ask a follow-up
        // ("and how do I save it as Swift?") and Gemini still has the
        // conversational memory of the plan it just described. Session
        // only really closes when the user hotkey-toggles it off.
        print("[Workflow] entering Gemini narration mode — mic/screenshots paused, socket kept alive for narration")
        geminiLiveSession.enterNarrationMode()
        scheduleExitNarrationModeAfterSpeechEnds()
        

        return [
            "ok": true,
            "accepted_steps": stepLabels.count
        ]
    }

    /// Wait for Gemini's post-tool narration turn to finish, then exit
    /// narration mode so the mic + periodic screenshots resume. Session
    /// stays open for conversational follow-ups.
    ///
    /// Three ways this can complete:
    ///   - Speech observed and then quiet for 800ms continuously → exit.
    ///   - Gemini never spoke at all within the `silentNarrationGraceSeconds`
    ///     window → exit immediately (don't strand the user muted while
    ///     we wait forever for speech that isn't coming).
    ///   - Hard ceiling of `maxTotalWaitSeconds` regardless → exit.
    private func scheduleExitNarrationModeAfterSpeechEnds() {
        // If Gemini hasn't started speaking by this point, assume it
        // doesn't intend to narrate this turn and resume mic right away.
        // Keeps the "stops listening" feeling from happening.
        let silentNarrationGraceSeconds: TimeInterval = 3.0
        // After speech has finished, this much continuous quiet means
        // the turn is really over (not mid-sentence pause).
        let quietConfirmationSeconds: TimeInterval = 0.8
        // Absolute maximum we'll keep mic paused, even for a wordy turn.
        let maxTotalWaitSeconds: TimeInterval = 15.0

        Task { [weak self] in
            guard let self = self else { return }

            let startedAt = Date()
            let maxDeadline = startedAt.addingTimeInterval(maxTotalWaitSeconds)
            var hasObservedSpeechStart = false
            var quietSinceTimestamp: Date?

            while Date() < maxDeadline {
                try? await Task.sleep(nanoseconds: 200_000_000)

                let (isActive, speaking, playing) = await MainActor.run { () -> (Bool, Bool, Bool) in
                    (
                        self.geminiLiveSession.isActive,
                        self.geminiLiveSession.isModelSpeaking,
                        self.geminiLiveSession.isAudioPlaying
                    )
                }
                if !isActive { return }

                let currentlySpeaking = speaking || playing
                if currentlySpeaking {
                    hasObservedSpeechStart = true
                    quietSinceTimestamp = nil
                    continue
                }

                // Gemini hasn't said anything yet and the grace window
                // is up — exit narration mode so the user isn't stuck
                // with the mic paused.
                if !hasObservedSpeechStart,
                   Date().timeIntervalSince(startedAt) >= silentNarrationGraceSeconds {
                    break
                }

                // Speech happened and is now over — confirm it stays
                // quiet for a beat so we don't cut off a mid-sentence pause.
                if hasObservedSpeechStart {
                    if quietSinceTimestamp == nil {
                        quietSinceTimestamp = Date()
                    } else if let quietStart = quietSinceTimestamp,
                              Date().timeIntervalSince(quietStart) >= quietConfirmationSeconds {
                        break
                    }
                }
            }

            await MainActor.run {
                guard self.geminiLiveSession.isActive else { return }
                print("[Workflow] narration window closed — exiting narration mode, session stays alive for follow-ups")
                self.geminiLiveSession.exitNarrationMode()
                self.planAppliedThisTurn = false
            }
        }
    }

    /// Track whether a plan has already been applied this turn so the
    /// transcript-tag path doesn't overwrite it with a stale [POINT:].
    /// Set of tool-call IDs we've already dispatched within the current
    /// user utterance. Gemini Live occasionally emits the SAME function
    /// call twice in one turn (once inline in modelTurn.parts, once as
    /// a top-level toolCall envelope) — both copies share the same id,
    /// so ID-based dedup catches them. But legitimately different tool
    /// calls within the same turn (e.g. a refined point_at_element →
    /// submit_workflow_plan) get different IDs and both execute.
    /// Reset when a new user utterance starts.
    private var handledToolCallIDsThisUtterance: Set<String> = []

    /// Set by the legacy [POINT:] transcript-tag path so it doesn't
    /// fight a plan that was emitted by a proper tool call in the same
    /// turn. Reset alongside the ID set on new utterance.
    private var planAppliedThisTurn: Bool = false

    /// Tracks how long the input transcript was on the last update so
    /// we can detect "transcript went from empty → non-empty" — the
    /// reliable signal that a new user utterance just began. See the
    /// onInputTranscriptUpdate hook in the session setup for why.
    private var previousInputTranscriptLength: Int = 0


    func setSelectedModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "selectedClaudeModel")
        claudeAPI.model = model
    }

    /// User preference for whether the TipTour cursor should be shown.
    /// When toggled off, the overlay is hidden and push-to-talk is disabled.
    /// Persisted to UserDefaults so the choice survives app restarts.
    @Published var isTipTourCursorEnabled: Bool = UserDefaults.standard.object(forKey: "isTipTourCursorEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isTipTourCursorEnabled")

    /// Debug flag for the workflow checklist: when true, ClickDetector
    /// advances on ANY click instead of requiring the click to land
    /// within 40pt of the resolved target. Lets the user progress
    /// through a plan even when YOLO/AX resolves wrong. Persisted so
    /// testing sessions survive app restarts.
    @Published var advanceOnAnyClickEnabled: Bool = UserDefaults.standard.bool(forKey: "advanceOnAnyClickEnabled") {
        didSet {
            ClickDetector.advanceOnAnyClickEnabled = advanceOnAnyClickEnabled
        }
    }

    func setAdvanceOnAnyClickEnabled(_ enabled: Bool) {
        advanceOnAnyClickEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "advanceOnAnyClickEnabled")
    }

    /// User preference for whether the menu bar panel stays visible when
    /// the user clicks outside of it (like Raycast / a pinned popover).
    /// When false (default), the panel auto-dismisses on outside click
    /// — standard macOS menu bar behavior. When true, only the × close
    /// button or clicking the menu bar icon dismisses it. Persisted.
    @Published var isPanelPinned: Bool = UserDefaults.standard.bool(forKey: "isPanelPinned")

    func setPanelPinned(_ pinned: Bool) {
        isPanelPinned = pinned
        UserDefaults.standard.set(pinned, forKey: "isPanelPinned")
        // Let the panel manager react — install or remove the
        // click-outside monitor as needed without hiding the panel.
        NotificationCenter.default.post(name: .tipTourPanelPinStateChanged, object: nil)
    }

    /// Neko mode: replace the blue triangle cursor with a pixel-art
    /// cat (classic oneko sprites) that runs toward whatever the
    /// cursor is pointing at, picking one of 8 directional sprite
    /// pairs based on its velocity and alternating animation frames.
    /// Falls asleep after a few seconds of stillness. Purely a
    /// visual personality toggle — doesn't change any behavior.
    /// Defaults to ON for new installs (the cat is part of TipTour's
    /// identity). If the user has explicitly toggled it off, that
    /// preference is preserved across restarts.
    @Published var isNekoModeEnabled: Bool = UserDefaults.standard.object(forKey: "isNekoModeEnabled") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "isNekoModeEnabled")

    func setNekoModeEnabled(_ enabled: Bool) {
        isNekoModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isNekoModeEnabled")
    }

    func setTipTourCursorEnabled(_ enabled: Bool) {
        isTipTourCursorEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isTipTourCursorEnabled")
        transientHideTask?.cancel()
        transientHideTask = nil

        if enabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        } else {
            overlayWindowManager.hideOverlay()
            isOverlayVisible = false
        }
    }

    /// Whether the user has completed onboarding at least once. Persisted
    /// to UserDefaults so the Start button only appears on first launch.
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    /// Whether the user has submitted their email during onboarding.
    @Published var hasSubmittedEmail: Bool = true  // bypassed

    /// Submits the user's email to FormSpark and identifies them in PostHog.
    func submitEmail(_ email: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        hasSubmittedEmail = true
        UserDefaults.standard.set(true, forKey: "hasSubmittedEmail")

        // Identify user in PostHog
        PostHogSDK.shared.identify(trimmedEmail, userProperties: [
            "email": trimmedEmail
        ])

        // Submit to FormSpark
        Task {
            var request = URLRequest(url: URL(string: "https://submit-form.com/RWbGJxmIs")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmedEmail])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func start() {
        refreshAllPermissions()
        print("🔑 TipTour start — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission), onboarded: \(hasCompletedOnboarding)")
        startPermissionPolling()
        bindVoiceStateObservation()
        bindAudioPowerLevel()
        bindShortcutTransitions()
        beginTrackingUserTargetApp()
        // Push the persisted debug flag into ClickDetector — the
        // @Published didSet only fires on assignment, so the initial
        // load from UserDefaults needs to be copied across manually.
        ClickDetector.advanceOnAnyClickEnabled = advanceOnAnyClickEnabled
        // Eagerly touch the Claude API so its TLS warmup handshake completes
        // well before the onboarding demo fires at ~40s into the video.
        _ = claudeAPI

        // Detection runs on-demand (hotkey press, tutorials, pointing) — not in background.
        // Background live feeding was causing cursor jank from ScreenCaptureKit + CoreML
        // contending with the 60fps cursor tracking timer on the main thread.

        // If the user already completed onboarding AND all permissions are
        // still granted, show the cursor overlay immediately. If permissions
        // were revoked (e.g. signing change), don't show the cursor — the
        // panel will show the permissions UI instead.
        if hasCompletedOnboarding && allPermissionsGranted && isTipTourCursorEnabled {
            overlayWindowManager.hasShownOverlayBefore = true
            overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
            isOverlayVisible = true
        }
    }

    /// Called when the user taps Start TipTour in the menu bar panel
    /// after granting permissions. Dismisses the panel and surfaces the
    /// cursor overlay; the welcome animation + hotkey prompt run from
    /// BlueCursorView.onAppear when isFirstAppearance is true.
    func triggerOnboarding() {
        NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)

        // Mark onboarding as completed so the Start button won't appear
        // again on future launches — the cursor will auto-show instead
        hasCompletedOnboarding = true

        TipTourAnalytics.trackOnboardingStarted()

        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
        isOverlayVisible = true
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementDisplayFrame = nil
        detectedElementBubbleText = nil
        highlightedElementLabel = nil
    }

    func stop() {
        globalPushToTalkShortcutMonitor.stop()
        buddyDictationManager.cancelCurrentDictation()
        overlayWindowManager.hideOverlay()
        transientHideTask?.cancel()

        currentResponseTask?.cancel()
        currentResponseTask = nil
        shortcutTransitionCancellable?.cancel()
        voiceStateCancellable?.cancel()
        audioPowerCancellable?.cancel()
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
    }

    func refreshAllPermissions() {
        let previouslyHadAccessibility = hasAccessibilityPermission
        let previouslyHadScreenRecording = hasScreenRecordingPermission
        let previouslyHadMicrophone = hasMicrophonePermission
        let previouslyHadAll = allPermissionsGranted

        let currentlyHasAccessibility = WindowPositionManager.hasAccessibilityPermission()
        hasAccessibilityPermission = currentlyHasAccessibility

        if currentlyHasAccessibility {
            globalPushToTalkShortcutMonitor.start()
        } else {
            globalPushToTalkShortcutMonitor.stop()
        }

        hasScreenRecordingPermission = WindowPositionManager.hasScreenRecordingPermission()

        let micAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        hasMicrophonePermission = micAuthStatus == .authorized

        // Debug: log permission state on changes
        if previouslyHadAccessibility != hasAccessibilityPermission
            || previouslyHadScreenRecording != hasScreenRecordingPermission
            || previouslyHadMicrophone != hasMicrophonePermission {
            print("🔑 Permissions — accessibility: \(hasAccessibilityPermission), screen: \(hasScreenRecordingPermission), mic: \(hasMicrophonePermission), screenContent: \(hasScreenContentPermission)")
        }

        // Track individual permission grants as they happen
        if !previouslyHadAccessibility && hasAccessibilityPermission {
            TipTourAnalytics.trackPermissionGranted(permission: "accessibility")
        }
        if !previouslyHadScreenRecording && hasScreenRecordingPermission {
            TipTourAnalytics.trackPermissionGranted(permission: "screen_recording")
        }
        if !previouslyHadMicrophone && hasMicrophonePermission {
            TipTourAnalytics.trackPermissionGranted(permission: "microphone")
        }
        // Screen content permission is persisted — once the user has approved the
        // SCShareableContent picker, we don't need to re-check it.
        if !hasScreenContentPermission {
            hasScreenContentPermission = UserDefaults.standard.bool(forKey: "hasScreenContentPermission")
        }

        if !previouslyHadAll && allPermissionsGranted {
            TipTourAnalytics.trackAllPermissionsGranted()
        }
    }

    /// Triggers the macOS screen content picker by performing a dummy
    /// screenshot capture. Once the user approves, we persist the grant
    /// so they're never asked again during onboarding.
    @Published private(set) var isRequestingScreenContent = false

    func requestScreenContentPermission() {
        guard !isRequestingScreenContent else { return }
        isRequestingScreenContent = true
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    await MainActor.run { isRequestingScreenContent = false }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 240
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                // Verify the capture actually returned real content — a 0x0 or
                // fully-empty image means the user denied the prompt.
                let didCapture = image.width > 0 && image.height > 0
                print("🔑 Screen content capture result — width: \(image.width), height: \(image.height), didCapture: \(didCapture)")
                await MainActor.run {
                    isRequestingScreenContent = false
                    guard didCapture else { return }
                    hasScreenContentPermission = true
                    UserDefaults.standard.set(true, forKey: "hasScreenContentPermission")
                    TipTourAnalytics.trackPermissionGranted(permission: "screen_content")

                    // If onboarding was already completed, show the cursor overlay now
                    if hasCompletedOnboarding && allPermissionsGranted && !isOverlayVisible && isTipTourCursorEnabled {
                        overlayWindowManager.hasShownOverlayBefore = true
                        overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                        isOverlayVisible = true
                    }
                }
            } catch {
                print("⚠️ Screen content permission request failed: \(error)")
                await MainActor.run { isRequestingScreenContent = false }
            }
        }
    }

    // MARK: - Private

    /// Triggers the system microphone prompt if the user has never been asked.
    /// Once granted/denied the status sticks and polling picks it up.
    private func promptForMicrophoneIfNotDetermined() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasMicrophonePermission = granted
            }
        }
    }

    /// Polls all permissions frequently so the UI updates live after the
    /// user grants them in System Settings. Screen Recording is the exception —
    /// macOS requires an app restart for that one to take effect.
    private func startPermissionPolling() {
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllPermissions()
            }
        }
    }

    /// Audio power cancellable for the Gemini Live session (separate from
    /// the dictation manager's stream since they're independent audio engines).
    private var geminiAudioPowerCancellable: AnyCancellable?
    private var geminiModelSpeakingCancellable: AnyCancellable?

    private func bindAudioPowerLevel() {
        audioPowerCancellable = buddyDictationManager.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                // Ignore dictation's power in Gemini mode — the Gemini session
                // publishes its own level from a separate audio engine.
                guard self?.voiceMode != .geminiLive else { return }
                self?.currentAudioPowerLevel = powerLevel
            }

        geminiAudioPowerCancellable = geminiLiveSession.$currentAudioPowerLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] powerLevel in
                guard self?.voiceMode == .geminiLive else { return }
                self?.currentAudioPowerLevel = powerLevel
            }

        // When Gemini finishes its turn, drop back to .listening so the
        // waveform stays visible while the user decides what to say next.
        geminiModelSpeakingCancellable = geminiLiveSession.$isModelSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isSpeaking in
                guard let self = self, self.voiceMode == .geminiLive, self.geminiLiveSession.isActive else { return }
                self.voiceState = isSpeaking ? .responding : .listening
            }
    }

    private func bindVoiceStateObservation() {
        voiceStateCancellable = buddyDictationManager.$isRecordingFromKeyboardShortcut
            .combineLatest(
                buddyDictationManager.$isFinalizingTranscript,
                buddyDictationManager.$isPreparingToRecord
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording, isFinalizing, isPreparing in
                guard let self else { return }
                // Don't override .responding — the AI response pipeline
                // manages that state directly until streaming finishes.
                guard self.voiceState != .responding else { return }

                if isFinalizing {
                    self.voiceState = .processing
                } else if isRecording {
                    self.voiceState = .listening
                } else if isPreparing {
                    self.voiceState = .processing
                } else {
                    self.voiceState = .idle
                    // If the user pressed and released the hotkey without
                    // saying anything, no response task runs — schedule the
                    // transient hide here so the overlay doesn't get stuck.
                    // Only do this when no response is in flight, otherwise
                    // the brief idle gap between recording and processing
                    // would prematurely hide the overlay.
                    if self.currentResponseTask == nil {
                        self.scheduleTransientHideIfNeeded()
                    }
                }
            }
    }

    /// Start live feeding for the detection overlay debug tool.
    /// Only runs while the overlay toggle is on — stops when toggled off.
    func startDetectionOverlayFeeding() {
        NativeElementDetector.shared.startLiveFeeding(interval: 1.5) { [weak self] in
            guard let cgImage = try? await CompanionScreenCaptureUtility.capturePrimaryScreenAsCGImage() else { return nil }

            Task {
                await self?.updateDetectionOverlay()
            }

            return cgImage
        }
    }

    /// Fetch all detected elements from native detector for overlay rendering
    private func updateDetectionOverlay() async {
        let cached = NativeElementDetector.shared.getCachedElements()

        await MainActor.run {
            self.detectedElements = cached.elements
            self.detectedImageSize = cached.imageSize
        }
    }

    private func bindShortcutTransitions() {
        shortcutTransitionCancellable = globalPushToTalkShortcutMonitor
            .shortcutTransitionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transition in
                self?.handleShortcutTransition(transition)
            }
    }

    /// Watch NSWorkspace for app-activation events and continuously
    /// remember the last NON-TipTour app the user activated. This is
    /// the `userTargetAppOverride` the AX resolver uses to route
    /// queries at the right app.
    ///
    /// Why this exists: capturing the frontmost app only at hotkey
    /// press time breaks if the user has interacted with TipTour's
    /// menu bar panel first (e.g. pasted an API key in the Developer
    /// section) — at hotkey press, frontmost is TipTour, we skip
    /// updating the override, and the AX resolver falls back to
    /// "most recent launched app" which may be completely unrelated
    /// to whatever the user actually had focused.
    ///
    /// With this observer, every time the user activates Xcode /
    /// Blender / Chrome / whatever, we update the override. By the
    /// time they press Ctrl+Option, the override is already correct.
    private func beginTrackingUserTargetApp() {
        // Seed with current frontmost (handles the case where the app
        // launches while the user is already focused in e.g. Xcode).
        if let current = NSWorkspace.shared.frontmostApplication,
           current.bundleIdentifier != Bundle.main.bundleIdentifier {
            AccessibilityTreeResolver.userTargetAppOverride = current
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            // Skip our own activations (menu bar panel, text field focus,
            // etc.) — we only care about apps the user might want TipTour
            // to point into.
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            AccessibilityTreeResolver.userTargetAppOverride = app
        }
    }

    private func handleShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        switch transition {
        case .pressed:
            // Snapshot the user's real frontmost app BEFORE opening the
            // menu bar panel or cursor overlay. Once TipTour shows any UI
            // macOS may flip frontmost to us, so this is the only reliable
            // moment to capture which app the user was actually looking at.
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
                AccessibilityTreeResolver.userTargetAppOverride = frontmost
                print("[Target] user's app at hotkey press: \(frontmost.bundleIdentifier ?? "?") (\(frontmost.localizedName ?? "?"))")
            }

            // If a tutorial is active, advance to next step instead of dictation
            if isTutorialActive {
                advanceTutorial()
                return
            }

            guard !buddyDictationManager.isDictationInProgress else { return }
            // Don't register push-to-talk while the onboarding video is playing
            guard !showOnboardingVideo else { return }

            // Cancel any pending transient hide so the overlay stays visible
            transientHideTask?.cancel()
            transientHideTask = nil

            // If the cursor is hidden, bring it back transiently for this interaction
            if !isTipTourCursorEnabled && !isOverlayVisible {
                overlayWindowManager.hasShownOverlayBefore = true
                overlayWindowManager.showOverlay(onScreens: NSScreen.screens, companionManager: self)
                isOverlayVisible = true
            }

            // Dismiss the menu bar panel so it doesn't cover the screen
            NotificationCenter.default.post(name: .tipTourDismissPanel, object: nil)

            // Cancel any in-progress response and TTS from a previous utterance
            currentResponseTask?.cancel()
            elevenLabsTTSClient.stopPlayback()
            clearDetectedElementLocation()

            // Clear any tutorial/prompt overlay
            showOnboardingPrompt = false
            onboardingPromptText = ""
            onboardingPromptOpacity = 0.0
            tutorialActionType = ""
            tutorialKeyLabel = ""
    

            TipTourAnalytics.trackPushToTalkStarted()

            // Gemini Live uses TOGGLE behavior, not hold-to-talk. The connection
            // stays open across turns so the user can have a real conversation —
            // talk naturally, pause, hear Gemini respond, interrupt, etc. Press
            // hotkey once to start, press again to end.
            if voiceMode == .geminiLive {
                if geminiLiveSession.isActive {
                    stopGeminiLiveSession()
                    voiceState = .idle
                } else {
                    startGeminiLiveSession()
                    voiceState = .listening
                }
                return
            }

            // Warm AX tree + YOLO cache for the current app RIGHT NOW —
            // in parallel with dictation startup. By the time the user
            // finishes speaking and Claude responds, everything's hot.
            Task.detached(priority: .userInitiated) {
                await Self.warmLocalResolvers()
            }

            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = Task {
                await buddyDictationManager.startPushToTalkFromKeyboardShortcut(
                    currentDraftText: "",
                    updateDraftText: { _ in
                        // Partial transcripts are hidden (waveform-only UI)
                    },
                    submitDraftText: { [weak self] finalTranscript in
                        self?.lastTranscript = finalTranscript
                        print("🗣️ Companion received transcript: \(finalTranscript)")
                        TipTourAnalytics.trackUserMessageSent(transcript: finalTranscript)
                        self?.sendTranscriptToClaudeWithScreenshot(transcript: finalTranscript)
                    }
                )
            }
        case .released:
            // Cancel the pending start task in case the user released the shortcut
            // before the async startPushToTalk had a chance to begin recording.
            // Without this, a quick press-and-release drops the release event and
            // leaves the waveform overlay stuck on screen indefinitely.
            TipTourAnalytics.trackPushToTalkReleased()

            // In Gemini Live mode release is a no-op — the session is toggled
            // by hotkey PRESS, not by press/release.
            if voiceMode == .geminiLive {
                return
            }

            pendingKeyboardShortcutStartTask?.cancel()
            pendingKeyboardShortcutStartTask = nil
            buddyDictationManager.stopPushToTalkFromKeyboardShortcut()
        case .none:
            break
        }
    }

    // MARK: - Companion Prompt

    private static let companionVoiceResponseSystemPrompt = """
    you're tiptour, a friendly always-on companion that lives in the user's menu bar. the user just spoke to you via push-to-talk and you can see their screen(s). your reply will be spoken aloud via text-to-speech, so write the way you'd actually talk. this is an ongoing conversation — you remember everything they've said before.

    rules:
    - default to one or two sentences. be direct and dense. BUT if the user asks you to explain more, go deeper, or elaborate, then go all out — give a thorough, detailed explanation with no length limit.
    - all lowercase, casual, warm. no emojis.
    - write for the ear, not the eye. short sentences. no lists, bullet points, markdown, or formatting — just natural speech.
    - don't use abbreviations or symbols that sound weird read aloud. write "for example" not "e.g.", spell out small numbers.
    - if the user's question relates to what's on their screen, reference specific things you see.
    - if the screenshot doesn't seem relevant to their question, just answer the question directly.
    - you can help with anything — coding, writing, general knowledge, brainstorming.
    - never say "simply" or "just".
    - don't read out code verbatim. describe what the code does or what needs to change conversationally.
    - focus on giving a thorough, useful explanation. don't end with simple yes/no questions like "want me to explain more?" or "should i show you?" — those are dead ends that force the user to just say yes.
    - instead, when it fits naturally, end by planting a seed — mention something bigger or more ambitious they could try, a related concept that goes deeper, or a next-level technique that builds on what you just explained. make it something worth coming back for, not a question they'd just nod to. it's okay to not end with anything extra if the answer is complete on its own.
    - if you receive multiple screen images, the one labeled "primary focus" is where the cursor is — prioritize that one but reference others if relevant.

    element pointing via tools (VERY IMPORTANT — read carefully):

    you have exactly TWO tools. call AT MOST ONE tool per turn. do NOT narrate before the tool call. call it silently, wait for the response, THEN speak ONCE.

    TOOL: point_at_element(label)
      use for a SINGLE visible element. examples: "where's the save button", "point at the color inspector", "what is this tab".
      label = literal visible text on screen.

    UI ELEMENT HINTS (set-of-marks):
    alongside screenshots you will sometimes receive a "UI elements on screen" message listing pointable elements as [role:label] tokens — for example [button:Save] [menu:File] [item:New File...] [tab:Preview] [field:Search].
    these labels come straight from the accessibility tree, so they are guaranteed to resolve. when a listed element matches what the user asked for, pass that EXACT label string (the part after the colon) to point_at_element or to a workflow step. if nothing matches, fall back to the visible text you see in the screenshot.

    TOOL: submit_workflow_plan(goal, app, steps)
      use for ANYTHING that requires more than one click, including:
        - opening a menu then picking an item ("how do I save" → File → Save)
        - navigating through panels or tabs
        - ANY "how do I X" / "walk me through" / "show me how to" / "teach me" question
      produce the FULL plan yourself — you see the screenshot, you know the user's request, you know the app. you DO NOT need an external planner. emit every step in order.
      arguments:
        goal  = short summary of the user's intent ("create a new file", "render an animation").
        app   = exact foreground app name visible in the screenshot ("Blender", "Xcode", "GarageBand"). never "macOS" or "unknown".
        steps = ordered array of {label, hint, x?, y?}. first step MUST be visible on the current screen. subsequent steps describe the path to take after clicking step 1; x/y optional on those. include x,y on step 1 only when the app lacks accessibility support (Blender, games, canvas tools).

    ABSOLUTE RULES:
    - exactly ONE tool call per turn. never both tools, never the same tool twice.
    - single visible element → point_at_element.
    - anything needing a sequence → submit_workflow_plan.
    - no UI involvement (pure knowledge or chit-chat) → no tool, just speak.

    PRE-TOOL-CALL SILENCE:
    if your next action is a tool call, stay completely silent — no filler, no "sure", no "hmm". call the tool, wait for toolResponse, THEN speak. if you speak before the tool call, the user hears a half-word that cuts off when the tool fires.

    this rule ONLY applies when a tool call is coming. for pure knowledge / chit-chat with no tool, speak normally.

    after submit_workflow_plan returns, narrate the full plan out loud in ONE natural-sounding turn. one to two short sentences total. describe the sequence the user will follow. do NOT pause between steps, do NOT wait for anything — speak the whole thing uninterrupted and then stop. the cursor and checklist handle per-step timing independently; your job is the voice-over, not the sync.
      example: "click File, then New, then File..."
      example: "open the Render menu and pick Render Animation."

    examples:

    user: "where's the File menu"
      → point_at_element(label: "File")
      → speak: "right at the top left"

    user: "how do I create a new file in Xcode"
      → submit_workflow_plan(goal: "create a new file", app: "Xcode",
           steps: [{label:"File", hint:"Open the File menu"},
                   {label:"New", hint:"Pick New"},
                   {label:"File...", hint:"Choose File..."}])
      → speak: "here's how to create a new file."
      (then later, per-step NARRATE: messages arrive one at a time)

    user: "what is HTML"
      → no tool
      → speak your answer
    """

    // MARK: - AI Response Pipeline

    /// Captures a screenshot, sends it along with the transcript to Claude,
    /// and plays the response aloud via ElevenLabs TTS. The cursor stays in
    /// the spinner/processing state until TTS audio begins playing.
    /// Claude's response may include a [POINT:x,y:label] tag which triggers
    /// the buddy to fly to that element on screen.
    private func sendTranscriptToClaudeWithScreenshot(transcript: String) {
        currentResponseTask?.cancel()
        elevenLabsTTSClient.stopPlayback()

        currentResponseTask = Task {
            // Stay in processing (spinner) state — no streaming text displayed
            voiceState = .processing

            do {
                // Capture all connected screens so the AI has full context
                let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

                // Run on-device detection on the primary screen so the cache
                // is warm for any [POINT:] tags Claude returns, and the
                // detection overlay (if toggled on) gets populated.
                if let primaryCapture = screenCaptures.first,
                   let cgImage = Self.cgImage(from: primaryCapture.imageData) {
                    await NativeElementDetector.shared.detectElements(in: cgImage)
                    if showDetectionOverlay {
                        await updateDetectionOverlay()
                    }
                }

                guard !Task.isCancelled else { return }

                // Build image labels with the actual screenshot pixel dimensions
                // so Claude's coordinate space matches the image it sees. We
                // scale from screenshot pixels to display points ourselves.
                let labeledImages = screenCaptures.map { capture in
                    let dimensionInfo = " (image dimensions: \(capture.screenshotWidthInPixels)x\(capture.screenshotHeightInPixels) pixels)"
                    return (data: capture.imageData, label: capture.label + dimensionInfo)
                }

                // Pass conversation history so Claude remembers prior exchanges
                let historyForAPI = conversationHistory.map { entry in
                    (userPlaceholder: entry.userTranscript, assistantResponse: entry.assistantResponse)
                }

                let (fullResponseText, _) = try await claudeAPI.analyzeImageStreaming(
                    images: labeledImages,
                    systemPrompt: Self.companionVoiceResponseSystemPrompt,
                    conversationHistory: historyForAPI,
                    userPrompt: transcript,
                    onTextChunk: { _ in
                        // No streaming text display — spinner stays until TTS plays
                    }
                )

                guard !Task.isCancelled else { return }

                // Check for multi-step [STEP] markers
                let hasMultiStep = fullResponseText.contains("[STEP]")
                var pendingStepLabels: [String] = []

                if hasMultiStep {
                    // Extract labels from all [POINT:...] tags after [STEP] markers
                    let steps = fullResponseText.components(separatedBy: "[STEP]")
                    for step in steps.dropFirst() {
                        // Parse [POINT:x,y:label] or [POINT:none:label] from each step
                        let stepParse = Self.parsePointingCoordinates(from: step)
                        if let label = stepParse.elementLabel, label != "none" {
                            pendingStepLabels.append(label)
                        }
                    }
                    print("🎯 Multi-step: \(pendingStepLabels.count) pending steps: \(pendingStepLabels)")
                }

                // Parse the first [POINT:...] tag from Claude's response
                let firstStep = hasMultiStep ? fullResponseText.components(separatedBy: "[STEP]").first ?? fullResponseText : fullResponseText
                let parseResult = Self.parsePointingCoordinates(from: firstStep)
                let spokenText = parseResult.spokenText

                // Handle element pointing if Claude returned coordinates.
                // Switch to idle BEFORE setting the location so the triangle
                // becomes visible and can fly to the target. Without this, the
                // spinner hides the triangle and the flight animation is invisible.
                let hasPointCoordinate = parseResult.coordinate != nil
                if hasPointCoordinate {
                    voiceState = .idle
                }

                // Pick the screen capture matching Claude's screen number,
                // falling back to the cursor screen if not specified.
                let targetScreenCapture: CompanionScreenCapture? = {
                    if let screenNumber = parseResult.screenNumber,
                       screenNumber >= 1 && screenNumber <= screenCaptures.count {
                        return screenCaptures[screenNumber - 1]
                    }
                    return screenCaptures.first(where: { $0.isCursorScreen })
                }()

                // Route through the unified ElementResolver.
                if let rawLabel = parseResult.elementLabel,
                   rawLabel.lowercased() != "none",
                   let targetScreenCapture {
                    let elementLabel = rawLabel
                    let targetCapture = targetScreenCapture

                    // resolve() handles the AX → YOLO → LLM cascade internally,
                    // including running YOLO detection only if AX missed.
                    let resolution = await ElementResolver.shared.resolve(
                        label: elementLabel,
                        llmHintInScreenshotPixels: parseResult.coordinate,
                        latestCapture: targetCapture
                    )

                    if let resolution {
                        await MainActor.run {
                            self.pointAtResolution(resolution)
                        }
                    } else {
                        print("🎯 could not resolve \"\(elementLabel)\"")
                    }

                    // Highlight the matched element in the detection overlay
                    self.highlightedElementLabel = elementLabel
                    TipTourAnalytics.trackElementPointed(elementLabel: parseResult.elementLabel)

                    // Queue remaining steps for multi-step navigation.
                    // Only the legacy Claude pipeline uses this timed
                    // queue — Gemini Live has its own click-driven
                    // WorkflowRunner and the two must not both run.
                    if !pendingStepLabels.isEmpty,
                       self.voiceMode == .claudeAndElevenLabs {
                        self.queuePendingSteps(pendingStepLabels)
                    }
                } else {
                    print("🎯 Element pointing: \(parseResult.elementLabel ?? "no element")")
                }

                // Save this exchange to conversation history (with the point tag
                // stripped so it doesn't confuse future context)
                conversationHistory.append((
                    userTranscript: transcript,
                    assistantResponse: spokenText
                ))

                // Keep only the last 10 exchanges to avoid unbounded context growth
                if conversationHistory.count > 10 {
                    conversationHistory.removeFirst(conversationHistory.count - 10)
                }

                print("🧠 Conversation history: \(conversationHistory.count) exchanges")

                TipTourAnalytics.trackAIResponseReceived(response: spokenText)

                // Play the response via TTS. Keep the spinner (processing state)
                // until the audio actually starts playing, then switch to responding.
                if !spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        try await elevenLabsTTSClient.speakText(spokenText)
                        // speakText returns after player.play() — audio is now playing
                        voiceState = .responding
                    } catch {
                        TipTourAnalytics.trackTTSError(error: error.localizedDescription)
                        print("⚠️ ElevenLabs TTS error: \(error)")
                        speakCreditsErrorFallback()
                    }
                }
            } catch is CancellationError {
                // User spoke again — response was interrupted
            } catch {
                TipTourAnalytics.trackResponseError(error: error.localizedDescription)
                print("⚠️ Companion response error: \(error)")
                speakCreditsErrorFallback()
            }

            if !Task.isCancelled {
                voiceState = .idle
                scheduleTransientHideIfNeeded()
            }
        }
    }

    /// If the cursor is in transient mode (user toggled "Show TipTour" off),
    /// waits for TTS playback and any pointing animation to finish, then
    /// fades out the overlay after a 1-second pause. Cancelled automatically
    /// if the user starts another push-to-talk interaction.
    private func scheduleTransientHideIfNeeded() {
        guard !isTipTourCursorEnabled && isOverlayVisible else { return }

        transientHideTask?.cancel()
        transientHideTask = Task {
            // Wait for TTS audio to finish playing
            while elevenLabsTTSClient.isPlaying {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Wait for pointing animation to finish (location is cleared
            // when the buddy flies back to the cursor)
            while detectedElementScreenLocation != nil {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
            }

            // Pause 1s after everything finishes, then fade out
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            overlayWindowManager.fadeOutAndHideOverlay()
            isOverlayVisible = false
        }
    }

    /// Speaks a hardcoded error message using macOS system TTS when API
    /// credits run out. Uses NSSpeechSynthesizer so it works even when
    /// ElevenLabs is down.
    private func speakCreditsErrorFallback() {
        let utterance = "I'm all out of credits. Please reach out to the developer to bring me back to life."
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(utterance)
        voiceState = .responding
    }

    // MARK: - Point Tag Parsing

    /// Result of parsing a [POINT:...] tag from Claude's response.
    struct PointingParseResult {
        /// The response text with the [POINT:...] tag removed — this is what gets spoken.
        let spokenText: String
        /// The parsed pixel coordinate, or nil if Claude said "none" or no tag was found.
        let coordinate: CGPoint?
        /// Short label describing the element (e.g. "run button"), or "none".
        let elementLabel: String?
        /// Which screen the coordinate refers to (1-based), or nil to default to cursor screen.
        let screenNumber: Int?
    }

    /// Parses a [POINT:...] tag from the end of the LLM's response.
    /// Accepts three formats:
    ///   • [POINT:label]                      — label-only (preferred)
    ///   • [POINT:label:screenN]              — label on secondary screen
    ///   • [POINT:x,y:label]                  — legacy pixel-coord form
    ///   • [POINT:x,y:label:screenN]          — legacy with screen
    ///   • [POINT:none]                       — no pointing
    /// Returns the spoken text (tag removed) and the coordinate (if any) + label + screen.
    static func parsePointingCoordinates(from responseText: String) -> PointingParseResult {
        // Try the legacy x,y form first so its numeric prefix doesn't accidentally match as a label.
        // Pattern breakdown:
        //   \[POINT:
        //     (?: none
        //       | (\d+)\s*,\s*(\d+)           -> groups 1,2: x,y (legacy form)
        //         (?::([^\]:]+?))?            -> group 3: legacy label
        //         (?::screen(\d+))?           -> group 4: legacy screen
        //       | ([^\]:\d][^\]:]*?)          -> group 5: label-only (must not start with digit)
        //         (?::screen(\d+))?           -> group 6: label-only screen
        //     )
        //   \]\s*$
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:]+?))?(?::screen(\d+))?|([^\]:\d][^\]:]*?)(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Legacy x,y form: groups 1 and 2 captured.
        if let xRange = Range(match.range(at: 1), in: responseText),
           let yRange = Range(match.range(at: 2), in: responseText),
           let x = Double(responseText[xRange]),
           let y = Double(responseText[yRange]) {

            var elementLabel: String? = nil
            if let labelRange = Range(match.range(at: 3), in: responseText) {
                elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
            }
            var screenNumber: Int? = nil
            if let screenRange = Range(match.range(at: 4), in: responseText) {
                screenNumber = Int(responseText[screenRange])
            }

            return PointingParseResult(
                spokenText: spokenText,
                coordinate: CGPoint(x: x, y: y),
                elementLabel: elementLabel,
                screenNumber: screenNumber
            )
        }

        // Label-only form: group 5 captured.
        if let labelRange = Range(match.range(at: 5), in: responseText) {
            let elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
            var screenNumber: Int? = nil
            if let screenRange = Range(match.range(at: 6), in: responseText) {
                screenNumber = Int(responseText[screenRange])
            }
            return PointingParseResult(
                spokenText: spokenText,
                coordinate: nil,
                elementLabel: elementLabel,
                screenNumber: screenNumber
            )
        }

        // [POINT:none] — match succeeded but no captures.
        return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
    }

    // MARK: - Onboarding Video

    /// Public entry point for the "press control + option" prompt
    /// that used to play after the onboarding video. Called directly
    /// from the overlay's welcome animation now that the video is
    /// skipped — user goes welcome bubble → hotkey prompt → live app.
    func showOnboardingHotkeyPrompt() {
        startOnboardingPromptStream()
    }

    private func startOnboardingPromptStream() {
        let message = "press control + option and introduce yourself"
        onboardingPromptText = ""
        showOnboardingPrompt = true
        onboardingPromptOpacity = 0.0

        withAnimation(.easeIn(duration: 0.4)) {
            onboardingPromptOpacity = 1.0
        }

        var currentIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            guard currentIndex < message.count else {
                timer.invalidate()
                // Auto-dismiss after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard self.showOnboardingPrompt else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.onboardingPromptOpacity = 0.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showOnboardingPrompt = false
                        self.onboardingPromptText = ""
                    }
                }
                return
            }
            let index = message.index(message.startIndex, offsetBy: currentIndex)
            self.onboardingPromptText.append(message[index])
            currentIndex += 1
        }
    }

    // MARK: - Image Conversion

    /// Convert JPEG Data to CGImage for native element detection.
    static func cgImage(from jpegData: Data) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }

    // MARK: - Gemini Live Mode

    /// Track the last parsed transcript prefix so we only process new [POINT:] tags once.
    private var lastGeminiTranscriptLength: Int = 0

    /// Called whenever Gemini's output transcript grows — scans for [POINT:]
    /// tags and triggers cursor pointing for each new one.
    ///
    /// The key correctness guarantee: we use the EXACT same frame Gemini
    /// reasoned about (via `geminiLiveSession.latestCapture`) — not a fresh
    /// screenshot. This matters because Gemini's coordinates are relative
    /// to the JPEG bytes we sent it, and YOLO's cache was populated on the
    /// same pixels. Any other screenshot would be in a slightly different
    /// coordinate space and the cursor would land off-target.
    private func handleGeminiTranscriptUpdate(_ fullTranscript: String) {
        guard fullTranscript.count > lastGeminiTranscriptLength else { return }
        let newPortion = String(fullTranscript.suffix(fullTranscript.count - lastGeminiTranscriptLength))
        lastGeminiTranscriptLength = fullTranscript.count

        // If the parallel planner already set a pointing target this
        // turn, don't let a transcript [POINT:] tag overwrite it — the
        // planner's plan is more reliable than speech-transcribed tags.
        if planAppliedThisTurn { return }

        let parseResult = Self.parsePointingCoordinates(from: newPortion)

        guard let elementLabel = parseResult.elementLabel,
              elementLabel.lowercased() != "none" else {
            return
        }

        let hint = parseResult.coordinate
        let capture = geminiLiveSession.latestCapture

        Task {
            // resolve() runs AX first, then lazily runs YOLO detection on
            // the capture only if AX missed. Keeps work minimal during
            // audio-sensitive sessions.
            guard let resolution = await ElementResolver.shared.resolve(
                label: elementLabel,
                llmHintInScreenshotPixels: hint,
                latestCapture: capture
            ) else {
                return
            }
            await MainActor.run {
                self.pointAtResolution(resolution)
            }
        }
    }

    /// Execute a workflow plan emitted by Gemini. For now we just fly
    /// the cursor to step 1 — Gemini speaks the rest of the flow aloud
    /// and the user follows the menu path themselves. Clicks, state
    /// verification, and auto-advance will come later.
    private func startWorkflowPlan(_ plan: WorkflowPlan) {
        print("[Workflow] received plan from LLM: \"\(plan.goal)\" (\(plan.steps.count) steps)")
        WorkflowRunner.shared.start(
            plan: plan,
            pointHandler: { [weak self] resolution in
                self?.pointAtResolution(resolution)
            },
            latestCapture: geminiLiveSession.latestCapture
        )
    }

    /// Start a Gemini Live session on hotkey press (when voiceMode is .geminiLive).
    /// We run three things in parallel from the instant the hotkey fires:
    ///   1. WebSocket open + Gemini session setup (~300-500ms)
    ///   2. Screenshot capture + YOLO/OCR detection on the active frame
    ///   3. AX tree warmup on the frontmost app
    /// By the time Gemini's first response streams back, both the YOLO
    /// cache and the AX tree are already hot — so the very first [POINT:]
    /// resolves as accurately as every subsequent one.
    func startGeminiLiveSession() {
        lastGeminiTranscriptLength = 0

        // Kick off local warmup IMMEDIATELY — doesn't wait for the
        // WebSocket. This is the most time we save.
        Task.detached(priority: .userInitiated) {
            await Self.warmLocalResolvers()
        }

        Task {
            do {
                try await geminiLiveSession.start(initialScreenshot: nil)
            } catch {
                print("[GeminiLive] Failed to start session: \(error.localizedDescription)")
            }
        }
    }

    /// Capture a fresh frame + run YOLO/OCR + prime the AX tree.
    /// Safe to call from any thread — everything here is thread-safe.
    private static func warmLocalResolvers() async {
        // Screenshot + detection — run the CoreML pass at background
        // priority so it can't contend with Gemini Live's audio thread
        // once narration starts.
        if let cgImage = try? await CompanionScreenCaptureUtility.capturePrimaryScreenAsCGImage() {
            await Task.detached(priority: .background) {
                await NativeElementDetector.shared.detectElements(in: cgImage)
            }.value
        }
        // AX tree throwaway query — forces macOS to populate the tree
        // for the frontmost app so the first real lookup is hot.
        _ = await ElementResolver.shared.tryAccessibilityTree(label: "__warmup__")
    }

    /// End the Gemini Live session (on hotkey release).
    func stopGeminiLiveSession() {
        WorkflowRunner.shared.stop()
        planAppliedThisTurn = false
        geminiLiveSession.stop()
    }

}
