//
//  YouTubeEmbedView.swift
//  TipTour
//
//  WKWebView-backed YouTube IFrame Player API wrapper. Replaces the old
//  yt-dlp + AVPlayer pipeline. The video plays inside YouTube's own
//  embedded player (so we don't download anything, don't violate
//  YouTube's TOS, and don't need yt-dlp installed on the user's Mac).
//
//  Two surfaces consume this view:
//    1. The menu bar panel (CompanionPanelView) — embedded video +
//       step controls inside the menu bar dropdown (default mode).
//       Panel auto-pins for the duration of the tutorial.
//    2. OverlayWindow — a chip that follows the cursor, used when the
//       user prefers the cursor-following layout.
//
//  Both surfaces share the same YouTubeEmbedController so play/pause/
//  seek/getCurrentTime calls work identically regardless of where the
//  WebView is mounted. The controller is the single source of truth
//  for tutorial-step timing — CompanionManager polls it every 0.5s
//  to know when to advance.
//

import AppKit
import Combine
import SwiftUI
import WebKit

/// SwiftUI wrapper around a `WKWebView` that loads YouTube's IFrame
/// Player API and exposes play/pause/seek to the rest of the app via
/// `YouTubeEmbedController`.
struct YouTubeEmbedView: NSViewRepresentable {
    let videoID: String
    @ObservedObject var controller: YouTubeEmbedController

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        // YouTube's IFrame Player calls `playVideo()` programmatically on
        // load. Without this, autoplay is blocked.
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")  // black behind the player
        webView.layer?.backgroundColor = NSColor.black.cgColor

