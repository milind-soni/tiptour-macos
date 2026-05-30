//
//  TipTourEngine.swift
//  TipTour
//
//  Thin engine facade for callers that should not know about
//  CompanionManager. Keep this small: it centralizes observe + one-action
//  workflow submission before we add richer ground/act/record APIs.
//

import AppKit
import Foundation
import ImageIO

struct TipTourEngineSubmissionResult: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let traceID: String?
    let acceptedSteps: Int
    let ignoredSteps: Int
    let activeApp: String?
    let workflowOutcome: TipTourEngineWorkflowOutcome?
    let targetCountAfterAction: Int?

    private enum CodingKeys: String, CodingKey {
        case ok
        case reason
        case message
        case traceID = "trace_id"
        case acceptedSteps
        case ignoredSteps
        case activeApp
        case workflowOutcome
        case targetCountAfterAction
    }

    init(
        ok: Bool,
        reason: String?,
        message: String?,
        traceID: String? = nil,
        acceptedSteps: Int,
        ignoredSteps: Int,
        activeApp: String?,
        workflowOutcome: TipTourEngineWorkflowOutcome? = nil,
        targetCountAfterAction: Int? = nil
    ) {
        self.ok = ok
        self.reason = reason
        self.message = message
        self.traceID = traceID
        self.acceptedSteps = acceptedSteps
        self.ignoredSteps = ignoredSteps
        self.activeApp = activeApp
        self.workflowOutcome = workflowOutcome
        self.targetCountAfterAction = targetCountAfterAction
    }
}

struct TipTourEngineObservation: Encodable {
    let ok: Bool
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let activePlanGoal: String?
    let isAutopilotEnabled: Bool
    let isScreenshotStreamingEnabled: Bool
    let isAccurateGroundingEnabled: Bool
    let isCuaActionDriverEnabled: Bool
    let isHermesOrchestratorEnabled: Bool
    let detectionElementCount: Int
    let externalHarnessVisualContext: String
}

struct TipTourEngineSkillList: Encodable {
    let ok: Bool
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let skillCount: Int
    let skills: [MarkdownAppSkillInfo]
}

struct TipTourEngineActiveSkill: Encodable {
    let ok: Bool
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let skill: MarkdownAppSkillInfo?
}

struct TipTourEngineTargetList: Encodable {
    let ok: Bool
    let refreshed: Bool
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let targetCount: Int
    let targets: [LocalPerceptionTargetCache.SnapshotTarget]
}

struct TipTourEngineGroundedTarget: Encodable {
    let targetID: String
    let targetMark: Int
    let label: String
    let source: String
    let confidence: Double
    let box2D: [Int]
    let globalCenter: [Double]
    let globalBox: [Double]
    let displayFrame: [Double]
    let cacheAgeMs: Int

    init(_ target: LocalPerceptionTargetCache.SnapshotTarget) {
        self.targetID = target.id
        self.targetMark = target.mark
        self.label = target.label
        self.source = target.source
        self.confidence = target.confidence
        self.box2D = target.normalizedBox2D
        self.globalCenter = target.globalCenter
        self.globalBox = target.globalBox
        self.displayFrame = target.displayFrame
        self.cacheAgeMs = target.cacheAgeMs
    }
}

struct TipTourEngineGroundTargetResult: Encodable {
    let ok: Bool
    let traceID: String
    let reason: String?
    let message: String?
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let refreshed: Bool
    let goal: String
    let query: String?
    let actionType: String
    let candidateCount: Int
    let matchedBy: String?
    let aiMatchLatencyMs: Int?
    let target: TipTourEngineGroundedTarget?

    private enum CodingKeys: String, CodingKey {
        case ok
        case traceID = "trace_id"
        case reason
        case message
        case activeAppName
        case activeBundleIdentifier
        case refreshed
        case goal
        case query
        case actionType
        case candidateCount
        case matchedBy
        case aiMatchLatencyMs
        case target
    }
}

struct TipTourEngineScreenshotList: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let screenshotCount: Int
    let screenshots: [TipTourEngineScreenshot]
}

struct TipTourEngineScreenshot: Encodable {
    let label: String
    let isCursorScreen: Bool
    let displayWidthInPoints: Int
    let displayHeightInPoints: Int
    let screenshotWidthInPixels: Int
    let screenshotHeightInPixels: Int
    let capturedAt: String
    let mediaType: String
    let dataURL: String
}

struct TipTourEngineVisualContextDecision: Encodable {
    let mode: String
    let requestedMode: String
    let reasons: [String]
    let screenshotAllowed: Bool
    let screenshotIncluded: Bool
    let screenChangedSinceLastSnapshot: Bool?
}

struct TipTourEngineVisualContextSnapshot: Encodable {
    let ok: Bool
    let traceID: String?
    let reason: String?
    let message: String?
    let snapshotID: String
    let capturedAt: String
    let activeAppName: String?
    let activeBundleIdentifier: String?
    let activePlanGoal: String?
    let intent: String?
    let decision: TipTourEngineVisualContextDecision
    let targetCount: Int
    let targets: [TipTourEngineGroundedTarget]
    let focusTarget: TipTourEngineGroundedTarget?
    let screenshotHash: String?
    let screenshots: [TipTourEngineScreenshot]

    private enum CodingKeys: String, CodingKey {
        case ok
        case traceID = "trace_id"
        case reason
        case message
        case snapshotID
        case capturedAt
        case activeAppName
        case activeBundleIdentifier
        case activePlanGoal
        case intent
        case decision
        case targetCount
        case targets
        case focusTarget
        case screenshotHash
        case screenshots
    }
}

private struct TipTourVisualContextScreenshotCaptureResult {
    let screenshots: [TipTourEngineScreenshot]
    let hash: UInt64?
    let changed: Bool?
    let failure: String?
    let actualMode: String?

    static let empty = TipTourVisualContextScreenshotCaptureResult(
        screenshots: [],
        hash: nil,
        changed: nil,
        failure: nil,
        actualMode: nil
    )
}

struct TipTourEnginePlannedActionStep: Encodable {
    let type: String
    let label: String
    let targetID: String
    let targetMark: Int
    let hint: String
    let box2D: [Int]
    let matchedSource: String
    let matchedConfidence: Double
}

struct TipTourEngineWorkflowOutcome: Encodable {
    let status: String
    let reason: String?
    let message: String?
    let waitMs: Int
}

struct TipTourEngineActionValidation: Encodable {
    let stateChanged: Bool
    let requiredStateChange: Bool
    let beforeTargetCount: Int
    let afterTargetCount: Int
}

struct TipTourEngineActionAttempt: Encodable {
    let traceID: String
    let attemptNumber: Int
    let timestamp: String
    let target: LocalPerceptionTargetCache.SnapshotTarget
    let plannedStep: TipTourEnginePlannedActionStep
    let submission: TipTourEngineSubmissionResult
    let workflowOutcome: TipTourEngineWorkflowOutcome
    let validation: TipTourEngineActionValidation

    private enum CodingKeys: String, CodingKey {
        case traceID = "trace_id"
        case attemptNumber
        case timestamp
        case target
        case plannedStep
        case submission
        case workflowOutcome
        case validation
    }
}

struct TipTourEngineActionHistory: Encodable {
    let ok: Bool
    let attempts: [TipTourEngineActionAttempt]
}

struct TipTourEnginePlanNextActionResult: Encodable {
    let ok: Bool
    let traceID: String
    let reason: String?
    let message: String?
    let activeApp: String?
    let plannedStep: TipTourEnginePlannedActionStep?
    let submission: TipTourEngineSubmissionResult?
    let workflowOutcome: TipTourEngineWorkflowOutcome?
    let validation: TipTourEngineActionValidation?
    let attempts: [TipTourEngineActionAttempt]
    let repaired: Bool
    let targets: [LocalPerceptionTargetCache.SnapshotTarget]

    private enum CodingKeys: String, CodingKey {
        case ok
        case traceID = "trace_id"
        case reason
        case message
        case activeApp
        case plannedStep
        case submission
        case workflowOutcome
        case validation
        case attempts
        case repaired
        case targets
    }
}

@MainActor
final class TipTourEngine {
    private let isAutopilotEnabledProvider: () -> Bool
    private let isScreenshotStreamingEnabledProvider: () -> Bool
    private let isAccurateGroundingEnabledProvider: () -> Bool
    private let isCuaActionDriverEnabledProvider: () -> Bool
    private let isHermesOrchestratorEnabledProvider: () -> Bool
    private let detectionElementCountProvider: () -> Int
    private let currentFocusHighlightContextProvider: () -> FocusHighlightContext?
    private let currentTargetApplicationProvider: () -> NSRunningApplication?
    private let latestScreenCaptureProvider: () -> CompanionScreenCapture?
    private let refreshLocalPerception: (String) async -> Void
    private let normalizeWorkflowSteps: ([WorkflowStep], String) -> [WorkflowStep]
    private let startWorkflowPlan: (WorkflowPlan) -> Void
    private let activityReporter: @MainActor (String) -> Void
    private var recentActionAttempts: [TipTourEngineActionAttempt] = []
    private let maximumRecentActionAttempts = 24
    private let workflowSettlementTimeoutSeconds: TimeInterval = 7.0
    private var lastVisualContextScreenshotHash: UInt64?
    private lazy var longTaskCoordinator = TipTourLongTaskCoordinator(
        engine: self,
        activityReporter: activityReporter
    )
    private lazy var imageEditService = TipTourImageEditService(
        currentFocusHighlightContextProvider: currentFocusHighlightContextProvider,
        currentTargetApplicationProvider: currentTargetApplicationProvider,
        latestScreenCaptureProvider: latestScreenCaptureProvider,
        isScreenshotStreamingEnabledProvider: isScreenshotStreamingEnabledProvider
    )

    init(
        isAutopilotEnabledProvider: @escaping () -> Bool,
        isScreenshotStreamingEnabledProvider: @escaping () -> Bool,
        isAccurateGroundingEnabledProvider: @escaping () -> Bool,
        isCuaActionDriverEnabledProvider: @escaping () -> Bool,
        isHermesOrchestratorEnabledProvider: @escaping () -> Bool,
        detectionElementCountProvider: @escaping () -> Int,
        currentFocusHighlightContextProvider: @escaping () -> FocusHighlightContext? = { nil },
        currentTargetApplicationProvider: @escaping () -> NSRunningApplication? = { nil },
        latestScreenCaptureProvider: @escaping () -> CompanionScreenCapture? = { nil },
        refreshLocalPerception: @escaping (String) async -> Void,
        normalizeWorkflowSteps: @escaping ([WorkflowStep], String) -> [WorkflowStep],
        startWorkflowPlan: @escaping (WorkflowPlan) -> Void,
        activityReporter: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.isAutopilotEnabledProvider = isAutopilotEnabledProvider
        self.isScreenshotStreamingEnabledProvider = isScreenshotStreamingEnabledProvider
        self.isAccurateGroundingEnabledProvider = isAccurateGroundingEnabledProvider
        self.isCuaActionDriverEnabledProvider = isCuaActionDriverEnabledProvider
        self.isHermesOrchestratorEnabledProvider = isHermesOrchestratorEnabledProvider
        self.detectionElementCountProvider = detectionElementCountProvider
        self.currentFocusHighlightContextProvider = currentFocusHighlightContextProvider
        self.currentTargetApplicationProvider = currentTargetApplicationProvider
        self.latestScreenCaptureProvider = latestScreenCaptureProvider
        self.refreshLocalPerception = refreshLocalPerception
        self.normalizeWorkflowSteps = normalizeWorkflowSteps
        self.startWorkflowPlan = startWorkflowPlan
        self.activityReporter = activityReporter
    }

    func observe() -> TipTourEngineObservation {
        let activeApp = NSWorkspace.shared.frontmostApplication
        recordEngineEvent(
            name: "observe",
            status: "ok",
            metadata: [
                "active_app": activeApp?.localizedName ?? "unknown",
                "active_bundle": activeApp?.bundleIdentifier ?? "unknown",
                "active_plan": WorkflowRunner.shared.activePlan?.goal ?? "none",
                "detection_count": String(detectionElementCountProvider())
            ]
        )
        return TipTourEngineObservation(
            ok: true,
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            activePlanGoal: WorkflowRunner.shared.activePlan?.goal,
            isAutopilotEnabled: isAutopilotEnabledProvider(),
            isScreenshotStreamingEnabled: isScreenshotStreamingEnabledProvider(),
            isAccurateGroundingEnabled: isAccurateGroundingEnabledProvider(),
            isCuaActionDriverEnabled: isCuaActionDriverEnabledProvider(),
            isHermesOrchestratorEnabled: isHermesOrchestratorEnabledProvider(),
            detectionElementCount: detectionElementCountProvider(),
            externalHarnessVisualContext: "External harnesses should call /v1/visual-context with visual_context=auto so TipTour can decide whether compact state is enough or a screenshot is worth sending. Use /v1/screenshots only for explicit raw screenshot debugging, POST /v1/ground-target for one compact grounded visible target, and keep GET /v1/targets for debug or full-graph inspection only."
        )
    }

    func imageEdit(_ request: TipTourImageEditRequest) async -> TipTourImageEditResponse {
        let result = await imageEditService.prepareOrExecute(request)
        recordEngineEvent(
            name: "image_edit",
            status: result.ok ? "ok" : "failed",
            message: result.message,
            metadata: [
                TipTourActionTrace.metadataKey: result.traceID,
                "source_kind": result.source.kind,
                "source_path": result.source.filePath ?? "none",
                "source_url": result.source.sourceURL ?? "none",
                "executed": String(result.execution?.attempted ?? false),
                "execution_ok": String(result.execution?.ok ?? false),
                "output_path": result.execution?.outputPath ?? "none"
            ]
        )
        return result
    }

