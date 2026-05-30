import Foundation

struct TipTourFollowAlongFrameReference: Identifiable, Hashable, Sendable {
    let id: String
    let fileURL: URL
    let timestampSeconds: Double?

    init(fileURL: URL, index: Int, timestampSeconds: Double? = nil) {
        self.id = "frame_\(index)"
        self.fileURL = fileURL
        self.timestampSeconds = timestampSeconds
    }

    var displayName: String {
        if let timestampSeconds {
            return "\(id) @ \(Self.timestamp(timestampSeconds))"
        }
        return id
    }

    private static func timestamp(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct TipTourFollowAlongVisualStep: Codable, Hashable, Sendable {
    let transcriptHint: String?
    let visualRegion: String?
    let visibleLabels: [String]?
    let liveGroundingQuery: String?
    let actionKind: String?
    let confidence: Double?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case transcriptHint = "transcript_hint"
        case visualRegion = "visual_region"
        case visibleLabels = "visible_labels"
        case liveGroundingQuery = "live_grounding_query"
        case actionKind = "action_kind"
        case confidence
        case notes
    }
}

struct TipTourFollowAlongEnrichment: Sendable {
    let model: String
    let summary: String
    let steps: [TipTourFollowAlongVisualStep]
    let manualCheckpoints: [String]
    let frameCount: Int
    let rawResponseText: String

    var plannerContext: String {
        var lines: [String] = []
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Video summary: \(summary)")
        }

        let stepLines = steps.prefix(40).enumerated().map { index, step in
            let labels = step.visibleLabels?.prefix(8).joined(separator: ", ") ?? ""
            let query = step.liveGroundingQuery ?? ""
            let region = step.visualRegion ?? "unknown"
            let action = step.actionKind ?? "unknown"
            let notes = step.notes ?? ""
            return "\(index + 1). action=\(action); region=\(region); query=\(query); labels=[\(labels)]; notes=\(notes)"
        }
        if !stepLines.isEmpty {
            lines.append("Visual grounding hints:\n\(stepLines.joined(separator: "\n"))")
        }

        if !manualCheckpoints.isEmpty {
            lines.append("Manual/visual checkpoints:\n\(manualCheckpoints.prefix(20).joined(separator: "\n"))")
        }

        if lines.isEmpty {
            return rawResponseText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.joined(separator: "\n\n")
    }
}

struct TipTourFollowAlongVisualHistoryItem: Hashable, Sendable {
    struct Screenshot: Hashable, Sendable {
        let label: String
        let mediaType: String
        let dataURL: String
    }

    let snapshotID: String
    let capturedAt: String
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let screenshotHash: String?
    let targetCount: Int
    let targetLabels: [String]
    let screenshots: [Screenshot]

    var hasScreenshots: Bool {
        !screenshots.isEmpty
    }

    var promptSummary: String {
        let labels = targetLabels.prefix(24).joined(separator: ", ")
        return """
        snapshot_id=\(snapshotID)
        captured_at=\(capturedAt)
        active_app=\(activeAppName ?? "unknown")
        active_bundle=\(activeBundleIdentifier ?? "unknown")
        screenshot_hash=\(screenshotHash ?? "none")
        target_count=\(targetCount)
        visible_labels=\(labels)
        """
    }

    init(
        visualContext: TipTourEngineVisualContextSnapshot,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) {
        snapshotID = visualContext.snapshotID
        capturedAt = visualContext.capturedAt
        activeAppName = visualContext.activeAppName
        activeBundleIdentifier = visualContext.activeBundleIdentifier
        screenshotHash = visualContext.screenshotHash
        targetCount = targets.count
        targetLabels = Array(targets
            .map(\.label)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(36))
        screenshots = Array(visualContext.screenshots.prefix(1)).map {
            Screenshot(
                label: $0.label,
                mediaType: $0.mediaType,
                dataURL: $0.dataURL
            )
        }
    }
}
