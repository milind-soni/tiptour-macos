//
//  WorkflowRunner.swift
//  TipTour
//
//  Executes a WorkflowPlan step-by-step:
//    • Resolves the active step's element via ElementResolver and flies
//      the cursor there.
//    • Arms ClickDetector on the resolved target (preferring the real
//      AX rect over a fixed radius) so a real user click advances the
//      plan automatically.
//    • Publishes the full plan so the overlay/panel can show the
//      remaining steps as a checklist.
//    • Retries resolution with a budget instead of giving up silently
//      when an element hasn't appeared yet — a menu that's still
//      animating open should not stall the runner.
//

import AppKit
import Combine
import Foundation

@MainActor
final class WorkflowRunner: ObservableObject {

    static let shared = WorkflowRunner()

    /// The currently-active plan, or nil if no workflow is running.
    @Published private(set) var activePlan: WorkflowPlan?

    /// Which step is currently highlighted (0-indexed). Advances when
    /// ClickDetector sees the user click the armed target, when the
    /// user taps "Skip", or when resolution succeeds on a retry.
    @Published private(set) var activeStepIndex: Int = 0

    /// True while we're mid-resolve on a step — used by the UI to show
    /// a subtle "looking for next element..." indicator instead of
    /// making the row look stuck.
    @Published private(set) var isResolvingCurrentStep: Bool = false

    /// Non-nil when the current step failed to resolve after the full
    /// retry budget. Surfaces a "couldn't find: X — skip?" prompt so
    /// the user isn't stranded.
    @Published private(set) var currentStepResolutionFailureLabel: String?

    /// Remembered between `start` and subsequent `advance` calls so the
    /// click-driven auto-advance doesn't need the caller to re-thread
    /// these dependencies every step. Cleared on `stop`.
    private var pointHandlerForActivePlan: ((ElementResolver.Resolution) -> Void)?
    private var latestCaptureForActivePlan: CompanionScreenCapture?

    /// The previously-resolved step's global screen coordinate. Passed
    /// to `ElementResolver.resolve` as a proximity anchor so that when
    /// the current step's label (e.g. "New") matches multiple places
    /// on screen, we prefer the one closest to where the user just
    /// clicked — effectively "follow the menu chain" without modeling
    /// parent-child structure explicitly.
    private var previousStepResolvedGlobalScreenPoint: CGPoint?

    /// Cancels any in-flight resolution loop when the user skips, stops,
    /// or the plan advances for another reason.
    private var activeStepResolutionTask: Task<Void, Never>?

    /// Total budget for trying to find a step's element across retries.
    /// Covers animated menu opens, sheet transitions, and apps that take
    /// a beat to settle. We exit early the moment we get a hit.
    private let stepResolutionTimeoutSeconds: Double = 3.5

    /// Short settle nap on the very first resolve attempt after a click
    /// fires the advance. Gives the click's effect (menu open, sheet
    /// appear) a moment to start rendering before we poll.
    private let postClickInitialSettleSeconds: Double = 0.08

    /// Time budget for each individual AX poll pass inside a retry.
    /// Kept short so we react to newly-appearing elements quickly.
    private let axPollTimeoutPerAttemptSeconds: Double = 0.9

    /// The step that the cursor is currently pointed at. nil = no
    /// step is active (either no plan, or the plan has finished).
    var activeStep: WorkflowStep? {
        guard let plan = activePlan,
              activeStepIndex >= 0 && activeStepIndex < plan.steps.count else {
            return nil
        }
        return plan.steps[activeStepIndex]
    }

    /// Remaining steps after the current one — used for the UI preview.
    var upcomingSteps: [WorkflowStep] {
        guard let plan = activePlan else { return [] }
        let startIndex = activeStepIndex + 1
        guard startIndex < plan.steps.count else { return [] }
        return Array(plan.steps[startIndex...])
    }

    // MARK: - Start / Stop

