//
//  GeminiLiveSession.swift
//  leanring-buddy
//
//  Orchestrates a full Gemini Live conversation session:
//    1. Opens a WebSocket to Gemini via GeminiLiveClient
//    2. Captures mic audio with AVAudioEngine, converts to PCM16 16kHz,
//       and streams it over the WebSocket
//    3. Sends a screenshot at session start so Gemini can see the screen
//    4. Plays back audio responses in real time via GeminiLiveAudioPlayer
//    5. Exposes input/output transcripts and [POINT:] coordinates for
//       the overlay to consume
//

import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class GeminiLiveSession: ObservableObject {

    // MARK: - Published State (bindable from SwiftUI)

    /// Whether a Gemini Live session is currently active.
    @Published private(set) var isActive: Bool = false

    /// Latest partial transcript of what the user is saying.
    @Published private(set) var inputTranscript: String = ""

    /// Accumulated transcript of what the model has said this turn.
    /// Used to parse [POINT:x,y:label] tags.
    @Published private(set) var outputTranscript: String = ""

    /// Whether the model is currently speaking (audio is playing back).
    @Published private(set) var isModelSpeaking: Bool = false {
        didSet {
            // Mirror to a thread-safe atomic so the mic tap callback (which
            // runs on the real-time audio thread) can read without hopping
            // to main actor.
            modelSpeakingLock.withLock { modelSpeakingFlag = isModelSpeaking }
        }
    }

    /// Lock-protected mirror of `isModelSpeaking` for audio-thread reads.
    private var modelSpeakingFlag: Bool = false
    private let modelSpeakingLock = NSLock()

    /// Current mic audio power level (0.0–1.0), for driving the waveform animation.
    @Published private(set) var currentAudioPowerLevel: CGFloat = 0.0

    // MARK: - Callbacks

    /// Fires whenever new output transcript text arrives — the caller can
    /// parse it for [POINT:] tags and trigger cursor pointing.
    var onOutputTranscript: ((String) -> Void)?

    /// Fires when the model finishes its turn.
    var onTurnComplete: (() -> Void)?

    /// Fires when the user interrupts the model (barge-in).
    var onInterrupted: (() -> Void)?

    /// Fires on fatal errors so the caller can surface them to the user.
    var onError: ((Error) -> Void)?

    /// Fired when Gemini calls `point_at_element(label)`. The handler must
    /// resolve the label to a screen position, point the cursor there, and
    /// return a short dictionary describing the result. That dictionary is
    /// sent back to Gemini as the tool response so it can continue narrating
    /// with knowledge of what was pointed at.
    var onPointAtElement: ((_ label: String, _ screenshotJPEG: Data?) async -> [String: Any])?

    /// Fired when Gemini calls `submit_workflow_plan(goal, app, steps)`.
    /// Gemini produces the plan itself via its own vision + reasoning, so
    /// the handler just hands the steps off to WorkflowRunner and returns
    /// an acknowledgement — no separate planner round-trip needed.
    var onSubmitWorkflowPlan: ((_ goal: String, _ app: String, _ steps: [[String: Any]]) async -> [String: Any])?

    // MARK: - Dependencies

    private let geminiClient = GeminiLiveClient()
    private let audioPlayer = GeminiLiveAudioPlayer()

    /// Whether the local audio queue still has speech scheduled for
    /// playback. Used by the handoff-close logic in CompanionManager
    /// to avoid cutting off Gemini's acknowledgement mid-word.
    var isAudioPlaying: Bool {
        return audioPlayer.isPlaying
    }
    /// AVAudioEngine is rebuilt every session. Reusing a single engine
    /// across sessions caches the input format at the moment of first
    /// creation — if the user later changes input device (AirPods on/off,
    /// sample rate switch from 44.1k to 48k, etc.), installTap explodes
    /// with a format-mismatch fault because we ask for the old format.
    /// A fresh engine per session always queries the CURRENT input format.
    private var audioEngine = AVAudioEngine()
    private let pcm16Converter = BuddyPCM16AudioConverter(targetSampleRate: GeminiLiveClient.inputSampleRate)

    /// Where to fetch the Gemini API key. Points to the Worker's
    /// /gemini-live-key endpoint.
    private let apiKeyURL: URL

    /// The system prompt given to Gemini. Keeps POINT-tag behavior identical
    /// to the existing Claude flow so the cursor pointing keeps working.
    private let systemPrompt: String

    /// Whether the audio input tap has been installed on the engine.
    private var isAudioTapInstalled: Bool = false

    /// Timer that periodically captures a fresh screenshot and sends it to
    /// Gemini so it sees screen changes during the conversation.
    ///
    /// 3 seconds is a deliberate choice. The AX tree lookup (primary pointing
    /// path) is LIVE — it always reflects the current UI state — so we don't
    /// need frequent screenshot refreshes to keep coordinates fresh. The
    /// screenshot only matters for Gemini's visual context ("what is the
    /// user looking at"), which tolerates a few seconds of lag.
    ///
    /// Previously was 1.5s + ran YOLO on every tick, which starved Core Audio
    /// and caused audible stutter in Gemini's speech. YOLO now runs only
    /// on-demand when AX tree lookups miss.
    private var screenshotUpdateTimer: Timer?
    private static let screenshotUpdateInterval: TimeInterval = 3.0

    /// The most recent screenshot sent to Gemini, with full metadata.
    /// CompanionManager reads this when parsing [POINT:] tags so it maps
    /// Gemini's coordinates (which are relative to this exact screenshot)
    /// to the correct screen location. Without this the coordinates would
    /// be off by the drift between "what Gemini saw" and "current screen".
    @Published private(set) var latestCapture: CompanionScreenCapture?

    // MARK: - Init

    init(apiKeyURL: String, systemPrompt: String) {
        self.apiKeyURL = URL(string: apiKeyURL)!
        self.systemPrompt = systemPrompt

        geminiClient.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleGeminiEvent(event)
            }
        }
    }

    // MARK: - Session Lifecycle

    /// Start a new Gemini Live session. Opens the WebSocket, sends the
    /// initial screenshot, and begins streaming mic audio.
    /// Throws if the API key fetch or WebSocket setup fails.
    func start(initialScreenshot: Data?) async throws {
        guard !isActive else {
            print("[GeminiLiveSession] Already active — ignoring start()")
            return
        }

        let apiKey = try await fetchAPIKey()

        try await geminiClient.connect(
            apiKey: apiKey,
            systemPrompt: systemPrompt
        )

        // Initial frame capture + send to Gemini so it has visual context
        // for the user's first utterance. Local resolver warmup (YOLO/OCR
        // + AX tree) runs in parallel from CompanionManager the moment the
        // hotkey fires, so both caches are already hot by the time we get
        // here — we just need Gemini to see the same frame.
        _ = initialScreenshot
        await captureAndProcessFrameForGemini()

        try startMicCapture()

        // Prepare the audio output engine so there's no startup delay
        // on the first audio chunk Gemini sends back.
        audioPlayer.startEngine()

        isActive = true
        inputTranscript = ""
        outputTranscript = ""

        startPeriodicScreenshotUpdates()

        print("[GeminiLiveSession] Session started")
    }

    /// End the session — stops mic capture, closes WebSocket, stops playback.
    func stop() {
        guard isActive else { return }

        stopPeriodicScreenshotUpdates()
        stopMicCapture()
        audioPlayer.stopAndClearQueue()
        geminiClient.disconnect()

        isActive = false
        isModelSpeaking = false
        print("[GeminiLiveSession] Session stopped")
    }

    // MARK: - Narration Mode
    //
    // Narration mode is entered once `submit_workflow_plan` has been
    // accepted and the local runner owns the plan. We stop streaming
    // mic audio and screenshots (both risk feeding Gemini noise that
    // triggers interrupts), but keep the WebSocket + audio playback
    // alive so we can push a single-sentence text per step and hear
    // Gemini speak it in the same voice the user just heard.

    /// True while we've paused mic+screenshot streaming but still have
    /// a live socket for text-driven narration.
    private(set) var isInNarrationMode: Bool = false

    /// Pause mic capture and periodic screenshots while keeping the
    /// WebSocket and audio player alive. Use this while Gemini is
    /// speaking a post-tool-call narration so its own speech doesn't
    /// leak through the mic or get interrupted by stray screenshots.
    func enterNarrationMode() {
        guard isActive else { return }
        guard !isInNarrationMode else { return }
        stopPeriodicScreenshotUpdates()
        stopMicCapture()
        isInNarrationMode = true
        print("[GeminiLiveSession] Narration mode entered (mic + screenshots paused)")
    }

    /// Resume mic capture + periodic screenshots after narration
    /// finishes. The WebSocket stays open so Gemini's conversational
    /// memory of the current session carries over — user can ask
    /// follow-up questions ("and now save it?") and Gemini remembers
    /// everything said on this socket.
    func exitNarrationMode() {
        guard isActive else { return }
        guard isInNarrationMode else { return }
        do {
            try startMicCapture()
        } catch {
            print("[GeminiLiveSession] Failed to restart mic after narration: \(error)")
        }
        startPeriodicScreenshotUpdates()
        isInNarrationMode = false
        print("[GeminiLiveSession] Narration mode exited (mic + screenshots resumed)")
    }

    /// Send a text input to Gemini — kept around for future use (e.g.
    /// programmatic questions or context injection). Not used by the
    /// current one-shot narration flow.
    func sendText(_ text: String) {
        guard isActive else { return }
        geminiClient.sendText(text)
    }

    // MARK: - Push-To-Talk Mic Gating
    //
    // With classic push-to-talk semantics the user HOLDS the hotkey
    // while speaking and RELEASES to commit. On press we resume mic
    // streaming; on release we stop streaming audio to Gemini but
    // keep the WebSocket + audio player alive so Gemini's response
    // plays back cleanly. This eliminates ambient-noise contamination
    // and gives Gemini an immediate end-of-speech signal (no waiting
    // for VAD to guess), cutting perceived response latency.

    /// Stop streaming mic audio to Gemini. The audio engine is torn
    /// down so no buffers are even captured — zero ambient noise
    /// leaks, zero CPU cost. Safe no-op when already paused.
    func pauseMicCaptureForPushToTalk() {
        guard isActive else { return }
        stopMicCapture()
        print("[GeminiLiveSession] 🎤 Mic paused (push-to-talk released)")
    }

    /// Restart mic streaming when the user holds the hotkey for a
    /// new utterance. Rebuilds the audio engine from scratch because
    /// the input device/sample-rate may have changed since last use.
    func resumeMicCaptureForPushToTalk() {
        guard isActive else { return }
        do {
            try startMicCapture()
            print("[GeminiLiveSession] 🎤 Mic resumed (push-to-talk pressed)")
        } catch {
            print("[GeminiLiveSession] ✗ Failed to resume mic for push-to-talk: \(error)")
        }
    }

    // MARK: - Periodic Screenshot Updates

    /// Start sending fresh screenshots every 1.5s so Gemini sees window
    /// changes, scrolls, new content, etc. throughout the conversation.
    ///
    /// Each tick does three things atomically against a single frame:
    ///   1. Send JPEG to Gemini (so it has fresh visual context)
    ///   2. Run YOLO+OCR detection on the same frame (populates cache)
    ///   3. Publish the CompanionScreenCapture as latestCapture
    ///
    /// This is the key to accurate pointing: when Gemini later says
    /// [POINT:x,y:label], the coordinates are relative to this exact
    /// frame, and the detector cache already has the label's true
    /// position in the same coordinate space.
    private func startPeriodicScreenshotUpdates() {
        screenshotUpdateTimer?.invalidate()
        screenshotUpdateTimer = Timer.scheduledTimer(withTimeInterval: Self.screenshotUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                await self.captureAndProcessFrameForGemini()
            }
        }
    }

    private func stopPeriodicScreenshotUpdates() {
        screenshotUpdateTimer?.invalidate()
        screenshotUpdateTimer = nil
    }

    /// Capture one frame and send it to Gemini for visual context.
    /// YOLO detection is NOT run here — it only runs on-demand when the
    /// AX tree lookup fails. Keeping this method lightweight is critical
    /// for audio stability: heavy periodic work starves Core Audio and
    /// causes Gemini's voice to stutter.
    private func captureAndProcessFrameForGemini() async {
        guard let screenshots = try? await CompanionScreenCaptureUtility.captureAllScreensAsJPEG(),
              let primaryCapture = screenshots.first else {
            return
        }

        latestCapture = primaryCapture
        geminiClient.sendScreenshot(primaryCapture.imageData)
    }

    /// Decode JPEG Data into a CGImage for detector input.
    private static func cgImage(from jpegData: Data) -> CGImage? {
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }

    /// Send a fresh screenshot during the session — useful when the user
    /// mentions a new UI element and we want Gemini to see the current state.
    func sendScreenshot(_ jpegData: Data) {
        guard isActive else { return }
        geminiClient.sendScreenshot(jpegData)
    }

    // MARK: - API Key Fetch

    private func fetchAPIKey() async throws -> String {
        var request = URLRequest(url: apiKeyURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GeminiLiveSession", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to fetch Gemini API key"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["apiKey"] as? String else {
            throw NSError(domain: "GeminiLiveSession", code: -11,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid API key response"])
        }

        return apiKey
    }

    // MARK: - Mic Capture

    private func startMicCapture() throws {
        // Rebuild the engine from scratch every session. This forces a
        // re-query of the current input device's format. If we reused a
        // cached engine after the user switched hardware (AirPods,
        // different sample rate, etc.), installTap would throw a format
        // mismatch fault and the session would be unrecoverable.
        audioEngine = AVAudioEngine()
        isAudioTapInstalled = false

        let inputNode = audioEngine.inputNode
        // Query the format fresh from the hardware AT THIS MOMENT.
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Sanity check: if the format is invalid (sample rate 0 or no
        // channels), the audio subsystem is in a weird state — bail out
        // rather than crash inside installTap.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "GeminiLiveSession", code: -20,
                          userInfo: [NSLocalizedDescriptionKey: "Mic input format invalid — sample rate \(inputFormat.sampleRate), channels \(inputFormat.channelCount)"])
        }
        print("[GeminiLiveSession] Mic input format: \(inputFormat)")

        // CRITICAL: this callback runs on a real-time audio thread ~40x/sec.
        // Never block it and never hop to the main actor from inside — both
        // will starve Core Audio and cause Gemini's voice to stutter.
        // All work here must be thread-safe and fast.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Skip work entirely while the model is speaking — macOS doesn't
            // do echo cancellation on AVAudioEngine by default, and sending
            // the speaker output back through the mic would trigger Gemini
            // to interrupt itself in an infinite feedback loop.
            let isSpeaking: Bool = self.modelSpeakingLock.withLock { self.modelSpeakingFlag }
            guard !isSpeaking else { return }

            // Compute on audio thread — both are thread-safe CPU work.
            let powerLevel = Self.audioPowerLevel(from: buffer)
            let pcm16Data = self.pcm16Converter.convertToPCM16Data(from: buffer)

            // Fire WebSocket send on a detached task (doesn't need main).
            if let pcm16Data {
                self.geminiClient.sendAudioChunk(pcm16Data)
            }

            // Publish power level to main with minimal overhead. We don't
            // await or block — just schedule the update and return.
            DispatchQueue.main.async { [weak self] in
                self?.currentAudioPowerLevel = powerLevel
            }
        }
        isAudioTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        print("[GeminiLiveSession] Mic capture started")
    }

    private func stopMicCapture() {
        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        currentAudioPowerLevel = 0.0
        print("[GeminiLiveSession] Mic capture stopped")
    }

    /// Compute an RMS-style power level (0-1) from an audio buffer —
    /// used to drive the waveform animation.
    private static func audioPowerLevel(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(frameLength))
        // Clamp to 0-1 range with some amplification so quiet speech still shows
        return CGFloat(min(1.0, rms * 5.0))
    }

    // MARK: - Gemini Event Handling

    private func handleGeminiEvent(_ event: GeminiLiveEvent) {
        switch event {
        case .setupComplete:
            // Already awaited in connect() — nothing to do here.
            break

        case .audioChunk(let pcm24kHzData):
            audioPlayer.enqueueAudioChunk(pcm24kHzData)
            isModelSpeaking = true

        case .inputTranscript(let text):
            // Gemini sends incremental transcripts — accumulate them so the
            // UI sees the full utterance as it builds up.
            inputTranscript += text

        case .outputTranscript(let text):
            outputTranscript += text
            onOutputTranscript?(outputTranscript)

        case .turnComplete:
            isModelSpeaking = false
            onTurnComplete?()
            // Reset transcripts so the next turn starts fresh.
            inputTranscript = ""
            outputTranscript = ""
            toolCallsThisTurn = 0

        case .interrupted:
            // User started speaking while the model was still talking.
            // Drop queued audio without restarting the engine — the model
            // will start streaming new audio for its next response and the
            // player node is ready to accept it immediately.
            audioPlayer.clearQueuedAudio()
            isModelSpeaking = false
            onInterrupted?()

        case .toolCall(let id, let name, let args):
            handleToolCall(id: id, name: name, args: args)

        case .error(let error):
            onError?(error)
            stop()
        }
    }

    // MARK: - Tool Call Dispatch

    /// Track tool calls within the current Gemini turn so we can detect
    /// and warn about duplicate calls (which would narrate twice).
    private var toolCallsThisTurn: Int = 0

    /// Gemini's turn is paused until we send a toolResponse back, so this
    /// runs the handler on a Task and replies as soon as we have a result.
    /// Handlers are resolved from CompanionManager via the onPoint/onWorkflow
    /// callbacks; if neither is set we send a benign empty response so the
    /// model can continue its turn instead of hanging.
    private func handleToolCall(id: String, name: String, args: [String: Any]) {
        toolCallsThisTurn += 1
        if toolCallsThisTurn > 1 {
            print("[GeminiLiveSession] ⚠️ Gemini called \(toolCallsThisTurn) tools in one turn — this will cause double narration. Prompt likely needs tightening.")
        }
        print("[GeminiLiveSession] ← toolCall #\(toolCallsThisTurn) \(name) id=\(id) args=\(args)")

        // Gemini often narrates a short intro ("sure, let me check...") BEFORE
        // emitting the tool call, then a proper response after the tool returns.
        // That reads as "speaking twice" to users. Drop whatever's queued the
        // moment a tool call arrives so only the post-response narration plays.
        audioPlayer.clearQueuedAudio()
        isModelSpeaking = false

        let screenshot = latestCapture?.imageData

        Task {
            var response: [String: Any] = ["ok": false, "error": "tool_unavailable"]

            switch name {
            case "point_at_element":
                let label = (args["label"] as? String) ?? ""
                if !label.isEmpty, let handler = onPointAtElement {
                    response = await handler(label, screenshot)
                } else {
                    print("[GeminiLiveSession] point_at_element called with no handler or empty label")
                }

            case "submit_workflow_plan":
                let goal = (args["goal"] as? String) ?? ""
                let app = (args["app"] as? String) ?? ""
                let steps = (args["steps"] as? [[String: Any]]) ?? []
                if !goal.isEmpty, !steps.isEmpty, let handler = onSubmitWorkflowPlan {
                    response = await handler(goal, app, steps)
                } else {
                    print("[GeminiLiveSession] submit_workflow_plan called with no handler or empty steps")
                }

            default:
                print("[GeminiLiveSession] unknown tool \(name) — ignoring")
                response = ["ok": false, "error": "unknown_tool"]
            }

            print("[GeminiLiveSession] → toolResponse \(name) id=\(id) response=\(response)")
            geminiClient.sendToolResponse(id: id, name: name, response: response)
        }
    }
}
