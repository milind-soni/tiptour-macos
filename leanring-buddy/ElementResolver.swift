//
//  ElementResolver.swift
//  TipTour
//
//  Single entry point for "where on screen should the cursor fly to?"
//
//  Tries three lookup strategies in order of reliability:
//    1. Accessibility tree (~30ms, pixel-perfect when app supports AX —
//       almost all native Mac apps, most Electron apps, etc.)
//    2. YOLO + OCR visual detection with LLM coordinate hint as proximity
//       anchor (~10ms cached, fallback for apps with no AX — Blender,
//       games, some web content)
//    3. Raw LLM coordinates (~0ms, trust Claude/Gemini as absolute
//       last resort when both local sources miss)
//
//  The resolver returns a global AppKit screen coordinate so the cursor
//  overlay can fly to it without further conversion.
//

import AppKit
import Foundation

final class ElementResolver: @unchecked Sendable {

    static let shared = ElementResolver()

    private let axResolver = AccessibilityTreeResolver()

    // MARK: - Public Types

    /// Where the resolved coordinate came from — useful for logging and
    /// telling the cursor what confidence to render with.
    enum ResolutionSource {
        case accessibilityTree       // AX tree gave us exact frame
        case yoloWithLLMHint         // YOLO box near LLM's hint pixel
        case llmRawCoordinates       // Straight from the LLM, no refinement
    }

    struct Resolution {
        /// Global AppKit-space coordinate — ready to pass to the overlay.
        let globalScreenPoint: CGPoint
        /// The display the point is on.
        let displayFrame: CGRect
        /// Human-readable label describing what was pointed at.
        let label: String
        /// Where the resolution came from — for logging/telemetry.
        let source: ResolutionSource
        /// Global AppKit-space rect for the matched element, when the
        /// resolution source can produce one. AX always gives us this
        /// (pixel-perfect). YOLO/LLM fallbacks don't — the click
        /// detector falls back to a radius around `globalScreenPoint`
        /// when this is nil.
        let globalScreenRect: CGRect?
    }

    // MARK: - Resolution

    /// Resolve a cursor target from an LLM pointing tag.
    ///
    /// - Parameters:
    ///   - label: the element's label (e.g. "Save", "File menu")
    ///   - llmHintInScreenshotPixels: the LLM's (x,y) in screenshot pixel
    ///     space. Optional — when using coordinate-free `[POINT:label]`
    ///     tags this is nil and we rely entirely on AX + YOLO label matching.
    ///   - latestCapture: the screenshot + metadata (display frame, pixel
    ///     dimensions) needed to convert screenshot pixels → global screen
    ///     coordinates. Required for YOLO/LLM paths; not used by AX.
    /// Try AX tree only. Runs on a background task so the walk doesn't
    /// block main. Returns nil if AX has no match for the label.
    /// `targetAppHint` (e.g. "Blender") lets us query the app the user
    /// is actually looking at when the system's focused app is a
    /// background recorder like Cap.
    func tryAccessibilityTree(label: String, targetAppHint: String? = nil) async -> Resolution? {
        let axResolverRef = axResolver
        let axResult = await Task.detached(priority: .userInitiated) {
            return axResolverRef.findElement(byLabel: label, targetAppHint: targetAppHint)
        }.value

        guard let axResult else { return nil }

        let globalPoint = await MainActor.run {
            displayFrameContaining(axResult.center) ?? axResult.screenFrame
        }
        print("[ElementResolver] ✓ AX matched \"\(label)\" → \"\(axResult.title)\" [\(axResult.role)] at \(axResult.center)")
        return Resolution(
            globalScreenPoint: axResult.center,
            displayFrame: globalPoint,
            label: label,
            source: .accessibilityTree,
            globalScreenRect: axResult.screenFrame
        )
    }

