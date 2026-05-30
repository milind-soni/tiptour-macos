import Foundation

final class TipTourFollowAlongTraceStore {
    static let shared = TipTourFollowAlongTraceStore()

    struct Record: Codable {
        let schemaVersion: Int
        let timestamp: String
        let runID: String
        let traceID: String
        let stepIndex: Int
        let stepCount: Int
        let sourceText: String
        let targetApp: String?
        let draftStep: WorkflowStep
        let preparedStep: WorkflowStep?
        let preState: StateSnapshot
        let stateActionState: StateSnapshot
        let postState: StateSnapshot?
        let chosenTarget: TargetSummary?
        let result: ResultSummary

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case timestamp
            case runID = "run_id"
            case traceID = "trace_id"
            case stepIndex = "step_index"
            case stepCount = "step_count"
            case sourceText = "source_text"
            case targetApp = "target_app"
            case draftStep = "draft_step"
            case preparedStep = "prepared_step"
            case preState = "pre_state"
            case stateActionState = "state_action_state"
            case postState = "post_state"
            case chosenTarget = "chosen_target"
            case result
        }
    }

    struct StateSnapshot: Codable {
        let snapshotID: String?
        let capturedAt: String?
        let activeAppName: String?
        let activeBundleIdentifier: String?
        let visualMode: String?
        let screenshotIncluded: Bool
        let screenChangedSinceLastSnapshot: Bool?
        let screenshotHash: String?
        let targetCount: Int
        let targets: [TargetSummary]

        enum CodingKeys: String, CodingKey {
            case snapshotID = "snapshot_id"
            case capturedAt = "captured_at"
            case activeAppName = "active_app_name"
            case activeBundleIdentifier = "active_bundle_identifier"
            case visualMode = "visual_mode"
            case screenshotIncluded = "screenshot_included"
            case screenChangedSinceLastSnapshot = "screen_changed_since_last_snapshot"
            case screenshotHash = "screenshot_hash"
            case targetCount = "target_count"
            case targets
        }

        init(
            visualContext: TipTourEngineVisualContextSnapshot,
            fullTargets: [LocalPerceptionTargetCache.SnapshotTarget],
            targetLimit: Int = 80
        ) {
            snapshotID = visualContext.snapshotID
            capturedAt = visualContext.capturedAt
            activeAppName = visualContext.activeAppName
            activeBundleIdentifier = visualContext.activeBundleIdentifier
            visualMode = visualContext.decision.mode
            screenshotIncluded = visualContext.decision.screenshotIncluded
            screenChangedSinceLastSnapshot = visualContext.decision.screenChangedSinceLastSnapshot
            screenshotHash = visualContext.screenshotHash
            targetCount = fullTargets.count
            targets = fullTargets.prefix(targetLimit).map(TargetSummary.init)
        }
    }

    struct TargetSummary: Codable {
        let id: String
        let mark: Int
        let label: String
        let source: String
        let confidence: Double
        let box2D: [Int]
        let globalCenter: [Double]
        let globalBox: [Double]

        enum CodingKeys: String, CodingKey {
            case id
            case mark
            case label
            case source
            case confidence
            case box2D = "box_2d"
            case globalCenter = "global_center"
            case globalBox = "global_box"
        }

        init(_ target: LocalPerceptionTargetCache.SnapshotTarget) {
            id = target.id
            mark = target.mark
            label = target.label
            source = target.source
            confidence = target.confidence
            box2D = target.normalizedBox2D
            globalCenter = target.globalCenter
            globalBox = target.globalBox
        }
    }

    struct ResultSummary: Codable {
        let ok: Bool
        let stage: String
        let status: String
        let reason: String?
        let message: String?
        let activeApp: String?
        let workflowStatus: String?
        let workflowWaitMs: Int?
        let targetCountAfterAction: Int?

        enum CodingKeys: String, CodingKey {
            case ok
            case stage
            case status
            case reason
            case message
            case activeApp = "active_app"
            case workflowStatus = "workflow_status"
            case workflowWaitMs = "workflow_wait_ms"
            case targetCountAfterAction = "target_count_after_action"
        }

        static func preflightFailure(_ message: String) -> ResultSummary {
            ResultSummary(
                ok: false,
                stage: "preflight",
                status: "failed",
                reason: "preflight_failed",
                message: message,
                activeApp: nil,
                workflowStatus: nil,
                workflowWaitMs: nil,
                targetCountAfterAction: nil
            )
        }

        init(submission: TipTourEngineSubmissionResult) {
            ok = submission.ok
            stage = "execution"
            status = submission.ok ? "ok" : "failed"
            reason = submission.reason
            message = submission.message
            activeApp = submission.activeApp
            workflowStatus = submission.workflowOutcome?.status
            workflowWaitMs = submission.workflowOutcome?.waitMs
            targetCountAfterAction = submission.targetCountAfterAction
        }

        private init(
            ok: Bool,
            stage: String,
            status: String,
            reason: String?,
            message: String?,
            activeApp: String?,
            workflowStatus: String?,
            workflowWaitMs: Int?,
            targetCountAfterAction: Int?
        ) {
            self.ok = ok
            self.stage = stage
            self.status = status
            self.reason = reason
            self.message = message
            self.activeApp = activeApp
            self.workflowStatus = workflowStatus
            self.workflowWaitMs = workflowWaitMs
            self.targetCountAfterAction = targetCountAfterAction
        }
    }

    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private init() {}

    func makeRunID() -> String {
        "follow_\(UUID().uuidString.prefix(8))"
    }

    @discardableResult
    func append(_ record: Record) throws -> URL {
        let fileURL = try traceFileURL(for: record.runID)
        let data = try encoder.encode(record)
        guard let line = String(data: data, encoding: .utf8)?.appending("\n"),
              let lineData = line.data(using: .utf8) else {
            throw failure("Could not encode follow-along trace record.")
        }

        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } else {
            try lineData.write(to: fileURL, options: .atomic)
        }
        return fileURL
    }

    func readTrace(runID: String) throws -> String {
        let fileURL = try traceFileURL(for: runID)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func decodeRecords(from jsonl: String) -> [Record] {
        jsonl
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Record? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(Record.self, from: data)
            }
    }

    private func traceFileURL(for runID: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TipTour/follow-along-traces", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(runID).jsonl")
    }

    private func failure(_ message: String) -> NSError {
        NSError(
            domain: "TipTourFollowAlongTraceStore",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
