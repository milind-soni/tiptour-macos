//
//  PipecatVoiceHarnessClient.swift
//  TipTour
//
//  Lightweight contract for a local Pipecat sidecar. TipTour remains the
//  macOS pointer/action engine; Pipecat can own realtime voice I/O and call
//  the local TipTour and Hermes HTTP tools.
//

import Foundation

enum PipecatVoiceHarnessConnectionState: Equatable {
    case idle
    case checking
    case connected
    case notRunning
    case wrongServer
    case error

    var title: String {
        switch self {
        case .idle: return "Not checked"
        case .checking: return "Checking"
        case .connected: return "Connected"
        case .notRunning: return "Not running"
        case .wrongServer: return "Wrong server"
        case .error: return "Error"
        }
    }
}

struct PipecatVoiceHarnessConnectionStatus: Equatable {
    var state: PipecatVoiceHarnessConnectionState
    var baseURL: String
    var detail: String
    var isActive: Bool
    var isPipecatInstalled: Bool?

    static let idle = PipecatVoiceHarnessConnectionStatus(
        state: .idle,
        baseURL: PipecatVoiceHarnessClient.defaultBaseURL.absoluteString,
        detail: "Pipecat voice sidecar has not been checked yet.",
        isActive: false,
        isPipecatInstalled: nil
    )
}

struct PipecatVoiceHarnessHealth: Decodable {
    let ok: Bool
    let service: String?
    let message: String?
    let active: Bool?
    let mode: String?
    let provider: String?
    let lastError: String?
    let pipecat: PipecatRuntimeStatus?

    enum CodingKeys: String, CodingKey {
        case ok
        case service
        case message
        case active
        case mode
        case provider
        case lastError = "last_error"
        case pipecat
    }

    struct PipecatRuntimeStatus: Decodable, Equatable {
        let installed: Bool?
        let importReady: Bool?
        let version: String?
        let importError: String?

        enum CodingKeys: String, CodingKey {
            case installed
            case importReady = "import_ready"
            case version
            case importError = "import_error"
        }
    }
}

struct PipecatVoiceHarnessStartRequest: Encodable {
    let tipTourBaseURL: String
    let hermesBaseURL: String
    let mode: String
    let provider: String?
    let googleAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case tipTourBaseURL = "tiptour_base_url"
        case hermesBaseURL = "hermes_base_url"
        case mode
        case provider
        case googleAPIKey = "google_api_key"
    }
}

struct PipecatVoiceHarnessEvents: Decodable {
    let ok: Bool
    let active: Bool?
    let sessionID: String?
    let events: [PipecatVoiceHarnessEvent]

    enum CodingKeys: String, CodingKey {
        case ok
        case active
        case sessionID = "session_id"
        case events
    }
}

struct PipecatVoiceHarnessEvent: Decodable, Equatable {
    let id: String
    let type: String
    let message: String
    let timestamp: Double
}

struct PipecatVoiceHarnessClient {
    static let defaultBaseURL = URL(string: "http://127.0.0.1:7860")!

    let baseURL: URL

    init(baseURL: URL = Self.defaultBaseURL) {
        self.baseURL = baseURL
    }

