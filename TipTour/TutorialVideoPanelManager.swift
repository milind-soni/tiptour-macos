//
//  TutorialVideoPanelManager.swift
//  TipTour
//
//  Floating Picture-in-Picture NSPanel that hosts the YouTubeEmbedView
//  during a tutorial. Default tutorial video surface — sits in a corner
//  of the user's screen, draggable, always-on-top, doesn't steal focus.
//
//  When the user prefers the cursor-following layout instead, this
//  panel stays hidden and the same YouTubeEmbedView is rendered inline
//  inside OverlayWindow next to the cursor companion.
//
//  Position is persisted across launches via UserDefaults so the user
//  drags it once and it stays where they left it.
//

import AppKit
import SwiftUI

@MainActor
final class TutorialVideoPanelManager {

    static let shared = TutorialVideoPanelManager()

    /// The floating panel itself. Created on first show, reused
    /// thereafter, never destroyed (cheap to keep around hidden).
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TutorialVideoPanelContent>?

    /// Defaults key that stores the user's last drag position so the
    /// panel reappears where they put it last time.
    private static let positionDefaultsKey = "tutorialVideoPanelOrigin.v1"

    /// Default panel size. 480x270 is YouTube's recommended minimum
    /// 16:9 dimensions and easily readable for tutorial content.
    private static let defaultPanelSize = NSSize(width: 480, height: 270)

    /// Show the floating PiP panel containing the embedded YouTube
    /// video. Idempotent — if already visible, just updates the
    /// videoID (handled inside the SwiftUI content).
    func show(videoID: String, controller: YouTubeEmbedController) {
        let panel = self.panel ?? createPanel()
        self.panel = panel

        let content = TutorialVideoPanelContent(
            videoID: videoID,
            controller: controller,
            onClosePressed: { [weak self] in self?.hide() }
        )

        if let existingHost = hostingView {
            existingHost.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            panel.contentView = host
            hostingView = host
        }

        positionPanelAtSavedOrDefaultLocation()
        panel.orderFrontRegardless()
    }

    /// Hide the panel without destroying it. Cheaper than tearing down
    /// and rebuilding when the user starts another tutorial later.
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel Creation

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultPanelSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating  // always above regular windows but below screen savers
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Persist position whenever the user drags it.
        panel.delegate = WindowDelegate.shared
        return panel
    }

    /// Where to put the panel. Loads the user's persisted position if
    /// any. Otherwise places the panel in the top-right corner of the
    /// primary screen, with 24pt margins. We clamp to the visible screen
    /// frame so a saved position from a now-disconnected monitor doesn't
    /// leave the panel offscreen.
    private func positionPanelAtSavedOrDefaultLocation() {
        guard let panel = panel else { return }
        let panelSize = panel.frame.size

        if let savedOrigin = loadSavedOrigin() {
            // Validate the saved point is still inside SOME visible screen.
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(savedOrigin) }) {
                _ = screen
                panel.setFrameOrigin(savedOrigin)
                return
            }
        }

        // Default: top-right of primary screen, 24pt inset.
        guard let primaryScreen = NSScreen.main ?? NSScreen.screens.first else {
            panel.setFrameOrigin(.zero)
            return
        }
        let visibleFrame = primaryScreen.visibleFrame
        let inset: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - panelSize.width - inset,
            y: visibleFrame.maxY - panelSize.height - inset
        )
        panel.setFrameOrigin(origin)
    }

    fileprivate func saveCurrentOrigin() {
        guard let panel = panel else { return }
        let origin = panel.frame.origin
        let dict: [String: CGFloat] = ["x": origin.x, "y": origin.y]
        UserDefaults.standard.set(dict, forKey: Self.positionDefaultsKey)
    }

    private func loadSavedOrigin() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.positionDefaultsKey) as? [String: CGFloat],
              let x = dict["x"], let y = dict["y"] else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    // MARK: - Window Delegate

    /// Persists position drag-by-drag. Singleton to keep the
    /// delegate simple — only one tutorial PiP panel ever exists.
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()
        func windowDidMove(_ notification: Notification) {
            Task { @MainActor in
                TutorialVideoPanelManager.shared.saveCurrentOrigin()
            }
        }
    }
}

/// SwiftUI content of the panel — a YouTubeEmbedView with a small
/// close button overlaid in the top-right. Rounded corners + a border
/// for a clean PiP look.
private struct TutorialVideoPanelContent: View {
    let videoID: String
    @ObservedObject var controller: YouTubeEmbedController
    let onClosePressed: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            YouTubeEmbedView(videoID: videoID, controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 8)
                .padding(8)

            // Close affordance — tucked into the corner, only shows
            // on hover so it doesn't compete with YouTube's controls.
            CloseButton(onClick: onClosePressed)
                .padding(14)
        }
    }
}

private struct CloseButton: View {
    let onClick: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onClick) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Color.black.opacity(isHovered ? 0.85 : 0.5))
                )
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1.0 : 0.6)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