    func resolveHighlightSource(_ request: TipTourHighlightSourceRequest) -> TipTourHighlightSourceResponse {
        let traceID = request.normalizedTraceID ?? TipTourActionTrace.makeID(source: "source")
        let source = TipTourHighlightSourceResolver.resolve(
            explicitFilePath: request.normalizedSourceFilePath,
            highlightContext: currentFocusHighlightContextProvider(),
            fallbackApplication: currentTargetApplicationProvider()
        )
        recordEngineEvent(
            name: "resolve_highlight_source",
            status: source.ok ? "ok" : "failed",
            message: source.message,
            metadata: [
                TipTourActionTrace.metadataKey: traceID,
                "source_kind": source.kind,
                "content_category": source.contentCategory,
                "file_path": source.filePath ?? "none",
                "source_url": source.sourceURL ?? "none",
                "tool_count": String(source.tools.count)
            ]
        )
        return TipTourHighlightSourceResponse(
            ok: source.ok,
            traceID: traceID,
            source: source
        )
    }

    func visualContext(
        intent: String?,
        app: String?,
        requestedMode rawRequestedMode: String?,
        reason rawReason: String?,
        targetLabel: String?,
        targetID: String?,
        targetMark: Int?,
        refresh: Bool,
        traceID: String? = nil
    ) async -> TipTourEngineVisualContextSnapshot {
        let traceID = traceID ?? TipTourActionTrace.makeID(source: "visual")
        let requestedMode = normalizedVisualContextMode(rawRequestedMode)
        let policyReason = normalizedVisualContextReason(rawReason)
        if refresh || !requestedApplicationIsFrontmost(app) {
            await activateRequestedApplicationForPerceptionIfNeeded(app)
            await refreshLocalPerception("harness /v1/visual-context")
        }

        let activeApp = NSWorkspace.shared.frontmostApplication
        let targets = LocalPerceptionTargetCache.shared.currentTargets()
        let focusTarget = visualFocusTarget(
            targetLabel: targetLabel,
            targetID: targetID,
            targetMark: targetMark,
            targets: targets
        )
        let targetDiagnosis = visualTargetDiagnosis(
            targetLabel: targetLabel,
            targetID: targetID,
            targetMark: targetMark,
            targets: targets
        )
        let decision = visualContextDecision(
            requestedMode: requestedMode,
            policyReason: policyReason,
            activeApp: activeApp,
            targetCount: targets.count,
            targetDiagnosis: targetDiagnosis,
            hasFocusTarget: focusTarget != nil
        )
        let snapshotID = "obs_\(UUID().uuidString.prefix(8))"
        let capturedAt = Self.iso8601Formatter.string(from: Date())
        let topTargets = targets.prefix(24).map(TipTourEngineGroundedTarget.init)

        let screenshotResult: TipTourVisualContextScreenshotCaptureResult
        if decision.mode == "full_screenshot" || decision.mode == "target_crop" {
            screenshotResult = await captureVisualContextScreenshots(
                preferredMode: decision.mode,
                focusTarget: focusTarget
            )
        } else {
            screenshotResult = .empty
        }

        var finalReasons = decision.reasons
        if let failure = screenshotResult.failure {
            finalReasons.append(failure)
        }

        let finalMode = screenshotResult.actualMode ?? (screenshotResult.failure == nil ? decision.mode : "compact_state")
        let finalDecision = TipTourEngineVisualContextDecision(
            mode: finalMode,
            requestedMode: requestedMode,
            reasons: finalReasons,
            screenshotAllowed: isScreenshotStreamingEnabledProvider(),
            screenshotIncluded: !screenshotResult.screenshots.isEmpty,
            screenChangedSinceLastSnapshot: screenshotResult.changed
        )

        recordEngineEvent(
            name: "visual_context",
            status: "ok",
            metadata: [
                TipTourActionTrace.metadataKey: traceID,
                "snapshot_id": snapshotID,
                "mode": finalDecision.mode,
                "requested_mode": requestedMode,
                "reasons": finalDecision.reasons.joined(separator: ","),
                "screenshot_included": String(finalDecision.screenshotIncluded),
                "screen_changed": finalDecision.screenChangedSinceLastSnapshot.map(String.init) ?? "unknown",
                "target_count": String(targets.count),
                "active_app": activeApp?.localizedName ?? "unknown",
                "active_bundle": activeApp?.bundleIdentifier ?? "unknown"
            ]
        )

        return TipTourEngineVisualContextSnapshot(
            ok: true,
            traceID: traceID,
            reason: nil,
            message: "Prepared TipTour visual context.",
            snapshotID: snapshotID,
            capturedAt: capturedAt,
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            activePlanGoal: WorkflowRunner.shared.activePlan?.goal,
            intent: nonEmpty(intent),
            decision: finalDecision,
            targetCount: targets.count,
            targets: topTargets,
            focusTarget: focusTarget.map(TipTourEngineGroundedTarget.init),
            screenshotHash: screenshotResult.hash.map { String(format: "%016llx", $0) },
            screenshots: screenshotResult.screenshots
        )
    }

    func localPerceptionTargets(refresh: Bool, reason: String = "harness requested targets") async -> TipTourEngineTargetList {
        if refresh {
            await refreshLocalPerception(reason)
        }

        let activeApp = NSWorkspace.shared.frontmostApplication
        let targets = LocalPerceptionTargetCache.shared.currentTargets()
        recordEngineEvent(
            name: "targets",
            status: "ok",
            metadata: [
                "refreshed": String(refresh),
                "reason": reason,
                "target_count": String(targets.count),
                "active_app": activeApp?.localizedName ?? "unknown",
                "active_bundle": activeApp?.bundleIdentifier ?? "unknown"
            ]
        )
        return TipTourEngineTargetList(
            ok: true,
            refreshed: refresh,
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            targetCount: targets.count,
            targets: targets
        )
    }