        controller.attach(webView: webView)
        // Critical: baseURL must NOT be a youtube.com origin. YouTube's
        // IFrame Player rejects "self-embedding" attempts (error 152) when
        // the Referer header matches youtube.com. Using a non-YouTube
        // origin makes the embed look like any normal third-party page,
        // matching how a regular `<iframe src="youtube.com/embed/...">`
        // hosted on someone's website behaves.
        webView.loadHTMLString(html(forVideoID: videoID), baseURL: URL(string: "https://tiptour.local/")!)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // If the videoID changes (e.g. user starts a different tutorial)
        // load a fresh page. Otherwise leave it alone — re-loading wipes
        // the player state.
        if controller.loadedVideoID != videoID {
            controller.loadedVideoID = videoID
            // Critical: baseURL must NOT be a youtube.com origin. YouTube's
        // IFrame Player rejects "self-embedding" attempts (error 152) when
        // the Referer header matches youtube.com. Using a non-YouTube
        // origin makes the embed look like any normal third-party page,
        // matching how a regular `<iframe src="youtube.com/embed/...">`
        // hosted on someone's website behaves.
        webView.loadHTMLString(html(forVideoID: videoID), baseURL: URL(string: "https://tiptour.local/")!)
        }
    }

    /// Inline HTML that hosts the YouTube IFrame Player. We could also
    /// load a remote URL, but inline keeps everything in one place and
    /// lets us tune player parameters precisely. Note: we DO NOT hide
    /// any of YouTube's controls — the IFrame TOS requires them visible.
    private func html(forVideoID videoID: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
          #player { width: 100%; height: 100%; }
        </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            // Called by the IFrame API once the script has loaded.
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                videoId: '\(videoID)',
                playerVars: {
                  playsinline: 1,
                  rel: 0,
                  modestbranding: 1,
                  controls: 1,            // YouTube TOS requires controls visible
                  iv_load_policy: 3,      // hide annotations
                  // origin must match our baseURL so YouTube's
                  // postMessage handshake accepts our JS bridge calls.
                  origin: 'https://tiptour.local'
                },
                events: {
                  onReady: () => {
                    window.webkit.messageHandlers.tiptour.postMessage({ kind: 'ready' });
                  },
                  onStateChange: (event) => {
                    window.webkit.messageHandlers.tiptour.postMessage({ kind: 'state', state: event.data });
                  },
                  onError: (event) => {
                    window.webkit.messageHandlers.tiptour.postMessage({ kind: 'error', code: event.data });
                  }
                }
              });
            }
            // Bridge functions invoked by Swift via evaluateJavaScript.
            window.tiptourBridge = {
              play:           () => player && player.playVideo(),
              pause:          () => player && player.pauseVideo(),
              seekTo:         (seconds) => player && player.seekTo(seconds, true),
              getCurrentTime: () => player ? player.getCurrentTime() : 0,
              getDuration:    () => player ? player.getDuration() : 0,
              setMuted:       (muted) => { if (!player) return; muted ? player.mute() : player.unMute(); }
            };
          </script>
        </body>
        </html>
        """
    }
}

/// Owns the JS bridge to a single WKWebView. Outlives any particular
/// view instance so SwiftUI can rebuild the wrapper without losing the
/// player state. Methods are fire-and-forget because YouTube's player
/// queues commands itself.
@MainActor
final class YouTubeEmbedController: NSObject, ObservableObject {

    /// Tracks which video the WebView currently has loaded. Lets
    /// `updateNSView` decide whether a re-load is required.
    @Published var loadedVideoID: String = ""

    /// True once the YouTube IFrame Player has called back with
    /// `onReady`. Use this to gate seek/play calls — sending them
    /// before ready silently no-ops.
    @Published private(set) var isPlayerReady: Bool = false

    /// Latest player state from `onStateChange`:
    ///   -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued.
    @Published private(set) var playerState: Int = -1

    /// Whether playback is currently happening. Mirrors `playerState == 1`
    /// in a more readable form for UI.
    var isPlaying: Bool { playerState == 1 }

    private weak var webView: WKWebView?

    /// Called by the SwiftUI wrapper when the WKWebView is created.
    /// Installs the JS message handler so the IFrame can call back
    /// into Swift on `onReady`/`onStateChange`/`onError`.
    func attach(webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.add(
            JSMessageHandler(controller: self),
            name: "tiptour"
        )
    }

    // MARK: - Public Bridge Calls

    /// Resume playback. No-op until `isPlayerReady` is true.
    func play() {
        evaluate("window.tiptourBridge && window.tiptourBridge.play()")
    }

    /// Pause playback.
    func pause() {
        evaluate("window.tiptourBridge && window.tiptourBridge.pause()")
    }

    /// Seek to an absolute timestamp in seconds. YouTube handles the
    /// "play after seek" decision based on current state.
    func seek(toSeconds seconds: Double) {
        evaluate("window.tiptourBridge && window.tiptourBridge.seekTo(\(seconds))")
    }

    /// Mute / unmute. Useful when the user prefers to listen to the
    /// app's own narration instead of the video's audio.
    func setMuted(_ muted: Bool) {
        evaluate("window.tiptourBridge && window.tiptourBridge.setMuted(\(muted ? "true" : "false"))")
    }

    /// Read the current playhead time in seconds. Returns 0 before the
    /// player is ready or if the bridge hasn't been installed yet.
    func currentTimeSeconds() async -> Double {
        guard let webView = webView else { return 0 }
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.tiptourBridge ? window.tiptourBridge.getCurrentTime() : 0") { result, _ in
                if let number = result as? Double {
                    continuation.resume(returning: number)
                } else if let intResult = result as? Int {
                    continuation.resume(returning: Double(intResult))
                } else {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Internal

    private func evaluate(_ javaScript: String) {
        webView?.evaluateJavaScript(javaScript, completionHandler: nil)
    }

    fileprivate func handleBridgeMessage(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String else { return }
        switch kind {
        case "ready":
            isPlayerReady = true
        case "state":
            if let stateNumber = message["state"] as? Int {
                playerState = stateNumber
            }
        case "error":
            if let code = message["code"] as? Int {
                print("[YouTubeEmbed] player error code \(code) (5=html5, 100=video unavailable, 101/150=embedding disabled)")
            }
        default:
            break
        }
    }

    /// `WKScriptMessageHandler` requires NSObject conformance and
    /// shouldn't strongly retain its owner — so we use a thin wrapper
    /// that holds a weak controller reference.
    private final class JSMessageHandler: NSObject, WKScriptMessageHandler {
        weak var controller: YouTubeEmbedController?

        init(controller: YouTubeEmbedController) {
            self.controller = controller
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }
            Task { @MainActor in
                self.controller?.handleBridgeMessage(body)
            }
        }
    }
}
