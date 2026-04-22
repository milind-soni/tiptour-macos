//
//  ClickDetector.swift
//  TipTour
//
//  Listens for global left-mouse-down events and fires a callback if
//  the click lands inside (or within a small tolerance of) the currently
//  armed target. Used by WorkflowRunner to auto-advance the tutorial
//  checklist when the user clicks the element the cursor is pointing at.
//
//  Deliberately minimal:
//    • One armed target at a time (replaces the previous one).
//    • Listen-only CGEvent tap — never blocks or modifies the click.
//    • Single source of truth: WorkflowRunner owns when to arm/disarm.
//    • Prefers a real AX-frame rect when we have one (tight fit around
//      the element) and falls back to a 40pt radius around the point
//      when we don't (YOLO/LLM-only resolutions).
//    • Swallows extra clicks inside the "advance grace window" so a
//      double-click required by the UI (open file, activate tool)
//      doesn't race-advance the next step before its arm is wired up.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class ClickDetector {

    static let shared = ClickDetector()

    /// How far (in global screen points) a click can land from the armed
    /// target point and still count as "hit" when we have no element
    /// rect to check against. 40pt matches the overlay cursor size and
    /// forgives slight pointing inaccuracies.
    private let pointOnlyHitToleranceInScreenPoints: CGFloat = 40

    /// When we DO have an element rect (AX), we inflate it by this many
    /// points so a click that just barely misses the visual bounds still
    /// counts. 6pt is tight enough to reject adjacent menu items.
    private let rectInflationInScreenPoints: CGFloat = 6

    /// After firing a hit, briefly ignore further clicks. Lets a required
    /// double-click on the current step flow through to the app without
    /// racing into whatever target we arm next.
    private let postHitGraceIntervalInSeconds: TimeInterval = 0.18

    /// Debug: when true, ANY left-click advances the workflow — both the
    /// distance and rect checks are bypassed. Useful for walking through
    /// a plan when YOLO/AX resolves the wrong element so the user can
    /// still progress.
    static var advanceOnAnyClickEnabled: Bool = false

    /// The target the user is expected to click next, in global AppKit
    /// screen coordinates. Nil means nothing is armed — clicks are
    /// ignored.
    private var armedTargetPointInGlobalScreenCoordinates: CGPoint?

    /// Optional tight rect for the armed element, in global AppKit
    /// coordinates. When present, clicks inside it (plus inflation)
    /// count as a hit regardless of distance from the center point.
    /// When nil, we fall back to the radius check around the point.
    private var armedTargetRectInGlobalScreenCoordinates: CGRect?

    /// Timestamp of the most recent successful hit. Clicks that arrive
    /// within `postHitGraceIntervalInSeconds` of this are ignored so the
    /// next step's arm doesn't eat the second half of a double-click.
    private var lastSuccessfulHitTimestamp: Date?

    /// Fired on the main actor when a click lands within tolerance of
    /// the armed target. WorkflowRunner sets this to its advance routine.
    private var onTargetClicked: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    // MARK: - Arm / Disarm

    /// Arm the detector with a new target. Starts the global event tap
    /// lazily on first arm. Safe to call repeatedly — the previous target
    /// is simply replaced. Pass `targetRect` when you know the element's
    /// real bounds (AX resolution) for a tighter fit; pass nil when all
    /// you have is a point (YOLO/LLM).
    func arm(
        targetPointInGlobalScreenCoordinates: CGPoint,
        targetRectInGlobalScreenCoordinates: CGRect? = nil,
        onTargetClicked: @escaping @MainActor () -> Void
    ) {
        self.armedTargetPointInGlobalScreenCoordinates = targetPointInGlobalScreenCoordinates
        self.armedTargetRectInGlobalScreenCoordinates = targetRectInGlobalScreenCoordinates
        self.onTargetClicked = onTargetClicked
        startEventTapIfNeeded()
        if let rect = targetRectInGlobalScreenCoordinates {
            print("[ClickDetector] armed rect \(rect) (inflation \(rectInflationInScreenPoints)pt)")
        } else {
            print("[ClickDetector] armed point \(targetPointInGlobalScreenCoordinates) — tolerance \(pointOnlyHitToleranceInScreenPoints)pt")
        }
    }

    /// Disarm the detector. The event tap stays installed (cheap) but
    /// clicks are ignored until the next `arm` call.
    func disarm() {
        guard armedTargetPointInGlobalScreenCoordinates != nil
            || armedTargetRectInGlobalScreenCoordinates != nil else { return }
        armedTargetPointInGlobalScreenCoordinates = nil
        armedTargetRectInGlobalScreenCoordinates = nil
        onTargetClicked = nil
        print("[ClickDetector] disarmed")
    }

    // MARK: - Event Tap

    private func startEventTapIfNeeded() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)

        // Listen-only tap: callback is notified but cannot modify or drop
        // the event. Runs at the session level so it sees clicks in every
        // app the user interacts with.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: ClickDetector.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[ClickDetector] ✗ failed to create event tap — Accessibility permission missing?")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.eventTapRunLoopSource = runLoopSource
        print("[ClickDetector] event tap installed")
    }

    /// C-style callback bridged back into the actor.
    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let detector = Unmanaged<ClickDetector>.fromOpaque(userInfo).takeUnretainedValue()

        // If the system disabled our tap (long CPU stall, timeout), re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                if let tap = detector.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    print("[ClickDetector] tap was disabled — re-enabled")
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }

        let clickPointInCoreGraphicsCoordinates = event.location
        DispatchQueue.main.async {
            detector.handleClick(atCoreGraphicsPoint: clickPointInCoreGraphicsCoordinates)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleClick(atCoreGraphicsPoint clickPointInCoreGraphicsCoordinates: CGPoint) {
        guard let onTargetClicked else { return }

        // Double-click grace: the user may legitimately click again on the
        // step that just fired (app-required double click). Swallow extra
        // clicks for a very short window so we don't race-advance.
        if let lastHit = lastSuccessfulHitTimestamp,
           Date().timeIntervalSince(lastHit) < postHitGraceIntervalInSeconds {
            return
        }

        let clickPointInGlobalScreenCoordinates = convertCoreGraphicsPointToGlobalScreen(clickPointInCoreGraphicsCoordinates)

        let isWithinRect: Bool = {
            guard let rect = armedTargetRectInGlobalScreenCoordinates else { return false }
            let inflated = rect.insetBy(dx: -rectInflationInScreenPoints, dy: -rectInflationInScreenPoints)
            return inflated.contains(clickPointInGlobalScreenCoordinates)
        }()

        let distanceFromPoint: CGFloat = {
            guard let armedPoint = armedTargetPointInGlobalScreenCoordinates else { return .greatestFiniteMagnitude }
            return hypot(
                clickPointInGlobalScreenCoordinates.x - armedPoint.x,
                clickPointInGlobalScreenCoordinates.y - armedPoint.y
            )
        }()
        let isWithinPointRadius = armedTargetRectInGlobalScreenCoordinates == nil
            && distanceFromPoint <= pointOnlyHitToleranceInScreenPoints

        let shouldFireDueToDebugBypass = Self.advanceOnAnyClickEnabled
        let shouldFire = isWithinRect || isWithinPointRadius || shouldFireDueToDebugBypass

        let debugSuffix = shouldFireDueToDebugBypass && !isWithinRect && !isWithinPointRadius
            ? " [debug: advancing anyway]"
            : ""
        print("[ClickDetector] click at \(clickPointInGlobalScreenCoordinates) — rectHit=\(isWithinRect) pointHit=\(isWithinPointRadius) dist=\(Int(distanceFromPoint))pt\(debugSuffix)")

        guard shouldFire else { return }

        // Disarm before firing so the advance handler can arm a new
        // target for the next step without the callback re-entering.
        armedTargetPointInGlobalScreenCoordinates = nil
        armedTargetRectInGlobalScreenCoordinates = nil
        self.onTargetClicked = nil
        lastSuccessfulHitTimestamp = Date()
        onTargetClicked()
    }

    /// Convert a Core Graphics screen point (top-left origin, Y downward)
    /// to a global AppKit screen point (bottom-left origin, Y upward).
    private func convertCoreGraphicsPointToGlobalScreen(_ coreGraphicsPoint: CGPoint) -> CGPoint {
        guard let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main else {
            return coreGraphicsPoint
        }
        let primaryScreenHeight = primaryScreen.frame.height
        return CGPoint(
            x: coreGraphicsPoint.x,
            y: primaryScreenHeight - coreGraphicsPoint.y
        )
    }
}