    /// Try YOLO+OCR — both the label-only cache lookup (no coord hint)
    /// and the coord-hinted refinement if the LLM gave us a hint.
    /// Returns nil if neither strategy finds a match.
    func tryYOLO(
        label: String,
        llmHintInScreenshotPixels: CGPoint?,
        capture: CompanionScreenCapture,
        proximityAnchorInGlobalScreen: CGPoint? = nil
    ) async -> Resolution? {
        // If we have a proximity anchor (previous step's resolved
        // point), convert it into screenshot-pixel space so the
        // detector can use it to tie-break between multiple equally-
        // scoring label matches.
        let proximityAnchorInScreenshotPixels = proximityAnchorInGlobalScreen.map {
            globalScreenPointToScreenshotPixel($0, capture: capture)
        }

        // Label-only match — this is what worked well in the Claude-mode
        // version: OCR finds the text "File", YOLO finds the button
        // bounding box containing it, we use the button's center.
        if let labelMatch = NativeElementDetector.shared.findFromCache(
            query: label,
            preferMatchesNearPixel: proximityAnchorInScreenshotPixels
        ) {
            let globalPoint = screenshotPixelToGlobalScreen(labelMatch.center, capture: capture)
            let anchorLogNote = proximityAnchorInScreenshotPixels != nil ? " (proximity-biased)" : ""
            print("[ElementResolver] ✓ YOLO label-match \"\(label)\" → \"\(labelMatch.label)\" at \(globalPoint)\(anchorLogNote)")
            return Resolution(
                globalScreenPoint: globalPoint,
                displayFrame: capture.displayFrame,
                label: label,
                source: .yoloWithLLMHint,
                globalScreenRect: nil
            )
        }

        // Hint-based refinement — snap to the nearest YOLO box to the
        // LLM's suggested coordinate.
        if let hint = llmHintInScreenshotPixels,
           let refined = NativeElementDetector.shared.refineCoordinate(hint: hint, label: label) {
            let globalPoint = screenshotPixelToGlobalScreen(refined.center, capture: capture)
            print("[ElementResolver] ✓ YOLO hint-refined \"\(label)\" at \(hint) → screen \(globalPoint)")
            return Resolution(
                globalScreenPoint: globalPoint,
                displayFrame: capture.displayFrame,
                label: label,
                source: .yoloWithLLMHint,
                globalScreenRect: nil
            )
        }

        return nil
    }

    /// Absolute last resort — use the LLM's raw coordinate as-is.
    func rawLLMCoordinate(
        label: String,
        llmHintInScreenshotPixels: CGPoint,
        capture: CompanionScreenCapture
    ) -> Resolution {
        let globalPoint = screenshotPixelToGlobalScreen(llmHintInScreenshotPixels, capture: capture)
        print("[ElementResolver] ⚠ using raw LLM coords for \"\(label)\" → screen \(globalPoint)")
        return Resolution(
            globalScreenPoint: globalPoint,
            displayFrame: capture.displayFrame,
            label: label,
            source: .llmRawCoordinates,
            globalScreenRect: nil
        )
    }

    /// Poll the AX tree repeatedly for up to `timeoutSeconds` waiting
    /// for `label` to appear. Returns the first successful resolution.
    /// Used by the workflow runner to wait for a newly-opened menu or
    /// sheet to settle after a click, instead of sleeping a fixed time.
    /// Polling is cheap (~20-40ms per tick) and exits early on match.
    func pollAccessibilityTree(
        label: String,
        targetAppHint: String?,
        timeoutSeconds: Double,
        pollIntervalSeconds: Double = 0.08
    ) async -> Resolution? {
        // Short-circuit for apps we already know don't expose an AX
        // tree (Blender, Unity, games). Saves up to a full `timeoutSeconds`
        // of wasted polling per step AND the CPU churn that causes
        // audio underruns in the Gemini Live output stream.
        if AccessibilityTreeResolver.isAppKnownToLackAXTree(hint: targetAppHint) {
            print("[AX] skipping poll for \"\(label)\" — app \"\(targetAppHint ?? "?")\" flagged as no-AX-tree")
            return nil
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let hit = await tryAccessibilityTree(label: label, targetAppHint: targetAppHint) {
                return hit
            }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }
        return nil
    }

