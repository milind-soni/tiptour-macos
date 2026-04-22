//
//  AccessibilityTreeResolver.swift
//  TipTour
//
//  Walks the macOS Accessibility (AX) tree of the frontmost app and looks
//  up UI elements by title. Returns pixel-perfect frames from the app's
//  own accessibility data — no LLM coordinate guessing required.
//
//  Why this exists:
//    Asking an LLM for pixel coordinates is slow (round-trip) and
//    imprecise (LLMs aren't great at exact pixels). macOS apps that
//    expose their AX tree properly — which is most native apps — let
//    us query "find the element titled Save" and get back the exact
//    CGRect in global screen space. ~30ms, pixel-perfect.
//
//  What this does NOT cover:
//    Apps that render their own UI via OpenGL/Canvas (Blender, games,
//    some Electron apps) have empty or incomplete AX trees. For those,
//    the caller falls back to YOLO visual detection.
//

import ApplicationServices
import AppKit
import Foundation

/// Intentionally NOT @MainActor — AX tree walking can take 100-300ms on
/// complex apps (Xcode has thousands of nodes). Blocking main that long
/// starves Core Audio and causes Gemini Live's voice to stutter. All
/// AX APIs are thread-safe to call, so we traverse off-main.
final class AccessibilityTreeResolver: @unchecked Sendable {

    // MARK: - Public Types

    /// A matched UI element from the AX tree.
    struct ResolvedElement {
        /// Global-screen-coordinate frame (AppKit coordinates, bottom-left origin).
        let screenFrame: CGRect
        /// The element's AX role (e.g. "AXButton", "AXMenuBarItem").
        let role: String
        /// The title we matched against (or empty if matched via description/value).
        let title: String
        /// The bundle ID of the app that owns the element.
        let appBundleID: String?

        /// Pixel coordinates for cursor pointing, in AppKit global space.
        var center: CGPoint {
            CGPoint(x: screenFrame.midX, y: screenFrame.midY)
        }
    }

    // MARK: - Permission

    /// Returns true if the app already has Accessibility permission.
    static var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user for Accessibility permission if not already granted.
    /// Returns the current status after the prompt.
    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Entry Point

    /// Find the best matching element by title in the frontmost app's AX tree.
    /// Returns nil if the app has no AX tree (Blender-like), or no element matches.
    ///
    /// Matching strategy (best → worst score):
    ///   1. Exact case-insensitive title match, interactive role
    ///   2. Exact match on any of: title, description, help, value
    ///   3. Contains match (query ⊂ element text or vice versa)
    ///   4. Word overlap
    /// Look up an element by label. If `targetAppHint` is provided we
    /// search that specific app's tree (by localized name, bundle ID,
    /// or substring match) — this is critical when the system's
    /// frontmost app isn't what the user is actually looking at (e.g.
    /// a screen recorder like Cap being frontmost while the user is
    /// working in Blender).
    func findElement(byLabel query: String, targetAppHint: String? = nil) -> ResolvedElement? {
        guard Self.isPermissionGranted else {
            print("[AX] permission not granted")
            return nil
        }

        let (targetApp, targetBundleID) = resolveTargetApp(hint: targetAppHint)
        guard let targetApp else {
            print("[AX] no target app (hint: \"\(targetAppHint ?? "nil")\")")
            return nil
        }

        // CRITICAL: set a messaging timeout so AX calls fail fast if the
        // target app is busy (e.g. Blender mid-render, games in a frame).
        AXUIElementSetMessagingTimeout(targetApp, 0.2)

        print("[AX] searching \"\(targetBundleID ?? "?")\" for \"\(query)\" (hint: \"\(targetAppHint ?? "none")\")")

        let scoredCandidates = collectCandidates(
            from: targetApp,
            query: query,
            appBundleID: targetBundleID
        )

        guard let winner = scoredCandidates.max(by: { $0.score < $1.score })?.element else {
            // Zero scored candidates can mean either (a) the app has no
            // AX tree at all, or (b) the tree is fine but this specific
            // label didn't match. We distinguish by checking whether
            // the menu bar — which every AppKit-based app exposes with
            // File/Edit/View/… children — has any children. If the
            // menu bar is empty, the app is rendering its UI outside
            // the AX tree (OpenGL/canvas/game-engine apps) and we
            // should stop wasting CPU polling AX for subsequent steps.
            let menuBarChildCount = menuBarChildrenCount(of: targetApp)
            if menuBarChildCount == 0 {
                Self.noteAppHasEmptyAXTree(hint: targetAppHint)
            }
            print("[AX] no match among \(scoredCandidates.count) candidates in \"\(targetBundleID ?? "?")\" (menuBarChildren=\(menuBarChildCount))")
            return nil
        }
        return winner
    }