    func health() async throws -> PipecatVoiceHarnessHealth {
        let (data, response) = try await request(path: "v1/health")
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Pipecat harness health",
            errorDomain: "PipecatVoiceHarnessClient"
        )
        return try JSONDecoder().decode(PipecatVoiceHarnessHealth.self, from: data)
    }

    func start(
        tipTourBaseURL: String = "http://127.0.0.1:19474",
        hermesBaseURL: String = TipTourDefaults.hermesAPIBaseURL,
        googleAPIKey: String? = KeychainStore.geminiAPIKey
    ) async throws -> PipecatVoiceHarnessHealth {
        let payload = PipecatVoiceHarnessStartRequest(
            tipTourBaseURL: tipTourBaseURL,
            hermesBaseURL: hermesBaseURL,
            mode: "gemini-live-local",
            provider: "gemini-live",
            googleAPIKey: googleAPIKey
        )
        let (data, response) = try await request(
            path: "v1/start",
            method: "POST",
            body: JSONEncoder().encode(payload)
        )
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Pipecat harness start",
            errorDomain: "PipecatVoiceHarnessClient"
        )
        return try JSONDecoder().decode(PipecatVoiceHarnessHealth.self, from: data)
    }

    func stop() async throws -> PipecatVoiceHarnessHealth {
        let (data, response) = try await request(path: "v1/stop", method: "POST")
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Pipecat harness stop",
            errorDomain: "PipecatVoiceHarnessClient"
        )
        return try JSONDecoder().decode(PipecatVoiceHarnessHealth.self, from: data)
    }

    func events() async throws -> PipecatVoiceHarnessEvents {
        let (data, response) = try await request(path: "v1/events")
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Pipecat harness events",
            errorDomain: "PipecatVoiceHarnessClient"
        )
        return try JSONDecoder().decode(PipecatVoiceHarnessEvents.self, from: data)
    }

    func testConnection() async -> PipecatVoiceHarnessConnectionStatus {
        do {
            let health = try await health()
            guard health.service == "tiptour-pipecat-voice" else {
                return PipecatVoiceHarnessConnectionStatus(
                    state: .wrongServer,
                    baseURL: baseURL.absoluteString,
                    detail: "A server answered on \(baseURL.absoluteString), but it does not look like the TipTour Pipecat sidecar.",
                    isActive: health.active ?? false,
                    isPipecatInstalled: health.pipecat?.installed
                )
            }

            let pipecatDetail: String
            if health.pipecat?.installed == true {
                pipecatDetail = "Pipecat runtime is installed."
            } else {
                pipecatDetail = "Install the optional Pipecat runtime when you are ready for realtime transport."
            }

            return PipecatVoiceHarnessConnectionStatus(
                state: .connected,
                baseURL: baseURL.absoluteString,
                detail: "Sidecar is reachable at \(baseURL.absoluteString). \(pipecatDetail)",
                isActive: health.active ?? false,
                isPipecatInstalled: health.pipecat?.installed
            )
        } catch {
            return PipecatVoiceHarnessConnectionStatus(
                state: .notRunning,
                baseURL: baseURL.absoluteString,
                detail: "No Pipecat sidecar answered on \(baseURL.absoluteString).",
                isActive: false,
                isPipecatInstalled: nil
            )
        }
    }

    private func request(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 3.0
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        return try await URLSession.shared.data(for: request)
    }

    static let tipTourToolInstructions = """
    You are Pipecat running as TipTour's local realtime voice harness.

    TipTour is the macOS pointer, perception, and action engine. Do not guess desktop coordinates yourself. Use TipTour's localhost harness for observation, grounding, pointer animation, and actions.

    TipTour tools:
    - GET http://127.0.0.1:19474/v1/observe
    - GET http://127.0.0.1:19474/v1/skills
    - GET http://127.0.0.1:19474/v1/skills/active
    - GET http://127.0.0.1:19474/v1/targets
    - GET http://127.0.0.1:19474/v1/action-history
    - POST http://127.0.0.1:19474/v1/plan-next-action
    - POST http://127.0.0.1:19474/v1/workflow-plan

    For visible UI clicks, prefer /v1/targets and /v1/plan-next-action with target_id or target_mark. For keys, typing, app launch, and scrolling, use /v1/workflow-plan with exactly one step. TipTour executes one action at a time and validates after each action.
    """

    static let hermesDelegationInstructions = """
    Hermes is the optional long-horizon planner. Use it when the user asks for a multi-step task, repeated work, memory-heavy reasoning, or a workflow that needs to continue across many observations.

    Hermes endpoint:
    - POST http://127.0.0.1:8642/v1/chat/completions

    Pipecat should not duplicate Hermes planning. For long tasks, delegate the high-level request to Hermes and let Hermes call TipTour's harness tools. Keep realtime voice responses short while Hermes works.
    """
}