    /// Full resolution pipeline: AX → YOLO → LLM coords, tried in order
    /// with early exit. YOLO detection is run lazily: only if AX misses.
    /// The caller can pass `runDetectorOnMiss: true` to automatically
    /// populate the YOLO cache from `latestCapture` if it's empty.
    func resolve(
        label: String,
        llmHintInScreenshotPixels: CGPoint?,
        latestCapture: CompanionScreenCapture?,
        targetAppHint: String? = nil,
        runDetectorOnMiss: Bool = true,
        proximityAnchorInGlobalScreen: CGPoint? = nil
    ) async -> Resolution? {

        // 1. AX tree first — fastest and most reliable for native apps.
        //    Target app hint lets us bypass the system's "frontmost" when
        //    that's a background recorder (Cap) instead of the app the
        //    user is actually working in (e.g. Blender).
        if let axResolution = await tryAccessibilityTree(label: label, targetAppHint: targetAppHint) {
            return axResolution
        }

        guard let capture = latestCapture else {
            print("[ElementResolver] ✗ no AX match and no screenshot capture — giving up on \"\(label)\"")
            return nil
        }

        // 2. Warm the YOLO cache on the exact frame we have (only runs
        //    if AX missed). Detached at `.background` priority so Core
        //    Audio preempts the CoreML pass — otherwise sustained YOLO
        //    inference can push HALC_ProxyIOContext into "skipping
        //    cycle due to overload" and we hear breaks in Gemini's
        //    voice playback. Detection ends up ~10-20% slower but the
        //    user can't hear the difference; they can definitely hear
        //    audio stutter.
        if runDetectorOnMiss,
           let cgImage = CompanionManager.cgImage(from: capture.imageData) {
            await Task.detached(priority: .background) {
                await NativeElementDetector.shared.detectElements(in: cgImage)
            }.value
        }

        // 3. YOLO label-only or hint-refined match. The proximity
        //    anchor (previous step's resolved screen point) lets the
        //    detector tie-break between multiple equal label matches
        //    in favor of the one closest to where we just clicked —
        //    fixes nested-menu ambiguity (e.g. "New" in an open File
        //    menu vs "New Tab" elsewhere on screen).
        if let yoloResolution = await tryYOLO(
            label: label,
            llmHintInScreenshotPixels: llmHintInScreenshotPixels,
            capture: capture,
            proximityAnchorInGlobalScreen: proximityAnchorInGlobalScreen
        ) {
            return yoloResolution
        }

        // 4. Raw LLM coordinates as last resort.
        if let hint = llmHintInScreenshotPixels {
            return rawLLMCoordinate(
                label: label,
                llmHintInScreenshotPixels: hint,
                capture: capture
            )
        }

        print("[ElementResolver] ✗ could not resolve \"\(label)\" — all strategies missed")
        return nil
    }

    // MARK: - Coordinate Conversion

    /// Convert a point in screenshot pixel space (top-left origin) to
    /// global AppKit screen coordinates (bottom-left origin, spans all displays).
    /// Uses the capture's metadata (display frame, pixel dimensions) to scale.
    private func screenshotPixelToGlobalScreen(_ pixel: CGPoint, capture: CompanionScreenCapture) -> CGPoint {
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

        return CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitY + displayFrame.origin.y
        )
    }

    /// Inverse of `screenshotPixelToGlobalScreen`. Maps a global AppKit
    /// point (bottom-left origin, spans all displays) back into the
    /// screenshot's pixel coordinate space (top-left origin). Used to
    /// pass a proximity anchor from global-screen-land into the
    /// detector's pixel-space tie-breaker.
    private func globalScreenPointToScreenshotPixel(
        _ globalPoint: CGPoint,
        capture: CompanionScreenCapture
    ) -> CGPoint {
        let screenshotWidth = CGFloat(capture.screenshotWidthInPixels)
        let screenshotHeight = CGFloat(capture.screenshotHeightInPixels)
        let displayWidth = CGFloat(capture.displayWidthInPoints)
        let displayHeight = CGFloat(capture.displayHeightInPoints)
        let displayFrame = capture.displayFrame

        let displayLocalX = globalPoint.x - displayFrame.origin.x
        let appKitY = globalPoint.y - displayFrame.origin.y
        let displayLocalY = displayHeight - appKitY

        let pixelX = displayLocalX * (screenshotWidth / displayWidth)
        let pixelY = displayLocalY * (screenshotHeight / displayHeight)

        return CGPoint(x: pixelX, y: pixelY)
    }

    /// Find the NSScreen whose frame contains the given global AppKit point.
    private func displayFrameContaining(_ globalPoint: CGPoint) -> CGRect? {
        for screen in NSScreen.screens {
            if screen.frame.contains(globalPoint) {
                return screen.frame
            }
        }
        return nil
    }
}