    /// Count the immediate children of the app's AX menu bar. Zero
    /// means the app has no accessibility-exposed menu structure.
    private func menuBarChildrenCount(of app: AXUIElement) -> Int {
        guard let menuBar = menuBar(of: app) else { return 0 }
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return 0
        }
        return children.count
    }

    /// The bundle ID of our own app — we NEVER query our own AX tree
    /// because opening the menu bar panel makes TipTour briefly frontmost
    /// and the panel's tree has nothing to do with what the user is
    /// actually looking at. Skipping ourselves forces the resolver to
    /// use the LAST foreground app before TipTour took focus.
    private static var ownBundleID: String? {
        Bundle.main.bundleIdentifier
    }

    /// Snapshot of the user's real frontmost app at the moment the hotkey
    /// was pressed. Set by CompanionManager.handleShortcutTransition at
    /// press time — before any of our UI shows — so we always know
    /// which app the user was actually looking at, even after TipTour's
    /// menu bar panel takes focus.
    nonisolated(unsafe) static var userTargetAppOverride: NSRunningApplication?

    // MARK: - Empty-Tree Cache (audio-latency escape hatch)
    //
    // Some apps render their UI via OpenGL / canvas / game engine and
    // expose NO accessibility tree at all — Blender, Unity, Unreal, most
    // DCC tools, games. Polling AX for 3 × 900ms per step in one of
    // these apps wastes ~2.7s per step AND burns CPU that Core Audio
    // needs to keep Gemini's voice smooth. Once we detect "this app has
    // an empty tree", we skip AX polling for subsequent steps in the
    // same window of time and go straight to YOLO. Auto-expires after
    // 10 minutes so re-installations or app updates that fix AX support
    // don't stay blocklisted forever.

    private static let emptyTreeCacheLock = NSLock()
    nonisolated(unsafe) private static var emptyTreeHintTimestamps: [String: Date] = [:]
    private static let emptyTreeMemoryDurationSeconds: TimeInterval = 600

    /// Record that an app (identified by the hint string used in the
    /// plan, like "Blender") has no walkable AX tree. Subsequent calls
    /// to `isAppKnownToLackAXTree(hint:)` will return true for 10min.
    static func noteAppHasEmptyAXTree(hint: String?) {
        guard let hint = hint, !hint.isEmpty else { return }
        let key = hint.lowercased()
        emptyTreeCacheLock.withLock {
            emptyTreeHintTimestamps[key] = Date()
        }
        print("[AX] 🚫 flagging app \"\(hint)\" as no-AX-tree for 10min — future steps will skip straight to YOLO")
    }

    /// Check whether an app's AX tree is known to be empty. Callers
    /// should use this to short-circuit expensive poll loops.
    static func isAppKnownToLackAXTree(hint: String?) -> Bool {
        guard let hint = hint, !hint.isEmpty else { return false }
        let key = hint.lowercased()
        return emptyTreeCacheLock.withLock {
            guard let ts = emptyTreeHintTimestamps[key] else { return false }
            if Date().timeIntervalSince(ts) > emptyTreeMemoryDurationSeconds {
                emptyTreeHintTimestamps.removeValue(forKey: key)
                return false
            }
            return true
        }
    }

    /// Resolve which app's AX tree we should query.
    /// Priority:
    ///   1. `hint` (app name from the planner's JSON, e.g. "Blender") —
    ///      look for a running app whose name or bundle ID matches.
    ///   2. System-wide focused app via AXUIElementCopyAttributeValue,
    ///      skipping our own app.
    ///   3. NSWorkspace.frontmostApplication (skipping our own).
    ///   4. Most recently active running app that isn't us — covers the
    ///      case where pressing the hotkey momentarily made TipTour
    ///      frontmost.
    private func resolveTargetApp(hint: String?) -> (AXUIElement?, String?) {
        if let hint, !hint.isEmpty, hint.lowercased() != "unknown" {
            if let runningApp = Self.findRunningApp(matching: hint) {
                let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
                return (axApp, runningApp.bundleIdentifier ?? runningApp.localizedName)
            }
            print("[AX] no running app matches hint \"\(hint)\" — falling back to snapshot")
        }

        // Snapshot captured at hotkey press time — most reliable signal of
        // which app the user actually wanted to interact with.
        if let snapshot = Self.userTargetAppOverride,
           snapshot.bundleIdentifier != Self.ownBundleID,
           !snapshot.isTerminated {
            return (AXUIElementCreateApplication(snapshot.processIdentifier), snapshot.bundleIdentifier)
        }

        // System-wide focused app — only if it isn't us
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
           let app = appRef {
            let axApp = app as! AXUIElement
            let bundleID = frontmostAppBundleID()
            if bundleID != Self.ownBundleID {
                return (axApp, bundleID)
            }
            print("[AX] focused app is our own menu bar — falling through")
        }

        // NSWorkspace frontmost, skipping ourselves
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Self.ownBundleID {
            return (AXUIElementCreateApplication(frontmost.processIdentifier), frontmost.bundleIdentifier)
        }

        // Most recently launched regular app that isn't us
        let candidateApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Self.ownBundleID }
            .sorted { (a, b) in
                let da = a.launchDate ?? .distantPast
                let db = b.launchDate ?? .distantPast
                return da > db
            }
        if let fallback = candidateApps.first {
            print("[AX] falling back to most recent real app: \(fallback.bundleIdentifier ?? "?")")
            return (AXUIElementCreateApplication(fallback.processIdentifier), fallback.bundleIdentifier)
        }

        return (nil, nil)
    }

    /// Find a running app whose localized name, bundle ID, or executable
    /// contains the hint (case-insensitive). Prefers regular apps
    /// (activationPolicy == .regular) over background agents, so a hint
    /// like "Blender" doesn't accidentally match an irrelevant daemon.
    private static func findRunningApp(matching hint: String) -> NSRunningApplication? {
        let needle = hint.lowercased()
        let running = NSWorkspace.shared.runningApplications

        func contains(_ app: NSRunningApplication) -> Bool {
            if let name = app.localizedName?.lowercased(), name.contains(needle) { return true }
            if let bid = app.bundleIdentifier?.lowercased(), bid.contains(needle) { return true }
            return false
        }

        // Prefer regular foreground apps.
        if let match = running.first(where: { $0.activationPolicy == .regular && contains($0) }) {
            return match
        }
        return running.first(where: contains)
    }

    // MARK: - Tree Traversal

    /// Roles that are typically clickable / meaningful pointing targets.
    private static let pointableRoles: Set<String> = [
        "AXButton", "AXMenuItem", "AXMenuBarItem", "AXPopUpButton",
        "AXCheckBox", "AXRadioButton", "AXLink", "AXTab", "AXStaticText",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSlider",
        "AXMenuButton", "AXToolbar", "AXImage", "AXCell", "AXRow"
    ]

    /// Get the frontmost app's AX element. Tries two strategies:
    /// 1. System-wide AX query (fast path, usually works)
    /// 2. NSWorkspace PID → AXUIElementCreateApplication (fallback when
    ///    the system-wide query returns nothing — happens during space
    ///    transitions, after app switches, or when a full-screen app
    ///    hasn't registered itself yet).
    private func focusedApplication() -> AXUIElement? {
        // Strategy 1: system-wide focused app
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
           let app = appRef {
            return (app as! AXUIElement)
        }

        // Strategy 2: fallback via NSWorkspace — works when system-wide
        // AX is momentarily blind (space switches, etc.)
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            return AXUIElementCreateApplication(frontmost.processIdentifier)
        }

        return nil
    }

    private func frontmostAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Depth-first traversal of the AX tree. Returns all candidates with scores.
    /// Capped depth prevents pathological hangs on misbehaving apps.
    private func collectCandidates(
        from root: AXUIElement,
        query: String,
        appBundleID: String?,
        maxDepth: Int = 10
    ) -> [(element: ResolvedElement, score: Int)] {

        var results: [(element: ResolvedElement, score: Int)] = []
        let queryLower = query.lowercased()
        let queryWords = Self.meaningfulWords(from: queryLower)

        // Hard wall-clock deadline so even a very responsive app with a
        // huge tree can't stall us past 400ms. Better to miss a match and
        // fall back to YOLO than to lock the pointing pipeline.
        let deadline = Date().addingTimeInterval(0.4)

        func walk(_ node: AXUIElement, depth: Int) {
            guard depth < maxDepth else { return }
            if Date() > deadline { return }

            // Check role first — cheap — and skip non-pointable decorative
            // containers early to save IPC roundtrips on the other attrs.
            let role = stringAttribute(node, attribute: kAXRoleAttribute) ?? ""

            // Only read the rest if the role is worth scoring. Containers
            // like AXGroup/AXSplitGroup have no text of their own; skip
            // the reads but still recurse into their children.
            let roleMatters = role.isEmpty || Self.pointableRoles.contains(role) || role == "AXStaticText"

            if roleMatters {
                let title = stringAttribute(node, attribute: kAXTitleAttribute) ?? ""
                let description = stringAttribute(node, attribute: kAXDescriptionAttribute) ?? ""
                let value = stringAttribute(node, attribute: kAXValueAttribute) ?? ""

                if let score = scoreAgainstQuery(
                    queryLower: queryLower,
                    queryWords: queryWords,
                    role: role,
                    title: title,
                    description: description,
                    value: value,
                    help: ""
                ), score > 0 {
                    if let frame = elementFrame(node), frame.width > 0 && frame.height > 0 {
                        // Reject absurd frames — a legitimate clickable
                        // target (menu item, button, tab, checkbox) is
                        // almost always under 800pt in either dimension.
                        // Anything bigger is a container/scroll view
                        // whose title/description happens to contain
                        // the query word (e.g. Xcode's Source Editor
                        // showing up because its description mentions
                        // "Assistant"). Clicking that rect doesn't do
                        // what the user asked for, and its giant rect
                        // would swallow every click on screen.
                        let maxReasonableClickableDimension: CGFloat = 800
                        if frame.width > maxReasonableClickableDimension
                            || frame.height > maxReasonableClickableDimension {
                            // Still recurse into its children — the real
                            // target may be a child inside this container.
                        } else {
                            let screenFrame = cgToAppKitFrame(frame)
                            let matchedText = !title.isEmpty ? title : (!description.isEmpty ? description : value)
                            let resolved = ResolvedElement(
                                screenFrame: screenFrame,
                                role: role,
                                title: matchedText,
                                appBundleID: appBundleID
                            )
                            results.append((resolved, score))
                        }
                    }
                }
            }

            // Recurse into children
            var childrenRef: AnyObject?
            if AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                for child in children {
                    if Date() > deadline { return }
                    walk(child, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 0)

        // Also walk the menu bar separately — menu bar items aren't always
        // reachable from the focused window tree but are highly relevant
        // for pointing ("click File menu").
        if let menuBar = menuBar(of: root) {
            walk(menuBar, depth: 0)
        }

        return results
    }

    private func menuBar(of app: AXUIElement) -> AXUIElement? {
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success else {
            return nil
        }
        return (menuBarRef as! AXUIElement)
    }

    // MARK: - Scoring

    /// Score an AX element against the query. Higher is better. Returns nil
    /// if the element can't match at all (non-pointable role with no text).
    private func scoreAgainstQuery(
        queryLower: String,
        queryWords: Set<String>,
        role: String,
        title: String,
        description: String,
        value: String,
        help: String
    ) -> Int? {
        // Prefer pointable roles but don't hard-exclude others — some apps
        // mark buttons with unusual roles. We just boost the pointables.
        let isPointableRole = Self.pointableRoles.contains(role)
        let roleBoost = isPointableRole ? 10 : 0

        let candidateTexts = [title, description, value, help].filter { !$0.isEmpty }
        guard !candidateTexts.isEmpty else { return nil }

        var bestScore = 0
        for text in candidateTexts {
            let textLower = text.lowercased()

            if textLower == queryLower {
                bestScore = max(bestScore, 100)
                continue
            }
            if textLower.contains(queryLower) || queryLower.contains(textLower) {
                bestScore = max(bestScore, 60)
                continue
            }
            let textWords = Self.meaningfulWords(from: textLower)
            let overlap = textWords.intersection(queryWords)
            if !overlap.isEmpty {
                let coverage = Double(overlap.count) / Double(max(queryWords.count, 1))
                bestScore = max(bestScore, Int(coverage * 40))
            }
        }

        guard bestScore > 0 else { return nil }
        return bestScore + roleBoost
    }

    /// Stop words we strip before comparing text — same logic as NativeElementDetector.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those",
        "button", "icon", "menu", "bar", "tab", "panel", "item", "option",
        "link", "field", "input", "box", "area", "section", "row", "cell"
    ]

    private static func meaningfulWords(from text: String) -> Set<String> {
        let rawWords = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let filtered = rawWords.filter { !stopWords.contains($0) }
        return Set(filtered.isEmpty ? rawWords : filtered)
    }

    // MARK: - Frame Extraction

    /// Read the element's frame in Core Graphics screen coordinates (top-left origin).
    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: AnyObject?
        var sizeRef: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard let posValue = positionRef, let sizeValue = sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    /// Convert a CG-coordinate frame (top-left origin, accumulated from primary screen)
    /// to AppKit global coordinates (bottom-left origin, matches NSEvent.mouseLocation).
    ///
    /// AX returns positions in "Core Graphics screen space" where (0,0) is the
    /// top-left of the primary display. AppKit uses bottom-left of the primary
    /// display. We flip Y around the primary display's height.
    private func cgToAppKitFrame(_ cgFrame: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else { return cgFrame }
        let primaryHeight = primaryScreen.frame.height

        // Flip Y: AppKit Y = primaryHeight - (CG Y + height)
        let appKitY = primaryHeight - cgFrame.origin.y - cgFrame.height

        return CGRect(
            x: cgFrame.origin.x,
            y: appKitY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }

    // MARK: - AX Helpers

    private func stringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }
}
