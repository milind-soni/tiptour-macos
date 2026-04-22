//
//  GeminiLiveClient.swift
//  TipTour
//
//  WebSocket client for Google's Gemini Live API. Single bidirectional
//  streaming connection that handles voice input, vision input, voice
//  output, and text transcription in one model — plus in-stream tool
//  calls for pointing + workflow planning.
//
//  Connection lifecycle:
//  1. connect() opens the WebSocket and sends the initial config message
//  2. Server responds with {"setupComplete": {}} — only then can we send data
//  3. sendAudioChunk() streams PCM16 16kHz mono audio (from the mic)
//  4. sendScreenshot() sends a JPEG frame (max 1 fps per docs)
//  5. Server streams back audio (PCM16 24kHz), input/output transcripts,
//     and turn lifecycle events (turnComplete, interrupted, etc.)
//

import Foundation

/// Events received from the Gemini Live WebSocket.
enum GeminiLiveEvent {
    /// Server is ready to receive audio/image/text input
    case setupComplete

    /// A chunk of PCM16 24kHz audio from the model's voice response
    case audioChunk(Data)

    /// Partial transcript of what the user said (ASR output)
    case inputTranscript(String)

    /// Partial transcript of what the model said (for [POINT:] parsing)
    case outputTranscript(String)

    /// Model finished its turn — safe to send new user input
    case turnComplete

    /// User interrupted the model (barge-in) — discard any queued audio
    case interrupted

    /// Model called one of our registered tools. The app must invoke the
    /// tool, then reply with `sendToolResponse(id:name:response:)` before
    /// Gemini can continue its turn.
    case toolCall(id: String, name: String, args: [String: Any])

    /// The WebSocket closed without us asking it to (server-initiated,
    /// network drop, etc.). The session orchestrator listens for this
    /// and may attempt to reconnect. Distinct from `.error` so the
    /// session can choose to reconnect-and-stay-alive vs surface a
    /// fatal failure to the user.
    case unexpectedDisconnect(Error)

    /// Fatal connection error — client will disconnect
    case error(Error)
}

/// Intentionally NOT @MainActor. `sendAudioChunk` is called from the
/// real-time audio thread (installTap callback) and cannot afford to
/// hop to main on every buffer — that starves Core Audio and causes
/// Gemini's voice playback to stutter. Internal state is protected by
/// `stateLock`. Event callbacks are dispatched to main explicitly.
final class GeminiLiveClient: @unchecked Sendable {

    // MARK: - Configuration

    /// The Gemini Live model ID. Flash-live is the fastest and cheapest.
    /// 3.1 Flash Live is the newer production-leaning model — faster
    /// TTFT (~300-500ms), more stable, fewer of the prompt-adherence
    /// quirks the 2.5 native-audio preview had (double-speak, function-
    /// call hallucination). See AI Studio reference quickstart.
    static let modelID = "models/gemini-3.1-flash-live-preview"

    /// Voice name. `gemini-3.1-flash-live-preview` has a different voice
    /// inventory from 2.5 native-audio — `"Zephyr"` is silently rejected
    /// by 3.1 (server closes socket before setupComplete). `"Kore"` is
    /// confirmed working on 3.1 per Google's capability docs.
    static let defaultVoice = "Kore"

    /// Audio input format: PCM16 16kHz mono, matches what BuddyPCM16AudioConverter produces
    static let inputSampleRate: Double = 16_000

    /// Audio output format: PCM16 24kHz mono — Gemini always returns this rate
    static let outputSampleRate: Double = 24_000

    // MARK: - State (protected by stateLock)

    private let stateLock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var _isConnected: Bool = false
    private var _isSetupComplete: Bool = false

    /// True between an explicit `disconnect()` call and the next `connect()`.
    /// Used to distinguish "user closed" from "server died" inside the
    /// receive loop's error handler — the former should NOT fire the
    /// `.unexpectedDisconnect` event (we don't want to trigger a reconnect
    /// when the user just released push-to-talk).
    private var _wasIntentionallyDisconnected: Bool = false