    /// Begin executing a plan. Resolves and points at step 1 immediately,
    /// using a freshly-captured screenshot rather than whatever was
    /// cached from Gemini Live's periodic updates. `pointHandler` is the
    /// closure that actually moves the cursor — injected so
    /// CompanionManager can own the overlay state.
    func start(
        plan: WorkflowPlan,
        pointHandler: @escaping (ElementResolver.Resolution) -> Void,
        latestCapture: CompanionScreenCapture?
    ) {
        guard !plan.steps.isEmpty else {
            print("[Workflow] ignoring plan with no steps")
            return
        }

        activeStepResolutionTask?.cancel()
        activePlan = plan
        activeStepIndex = 0
        currentStepResolutionFailureLabel = nil
        pointHandlerForActivePlan = pointHandler
        latestCaptureForActivePlan = latestCapture
        // Fresh plan — no prior step to bias toward.
        previousStepResolvedGlobalScreenPoint = nil
        print("[Workflow] starting \"\(plan.goal)\" — \(plan.steps.count) step(s)")

        // For step 1 the incoming `latestCapture` can be several seconds
        // stale (Gemini Live's periodic screenshot timer stops when we
        // close the session). Refresh first so YOLO/LLM fallback runs
        // against a current frame.
        activeStepResolutionTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCaptureAndResolveActiveStep(isPostClick: false)
        }
    }

    /// Update the cached screenshot used for step resolution. Called by
    /// CompanionManager when a fresh capture arrives so subsequent
    /// step transitions resolve against up-to-date pixels.
    func updateLatestCapture(_ capture: CompanionScreenCapture?) {
        latestCaptureForActivePlan = capture
    }

    /// Clear any active plan. Called when the user starts a new
    /// interaction or the session ends.
    func stop() {
        activeStepResolutionTask?.cancel()
        activeStepResolutionTask = nil

        guard activePlan != nil else {
            ClickDetector.shared.disarm()
            isResolvingCurrentStep = false
            currentStepResolutionFailureLabel = nil
            return
        }
        activePlan = nil
        activeStepIndex = 0
        isResolvingCurrentStep = false
        currentStepResolutionFailureLabel = nil
        pointHandlerForActivePlan = nil
        latestCaptureForActivePlan = nil
        previousStepResolvedGlobalScreenPoint = nil
        ClickDetector.shared.disarm()
        print("[Workflow] stopped")
    }

    // MARK: - Advance / Skip

    /// Move to the next step and point the cursor at it. Called either
    /// by ClickDetector (when the user clicks the armed target) or
    /// externally by debug UI.
    func advance(
        pointHandler: @escaping (ElementResolver.Resolution) -> Void,
        latestCapture: CompanionScreenCapture?
    ) {
        pointHandlerForActivePlan = pointHandler
        latestCaptureForActivePlan = latestCapture
        advanceUsingCachedHandlers(isPostClick: false)
    }

    /// Explicitly skip the current step. Used by the "Skip" button in
    /// the panel UI and by the resolution-failure prompt. Treated
    /// identically to a successful advance so the runner keeps flowing.
    func skipCurrentStep() {
        print("[Workflow] user skipped step \(activeStepIndex + 1)")
        currentStepResolutionFailureLabel = nil
        advanceUsingCachedHandlers(isPostClick: false)
    }

    /// Retry resolving the current step from scratch — re-captures the
    /// screen and reruns the full resolver cascade. Used when an
    /// earlier attempt timed out and the user taps "Try again".
    func retryCurrentStep() {
        print("[Workflow] user retrying step \(activeStepIndex + 1)")
        currentStepResolutionFailureLabel = nil
        activeStepResolutionTask?.cancel()
        activeStepResolutionTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshCaptureAndResolveActiveStep(isPostClick: false)
        }
    }

    /// Advance using the pointHandler/capture cached when the plan
    /// started. This is what ClickDetector's callback uses.
    private func advanceUsingCachedHandlers(isPostClick: Bool) {
        guard let plan = activePlan else { return }
        guard pointHandlerForActivePlan != nil else {
            print("[Workflow] advance requested but no cached pointHandler — stopping")
            stop()
            return
        }
        guard activeStepIndex + 1 < plan.steps.count else {
            print("[Workflow] plan complete")
            stop()
            return
        }
        activeStepIndex += 1
        currentStepResolutionFailureLabel = nil
        activeStepResolutionTask?.cancel()
        activeStepResolutionTask = Task { [weak self] in
            guard let self else { return }
            // After a real click, the UI is mid-transition (menu opening,
            // sheet appearing). Instead of blindly sleeping, give it a
            // very short nap to let the click register, then rely on the
            // AX-polling retry budget inside the resolve loop to catch
            // the next element the moment it appears.
            if isPostClick {
                try? await Task.sleep(nanoseconds: UInt64(self.postClickInitialSettleSeconds * 1_000_000_000))
            }
            await self.refreshCaptureAndResolveActiveStep(isPostClick: isPostClick)
        }
    }

    /// Capture a fresh screenshot of every connected display, then run
    /// the resolution loop on the active step. Polls AX for the element
    /// (up to the budget) so a menu that's animating open doesn't cause
    /// a silent stall.
    private func refreshCaptureAndResolveActiveStep(isPostClick: Bool) async {
        let freshCaptures = await Self.captureAllScreens()
        if let pickedCapture = freshCaptures.first(where: { $0.isCursorScreen }) ?? freshCaptures.first {
            latestCaptureForActivePlan = pickedCapture
        }

        guard let step = activeStep else { return }
        guard step.type == .click else {
            // Future step types (keyboardShortcut, type, scroll, etc.)
            // don't map to a pointer location. Skip for now.
            print("[Workflow] step \"\(step.hint)\" is .\(step.type.rawValue) — pointer not applicable yet")
            return
        }
        guard let label = step.label, !label.isEmpty else {
            print("[Workflow] step \"\(step.hint)\" has no label — skipping")
            return
        }

        await resolveActiveStepWithRetryBudget(
            label: label,
            allScreenCaptures: freshCaptures,
            isPostClick: isPostClick
        )
    }

    /// Core of the "don't stall silently" fix. We try AX first (cheap,
    /// reruns quickly), then fall back to YOLO on each new frame, for up
    /// to `stepResolutionTimeoutSeconds`. Exits early the moment any
    /// strategy finds the element. If nothing resolves in the budget,
    /// publishes a failure label the UI surfaces as "can't find X —
    /// skip?".
    private func resolveActiveStepWithRetryBudget(
        label: String,
        allScreenCaptures: [CompanionScreenCapture],
        isPostClick: Bool
    ) async {
        isResolvingCurrentStep = true
        defer { isResolvingCurrentStep = false }

        let deadline = Date().addingTimeInterval(stepResolutionTimeoutSeconds)
        var latestAllCaptures = allScreenCaptures
        var attemptIndex = 0

        while Date() < deadline {
            if Task.isCancelled { return }
            attemptIndex += 1

            // Pass 1: poll AX with a short budget. This is the fast path
            // for native apps and Electron — usually resolves in <100ms.
            if let axResolution = await ElementResolver.shared.pollAccessibilityTree(
                label: label,
                targetAppHint: activePlan?.app,
                timeoutSeconds: axPollTimeoutPerAttemptSeconds
            ) {
                if Task.isCancelled { return }
                armCursorAndClickDetector(with: axResolution, pickingFrom: latestAllCaptures)
                return
            }

            // Pass 2: refresh the screenshot (app may have redrawn since
            // the last capture) and try YOLO + LLM fallback.
            latestAllCaptures = await Self.captureAllScreens()
            let pickedCapture = latestAllCaptures.first(where: { $0.isCursorScreen }) ?? latestAllCaptures.first
            latestCaptureForActivePlan = pickedCapture

            if let capture = pickedCapture,
               let resolution = await ElementResolver.shared.resolve(
                   label: label,
                   llmHintInScreenshotPixels: activeStep?.hintCoordinate,
                   latestCapture: capture,
                   targetAppHint: activePlan?.app,
                   runDetectorOnMiss: true,
                   proximityAnchorInGlobalScreen: previousStepResolvedGlobalScreenPoint
               ) {
                if Task.isCancelled { return }
                armCursorAndClickDetector(with: resolution, pickingFrom: latestAllCaptures)
                return
            }

            // Didn't resolve yet — on a post-click retry the first couple
            // of attempts can miss because the UI is mid-animation. Short
            // wait before the next pass.
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // Ran out of budget. Surface the failure so the UI can prompt
        // the user to skip or retry instead of stalling silently.
        print("[Workflow] ✗ step \(activeStepIndex + 1) \"\(label)\" did not resolve within \(stepResolutionTimeoutSeconds)s (\(attemptIndex) attempts)")
        currentStepResolutionFailureLabel = label
    }

    /// Once we have a resolution, move the cursor, pick the right-monitor
    /// display frame, and arm the click detector with the tightest hit
    /// area available (AX rect when present, point + radius otherwise).
    private func armCursorAndClickDetector(
        with resolution: ElementResolver.Resolution,
        pickingFrom allScreenCaptures: [CompanionScreenCapture]
    ) {
        // Prefer the capture whose display actually contains the resolved
        // point — matters when the target is on a non-cursor monitor.
        if let matchingCapture = allScreenCaptures.first(where: {
            $0.displayFrame.contains(resolution.globalScreenPoint)
        }) {
            latestCaptureForActivePlan = matchingCapture
        }

        // Remember this step's resolved point so the NEXT step's
        // resolution can tie-break multiple label matches in favor of
        // the one closest to where we just clicked. That's how nested
        // menu resolution stays correct without modeling parent-child
        // structure — "New" near the just-opened File menu beats a
        // stray "New Tab" button elsewhere on screen.
        previousStepResolvedGlobalScreenPoint = resolution.globalScreenPoint

        // Arm the detector BEFORE handing the cursor the new resolution.
        // The cursor flight takes ~500ms and a fast user can click the
        // real element during that window; arming first closes the race.
        ClickDetector.shared.arm(
            targetPointInGlobalScreenCoordinates: resolution.globalScreenPoint,
            targetRectInGlobalScreenCoordinates: resolution.globalScreenRect,
            onTargetClicked: { [weak self] in
                guard let self else { return }
                print("[Workflow] target click detected — advancing to next step")
                self.advanceUsingCachedHandlers(isPostClick: true)
            }
        )

        // Fly the cursor. Handler is cached so subsequent steps keep it.
        if let pointHandler = pointHandlerForActivePlan {
            pointHandler(resolution)
        }
    }

    /// Grab a capture of every connected display. Returns an empty array
    /// on failure — the caller decides how to fall back.
    private static func captureAllScreens() async -> [CompanionScreenCapture] {
        do {
            return try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()
        } catch {
            print("[Workflow] failed to capture screens: \(error)")
            return []
        }
    }
}