    func groundTarget(
        goal: String,
        app: String?,
        actionType: WorkflowStep.StepType,
        targetLabel: String?,
        targetID: String?,
        targetMark: Int?,
        refresh: Bool,
        allowScreenshotPlanning: Bool,
        allowAIMatch: Bool
    ) async -> TipTourEngineGroundTargetResult {
        let traceID = TipTourActionTrace.makeID(source: "ground")
        let groundStartedAt = Date()
        let query = nonEmpty(targetLabel) ?? nonEmpty(goal)
        let requestedAppWasAlreadyFrontmost = requestedApplicationIsFrontmost(app)
        let pointerActionRequest = PointerActionRequest(
            goal: nonEmpty(goal) ?? query ?? "ground visible target",
            app: app,
            actionType: actionType,
            targetLabel: query,
            targetID: targetID,
            targetMark: targetMark,
            execute: false,
            allowScreenshotPlanning: allowScreenshotPlanning,
            validateStateChange: false,
            traceID: traceID
        )

        recordEngineEvent(
            name: "ground_target",
            status: "started",
            metadata: pointerActionMetadata(pointerActionRequest).merging(
                [
                    "requested_refresh": String(refresh),
                    "allow_ai_match": String(allowAIMatch),
                    "requested_app_was_frontmost": String(requestedAppWasAlreadyFrontmost)
                ],
                uniquingKeysWith: { existing, _ in existing }
            )
        )
        activityReporter("Grounding \(query ?? targetID ?? targetMark.map(String.init) ?? "target")")
        await activateRequestedApplicationForPerceptionIfNeeded(app)

        let shouldRefreshPerception = refresh || !requestedAppWasAlreadyFrontmost
        if shouldRefreshPerception {
            await refreshLocalPerception("harness /v1/ground-target")
        }

        let activeApp = NSWorkspace.shared.frontmostApplication
        let targets = LocalPerceptionTargetCache.shared.currentTargets()
        guard !targets.isEmpty else {
            recordEngineEvent(
                name: "ground_target",
                status: "failed",
                message: "No local perception targets were available.",
                metadata: pointerActionMetadata(pointerActionRequest).merging(
                    [
                        "reason": "no_local_targets",
                        "elapsed_ms": String(Self.elapsedMilliseconds(since: groundStartedAt))
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineGroundTargetResult(
                ok: false,
                traceID: traceID,
                reason: "no_local_targets",
                message: "No local YOLO/OCR targets are available yet. Turn on Accurate Grounding or wait for a fresh perception pass.",
                activeAppName: activeApp?.localizedName,
                activeBundleIdentifier: activeApp?.bundleIdentifier,
                refreshed: shouldRefreshPerception,
                goal: pointerActionRequest.goal,
                query: query,
                actionType: actionType.rawValue,
                candidateCount: 0,
                matchedBy: nil,
                aiMatchLatencyMs: nil,
                target: nil
            )
        }

        let didRequestExactTarget = didRequestExplicitTarget(targetID: targetID, targetMark: targetMark)
        let explicitlyMatchedTarget = explicitTarget(
            requestedTargetID: targetID,
            requestedTargetMark: targetMark,
            targets: targets
        )
        let matchedTarget = explicitlyMatchedTarget ?? (didRequestExactTarget ? nil : bestTarget(
            requestedLabel: query,
            goal: pointerActionRequest.goal,
            targets: targets,
            app: app,
            excludingTargetIDs: []
        ))

        let aiMatchStartDate = Date()
        let aiMatchedTarget = matchedTarget == nil && allowAIMatch && !didRequestExactTarget
            ? await aiMatchedTarget(
                query: query ?? pointerActionRequest.goal,
                intent: pointerActionRequest.goal,
                targets: targets,
                app: app
            )
            : nil
        let aiMatchLatencyMs = aiMatchedTarget == nil ? nil : Self.elapsedMilliseconds(since: aiMatchStartDate)
        let finalMatchedTarget = matchedTarget ?? aiMatchedTarget

        guard let finalMatchedTarget else {
            let reason: String
            let message: String
            if didRequestExactTarget {
                reason = "explicit_target_not_found"
                message = "The requested target_id or target_mark is not present in the current local perception snapshot."
            } else if allowAIMatch {
                reason = "ai_target_not_found"
                message = "No local or cheap AI target match was confident enough."
            } else if allowScreenshotPlanning {
                reason = "needs_screenshot_planner"
                message = "No local target matched. Screenshot planning can be requested separately, but /v1/ground-target does not guess raw coordinates."
            } else {
                reason = "target_not_found"
                message = "No local target matched the requested query or goal."
            }
            recordEngineEvent(
                name: "ground_target",
                status: "failed",
                message: message,
                metadata: pointerActionMetadata(pointerActionRequest).merging(
                    [
                        "reason": reason,
                        "allow_ai_match": String(allowAIMatch),
                        "target_count": String(targets.count),
                        "elapsed_ms": String(Self.elapsedMilliseconds(since: groundStartedAt))
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineGroundTargetResult(
                ok: false,
                traceID: traceID,
                reason: reason,
                message: message,
                activeAppName: activeApp?.localizedName,
                activeBundleIdentifier: activeApp?.bundleIdentifier,
                refreshed: shouldRefreshPerception,
                goal: pointerActionRequest.goal,
                query: query,
                actionType: actionType.rawValue,
                candidateCount: targets.count,
                matchedBy: nil,
                aiMatchLatencyMs: aiMatchLatencyMs,
                target: nil
            )
        }

        let matchedBy = didRequestExactTarget ? "explicit" : (aiMatchedTarget == nil ? "label" : "ai_match")
        recordEngineEvent(
            name: "ground_target",
            status: "ok",
            message: "Grounded one visible target.",
            metadata: pointerActionMetadata(pointerActionRequest).merging(
                targetMetadata(finalMatchedTarget).merging(
                    [
                        "matched_by": matchedBy,
                        "refreshed": String(shouldRefreshPerception),
                        "ai_match_latency_ms": aiMatchLatencyMs.map(String.init) ?? "none",
                        "target_count": String(targets.count),
                        "elapsed_ms": String(Self.elapsedMilliseconds(since: groundStartedAt))
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                ),
                uniquingKeysWith: { existing, _ in existing }
            )
        )
        return TipTourEngineGroundTargetResult(
            ok: true,
            traceID: traceID,
            reason: nil,
            message: "Grounded one visible target.",
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            refreshed: shouldRefreshPerception,
            goal: pointerActionRequest.goal,
            query: query,
            actionType: actionType.rawValue,
            candidateCount: targets.count,
            matchedBy: matchedBy,
            aiMatchLatencyMs: aiMatchLatencyMs,
            target: TipTourEngineGroundedTarget(finalMatchedTarget)
        )
    }

    func actionHistory() -> TipTourEngineActionHistory {
        TipTourEngineActionHistory(
            ok: true,
            attempts: recentActionAttempts
        )
    }

    func agentContract() -> TipTourAgentContractSnapshot {
        TipTourAgentContract.snapshot
    }

    func startLongTask(
        title: String?,
        prompt: String,
        app: String?,
        steps: [TipTourLongTaskStep],
        traceID: String? = nil
    ) -> TipTourLongTaskStartResponse {
        longTaskCoordinator.startTask(
            title: title,
            prompt: prompt,
            app: app,
            steps: steps,
            traceID: traceID
        )
    }

    func longTasks() -> TipTourLongTaskListResponse {
        longTaskCoordinator.listTasks()
    }

    func longTask(id: String) -> TipTourLongTaskStatusResponse {
        longTaskCoordinator.task(id: id)
    }

    func longTaskEvents(id: String) -> TipTourLongTaskEventsResponse {
        longTaskCoordinator.events(id: id)
    }

    func cancelLongTask(id: String) -> TipTourLongTaskCancelResponse {
        longTaskCoordinator.cancelTask(id: id)
    }

    func waitForLongTaskCompletion(
        id: String,
        timeoutSeconds: TimeInterval
    ) async -> TipTourLongTaskStatusResponse {
        await longTaskCoordinator.waitForTaskCompletion(
            id: id,
            timeoutSeconds: timeoutSeconds
        )
    }

    func skills() -> TipTourEngineSkillList {
        let activeApp = NSWorkspace.shared.frontmostApplication
        let skillInfos = MarkdownAppSkillRegistry.shared.skillInfos(activeApplication: activeApp)
        return TipTourEngineSkillList(
            ok: true,
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            skillCount: skillInfos.count,
            skills: skillInfos
        )
    }

    func activeSkill() -> TipTourEngineActiveSkill {
        let activeApp = NSWorkspace.shared.frontmostApplication
        return TipTourEngineActiveSkill(
            ok: true,
            activeAppName: activeApp?.localizedName,
            activeBundleIdentifier: activeApp?.bundleIdentifier,
            skill: MarkdownAppSkillRegistry.shared.activeSkillInfo(for: activeApp)
        )
    }

    func screenshots() async -> TipTourEngineScreenshotList {
        let activeApp = NSWorkspace.shared.frontmostApplication
        guard isScreenshotStreamingEnabledProvider() else {
            recordEngineEvent(
                name: "screenshots",
                status: "rejected",
                message: "Screenshots toggle is off.",
                metadata: [
                    "reason": "screenshots_disabled",
                    "active_app": activeApp?.localizedName ?? "unknown"
                ]
            )
            return TipTourEngineScreenshotList(
                ok: false,
                reason: "screenshots_disabled",
                message: "TipTour Screenshots is off, so the harness will not expose raw screen images.",
                activeAppName: activeApp?.localizedName,
                activeBundleIdentifier: activeApp?.bundleIdentifier,
                screenshotCount: 0,
                screenshots: []
            )
        }

        do {
            let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            let screenshots = captures.prefix(2).map { capture in
                TipTourEngineScreenshot(
                    label: capture.label,
                    isCursorScreen: capture.isCursorScreen,
                    displayWidthInPoints: capture.displayWidthInPoints,
                    displayHeightInPoints: capture.displayHeightInPoints,
                    screenshotWidthInPixels: capture.screenshotWidthInPixels,
                    screenshotHeightInPixels: capture.screenshotHeightInPixels,
                    capturedAt: Self.iso8601Formatter.string(from: capture.captureTimestamp),
                    mediaType: "image/jpeg",
                    dataURL: "data:image/jpeg;base64,\(capture.imageData.base64EncodedString())"
                )
            }

            recordEngineEvent(
                name: "screenshots",
                status: "ok",
                metadata: [
                    "capture_count": String(captures.count),
                    "returned_count": String(screenshots.count),
                    "active_app": activeApp?.localizedName ?? "unknown"
                ]
            )
            return TipTourEngineScreenshotList(
                ok: true,
                reason: nil,
                message: "Captured fresh TipTour screenshots.",
                activeAppName: activeApp?.localizedName,
                activeBundleIdentifier: activeApp?.bundleIdentifier,
                screenshotCount: screenshots.count,
                screenshots: screenshots
            )
        } catch {
            recordEngineEvent(
                name: "screenshots",
                status: "failed",
                message: error.localizedDescription,
                metadata: [
                    "reason": "screenshot_capture_failed",
                    "active_app": activeApp?.localizedName ?? "unknown"
                ]
            )
            return TipTourEngineScreenshotList(
                ok: false,
                reason: "screenshot_capture_failed",
                message: error.localizedDescription,
                activeAppName: activeApp?.localizedName,
                activeBundleIdentifier: activeApp?.bundleIdentifier,
                screenshotCount: 0,
                screenshots: []
            )
        }
    }

    private func captureVisualContextScreenshots(
        preferredMode: String,
        focusTarget: LocalPerceptionTargetCache.SnapshotTarget?
    ) async -> TipTourVisualContextScreenshotCaptureResult {
        guard isScreenshotStreamingEnabledProvider() else {
            return TipTourVisualContextScreenshotCaptureResult(
                screenshots: [],
                hash: nil,
                changed: nil,
                failure: "screenshots_disabled",
                actualMode: "compact_state"
            )
        }

        do {
            let captures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
            guard let selectedCapture = captureForVisualContext(focusTarget: focusTarget, captures: captures) else {
                return TipTourVisualContextScreenshotCaptureResult(
                    screenshots: [],
                    hash: nil,
                    changed: nil,
                    failure: "screenshot_capture_empty",
                    actualMode: "compact_state"
                )
            }

            if preferredMode == "target_crop",
               let focusTarget,
               let crop = croppedScreenshot(for: focusTarget, in: selectedCapture) {
                return visualContextScreenshotResult(
                    imageData: crop.imageData,
                    label: crop.label,
                    isCursorScreen: selectedCapture.isCursorScreen,
                    widthInPixels: crop.width,
                    heightInPixels: crop.height,
                    capturedAt: selectedCapture.captureTimestamp,
                    actualMode: "target_crop",
                    failure: nil
                )
            }

            let fallbackFailure = preferredMode == "target_crop" ? "target_crop_unavailable_full_screenshot_fallback" : nil
            return visualContextScreenshotResult(
                imageData: selectedCapture.imageData,
                label: selectedCapture.label,
                isCursorScreen: selectedCapture.isCursorScreen,
                widthInPixels: selectedCapture.screenshotWidthInPixels,
                heightInPixels: selectedCapture.screenshotHeightInPixels,
                capturedAt: selectedCapture.captureTimestamp,
                actualMode: "full_screenshot",
                failure: fallbackFailure
            )
        } catch {
            return TipTourVisualContextScreenshotCaptureResult(
                screenshots: [],
                hash: nil,
                changed: nil,
                failure: "screenshot_capture_failed",
                actualMode: "compact_state"
            )
        }
    }

    private func visualContextScreenshotResult(
        imageData: Data,
        label: String,
        isCursorScreen: Bool,
        widthInPixels: Int,
        heightInPixels: Int,
        capturedAt: Date,
        actualMode: String,
        failure: String?
    ) -> TipTourVisualContextScreenshotCaptureResult {
        let screenshotHash = ScreenshotPerceptualHash.perceptualHash(forJPEGData: imageData)
        let changed: Bool? = screenshotHash.map { newHash in
            guard let previousHash = lastVisualContextScreenshotHash else { return true }
            return !ScreenshotPerceptualHash.isSameScene(previousHash, newHash)
        }
        if let screenshotHash {
            lastVisualContextScreenshotHash = screenshotHash
        }

        let screenshot = TipTourEngineScreenshot(
            label: label,
            isCursorScreen: isCursorScreen,
            displayWidthInPoints: widthInPixels,
            displayHeightInPoints: heightInPixels,
            screenshotWidthInPixels: widthInPixels,
            screenshotHeightInPixels: heightInPixels,
            capturedAt: Self.iso8601Formatter.string(from: capturedAt),
            mediaType: "image/jpeg",
            dataURL: "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        )

        return TipTourVisualContextScreenshotCaptureResult(
            screenshots: [screenshot],
            hash: screenshotHash,
            changed: changed,
            failure: failure,
            actualMode: actualMode
        )
    }

    private func captureForVisualContext(
        focusTarget: LocalPerceptionTargetCache.SnapshotTarget?,
        captures: [CompanionScreenCapture]
    ) -> CompanionScreenCapture? {
        guard let focusTarget,
              let targetDisplayFrame = rect(from: focusTarget.displayFrame) else {
            return captures.first
        }

        return captures.first { capture in
            abs(capture.displayFrame.minX - targetDisplayFrame.minX) < 2
                && abs(capture.displayFrame.minY - targetDisplayFrame.minY) < 2
                && abs(capture.displayFrame.maxX - targetDisplayFrame.maxX) < 2
                && abs(capture.displayFrame.maxY - targetDisplayFrame.maxY) < 2
        } ?? captures.first
    }

    private func croppedScreenshot(
        for target: LocalPerceptionTargetCache.SnapshotTarget,
        in capture: CompanionScreenCapture
    ) -> (imageData: Data, label: String, width: Int, height: Int)? {
        guard let imageSource = CGImageSourceCreateWithData(capture.imageData as CFData, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let targetBox = rect(from: target.screenshotBox) else {
            return nil
        }

        let cropRect = paddedCropRect(
            around: targetBox,
            imageWidth: sourceImage.width,
            imageHeight: sourceImage.height
        )
        guard cropRect.width >= 8,
              cropRect.height >= 8,
              let croppedImage = sourceImage.cropping(to: cropRect),
              let jpegData = NSBitmapImageRep(cgImage: croppedImage)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            return nil
        }

        let label = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            jpegData,
            label.isEmpty ? "target crop" : "target crop around \"\(label)\"",
            croppedImage.width,
            croppedImage.height
        )
    }

    private func paddedCropRect(
        around targetBox: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let imageRect = CGRect(x: 0, y: 0, width: CGFloat(imageWidth), height: CGFloat(imageHeight))
        let targetSize = max(targetBox.width, targetBox.height)
        let padding = max(120, min(420, targetSize * 3.0))
        let minimumCropWidth: CGFloat = 360
        let minimumCropHeight: CGFloat = 260

        var cropRect = targetBox.insetBy(dx: -padding, dy: -padding)
        if cropRect.width < minimumCropWidth {
            cropRect = cropRect.insetBy(dx: -(minimumCropWidth - cropRect.width) / 2, dy: 0)
        }
        if cropRect.height < minimumCropHeight {
            cropRect = cropRect.insetBy(dx: 0, dy: -(minimumCropHeight - cropRect.height) / 2)
        }

        let clampedMinX = max(imageRect.minX, cropRect.minX)
        let clampedMinY = max(imageRect.minY, cropRect.minY)
        let clampedMaxX = min(imageRect.maxX, cropRect.maxX)
        let clampedMaxY = min(imageRect.maxY, cropRect.maxY)
        return CGRect(
            x: clampedMinX.rounded(.down),
            y: clampedMinY.rounded(.down),
            width: max(0, (clampedMaxX - clampedMinX).rounded(.up)),
            height: max(0, (clampedMaxY - clampedMinY).rounded(.up))
        )
    }

    private func rect(from values: [Double]) -> CGRect? {
        guard values.count == 4 else { return nil }
        let minX = values[0]
        let minY = values[1]
        let maxX = values[2]
        let maxY = values[3]
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    func planNextAction(
        goal: String,
        app: String?,
        requestedActionType: WorkflowStep.StepType,
        requestedTargetLabel: String?,
        execute: Bool,
        allowScreenshotPlanning: Bool,
        validateStateChange: Bool
    ) async -> TipTourEnginePlanNextActionResult {
        let traceID = TipTourActionTrace.makeID(source: "plan")
        let pointerActionRequest = PointerActionRequest(
            goal: goal,
            app: app,
            actionType: requestedActionType,
            targetLabel: requestedTargetLabel,
            targetID: nil,
            targetMark: nil,
            execute: execute,
            allowScreenshotPlanning: allowScreenshotPlanning,
            validateStateChange: validateStateChange,
            traceID: traceID
        )
        return await runPointerAction(pointerActionRequest)
    }

    func runPointerAction(_ pointerActionRequest: PointerActionRequest) async -> TipTourEnginePlanNextActionResult {
        let traceID = pointerActionRequest.traceID ?? TipTourActionTrace.makeID(source: "action")
        let pointerActionRequest = pointerActionRequest.withTraceID(traceID)
        let actionStartedAt = Date()
        recordEngineEvent(
            name: "pointer_action",
            status: "started",
            metadata: pointerActionMetadata(pointerActionRequest)
        )
        activityReporter("Hermes locating \(pointerActionRequest.targetLabel ?? pointerActionRequest.goal)")
        await activateRequestedApplicationForPerceptionIfNeeded(pointerActionRequest.app)

        if let targetlessStep = targetlessPlanNextActionStep(for: pointerActionRequest) {
            recordEngineEvent(
                name: "pointer_action_targetless",
                status: "ok",
                metadata: workflowStepMetadata(targetlessStep).merging(
                    pointerActionMetadata(pointerActionRequest),
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return await runTargetlessPlanNextAction(
                step: targetlessStep,
                pointerActionRequest: pointerActionRequest
            )
        }

        await refreshLocalPerception("harness plan-next-action")

        let targets = LocalPerceptionTargetCache.shared.currentTargets()
        guard !targets.isEmpty else {
            activityReporter("Hermes found no local targets")
            recordEngineEvent(
                name: "pointer_action",
                status: "failed",
                message: "No local perception targets were available.",
                metadata: pointerActionMetadata(pointerActionRequest).merging(
                    [
                        "reason": "no_local_targets",
                        "elapsed_ms": String(Self.elapsedMilliseconds(since: actionStartedAt))
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEnginePlanNextActionResult(
                ok: false,
                traceID: traceID,
                reason: "no_local_targets",
                message: "No local YOLO/OCR targets are available yet. Turn on Accurate Grounding or wait for a fresh perception pass.",
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                plannedStep: nil,
                submission: nil,
                workflowOutcome: nil,
                validation: nil,
                attempts: [],
                repaired: false,
                targets: []
            )
        }

        let didRequestExactTarget = didRequestExplicitTarget(
            targetID: pointerActionRequest.targetID,
            targetMark: pointerActionRequest.targetMark
        )
        let explicitlyMatchedTarget = explicitTarget(
            requestedTargetID: pointerActionRequest.targetID,
            requestedTargetMark: pointerActionRequest.targetMark,
            targets: targets
        )
        let matchedTarget = explicitlyMatchedTarget ?? (didRequestExactTarget ? nil : bestTarget(
            requestedLabel: pointerActionRequest.targetLabel,
            goal: pointerActionRequest.goal,
            targets: targets,
            app: pointerActionRequest.app,
            excludingTargetIDs: []
        ))

        guard let matchedTarget else {
            let reason = pointerActionRequest.allowScreenshotPlanning ? "needs_screenshot_planner" : "target_not_found"
            let message = pointerActionRequest.allowScreenshotPlanning
                ? "No local target matched. Screenshot planning can be added here, but this endpoint currently refuses to guess raw coordinates."
                : "No local target matched the requested label or goal."
            activityReporter("Hermes could not find \(pointerActionRequest.targetLabel ?? pointerActionRequest.goal)")
            recordEngineEvent(
                name: "pointer_action",
                status: "failed",
                message: message,
                metadata: pointerActionMetadata(pointerActionRequest).merging(
                    [
                        "reason": reason,
                        "target_count": String(targets.count),
                        "elapsed_ms": String(Self.elapsedMilliseconds(since: actionStartedAt))
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEnginePlanNextActionResult(
                ok: false,
                traceID: traceID,
                reason: reason,
                message: message,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                plannedStep: nil,
                submission: nil,
                workflowOutcome: nil,
                validation: nil,
                attempts: [],
                repaired: false,
                targets: targets
            )
        }

        let plannedStep = plannedActionStep(
            actionType: pointerActionRequest.actionType,
            target: matchedTarget
        )
        recordEngineEvent(
            name: "target_matched",
            status: "ok",
            metadata: pointerActionMetadata(pointerActionRequest).merging(
                targetMetadata(matchedTarget),
                uniquingKeysWith: { existing, _ in existing }
            )
        )

        guard pointerActionRequest.execute else {
            activityReporter("Hermes planned \(plannedStep.hint)")
            recordEngineEvent(
                name: "pointer_action",
                status: "ok",
                message: "Planned without execution.",
                metadata: pointerActionMetadata(pointerActionRequest).merging(
                    ["mode": "plan_only"],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEnginePlanNextActionResult(
                ok: true,
                traceID: traceID,
                reason: nil,
                message: "Planned one grounded TipTour action.",
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                plannedStep: plannedStep,
                submission: nil,
                workflowOutcome: nil,
                validation: nil,
                attempts: [],
                repaired: false,
                targets: targets
            )
        }

        let executionResult = await executeGroundedActionOnce(
            goal: pointerActionRequest.goal,
            app: pointerActionRequest.app,
            requestedActionType: pointerActionRequest.actionType,
            initialTarget: matchedTarget,
            initialTargets: targets,
            requireStateChange: pointerActionRequest.validateStateChange,
            traceID: traceID
        )

        recordEngineEvent(
            name: "pointer_action",
            status: executionResult.ok ? "ok" : "failed",
            message: executionResult.message,
            metadata: pointerActionMetadata(pointerActionRequest).merging(
                [
                    "reason": executionResult.reason ?? "none",
                    "attempt_count": String(executionResult.attempts.count),
                    "latest_target_count": String(executionResult.latestTargets.count),
                    "elapsed_ms": String(Self.elapsedMilliseconds(since: actionStartedAt))
                ],
                uniquingKeysWith: { existing, _ in existing }
            )
        )
        return TipTourEnginePlanNextActionResult(
            ok: executionResult.ok,
            traceID: traceID,
            reason: executionResult.reason,
            message: executionResult.message,
            activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            plannedStep: executionResult.attempts.first?.plannedStep ?? plannedStep,
            submission: executionResult.attempts.last?.submission,
            workflowOutcome: executionResult.attempts.last?.workflowOutcome,
            validation: executionResult.attempts.last?.validation,
            attempts: executionResult.attempts,
            repaired: executionResult.repaired,
            targets: executionResult.latestTargets
        )
    }

    func submitSingleActionWorkflowPlan(_ plan: WorkflowPlan) -> TipTourEngineSubmissionResult {
        let traceID = plan.traceID ?? TipTourActionTrace.makeID(source: "workflow")
        let plan = plan.withTraceID(traceID)
        recordEngineEvent(
            name: "workflow_plan",
            status: "received",
            metadata: workflowPlanMetadata(plan)
        )
        guard isAutopilotEnabledProvider() else {
            recordEngineEvent(
                name: "workflow_plan",
                status: "rejected",
                message: "Autopilot is disabled.",
                metadata: workflowPlanMetadata(plan).merging(
                    ["reason": "autopilot_disabled"],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineSubmissionResult(
                ok: false,
                reason: "autopilot_disabled",
                message: "TipTour Autopilot is off. Turn it on before external harnesses can execute actions.",
                traceID: traceID,
                acceptedSteps: 0,
                ignoredSteps: plan.steps.count,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        guard isCuaActionDriverEnabledProvider() else {
            recordEngineEvent(
                name: "workflow_plan",
                status: "rejected",
                message: "CUA Driver is disabled.",
                metadata: workflowPlanMetadata(plan).merging(
                    ["reason": "action_driver_disabled"],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineSubmissionResult(
                ok: false,
                reason: "action_driver_disabled",
                message: "CUA Driver is off. Turn it on before TipTour can execute desktop actions.",
                traceID: traceID,
                acceptedSteps: 0,
                ignoredSteps: plan.steps.count,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        activateRunningApplicationForWorkflowIfNeeded(plan.app)

        if let activePlan = WorkflowRunner.shared.activePlan {
            print("[Engine] superseding active plan \"\(activePlan.goal)\" with \"\(plan.goal)\"")
            recordEngineEvent(
                name: "workflow_plan_superseded",
                status: "warning",
                metadata: [
                    TipTourActionTrace.metadataKey: traceID,
                    "old_goal": activePlan.goal,
                    "new_goal": plan.goal
                ]
            )
            WorkflowRunner.shared.stop()
        }

        let normalizedSteps = normalizeWorkflowSteps(
            plan.steps,
            plan.app ?? ""
        ).map { step in
            stepWithHarnessDefaults(step, planGoal: plan.goal, appName: plan.app)
        }
        guard let firstStep = normalizedSteps.first else {
            recordEngineEvent(
                name: "workflow_plan",
                status: "rejected",
                message: "Workflow plan had no steps.",
                metadata: workflowPlanMetadata(plan).merging(
                    ["reason": "empty_steps"],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineSubmissionResult(
                ok: false,
                reason: "empty_steps",
                message: "Workflow plan must contain at least one step.",
                traceID: traceID,
                acceptedSteps: 0,
                ignoredSteps: 0,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        guard normalizedSteps.count == 1 else {
            print("[Engine] rejecting multi-step external workflow plan \"\(plan.goal)\" - received \(normalizedSteps.count) step(s)")
            recordEngineEvent(
                name: "workflow_plan",
                status: "rejected",
                message: "External harness plans must contain exactly one action.",
                metadata: workflowPlanMetadata(plan).merging(
                    [
                        "reason": "single_action_required",
                        "normalized_step_count": String(normalizedSteps.count),
                        "suggested_endpoint": "/v1/tasks"
                    ],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineSubmissionResult(
                ok: false,
                reason: "single_action_required",
                message: "TipTour external harness mode accepts exactly one action per /v1/workflow-plan request. Send only the next action, or use POST /v1/tasks for a concrete deterministic mini-sequence such as S, Z, type value, Return.",
                traceID: traceID,
                acceptedSteps: 0,
                ignoredSteps: normalizedSteps.count,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        if let invalidReason = invalidSingleActionReason(for: firstStep) {
            recordEngineEvent(
                name: "workflow_plan",
                status: "rejected",
                message: "Workflow step payload is invalid.",
                metadata: workflowPlanMetadata(plan).merging(
                    workflowStepMetadata(firstStep).merging(
                        ["reason": invalidReason],
                        uniquingKeysWith: { existing, _ in existing }
                    ),
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return TipTourEngineSubmissionResult(
                ok: false,
                reason: invalidReason,
                message: "Workflow step is missing the required payload for \(firstStep.type.rawValue).",
                traceID: traceID,
                acceptedSteps: 0,
                ignoredSteps: normalizedSteps.count,
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
            )
        }

        let singleActionPlan = WorkflowPlan(
            goal: plan.goal,
            app: plan.app,
            steps: [firstStep],
            traceID: traceID
        )

        let actionLabel = firstStep.label ?? firstStep.value ?? "<unlabeled>"
        print("[Engine] accepted workflow plan \"\(singleActionPlan.goal)\" -> \(actionLabel)")
        activityReporter("Hermes action - \(singleActionPlan.goal) -> \(actionLabel)")
        recordEngineEvent(
            name: "workflow_plan",
            status: "accepted",
            metadata: workflowPlanMetadata(singleActionPlan).merging(
                workflowStepMetadata(firstStep),
                uniquingKeysWith: { existing, _ in existing }
            )
        )
        startWorkflowPlan(singleActionPlan)

        return TipTourEngineSubmissionResult(
            ok: true,
            reason: nil,
            message: "Accepted one TipTour action.",
            traceID: traceID,
            acceptedSteps: 1,
            ignoredSteps: 0,
            activeApp: NSWorkspace.shared.frontmostApplication?.localizedName
        )
    }

    func submitSingleActionWorkflowPlanAndWait(_ plan: WorkflowPlan) async -> TipTourEngineSubmissionResult {
        let traceID = plan.traceID ?? TipTourActionTrace.makeID(source: "workflow")
        let tracedPlan = plan.withTraceID(traceID)
        let submission = submitSingleActionWorkflowPlan(tracedPlan)
        guard submission.ok else {
            recordEngineEvent(
                name: "workflow_plan_result",
                status: "rejected",
                message: submission.message,
                metadata: workflowPlanMetadata(tracedPlan).merging(
                    ["reason": submission.reason ?? "unknown"],
                    uniquingKeysWith: { existing, _ in existing }
                )
            )
            return submission
        }

        let workflowOutcome = await waitForWorkflowSettlement()
        if shouldRefreshPerceptionAfterWorkflowPlan(tracedPlan) {
            await refreshLocalPerception("harness workflow-plan post-action")
        }
        let completed = workflowOutcome.status == "completed"
        recordEngineEvent(
            name: "workflow_plan_result",
            status: completed ? "completed" : "failed",
            message: completed ? "WorkflowRunner completed the action." : workflowOutcome.message,
            metadata: workflowPlanMetadata(tracedPlan).merging(
                [
                    "workflow_status": workflowOutcome.status,
                    "reason": workflowOutcome.reason ?? "none",
                    "wait_ms": String(workflowOutcome.waitMs),
                    "target_count_after_action": String(LocalPerceptionTargetCache.shared.currentTargets().count)
                ],
                uniquingKeysWith: { existing, _ in existing }
            )
        )

        return TipTourEngineSubmissionResult(
            ok: completed,
            reason: completed ? nil : workflowOutcome.reason,
            message: completed ? "Executed one TipTour action." : workflowOutcome.message,
            traceID: traceID,
            acceptedSteps: submission.acceptedSteps,
            ignoredSteps: submission.ignoredSteps,
            activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            workflowOutcome: workflowOutcome,
            targetCountAfterAction: LocalPerceptionTargetCache.shared.currentTargets().count
        )
    }

    private func shouldRefreshPerceptionAfterWorkflowPlan(_ plan: WorkflowPlan) -> Bool {
        guard let step = plan.steps.first else { return false }
        if isTargetlessKeyboardLikeStep(step) {
            return false
        }

        switch step.type {
        case .observe:
            return false
        case .click, .rightClick, .doubleClick, .openApp, .openURL, .setValue, .scroll:
            return true
        case .keyboardShortcut, .pressKey, .type, .waitForState:
            return true
        }
    }

    private func isTargetlessKeyboardLikeStep(_ step: WorkflowStep) -> Bool {
        switch step.type {
        case .keyboardShortcut, .pressKey, .type:
            break
        default:
            return false
        }

        if didRequestExplicitTarget(targetID: step.targetID, targetMark: step.targetMark) {
            return false
        }
        if step.targetContext == .visibleElement {
            return false
        }
        if step.box2DNormalized?.isEmpty == false || step.hintX != nil || step.hintY != nil {
            return false
        }
        return true
    }

    private func didRequestExplicitTarget(targetID: String?, targetMark: Int?) -> Bool {
        if let targetID = targetID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !targetID.isEmpty {
            return true
        }
        return targetMark != nil
    }

    private func targetlessPlanNextActionStep(for request: PointerActionRequest) -> WorkflowStep? {
        switch request.actionType {
        case .pressKey:
            let key = nonEmpty(request.targetLabel) ?? inferredKeyToPress(from: request.goal, appName: request.app)
            return key.map {
                targetlessWorkflowStep(type: .pressKey, label: $0, value: nil, goal: request.goal)
            }
        case .keyboardShortcut:
            let shortcut = nonEmpty(request.targetLabel) ?? inferredKeyboardShortcut(from: request.goal)
            return shortcut.map {
                targetlessWorkflowStep(type: .keyboardShortcut, label: $0, value: nil, goal: request.goal)
            }
        case .type:
            let text = nonEmpty(request.targetLabel) ?? inferredTextToType(from: request.goal)
            return text.map {
                targetlessWorkflowStep(type: .type, label: nil, value: $0, goal: request.goal)
            }
        case .openApp:
            let applicationName = nonEmpty(request.targetLabel) ?? nonEmpty(request.app) ?? nonEmpty(request.goal)
            return applicationName.map {
                targetlessWorkflowStep(type: .openApp, label: $0, value: nil, goal: request.goal)
            }
        case .openURL:
            let urlString = nonEmpty(request.targetLabel) ?? nonEmpty(request.goal)
            return urlString.map {
                targetlessWorkflowStep(type: .openURL, label: $0, value: nil, goal: request.goal)
            }
        default:
            guard shouldForceReturnForBlenderConfirmation(request) else { return nil }
            return targetlessWorkflowStep(type: .pressKey, label: "Return", value: nil, goal: request.goal)
        }
    }

    private func runTargetlessPlanNextAction(
        step: WorkflowStep,
        pointerActionRequest: PointerActionRequest
    ) async -> TipTourEnginePlanNextActionResult {
        let traceID = pointerActionRequest.traceID ?? TipTourActionTrace.makeID(source: "targetless")
        let plannedStep = plannedTargetlessActionStep(step)
        guard pointerActionRequest.execute else {
            return TipTourEnginePlanNextActionResult(
                ok: true,
                traceID: traceID,
                reason: nil,
                message: "Planned one targetless TipTour action.",
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                plannedStep: plannedStep,
                submission: nil,
                workflowOutcome: nil,
                validation: nil,
                attempts: [],
                repaired: false,
                targets: LocalPerceptionTargetCache.shared.currentTargets()
            )
        }

        let submission = await submitSingleActionWorkflowPlanAndWait(
            WorkflowPlan(
                goal: pointerActionRequest.goal,
                app: pointerActionRequest.app,
                steps: [step],
                traceID: traceID
            )
        )

        return TipTourEnginePlanNextActionResult(
            ok: submission.ok,
            traceID: traceID,
            reason: submission.reason,
            message: submission.message,
            activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
            plannedStep: plannedStep,
            submission: submission,
            workflowOutcome: submission.workflowOutcome,
            validation: nil,
            attempts: [],
            repaired: false,
            targets: LocalPerceptionTargetCache.shared.currentTargets()
        )
    }

    private func targetlessWorkflowStep(
        type: WorkflowStep.StepType,
        label: String?,
        value: String?,
        goal: String
    ) -> WorkflowStep {
        WorkflowStep(
            id: "harness_targetless_step",
            type: type,
            label: label,
            targetID: nil,
            targetMark: nil,
            value: value,
            direction: nil,
            amount: nil,
            by: nil,
            targetContext: nil,
            hint: goal,
            hintX: nil,
            hintY: nil,
            box2DNormalized: nil,
            screenNumber: nil
        )
    }

    private func plannedTargetlessActionStep(_ step: WorkflowStep) -> TipTourEnginePlannedActionStep {
        let label = step.label ?? step.value ?? step.direction ?? step.type.rawValue
        return TipTourEnginePlannedActionStep(
            type: step.type.rawValue,
            label: label,
            targetID: "targetless",
            targetMark: 0,
            hint: "Run targetless \(step.type.rawValue) action \"\(label)\"",
            box2D: [],
            matchedSource: "semantic",
            matchedConfidence: 1.0
        )
    }

    private func shouldForceReturnForBlenderConfirmation(_ request: PointerActionRequest) -> Bool {
        guard isBlenderAppContext(request.app) else { return false }
        let normalizedText = normalizedCommandText("\(request.goal) \(request.targetLabel ?? "")")
        return normalizedText.contains("confirmdelete")
            || normalizedText.contains("deleteconfirmation")
            || (normalizedText.contains("confirm") && normalizedText.contains("delete"))
            || (normalizedText.contains("apply") && normalizedText.contains("delete"))
    }

    private func isBlenderAppContext(_ appName: String?) -> Bool {
        if skillForAppHint(appName)?.name == "blender" {
            return true
        }
        if normalizedCommandText(appName ?? "").contains("blender") {
            return true
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "org.blenderfoundation.blender"
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func normalizedVisualContextMode(_ mode: String?) -> String {
        switch normalizedCommandText(mode ?? "auto") {
        case "none", "off", "noscreenshot", "disabled":
            return "none"
        case "compact", "compactstate", "state", "text":
            return "compact_state"
        case "crop", "targetcrop", "target", "targetimage", "targetregion":
            return "target_crop"
        case "full", "screenshot", "fullscreenshot", "image":
            return "full_screenshot"
        default:
            return "auto"
        }
    }

    private func normalizedVisualContextReason(_ reason: String?) -> String? {
        nonEmpty(reason)?.lowercased()
    }

    private func visualContextDecision(
        requestedMode: String,
        policyReason: String?,
        activeApp: NSRunningApplication?,
        targetCount: Int,
        targetDiagnosis: String?,
        hasFocusTarget: Bool
    ) -> TipTourEngineVisualContextDecision {
        var reasons = [String]()
        if let policyReason {
            reasons.append(policyReason)
        }

        let screenshotsEnabled = isScreenshotStreamingEnabledProvider()
        let requestedNone = requestedMode == "none"
        if requestedNone {
            reasons.append("agent_requested_no_screenshot")
            return TipTourEngineVisualContextDecision(
                mode: "none",
                requestedMode: requestedMode,
                reasons: reasons,
                screenshotAllowed: screenshotsEnabled,
                screenshotIncluded: false,
                screenChangedSinceLastSnapshot: nil
            )
        }

        guard screenshotsEnabled else {
            reasons.append("screenshots_disabled")
            return TipTourEngineVisualContextDecision(
                mode: "compact_state",
                requestedMode: requestedMode,
                reasons: reasons,
                screenshotAllowed: false,
                screenshotIncluded: false,
                screenChangedSinceLastSnapshot: nil
            )
        }

        if requestedMode == "compact_state" {
            reasons.append("agent_requested_compact_state")
            return TipTourEngineVisualContextDecision(
                mode: "compact_state",
                requestedMode: requestedMode,
                reasons: reasons,
                screenshotAllowed: true,
                screenshotIncluded: false,
                screenChangedSinceLastSnapshot: nil
            )
        }

        if requestedMode == "target_crop" {
            reasons.append(hasFocusTarget ? "agent_requested_target_crop" : "target_crop_requested_without_target")
            return TipTourEngineVisualContextDecision(
                mode: hasFocusTarget ? "target_crop" : "full_screenshot",
                requestedMode: requestedMode,
                reasons: reasons,
                screenshotAllowed: true,
                screenshotIncluded: false,
                screenChangedSinceLastSnapshot: nil
            )
        }

        if requestedMode == "full_screenshot" {
            reasons.append("agent_requested_screenshot")
            return TipTourEngineVisualContextDecision(
                mode: "full_screenshot",
                requestedMode: requestedMode,
                reasons: reasons,
                screenshotAllowed: true,
                screenshotIncluded: false,
                screenChangedSinceLastSnapshot: nil
            )
        }

        let canvasApp = isVisualCanvasApplication(activeApp)
        if canvasApp {
            reasons.append("canvas_app")
        }
        if targetCount == 0 {
            reasons.append("no_local_targets")
        }
        if let targetDiagnosis {
            reasons.append(targetDiagnosis)
        }
        if hasFocusTarget {
            reasons.append("focus_target_available")
        }
        if recentActionNeedsVisualContext() {
            reasons.append("recent_action_uncertain")
        }
        if policyReasonNeedsScreenshot(policyReason) {
            reasons.append("reason_requests_visual_context")
        }

        let shouldIncludeVisualContext = canvasApp
            || targetCount == 0
            || hasFocusTarget
            || targetDiagnosis == "target_not_found"
            || targetDiagnosis == "target_ambiguous"
            || targetDiagnosis == "explicit_target_not_found"
            || recentActionNeedsVisualContext()
            || policyReasonNeedsScreenshot(policyReason)
        let shouldUseTargetCrop = hasFocusTarget && targetDiagnosis != "target_ambiguous"

        return TipTourEngineVisualContextDecision(
            mode: shouldIncludeVisualContext ? (shouldUseTargetCrop ? "target_crop" : "full_screenshot") : "compact_state",
            requestedMode: requestedMode,
            reasons: reasons.isEmpty ? ["local_state_sufficient"] : reasons,
            screenshotAllowed: true,
            screenshotIncluded: false,
            screenChangedSinceLastSnapshot: nil
        )
    }

    private func visualFocusTarget(
        targetLabel: String?,
        targetID: String?,
        targetMark: Int?,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> LocalPerceptionTargetCache.SnapshotTarget? {
        if let target = explicitTarget(
            requestedTargetID: targetID,
            requestedTargetMark: targetMark,
            targets: targets
        ) {
            return target
        }

        guard let targetLabel = nonEmpty(targetLabel) else { return nil }
        return bestTarget(
            requestedLabel: targetLabel,
            goal: targetLabel,
            targets: targets,
            app: NSWorkspace.shared.frontmostApplication?.localizedName,
            excludingTargetIDs: []
        )
    }

    private func visualTargetDiagnosis(
        targetLabel: String?,
        targetID: String?,
        targetMark: Int?,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> String? {
        if didRequestExplicitTarget(targetID: targetID, targetMark: targetMark),
           explicitTarget(requestedTargetID: targetID, requestedTargetMark: targetMark, targets: targets) == nil {
            return "explicit_target_not_found"
        }

        guard let targetLabel = nonEmpty(targetLabel) else { return nil }
        let normalizedLabel = normalizedCommandText(targetLabel)
        guard !normalizedLabel.isEmpty else { return nil }

        let exactMatches = targets.filter {
            normalizedCommandText($0.label) == normalizedLabel
        }
        if exactMatches.count > 1 {
            return "target_ambiguous"
        }
        if exactMatches.count == 1 {
            return nil
        }

        let matchedTarget = bestTarget(
            requestedLabel: targetLabel,
            goal: targetLabel,
            targets: targets,
            app: NSWorkspace.shared.frontmostApplication?.localizedName,
            excludingTargetIDs: []
        )
        return matchedTarget == nil ? "target_not_found" : nil
    }

    private func recentActionNeedsVisualContext() -> Bool {
        guard let latestAttempt = recentActionAttempts.last else { return false }
        if !latestAttempt.submission.ok {
            return true
        }
        if latestAttempt.workflowOutcome.status != "completed" {
            return true
        }
        if latestAttempt.validation.requiredStateChange && !latestAttempt.validation.stateChanged {
            return true
        }
        return false
    }

    private func policyReasonNeedsScreenshot(_ reason: String?) -> Bool {
        guard let reason = reason?.lowercased() else { return false }
        return reason.contains("start")
            || reason.contains("screenshot")
            || reason.contains("visual")
            || reason.contains("canvas")
            || reason.contains("target_not_found")
            || reason.contains("ambiguous")
            || reason.contains("failed")
            || reason.contains("uncertain")
            || reason.contains("state_did_not_change")
            || reason.contains("follow_along")
    }

    private func isVisualCanvasApplication(_ application: NSRunningApplication?) -> Bool {
        let bundleIdentifier = application?.bundleIdentifier?.lowercased() ?? ""
        let appName = normalizedCommandText(application?.localizedName ?? "")
        let canvasBundles: Set<String> = [
            "org.blenderfoundation.blender",
            "com.figma.desktop",
            "com.adobe.photoshop",
            "com.adobe.illustrator"
        ]
        if canvasBundles.contains(bundleIdentifier) {
            return true
        }
        return appName.contains("blender")
            || appName.contains("figma")
            || appName.contains("sketch")
            || appName.contains("photoshop")
            || appName.contains("illustrator")
            || appName.contains("unity")
            || appName.contains("unreal")
    }

    private func explicitTarget(
        requestedTargetID: String?,
        requestedTargetMark: Int?,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> LocalPerceptionTargetCache.SnapshotTarget? {
        let requestedIDLabel = requestedTargetID.flatMap(Self.labelFromTargetID)

        if let requestedTargetID = requestedTargetID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedTargetID.isEmpty,
           let target = targets.first(where: { $0.id == requestedTargetID }) {
            return target
        }

        if let requestedTargetMark,
           requestedTargetMark > 0,
           let target = targets.first(where: { $0.mark == requestedTargetMark }) {
            if let requestedIDLabel,
               labelMatchScore(query: requestedIDLabel, label: target.label) == nil {
                return nil
            }
            return target
        }

        return nil
    }

    private static func labelFromTargetID(_ targetID: String) -> String? {
        let parts = targetID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 5 else { return nil }
        let coordinateParts = parts.suffix(4)
        guard coordinateParts.allSatisfy({ Int($0) != nil }) else { return nil }
        let labelParts = parts.dropFirst().dropLast(4)
        let label = labelParts.joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private func bestTarget(
        requestedLabel: String?,
        goal: String,
        targets: [LocalPerceptionTargetCache.SnapshotTarget],
        app: String?,
        excludingTargetIDs: Set<String>
    ) -> LocalPerceptionTargetCache.SnapshotTarget? {
        let availableTargets = targetsForGoalContext(
            targets.filter { !excludingTargetIDs.contains($0.id) },
            goal: goal,
            app: app
        )
        guard !availableTargets.isEmpty else { return nil }

        let query = requestedLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query, !query.isEmpty {
            return availableTargets
                .compactMap { target -> (target: LocalPerceptionTargetCache.SnapshotTarget, score: Double)? in
                    guard let score = labelMatchScore(query: query, label: target.label) else { return nil }
                    return (target, score + sourceScore(target.source) + min(target.confidence, 1.0))
                }
                .max { $0.score < $1.score }?
                .target
        }

        return availableTargets
            .compactMap { target -> (target: LocalPerceptionTargetCache.SnapshotTarget, score: Double)? in
                guard let score = labelMatchScore(query: goal, label: target.label) else { return nil }
                return (target, score + sourceScore(target.source) + min(target.confidence, 1.0))
            }
            .max { $0.score < $1.score }?
            .target
    }

    private func stepWithHarnessDefaults(
        _ step: WorkflowStep,
        planGoal: String,
        appName: String?
    ) -> WorkflowStep {
        switch step.type {
        case .type:
            guard (step.value?.isEmpty == false) || (step.label?.isEmpty == false) else {
                guard let inferredText = inferredTextToType(from: planGoal) else { return step }
                return replacingStepPayload(step, label: step.label, value: inferredText)
            }
            return step
        case .pressKey:
            guard step.label?.isEmpty != false else { return step }
            guard let inferredKey = inferredKeyToPress(from: planGoal, appName: appName) else { return step }
            return replacingStepPayload(step, label: inferredKey, value: step.value)
        case .keyboardShortcut:
            guard step.label?.isEmpty != false else { return step }
            guard let inferredShortcut = inferredKeyboardShortcut(from: planGoal) else { return step }
            return replacingStepPayload(step, label: inferredShortcut, value: step.value)
        default:
            return step
        }
    }

    private func invalidSingleActionReason(for step: WorkflowStep) -> String? {
        switch step.type {
        case .type:
            return ((step.value ?? step.label)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? nil
                : "type_text_missing"
        case .pressKey:
            return (step.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? nil
                : "press_key_missing"
        case .keyboardShortcut:
            return (step.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? nil
                : "keyboard_shortcut_missing"
        case .openApp, .openURL, .setValue:
            return ((step.value ?? step.label)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? nil
                : "\(step.type.rawValue)_payload_missing"
        default:
            return nil
        }
    }

    private func inferredTextToType(from goal: String) -> String? {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedGoal = trimmedGoal.lowercased()
        for prefix in ["type ", "enter ", "input ", "write "] {
            guard lowercasedGoal.hasPrefix(prefix) else { continue }
            let startIndex = trimmedGoal.index(trimmedGoal.startIndex, offsetBy: prefix.count)
            let inferredText = String(trimmedGoal[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return inferredText.isEmpty ? nil : inferredText
        }
        return nil
    }

    private func inferredKeyToPress(from goal: String, appName: String?) -> String? {
        let normalizedGoal = normalizedCommandText(goal)

        if let activeSkill = skillForAppHint(appName),
           let skillCommandAlias = activeSkill.commandAlias(for: goal),
           skillCommandAlias.type == .pressKey {
            return skillCommandAlias.label
        }

        if normalizedGoal.contains("confirm") || normalizedGoal.contains("apply") || normalizedGoal == "enter" {
            return "Return"
        }
        if normalizedGoal.contains("escape") || normalizedGoal.contains("cancel") {
            return "Escape"
        }

        return nil
    }

    private func inferredKeyboardShortcut(from goal: String) -> String? {
        switch normalizedCommandText(goal) {
        case "selectall":
            return "Cmd+A"
        case "copy":
            return "Cmd+C"
        case "paste":
            return "Cmd+V"
        case "cut":
            return "Cmd+X"
        case "undo":
            return "Cmd+Z"
        case "redo":
            return "Cmd+Shift+Z"
        default:
            return nil
        }
    }

    private func replacingStepPayload(
        _ step: WorkflowStep,
        label: String?,
        value: String?
    ) -> WorkflowStep {
        WorkflowStep(
            id: step.id,
            type: step.type,
            label: label,
            targetID: step.targetID,
            targetMark: step.targetMark,
            value: value,
            direction: step.direction,
            amount: step.amount,
            by: step.by,
            targetContext: step.targetContext,
            hint: step.hint,
            hintX: step.hintX,
            hintY: step.hintY,
            box2DNormalized: step.box2DNormalized,
            screenNumber: step.screenNumber
        )
    }

    private func targetsForGoalContext(
        _ targets: [LocalPerceptionTargetCache.SnapshotTarget],
        goal: String,
        app: String?
    ) -> [LocalPerceptionTargetCache.SnapshotTarget] {
        let normalizedGoal = normalizedCommandText(goal)
        let isChoosingFromMenu = normalizedGoal.contains("submenu")
            || normalizedGoal.contains("menuitem")
            || normalizedGoal.contains("dropdown")
            || normalizedGoal.contains("popover")
            || normalizedGoal.contains("frommenu")

        guard isChoosingFromMenu else { return targets }
        guard let activeSkill = skillForAppHint(app),
              let maximumNormalizedX = activeSkill.menuSelectionPreferredLeftRegionMaxX else {
            return targets
        }

        let filteredTargets = targets.filter { target in
            guard target.globalCenter.count >= 2,
                  target.displayFrame.count >= 4 else {
                return true
            }

            let centerX = target.globalCenter[0]
            let displayMinX = target.displayFrame[0]
            let displayMaxX = target.displayFrame[2]
            let displayWidth = max(1, displayMaxX - displayMinX)
            let normalizedX = (centerX - displayMinX) / displayWidth

            return normalizedX < maximumNormalizedX
        }

        return filteredTargets.isEmpty ? targets : filteredTargets
    }

    private func skillForAppHint(_ appName: String?) -> MarkdownAppSkill? {
        MarkdownAppSkillRegistry.shared.skill(applicationName: appName)
            ?? MarkdownAppSkillRegistry.shared.skill(for: NSWorkspace.shared.frontmostApplication)
    }

    private func normalizedCommandText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func activateRequestedApplicationForPerceptionIfNeeded(_ applicationNameOrBundleIdentifier: String?) async {
        guard let applicationNameOrBundleIdentifier = applicationNameOrBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationNameOrBundleIdentifier.isEmpty else {
            return
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           Self.application(frontmostApplication, matches: applicationNameOrBundleIdentifier) {
            return
        }

        let runningApplication = NSWorkspace.shared.runningApplications.first {
            Self.application($0, matches: applicationNameOrBundleIdentifier)
        }

        if let runningApplication {
            runningApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 260_000_000)
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationNameOrBundleIdentifier) ??
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.commonBundleIdentifier(for: applicationNameOrBundleIdentifier) ?? "") else {
            print("[Engine] target app \"\(applicationNameOrBundleIdentifier)\" is not running and could not be found for perception activation")
            return
        }

        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let launchedApplication = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
            launchedApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            try? await Task.sleep(nanoseconds: 520_000_000)
        } catch {
            print("[Engine] failed to activate \"\(applicationNameOrBundleIdentifier)\" before perception refresh: \(error.localizedDescription)")
        }
    }

    private func requestedApplicationIsFrontmost(_ applicationNameOrBundleIdentifier: String?) -> Bool {
        guard let applicationNameOrBundleIdentifier = applicationNameOrBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationNameOrBundleIdentifier.isEmpty else {
            return true
        }
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        return Self.application(frontmostApplication, matches: applicationNameOrBundleIdentifier)
    }

    private static func application(_ runningApplication: NSRunningApplication, matches requestedNameOrBundleIdentifier: String) -> Bool {
        let normalizedRequestedValue = requestedNameOrBundleIdentifier.lowercased()
        return runningApplication.bundleIdentifier?.lowercased() == normalizedRequestedValue
            || runningApplication.localizedName?.lowercased() == normalizedRequestedValue
    }

    private func activateRunningApplicationForWorkflowIfNeeded(_ applicationNameOrBundleIdentifier: String?) {
        guard let applicationNameOrBundleIdentifier = applicationNameOrBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !applicationNameOrBundleIdentifier.isEmpty else {
            return
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           Self.application(frontmostApplication, matches: applicationNameOrBundleIdentifier) {
            return
        }

        let runningApplication = NSWorkspace.shared.runningApplications.first {
            Self.application($0, matches: applicationNameOrBundleIdentifier)
        }

        runningApplication?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private static func commonBundleIdentifier(for applicationName: String) -> String? {
        switch applicationName.lowercased() {
        case "blender":
            return "org.blenderfoundation.blender"
        case "chrome", "google chrome":
            return "com.google.Chrome"
        case "safari":
            return "com.apple.Safari"
        case "xcode":
            return "com.apple.dt.Xcode"
        case "terminal":
            return "com.apple.Terminal"
        default:
            return nil
        }
    }

    private func labelMatchScore(query: String, label: String) -> Double? {
        let compactQuery = normalizedCommandText(query)
        let compactLabel = normalizedCommandText(label)
        if !compactQuery.isEmpty, compactQuery == compactLabel {
            return 100
        }

        let queryWords = meaningfulWords(from: query)
        let labelWords = meaningfulWords(from: label)
        guard !queryWords.isEmpty, !labelWords.isEmpty else { return nil }

        let normalizedQuery = queryWords.joined(separator: " ")
        let normalizedLabel = labelWords.joined(separator: " ")
        if normalizedQuery == normalizedLabel { return 100 }
        if min(normalizedQuery.count, normalizedLabel.count) >= 5,
           (normalizedQuery.contains(normalizedLabel) || normalizedLabel.contains(normalizedQuery)) {
            return 72
        }

        if queryWords.count == 1,
           labelWords.count == 1,
           let fuzzyScore = fuzzySingleWordLabelScore(query: queryWords[0], label: labelWords[0]) {
            return fuzzyScore
        }

        let sharedWords = Set(queryWords).intersection(Set(labelWords))
        guard !sharedWords.isEmpty else { return nil }
        return 36 + (Double(sharedWords.count) / Double(max(labelWords.count, 1)) * 28)
    }

    private func fuzzySingleWordLabelScore(query: String, label: String) -> Double? {
        guard min(query.count, label.count) >= 4,
              max(query.count, label.count) <= 16 else {
            return nil
        }

        let distance = editDistance(query, label)
        if distance == 1 { return 68 }
        if distance == 2, max(query.count, label.count) >= 5 { return 54 }
        return nil
    }

    private func editDistance(_ firstText: String, _ secondText: String) -> Int {
        let firstCharacters = Array(firstText)
        let secondCharacters = Array(secondText)
        guard !firstCharacters.isEmpty else { return secondCharacters.count }
        guard !secondCharacters.isEmpty else { return firstCharacters.count }

        var previousRow = Array(0...secondCharacters.count)
        var currentRow = Array(repeating: 0, count: secondCharacters.count + 1)

        for firstIndex in 1...firstCharacters.count {
            currentRow[0] = firstIndex
            for secondIndex in 1...secondCharacters.count {
                let substitutionCost = firstCharacters[firstIndex - 1] == secondCharacters[secondIndex - 1] ? 0 : 1
                currentRow[secondIndex] = min(
                    previousRow[secondIndex] + 1,
                    currentRow[secondIndex - 1] + 1,
                    previousRow[secondIndex - 1] + substitutionCost
                )
            }
            previousRow = currentRow
        }

        return previousRow[secondCharacters.count]
    }

    private func meaningfulWords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "this", "that", "button", "menu", "item",
            "click", "press", "choose", "select", "open", "add", "go", "to",
            "category", "submenu", "panel", "field", "option", "icon", "target"
        ]
        let words = text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopWords.contains($0) }
        return words.isEmpty
            ? text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            : words
    }

    private func sourceScore(_ source: String) -> Double {
        source == "ocr" ? 4 : 1
    }

    private struct AIGroundingCandidate: Encodable {
        let index: Int
        let id: String
        let mark: Int
        let label: String
        let source: String
        let box2D: [Int]
    }

    private struct AIGroundingMatch: Decodable {
        let index: Int?
        let target_id: String?
        let targetID: String?
        let match: String?
        let confidence: Double?
    }

    private struct GeminiGenerateContentEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

    private func aiMatchedTarget(
        query: String,
        intent: String,
        targets: [LocalPerceptionTargetCache.SnapshotTarget],
        app: String?
    ) async -> LocalPerceptionTargetCache.SnapshotTarget? {
        let candidateTargets = Array(
            targetsForGoalContext(targets, goal: intent, app: app)
                .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(60)
        )
        guard !candidateTargets.isEmpty else { return nil }

        let aiCandidates = candidateTargets.enumerated().map { index, target in
            AIGroundingCandidate(
                index: index + 1,
                id: target.id,
                mark: target.mark,
                label: target.label,
                source: target.source,
                box2D: target.normalizedBox2D
            )
        }

        if let directMatch = await directGeminiTargetMatch(
            query: query,
            intent: intent,
            candidates: aiCandidates
        ),
           let target = target(for: directMatch, in: candidateTargets, query: query) {
            return target
        }

        if let workerMatch = await workerTargetMatch(
            query: query,
            candidates: candidateTargets.map(\.label)
        ) {
            return candidateTargets.first {
                $0.label.caseInsensitiveCompare(workerMatch) == .orderedSame
                    && aiMatchedTargetIsAcceptable(query: query, target: $0)
            }
        }

        return nil
    }

    private func directGeminiTargetMatch(
        query: String,
        intent: String,
        candidates: [AIGroundingCandidate]
    ) async -> AIGroundingMatch? {
        guard let apiKey = KeychainStore.geminiAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            return nil
        }
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=\(apiKey)") else {
            return nil
        }

        let candidateJSON = (try? String(
            data: JSONEncoder().encode(candidates),
            encoding: .utf8
        )) ?? "[]"
        let prompt = """
        Choose the single UI target that best matches the user's query and intent.
        OCR labels may contain small typos, for example "Cude" can mean "Cube".
        The returned target must match the Query itself.
        Do not choose a parent menu, prerequisite, or action that would reveal the target.
        For example, if the Query is "Cube", do not choose "Mesh" just because Mesh may contain Cube.
        For example, if the Query is "Mesh", do not choose "Add" just because Add may contain Mesh.
        Intent is only extra context for resolving ambiguity; it is not permission to choose a different step.
        Do not invent targets.

        Query: \(query)
        Intent: \(intent)

        Candidates JSON:
        \(candidateJSON)

        Reply with JSON only:
        {"index": <candidate index>, "confidence": <0 to 1>}
        If the query itself is not clearly visible in the candidates, reply:
        {"index": null, "confidence": 0}
        """

        let payload: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 128,
                "responseMimeType": "application/json"
            ]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }

            let envelope = try JSONDecoder().decode(GeminiGenerateContentEnvelope.self, from: data)
            let innerJSONText = envelope.candidates?.first?.content?.parts?.first?.text ?? "{}"
            guard let innerData = innerJSONText.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(AIGroundingMatch.self, from: innerData)
        } catch {
            return nil
        }
    }

    private func workerTargetMatch(query: String, candidates: [String]) async -> String? {
        guard let workerBaseURL = ElementResolver.workerBaseURLOverride,
              let endpoint = URL(string: "\(workerBaseURL)/match-label") else {
            return nil
        }

        struct MatchLabelRequest: Encodable {
            let query: String
            let candidates: [String]
        }

        let cappedCandidates = Array(candidates.prefix(60))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(MatchLabelRequest(
            query: query,
            candidates: cappedCandidates
        ))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }

            let envelope = try JSONDecoder().decode(GeminiGenerateContentEnvelope.self, from: data)
            let innerJSONText = envelope.candidates?.first?.content?.parts?.first?.text ?? "{}"
            guard let innerData = innerJSONText.data(using: .utf8) else { return nil }
            return (try? JSONDecoder().decode(AIGroundingMatch.self, from: innerData))?.match
        } catch {
            return nil
        }
    }

    private func target(
        for match: AIGroundingMatch,
        in targets: [LocalPerceptionTargetCache.SnapshotTarget],
        query: String
    ) -> LocalPerceptionTargetCache.SnapshotTarget? {
        if let confidence = match.confidence, confidence < 0.45 {
            return nil
        }

        let matchedTarget: LocalPerceptionTargetCache.SnapshotTarget?
        if let index = match.index,
           index > 0,
           index <= targets.count {
            matchedTarget = targets[index - 1]
        } else {
            let matchedTargetID = (match.target_id ?? match.targetID)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let matchedTargetID, !matchedTargetID.isEmpty {
                matchedTarget = targets.first { $0.id == matchedTargetID }
            } else if let matchedLabel = match.match?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !matchedLabel.isEmpty {
                matchedTarget = targets.first {
                    $0.label.caseInsensitiveCompare(matchedLabel) == .orderedSame
                }
            } else {
                matchedTarget = nil
            }
        }

        guard let matchedTarget,
              aiMatchedTargetIsAcceptable(query: query, target: matchedTarget) else {
            return nil
        }
        return matchedTarget
    }

    private func aiMatchedTargetIsAcceptable(
        query: String,
        target: LocalPerceptionTargetCache.SnapshotTarget
    ) -> Bool {
        guard let score = labelMatchScore(query: query, label: target.label) else {
            return false
        }

        // Keep the cheap AI matcher as an OCR typo/ambiguity resolver, not
        // as a planner. This allows Cube -> Cude, but rejects Cube -> Add.
        return score >= 54
    }

    private struct GroundedActionExecutionResult {
        let ok: Bool
        let reason: String?
        let message: String?
        let attempts: [TipTourEngineActionAttempt]
        let repaired: Bool
        let latestTargets: [LocalPerceptionTargetCache.SnapshotTarget]
    }

    private func executeGroundedActionOnce(
        goal: String,
        app: String?,
        requestedActionType: WorkflowStep.StepType,
        initialTarget: LocalPerceptionTargetCache.SnapshotTarget,
        initialTargets: [LocalPerceptionTargetCache.SnapshotTarget],
        requireStateChange: Bool,
        traceID: String
    ) async -> GroundedActionExecutionResult {
        let attempt = await executeGroundedActionAttempt(
            attemptNumber: 1,
            goal: goal,
            app: app,
            actionType: requestedActionType,
            target: initialTarget,
            targetsBeforeAttempt: initialTargets,
            requireStateChange: requireStateChange,
            traceID: traceID
        )
        recordActionAttempt(attempt)

        if attempt.submission.ok,
           attempt.workflowOutcome.status == "completed",
           (!attempt.validation.requiredStateChange || attempt.validation.stateChanged) {
            return GroundedActionExecutionResult(
                ok: true,
                reason: nil,
                message: "Executed one grounded TipTour action.",
                attempts: [attempt],
                repaired: false,
                latestTargets: LocalPerceptionTargetCache.shared.currentTargets()
            )
        }

        let reason: String
        if !attempt.submission.ok {
            reason = attempt.submission.reason ?? "submission_failed"
        } else if attempt.workflowOutcome.status != "completed" {
            reason = attempt.workflowOutcome.reason ?? attempt.workflowOutcome.status
        } else if attempt.validation.requiredStateChange,
                  !attempt.validation.stateChanged {
            reason = "state_unchanged"
        } else {
            reason = "grounded_action_failed"
        }

        return GroundedActionExecutionResult(
            ok: false,
            reason: reason,
            message: "TipTour ran one grounded action but could not validate it.",
            attempts: [attempt],
            repaired: false,
            latestTargets: LocalPerceptionTargetCache.shared.currentTargets()
        )
    }

    private func executeGroundedActionAttempt(
        attemptNumber: Int,
        goal: String,
        app: String?,
        actionType: WorkflowStep.StepType,
        target: LocalPerceptionTargetCache.SnapshotTarget,
        targetsBeforeAttempt: [LocalPerceptionTargetCache.SnapshotTarget],
        requireStateChange: Bool,
        traceID: String
    ) async -> TipTourEngineActionAttempt {
        let step = workflowStep(
            actionType: actionType,
            target: target,
            id: "harness_planned_step_\(attemptNumber)"
        )
        let plannedStep = plannedActionStep(
            actionType: actionType,
            target: target
        )
        let submission = submitSingleActionWorkflowPlan(
            WorkflowPlan(
                goal: goal,
                app: app,
                steps: [step],
                traceID: traceID
            )
        )

        let workflowOutcome: TipTourEngineWorkflowOutcome
        if submission.ok {
            workflowOutcome = await waitForWorkflowSettlement()
        } else {
            workflowOutcome = TipTourEngineWorkflowOutcome(
                status: "not_started",
                reason: submission.reason,
                message: submission.message,
                waitMs: 0
            )
        }

        await refreshLocalPerception("harness post-action validation")
        let targetsAfterAttempt = LocalPerceptionTargetCache.shared.currentTargets()
        let validation = validateTargetSetChange(
            beforeTargets: targetsBeforeAttempt,
            afterTargets: targetsAfterAttempt,
            requireStateChange: requireStateChange
        )

        return TipTourEngineActionAttempt(
            traceID: traceID,
            attemptNumber: attemptNumber,
            timestamp: Self.iso8601Formatter.string(from: Date()),
            target: target,
            plannedStep: plannedStep,
            submission: submission,
            workflowOutcome: workflowOutcome,
            validation: validation
        )
    }

    private func workflowStep(
        actionType: WorkflowStep.StepType,
        target: LocalPerceptionTargetCache.SnapshotTarget,
        id: String
    ) -> WorkflowStep {
        WorkflowStep(
            id: id,
            type: actionType,
            label: target.label,
            targetID: target.id,
            targetMark: target.mark,
            value: nil,
            direction: nil,
            amount: nil,
            by: nil,
            targetContext: .visibleElement,
            hint: "Use local perception target \"\(target.label)\"",
            hintX: nil,
            hintY: nil,
            box2DNormalized: target.normalizedBox2D,
            screenNumber: nil
        )
    }

    private func plannedActionStep(
        actionType: WorkflowStep.StepType,
        target: LocalPerceptionTargetCache.SnapshotTarget
    ) -> TipTourEnginePlannedActionStep {
        TipTourEnginePlannedActionStep(
            type: actionType.rawValue,
            label: target.label,
            targetID: target.id,
            targetMark: target.mark,
            hint: "Use local perception target \"\(target.label)\"",
            box2D: target.normalizedBox2D,
            matchedSource: target.source,
            matchedConfidence: target.confidence
        )
    }

    private func waitForWorkflowSettlement() async -> TipTourEngineWorkflowOutcome {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(workflowSettlementTimeoutSeconds)

        while Date() < deadline {
            if let pausedReason = WorkflowRunner.shared.pausedReason {
                return TipTourEngineWorkflowOutcome(
                    status: "paused",
                    reason: "workflow_paused",
                    message: pausedReason.humanReadable,
                    waitMs: Self.elapsedMilliseconds(since: startedAt)
                )
            }

            if let failedLabel = WorkflowRunner.shared.currentStepResolutionFailureLabel {
                return TipTourEngineWorkflowOutcome(
                    status: "resolution_failed",
                    reason: "target_not_resolved",
                    message: "Could not resolve \"\(failedLabel)\" within WorkflowRunner's retry budget.",
                    waitMs: Self.elapsedMilliseconds(since: startedAt)
                )
            }

            if WorkflowRunner.shared.activePlan == nil {
                return TipTourEngineWorkflowOutcome(
                    status: "completed",
                    reason: nil,
                    message: "WorkflowRunner completed the single action.",
                    waitMs: Self.elapsedMilliseconds(since: startedAt)
                )
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return TipTourEngineWorkflowOutcome(
            status: "timed_out",
            reason: "workflow_settlement_timeout",
            message: "WorkflowRunner did not complete or pause within \(workflowSettlementTimeoutSeconds)s.",
            waitMs: Self.elapsedMilliseconds(since: startedAt)
        )
    }

    private func validateTargetSetChange(
        beforeTargets: [LocalPerceptionTargetCache.SnapshotTarget],
        afterTargets: [LocalPerceptionTargetCache.SnapshotTarget],
        requireStateChange: Bool
    ) -> TipTourEngineActionValidation {
        TipTourEngineActionValidation(
            stateChanged: targetSetSignature(beforeTargets) != targetSetSignature(afterTargets),
            requiredStateChange: requireStateChange,
            beforeTargetCount: beforeTargets.count,
            afterTargetCount: afterTargets.count
        )
    }

    private func targetSetSignature(_ targets: [LocalPerceptionTargetCache.SnapshotTarget]) -> String {
        targets
            .map { target in
                let quantizedBox = target.normalizedBox2D
                    .map { coordinate in
                        Int((Double(coordinate) / 10.0).rounded()) * 10
                    }
                    .map(String.init)
                    .joined(separator: ",")
                return "\(target.source):\(target.label.lowercased()):\(quantizedBox)"
            }
            .sorted()
            .joined(separator: "|")
    }

    private func recordActionAttempt(_ attempt: TipTourEngineActionAttempt) {
        recentActionAttempts.append(attempt)
        if recentActionAttempts.count > maximumRecentActionAttempts {
            recentActionAttempts.removeFirst(recentActionAttempts.count - maximumRecentActionAttempts)
        }
        recordEngineEvent(
            name: "action_attempt",
            status: attempt.submission.ok && attempt.workflowOutcome.status == "completed" ? "ok" : "failed",
            message: attempt.workflowOutcome.message,
            metadata: [
                TipTourActionTrace.metadataKey: attempt.traceID,
                "attempt": String(attempt.attemptNumber),
                "target_label": attempt.target.label,
                "target_id": attempt.target.id,
                "target_mark": String(attempt.target.mark),
                "action_type": attempt.plannedStep.type,
                "submission_ok": String(attempt.submission.ok),
                "workflow_status": attempt.workflowOutcome.status,
                "state_changed": String(attempt.validation.stateChanged),
                "state_change_required": String(attempt.validation.requiredStateChange),
                "before_target_count": String(attempt.validation.beforeTargetCount),
                "after_target_count": String(attempt.validation.afterTargetCount)
            ]
        )
    }

    private func recordEngineEvent(
        name: String,
        status: String,
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        PipelineLogStore.shared.record(
            category: "engine",
            name: name,
            status: status,
            message: message,
            metadata: metadata
        )
    }

    private func workflowPlanMetadata(_ plan: WorkflowPlan) -> [String: String] {
        var metadata = [
            "goal": plan.goal,
            "app": plan.app ?? "unknown",
            "step_count": String(plan.steps.count)
        ]
        if let traceID = plan.traceID {
            metadata[TipTourActionTrace.metadataKey] = traceID
        }
        return metadata
    }

    private func workflowStepMetadata(_ step: WorkflowStep) -> [String: String] {
        var metadata: [String: String] = [
            "step_id": step.id,
            "action_type": step.type.rawValue,
            "label": step.label ?? "none",
            "value_preview": step.value.map { String($0.prefix(80)) } ?? "none",
            "target_id": step.targetID ?? "none",
            "target_mark": step.targetMark.map(String.init) ?? "none",
            "target_context": step.targetContext?.rawValue ?? "none",
            "hint": step.hint
        ]
        if let direction = step.direction {
            metadata["direction"] = direction
        }
        if let amount = step.amount {
            metadata["amount"] = String(amount)
        }
        if let by = step.by {
            metadata["by"] = by
        }
        if let box = step.box2DNormalized {
            metadata["box_2d"] = box.map(String.init).joined(separator: ",")
        }
        return metadata
    }

    private func pointerActionMetadata(_ request: PointerActionRequest) -> [String: String] {
        var metadata = [
            "goal": request.goal,
            "app": request.app ?? "unknown",
            "action_type": request.actionType.rawValue,
            "target_label": request.targetLabel ?? "none",
            "target_id": request.targetID ?? "none",
            "target_mark": request.targetMark.map(String.init) ?? "none",
            "execute": String(request.execute),
            "allow_screenshot_planning": String(request.allowScreenshotPlanning),
            "validate_state_change": String(request.validateStateChange)
        ]
        if let traceID = request.traceID {
            metadata[TipTourActionTrace.metadataKey] = traceID
        }
        return metadata
    }

    private func targetMetadata(_ target: LocalPerceptionTargetCache.SnapshotTarget) -> [String: String] {
        [
            "target_label": target.label,
            "target_id": target.id,
            "target_mark": String(target.mark),
            "target_source": target.source,
            "target_confidence": String(format: "%.3f", target.confidence),
            "target_box_2d": target.normalizedBox2D.map(String.init).joined(separator: ",")
        ]
    }

    private static func elapsedMilliseconds(since startDate: Date) -> Int {
        Int(Date().timeIntervalSince(startDate) * 1000)
    }

private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum TipTourLongTaskStatus: String, Codable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .queued, .running:
            return false
        }
    }
}

struct TipTourLongTaskRunSnapshot: Encodable {
    let id: String
    let traceID: String
    let title: String
    let prompt: String
    let app: String?
    let status: TipTourLongTaskStatus
    let currentStepIndex: Int
    let completedStepCount: Int
    let totalSteps: Int
    let createdAt: String
    let updatedAt: String
    let completedAt: String?
    let failureReason: String?
    let failureMessage: String?
    let eventCount: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case traceID = "trace_id"
        case title
        case prompt
        case app
        case status
        case currentStepIndex
        case completedStepCount
        case totalSteps
        case createdAt
        case updatedAt
        case completedAt
        case failureReason
        case failureMessage
        case eventCount
    }

    var isTerminal: Bool {
        status.isTerminal
    }
}

struct TipTourLongTaskEvent: Encodable {
    let id: Int
    let taskID: String
    let traceID: String
    let type: String
    let timestamp: String
    let stepIndex: Int?
    let totalSteps: Int
    let message: String
    let actionType: String?
    let actionLabel: String?
    let submission: TipTourEngineSubmissionResult?
    let workflowOutcome: TipTourEngineWorkflowOutcome?

    private enum CodingKeys: String, CodingKey {
        case id
        case taskID
        case traceID = "trace_id"
        case type
        case timestamp
        case stepIndex
        case totalSteps
        case message
        case actionType
        case actionLabel
        case submission
        case workflowOutcome
    }
}

struct TipTourLongTaskStartResponse: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let task: TipTourLongTaskRunSnapshot?
}

struct TipTourLongTaskListResponse: Encodable {
    let ok: Bool
    let activeTaskID: String?
    let tasks: [TipTourLongTaskRunSnapshot]
}

struct TipTourLongTaskStatusResponse: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let task: TipTourLongTaskRunSnapshot?
}

struct TipTourLongTaskEventsResponse: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let taskID: String?
    let events: [TipTourLongTaskEvent]
}

struct TipTourLongTaskCancelResponse: Encodable {
    let ok: Bool
    let reason: String?
    let message: String?
    let task: TipTourLongTaskRunSnapshot?
}

struct TipTourLongTaskStep {
    let title: String
    let goal: String
    let actionLabel: String
    let workflowStep: WorkflowStep
    let settleDelayMilliseconds: Int
    let refreshTargetsAfter: Bool
}

@MainActor
final class TipTourLongTaskCoordinator {
    private unowned let engine: TipTourEngine
    private let activityReporter: @MainActor (String) -> Void
    private var runs: [String: TipTourLongTaskRun] = [:]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var activeTaskID: String?
    private var nextEventID = 1
    private let maximumEventsPerRun = 300

    init(
        engine: TipTourEngine,
        activityReporter: @escaping @MainActor (String) -> Void
    ) {
        self.engine = engine
        self.activityReporter = activityReporter
    }

    func startTask(
        title: String?,
        prompt: String,
        app: String?,
        steps: [TipTourLongTaskStep],
        traceID: String?
    ) -> TipTourLongTaskStartResponse {
        if let activeTaskID,
           let activeRun = runs[activeTaskID],
           !activeRun.status.isTerminal {
            return TipTourLongTaskStartResponse(
                ok: false,
                reason: "task_already_running",
                message: "TipTour is already running \"\(activeRun.title)\". Cancel or wait for that task before starting another one.",
                task: snapshot(for: activeRun)
            )
        }

        guard !steps.isEmpty else {
            return TipTourLongTaskStartResponse(
                ok: false,
                reason: "workflow_steps_required",
                message: "TipTour local tasks need explicit workflow steps. Planning can live in Hermes or Claude now and in stored workflows later.",
                task: nil
            )
        }

        let taskID = Self.makeTaskID()
        let traceID = traceID ?? TipTourActionTrace.makeID(source: "task")
        let now = Date()
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let runTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? prompt
        let run = TipTourLongTaskRun(
            id: taskID,
            traceID: traceID,
            title: runTitle,
            prompt: prompt,
            app: app,
            steps: steps,
            status: .queued,
            currentStepIndex: 0,
            completedStepCount: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: nil,
            failureReason: nil,
            failureMessage: nil,
            events: []
        )
        runs[taskID] = run
        activeTaskID = taskID
        appendEvent(
            taskID: taskID,
            type: "created",
            stepIndex: nil,
            message: "Created local task \"\(run.title)\".",
            actionType: nil,
            actionLabel: nil,
            submission: nil,
            workflowOutcome: nil
        )

        runningTasks[taskID] = Task { @MainActor [weak self] in
            await self?.runTask(id: taskID)
        }

        return TipTourLongTaskStartResponse(
            ok: true,
            reason: nil,
            message: "Started local TipTour task \"\(run.title)\".",
            task: runs[taskID].map { snapshot(for: $0) }
        )
    }

    func listTasks() -> TipTourLongTaskListResponse {
        TipTourLongTaskListResponse(
            ok: true,
            activeTaskID: activeTaskID,
            tasks: runs.values
                .sorted { $0.createdAt > $1.createdAt }
                .map { snapshot(for: $0) }
        )
    }

    func task(id: String) -> TipTourLongTaskStatusResponse {
        guard let run = runs[id] else {
            return TipTourLongTaskStatusResponse(
                ok: false,
                reason: "task_not_found",
                message: "No TipTour task exists with id \(id).",
                task: nil
            )
        }

        return TipTourLongTaskStatusResponse(
            ok: true,
            reason: nil,
            message: nil,
            task: snapshot(for: run)
        )
    }

    func events(id: String) -> TipTourLongTaskEventsResponse {
        guard let run = runs[id] else {
            return TipTourLongTaskEventsResponse(
                ok: false,
                reason: "task_not_found",
                message: "No TipTour task exists with id \(id).",
                taskID: id,
                events: []
            )
        }

        return TipTourLongTaskEventsResponse(
            ok: true,
            reason: nil,
            message: nil,
            taskID: id,
            events: run.events
        )
    }

    func cancelTask(id: String) -> TipTourLongTaskCancelResponse {
        guard let run = runs[id] else {
            return TipTourLongTaskCancelResponse(
                ok: false,
                reason: "task_not_found",
                message: "No TipTour task exists with id \(id).",
                task: nil
            )
        }

        guard !run.status.isTerminal else {
            return TipTourLongTaskCancelResponse(
                ok: true,
                reason: nil,
                message: "Task is already \(run.status.rawValue).",
                task: snapshot(for: run)
            )
        }

        runningTasks[id]?.cancel()
        WorkflowRunner.shared.stop()
        finishTask(
            id: id,
            status: .cancelled,
            reason: "cancelled_by_request",
            message: "Task was cancelled."
        )

        return TipTourLongTaskCancelResponse(
            ok: true,
            reason: nil,
            message: "Cancelled task \(id).",
            task: runs[id].map { snapshot(for: $0) }
        )
    }

    func waitForTaskCompletion(
        id: String,
        timeoutSeconds: TimeInterval
    ) async -> TipTourLongTaskStatusResponse {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let response = task(id: id)
            if response.task?.isTerminal == true {
                return response
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let response = task(id: id)
        guard let task = response.task else { return response }
        return TipTourLongTaskStatusResponse(
            ok: false,
            reason: "task_wait_timeout",
            message: "Task \(task.id) is still \(task.status.rawValue).",
            task: task
        )
    }

    private func runTask(id: String) async {
        guard let run = runs[id] else { return }

        updateRun(id) { run in
            run.status = .running
        }
        appendEvent(
            taskID: id,
            type: "started",
            stepIndex: nil,
            message: "Running \(run.steps.count) local action(s).",
            actionType: nil,
            actionLabel: nil,
            submission: nil,
            workflowOutcome: nil
        )
        activityReporter("Local task - \(run.title)")

        for (zeroBasedIndex, step) in run.steps.enumerated() {
            if Task.isCancelled || runs[id]?.status == .cancelled {
                finishTask(
                    id: id,
                    status: .cancelled,
                    reason: "task_cancelled",
                    message: "Task was cancelled before step \(zeroBasedIndex + 1)."
                )
                return
            }

            let oneBasedStepIndex = zeroBasedIndex + 1
            updateRun(id) { run in
                run.currentStepIndex = oneBasedStepIndex
            }
            appendEvent(
                taskID: id,
                type: "step_started",
                stepIndex: oneBasedStepIndex,
                message: step.title,
                actionType: step.workflowStep.type.rawValue,
                actionLabel: step.actionLabel,
                submission: nil,
                workflowOutcome: nil
            )
            activityReporter("Local task - \(step.title)")

            let submission = await engine.submitSingleActionWorkflowPlanAndWait(
                WorkflowPlan(
                    goal: step.goal,
                    app: run.app,
                    steps: [step.workflowStep],
                    traceID: run.traceID
                )
            )

            if Task.isCancelled || runs[id]?.status == .cancelled {
                finishTask(
                    id: id,
                    status: .cancelled,
                    reason: "task_cancelled",
                    message: "Task was cancelled during \(step.title)."
                )
                return
            }

            appendEvent(
                taskID: id,
                type: submission.ok ? "action_completed" : "action_failed",
                stepIndex: oneBasedStepIndex,
                message: submission.message ?? (submission.ok ? "Action completed." : "Action failed."),
                actionType: step.workflowStep.type.rawValue,
                actionLabel: step.actionLabel,
                submission: submission,
                workflowOutcome: submission.workflowOutcome
            )

            guard submission.ok else {
                finishTask(
                    id: id,
                    status: .failed,
                    reason: submission.reason ?? "action_failed",
                    message: submission.message ?? "TipTour action failed during \(step.title)."
                )
                return
            }

            updateRun(id) { run in
                run.completedStepCount = oneBasedStepIndex
            }

            if step.settleDelayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(step.settleDelayMilliseconds) * 1_000_000)
            }

            if step.refreshTargetsAfter {
                let targets = await engine.localPerceptionTargets(
                    refresh: true,
                    reason: "local task checkpoint"
                )
                appendEvent(
                    taskID: id,
                    type: "checkpoint",
                    stepIndex: oneBasedStepIndex,
                    message: "Checkpoint captured \(targets.targetCount) visible target(s).",
                    actionType: nil,
                    actionLabel: nil,
                    submission: nil,
                    workflowOutcome: nil
                )
            }
        }

        finishTask(
            id: id,
            status: .completed,
            reason: nil,
            message: "Completed local task \"\(run.title)\"."
        )
    }

    private func finishTask(
        id: String,
        status: TipTourLongTaskStatus,
        reason: String?,
        message: String
    ) {
        if runs[id]?.status.isTerminal == true {
            runningTasks[id] = nil
            if activeTaskID == id {
                activeTaskID = nil
            }
            return
        }

        updateRun(id) { run in
            run.status = status
            run.completedAt = Date()
            run.failureReason = status == .failed || status == .cancelled ? reason : nil
            run.failureMessage = status == .failed || status == .cancelled ? message : nil
        }
        appendEvent(
            taskID: id,
            type: status.rawValue,
            stepIndex: nil,
            message: message,
            actionType: nil,
            actionLabel: nil,
            submission: nil,
            workflowOutcome: nil
        )
        activityReporter(message)
        runningTasks[id] = nil
        if activeTaskID == id {
            activeTaskID = nil
        }
    }

    private func updateRun(
        _ id: String,
        mutate: (inout TipTourLongTaskRun) -> Void
    ) {
        guard var run = runs[id] else { return }
        mutate(&run)
        run.updatedAt = Date()
        runs[id] = run
    }

    @discardableResult
    private func appendEvent(
        taskID: String,
        type: String,
        stepIndex: Int?,
        message: String,
        actionType: String?,
        actionLabel: String?,
        submission: TipTourEngineSubmissionResult?,
        workflowOutcome: TipTourEngineWorkflowOutcome?
    ) -> TipTourLongTaskEvent? {
        guard var run = runs[taskID] else { return nil }
        let event = TipTourLongTaskEvent(
            id: nextEventID,
            taskID: taskID,
            traceID: run.traceID,
            type: type,
            timestamp: Self.iso8601Formatter.string(from: Date()),
            stepIndex: stepIndex,
            totalSteps: run.steps.count,
            message: message,
            actionType: actionType,
            actionLabel: actionLabel,
            submission: submission,
            workflowOutcome: workflowOutcome
        )
        nextEventID += 1
        run.events.append(event)
        if run.events.count > maximumEventsPerRun {
            run.events.removeFirst(run.events.count - maximumEventsPerRun)
        }
        run.updatedAt = Date()
        runs[taskID] = run
        PipelineLogStore.shared.record(
            category: "task",
            name: type,
            status: taskLogStatus(
                eventType: type,
                submission: submission,
                workflowOutcome: workflowOutcome
            ),
            message: message,
            metadata: [
                TipTourActionTrace.metadataKey: run.traceID,
                "task_id": taskID,
                "task_title": run.title,
                "step_index": stepIndex.map(String.init) ?? "none",
                "total_steps": String(run.steps.count),
                "action_type": actionType ?? "none",
                "action_label": actionLabel ?? "none",
                "submission_ok": submission.map { String($0.ok) } ?? "none",
                "workflow_status": workflowOutcome?.status ?? "none",
                "reason": submission?.reason ?? workflowOutcome?.reason ?? "none"
            ]
        )
        return event
    }

    private func taskLogStatus(
        eventType: String,
        submission: TipTourEngineSubmissionResult?,
        workflowOutcome: TipTourEngineWorkflowOutcome?
    ) -> String {
        if submission?.ok == false {
            return "failed"
        }
        if let workflowOutcome,
           workflowOutcome.status != "completed" {
            return workflowOutcome.status
        }

        switch eventType {
        case "completed", "action_completed", "checkpoint":
            return "ok"
        case "failed", "action_failed":
            return "failed"
        case "cancelled":
            return "cancelled"
        default:
            return "info"
        }
    }

    private func snapshot(for run: TipTourLongTaskRun) -> TipTourLongTaskRunSnapshot {
        TipTourLongTaskRunSnapshot(
            id: run.id,
            traceID: run.traceID,
            title: run.title,
            prompt: run.prompt,
            app: run.app,
            status: run.status,
            currentStepIndex: run.currentStepIndex,
            completedStepCount: run.completedStepCount,
            totalSteps: run.steps.count,
            createdAt: Self.iso8601Formatter.string(from: run.createdAt),
            updatedAt: Self.iso8601Formatter.string(from: run.updatedAt),
            completedAt: run.completedAt.map { Self.iso8601Formatter.string(from: $0) },
            failureReason: run.failureReason,
            failureMessage: run.failureMessage,
            eventCount: run.events.count
        )
    }

    private static func makeTaskID() -> String {
        "task_" + UUID().uuidString.prefix(8).lowercased()
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct TipTourLongTaskRun {
    let id: String
    let traceID: String
    let title: String
    let prompt: String
    let app: String?
    let steps: [TipTourLongTaskStep]
    var status: TipTourLongTaskStatus
    var currentStepIndex: Int
    var completedStepCount: Int
    let createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var failureReason: String?
    var failureMessage: String?
    var events: [TipTourLongTaskEvent]
}