    /// Periodic no-op ping that prevents Gemini Live's silent idle
    /// disconnect. Per Google's docs the server closes the socket after
    /// roughly 30 minutes of inactivity; we send a benign clientContent
    /// frame every 25 minutes to keep it warm. Cancelled on disconnect().
    private var keepAlivePingTask: Task<Void, Never>?

    /// Interval between keep-alive pings, in seconds. Pulled out of the
    /// Task so it's easy to find and tweak.
    private static let keepAlivePingInterval: TimeInterval = 25 * 60

    var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }
    var isSetupComplete: Bool {
        stateLock.withLock { _isSetupComplete }
    }

    /// Callback invoked on every event received from the server.
    /// Dispatched to the main thread before firing so UI code can update safely.
    var onEvent: ((GeminiLiveEvent) -> Void)?

    private let urlSession: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 0  // no overall timeout — conversations can be long
        self.urlSession = URLSession(configuration: configuration)
    }

    // MARK: - Connection Lifecycle

    /// Opens the WebSocket and sends the initial session config.
    /// Waits until the server responds with setupComplete before returning.
    /// Throws if connection or setup fails.
    func connect(apiKey: String, systemPrompt: String, voice: String = GeminiLiveClient.defaultVoice) async throws {
        guard !isConnected else {
            print("[GeminiLive] Already connected — ignoring connect()")
            return
        }

        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "GeminiLive", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid WebSocket URL"])
        }

        let task = urlSession.webSocketTask(with: url)
        stateLock.withLock {
            self.webSocketTask = task
            self._isConnected = true
            // Clear the intentional-disconnect flag now that we're starting
            // a fresh connection. Any close from this point onward is
            // either user-initiated (sets the flag again) or unexpected.
            self._wasIntentionallyDisconnected = false
        }
        task.resume()
        print("[GeminiLive] WebSocket opened")

        // Start the receive loop so we can pick up the setupComplete event
        startReceiveLoop()

        // Send the setup message. This configures the session — model, voice,
        // response modalities (audio + text transcriptions), system instruction,
        // automatic voice activity detection, AND the tools Gemini can call.
        //
        // Two tools are declared:
        //   - point_at_element(label): single-element pointing for "where's X"
        //     type questions. Fast path — resolves locally via AX + YOLO.
        //   - create_workflow(goal): multi-step plan generation for "how do I X"
        //     walkthroughs. Runs the separate planner model which returns a
        //     JSON plan the voice then narrates in sync.
        //
        // Gemini chooses which tool to call based on the user's request. This
        // replaces the brittle [POINT:] tag parsing from spoken transcripts.
        let pointAtElementTool: [String: Any] = [
            "name": "point_at_element",
            "description": "Fly the cursor to a single visible UI element on the user's screen. Use for simple 'where is X' / 'point at X' questions where ONE element is all that's needed and it's visible right now.",
            "parameters": [
                "type": "object",
                "properties": [
                    "label": [
                        "type": "string",
                        "description": "The literal visible text of the element — e.g. 'Save', 'File', 'Source Control'. Use the actual text on screen, not a description."
                    ]
                ],
                "required": ["label"]
            ]
        ]
        // submit_workflow_plan folds the old planner model into this
        // single tool call. Gemini Live has vision + reasoning; it can
        // produce the plan itself without a second round-trip to a
        // separate planner API. The cursor moves the moment the tool
        // call arrives, in perfect sync with the speech that follows.
        let submitWorkflowPlanTool: [String: Any] = [
            "name": "submit_workflow_plan",
            "description": "For any multi-step walkthrough (opening a menu then picking an item, 'how do I X', 'walk me through Y', 'teach me Z'). Emit the FULL plan of steps as a structured argument. Gemini narrates each step after the tool returns, while the cursor flies through them in order.",
            "parameters": [
                "type": "object",
                "properties": [
                    "goal": [
                        "type": "string",
                        "description": "Short natural-language summary of what the user wants to accomplish."
                    ],
                    "app": [
                        "type": "string",
                        "description": "EXACT name of the foreground application visible in the screenshot — e.g. 'Blender', 'Xcode', 'GarageBand'. Used to target the right accessibility tree. Do NOT guess 'macOS' or 'unknown'."
                    ],
                    "steps": [
                        "type": "array",
                        "description": "Ordered list of steps. First step MUST be visible on the current screen; later steps describe the path to take after clicking step 1.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "label": [
                                    "type": "string",
                                    "description": "Literal visible text of the element, or nearest label for an icon."
                                ],
                                "hint": [
                                    "type": "string",
                                    "description": "Short sentence describing this step — e.g. 'Open the File menu'."
                                ],
                                "x": [
                                    "type": "integer",
                                    "description": "Optional pixel x-coordinate in the screenshot's coordinate space. Only needed for step 1, and only if the app lacks accessibility support (Blender, games, canvas tools)."
                                ],
                                "y": [
                                    "type": "integer",
                                    "description": "Optional pixel y-coordinate in the screenshot's coordinate space."
                                ]
                            ],
                            "required": ["label"]
                        ]
                    ]
                ],
                "required": ["goal", "app", "steps"]
            ]
        ]

        let setupMessage: [String: Any] = [
            "setup": [
                "model": Self.modelID,
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    // Server-side image-processing resolution for
                    // screenshots we stream in. MEDIUM matches the AI
                    // Studio reference. On 3.1 Flash Live this field
                    // lives INSIDE generationConfig (putting it at the
                    // setup top level is rejected by the newer schema).
                    "mediaResolution": "MEDIA_RESOLUTION_MEDIUM",
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": voice
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [["text": systemPrompt]]
                ],
                // Enable server-side transcription of both sides of the conversation.
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
                // Context-window compression — once accumulated tokens
                // pass `triggerTokens`, Gemini silently summarizes the
                // oldest turns down to `targetTokens` and keeps the
                // session alive. Without this, long sessions with many
                // screenshots (we send one every ~1.5s) hit the context
                // limit and the server starts dropping responses. Values
                // match the AI Studio quickstart reference.
                "contextWindowCompression": [
                    "triggerTokens": 104857,
                    "slidingWindow": [
                        "targetTokens": 52428
                    ]
                ],
                "tools": [
                    ["functionDeclarations": [pointAtElementTool, submitWorkflowPlanTool]]
                ]
            ]
        ]

        try await sendJSON(setupMessage)

        // Wait for setupComplete before allowing audio/image input.
        // The receive loop will flip isSetupComplete and fire the .setupComplete event.
        let setupDeadline = Date().addingTimeInterval(10)
        while !isSetupComplete {
            if Date() > setupDeadline {
                disconnect()
                throw NSError(domain: "GeminiLive", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Setup timeout — no setupComplete after 10s"])
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    /// Closes the WebSocket and cleans up state. Marks the disconnect as
    /// intentional so the receive loop won't fire `.unexpectedDisconnect`
    /// on the way out.
    func disconnect() {
        let (capturedReceiveTask, capturedWebSocketTask, capturedKeepAliveTask) = stateLock.withLock {
            let taken = (receiveLoopTask, webSocketTask, keepAlivePingTask)
            receiveLoopTask = nil
            webSocketTask = nil
            keepAlivePingTask = nil
            _isConnected = false
            _isSetupComplete = false
            _wasIntentionallyDisconnected = true
            return taken
        }
        capturedReceiveTask?.cancel()
        capturedKeepAliveTask?.cancel()
        capturedWebSocketTask?.cancel(with: .normalClosure, reason: nil)
        print("[GeminiLive] WebSocket closed")
    }

    // MARK: - Keep-Alive

    /// Spin up a long-running task that fires a no-op clientContent ping
    /// every `keepAlivePingInterval` seconds to keep Gemini's session
    /// from silently idle-disconnecting. The ping is an empty turn —
    /// the server accepts it without producing any audio response.
    /// Cancels itself the moment the WebSocket goes away.
    private func startKeepAlivePingLoop() {
        // Cancel any prior ping task before starting a new one — happens
        // on reconnects where setupComplete fires a second time.
        let priorTask = stateLock.withLock { keepAlivePingTask }
        priorTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.keepAlivePingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                // Skip the ping if we've drifted out of the connected state.
                guard self.isSetupComplete else { return }
                let pingMessage: [String: Any] = [
                    "clientContent": [
                        "turns": [
                            ["role": "user", "parts": [["text": ""]]]
                        ],
                        "turnComplete": false
                    ]
                ]
                do {
                    try await self.sendJSON(pingMessage)
                    print("[GeminiLive] Sent keep-alive ping")
                } catch {
                    print("[GeminiLive] Keep-alive ping failed: \(error.localizedDescription)")
                }
            }
        }
        stateLock.withLock { keepAlivePingTask = task }
    }

    // MARK: - Sending Data

    /// Send a chunk of PCM16 16kHz mono audio from the microphone.
    /// Callable from any thread — the audio tap calls this on the real-time
    /// audio thread so we must NOT hop to main. WebSocket .send() is
    /// thread-safe under the hood.
    func sendAudioChunk(_ pcm16Data: Data) {
        guard isSetupComplete else { return }
        let base64Audio = pcm16Data.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": base64Audio,
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
        Task {
            try? await self.sendJSON(message)
        }
    }

    /// Send a screenshot (JPEG data) so Gemini can see the user's screen.
    /// Per docs: max 1 frame per second, will be resized server-side.
    func sendScreenshot(_ jpegData: Data) {
        guard isSetupComplete else { return }
        let base64Image = jpegData.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "video": [
                    "data": base64Image,
                    "mimeType": "image/jpeg"
                ]
            ]
        ]
        Task {
            try? await self.sendJSON(message)
        }
    }

    /// Send a text message — useful for seeding context or asking without speaking.
    func sendText(_ text: String) {
        guard isSetupComplete else { return }
        let message: [String: Any] = [
            "realtimeInput": [
                "text": text
            ]
        ]
        Task {
            try? await self.sendJSON(message)
        }
    }

    /// How the model should handle the tool response relative to any
    /// audio it's currently speaking. Used only when the tool is
    /// declared `NON_BLOCKING`; sequential tools ignore it.
    enum ToolResponseScheduling: String {
        /// Cut current audio and speak the result immediately. Right for
        /// tools whose result the user is actively waiting on.
        case interrupt = "INTERRUPT"
        /// Wait for current audio (the conversational filler) to finish,
        /// then speak the result. Right for acknowledgment-style UX
        /// where you want the filler to land cleanly.
        case whenIdle = "WHEN_IDLE"
        /// Accept the result silently into context — don't speak. Right
        /// for background updates the model just needs to "know".
        case silent = "SILENT"
    }

    /// Reply to a tool call Gemini made. The model's turn is paused until
    /// this response arrives — it uses the result to continue narrating.
    /// The `response` dictionary is serialized as-is into the toolResponse
    /// envelope; keep it small and JSON-serializable.
    ///
    /// Pass a `scheduling` value for NON_BLOCKING tools so the post-tool
    /// narration queues correctly relative to any filler audio the model
    /// is currently speaking. Omit it for sequential tools.
    func sendToolResponse(
        id: String,
        name: String,
        response: [String: Any],
        scheduling: ToolResponseScheduling? = nil
    ) {
        guard isSetupComplete else { return }
        var functionResponse: [String: Any] = [
            "id": id,
            "name": name,
            "response": response
        ]
        if let scheduling {
            functionResponse["scheduling"] = scheduling.rawValue
        }
        let message: [String: Any] = [
            "toolResponse": [
                "functionResponses": [functionResponse]
            ]
        ]
        Task {
            try? await self.sendJSON(message)
        }
    }

    // MARK: - WebSocket I/O

    private func sendJSON(_ message: [String: Any]) async throws {
        let task = stateLock.withLock { webSocketTask }
        guard let task else { return }
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GeminiLive", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON as UTF-8"])
        }
        try await task.send(.string(jsonString))
    }

    private func startReceiveLoop() {
        let loopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                let task = self.stateLock.withLock { self.webSocketTask }
                guard let task else { break }
                do {
                    let message = try await task.receive()
                    await self.handleIncomingMessage(message)
                } catch {
                    if !Task.isCancelled {
                        // Distinguish a user-initiated close from a
                        // server/network-initiated one. The former is
                        // expected (push-to-talk released, app quit) and
                        // shouldn't surface anything; the latter should
                        // give the session a chance to reconnect.
                        let wasIntentional = self.stateLock.withLock { self._wasIntentionallyDisconnected }
                        if wasIntentional {
                            print("[GeminiLive] Receive loop ended after intentional disconnect")
                        } else {
                            print("[GeminiLive] Unexpected disconnect: \(error.localizedDescription)")
                            self.dispatchEvent(.unexpectedDisconnect(error))
                            self.disconnect()
                        }
                    }
                    break
                }
            }
        }
        stateLock.withLock { receiveLoopTask = loopTask }
    }

    private func dispatchEvent(_ event: GeminiLiveEvent) {
        // Callers expect onEvent to fire on main — Gemini events often
        // drive SwiftUI state updates (isModelSpeaking, waveform, etc.).
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func handleIncomingMessage(_ message: URLSessionWebSocketTask.Message) async {
        // Gemini sends messages either as JSON text frames OR as binary JSON data.
        // Handle both formats.
        let rawData: Data
        switch message {
        case .data(let data):
            rawData = data
        case .string(let text):
            rawData = text.data(using: .utf8) ?? Data()
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            print("[GeminiLive] Failed to parse message as JSON")
            return
        }

        // 1. Setup complete — we're ready to send input
        if json["setupComplete"] != nil {
            stateLock.withLock { _isSetupComplete = true }
            print("[GeminiLive] Setup complete")
            startKeepAlivePingLoop()
            dispatchEvent(.setupComplete)
            return
        }

        // 2. Server content — contains model turn audio, transcriptions, lifecycle flags
        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
            return
        }

        // 3. Tool call — Gemini wants us to run one of the registered tools
        //    (point_at_element or create_workflow). Its turn is paused until
        //    we reply via sendToolResponse.
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                let id = (call["id"] as? String) ?? ""
                let name = (call["name"] as? String) ?? ""
                let args = (call["args"] as? [String: Any]) ?? [:]
                print("[GeminiLive] toolCall \(name)(\(args)) id=\(id)")
                dispatchEvent(.toolCall(id: id, name: name, args: args))
            }
            return
        }

        // 4. goAway — server will disconnect soon, we should reconnect proactively
        if let goAway = json["goAway"] as? [String: Any] {
            print("[GeminiLive] Server signaled goAway: \(goAway)")
            return
        }

        // Unknown message shape — log and move on
        print("[GeminiLive] Unhandled message: \(json.keys)")
    }

    private func handleServerContent(_ serverContent: [String: Any]) {
        // Audio chunks from the model's voice response — and, occasionally,
        // inline function calls that Gemini Live emits inside modelTurn.parts
        // instead of as a top-level toolCall envelope.
        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   mimeType.hasPrefix("audio/pcm"),
                   let base64Audio = inlineData["data"] as? String,
                   let audioData = Data(base64Encoded: base64Audio) {
                    dispatchEvent(.audioChunk(audioData))
                }

                // Inline function call form — same payload as a toolCall, just
                // embedded in the model's turn. Gemini Live's docs aren't
                // fully consistent about which envelope it uses, so handle both.
                if let functionCall = part["functionCall"] as? [String: Any] {
                    let id = (functionCall["id"] as? String) ?? ""
                    let name = (functionCall["name"] as? String) ?? ""
                    let args = (functionCall["args"] as? [String: Any]) ?? [:]
                    print("[GeminiLive] inline functionCall \(name)(\(args)) id=\(id)")
                    dispatchEvent(.toolCall(id: id, name: name, args: args))
                }
            }
        }

        if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
           let text = inputTranscription["text"] as? String {
            dispatchEvent(.inputTranscript(text))
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            dispatchEvent(.outputTranscript(text))
        }

        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            dispatchEvent(.interrupted)
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            dispatchEvent(.turnComplete)
        }
    }
}

/// Minimal withLock helper — NSLocking gets this in Swift 5.9+ but we
/// define it here explicitly so the build doesn't depend on toolchain.
extension NSLocking {
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        self.lock()
        defer { self.unlock() }
        return try body()
    }
}
