//
//  NekoCursorView.swift
//  TipTour
//
//  Pixel-art cat that replaces the blue triangle cursor in Neko mode.
//  Based on the classic oneko sprites (Masayuki Koba, 1989), vendored
//  from github.com/crgimenes/neko under BSD-2-Clause — see the
//  LICENSE-NEKO.txt file alongside the sprite assets.
//
//  The cat picks one of 8 directional sprite pairs based on the
//  velocity of the cursor position, alternates between frame 1 and
//  frame 2 for a running animation, and falls asleep after a period
//  of no movement. Pixel art is scaled up 3× with nearest-neighbor
//  interpolation so it stays crisp on Retina displays.
//

import AppKit
import SwiftUI

/// 8-way compass direction derived from a velocity vector. Used to
/// pick which sprite pair to render.
enum NekoDirection: String, CaseIterable {
    case up, down, left, right
    case upLeft, upRight, downLeft, downRight

    /// Convert a velocity vector into one of the 8 compass directions.
    /// Returns nil when the vector is below a minimum magnitude —
    /// caller uses that to switch the neko to idle/sleep.
    static func from(velocityVector: CGVector, minimumMagnitude: CGFloat = 1.5) -> NekoDirection? {
        let magnitude = hypot(velocityVector.dx, velocityVector.dy)
        guard magnitude >= minimumMagnitude else { return nil }

        // SwiftUI Y axis points DOWN, so a positive dy is "moving down".
        // atan2(dy, dx) gives the angle in radians with 0 = right, π/2 = down.
        let angleRadians = atan2(velocityVector.dy, velocityVector.dx)
        let angleDegrees = angleRadians * 180.0 / .pi  // -180…180

        // Split the circle into 8 slices of 45° each, offset by 22.5°
        // so each direction's "natural" angle sits in the middle of its slice.
        let normalized = (angleDegrees + 360).truncatingRemainder(dividingBy: 360)
        switch normalized {
        case 0..<22.5, 337.5..<360:  return .right
        case 22.5..<67.5:            return .downRight
        case 67.5..<112.5:           return .down
        case 112.5..<157.5:          return .downLeft
        case 157.5..<202.5:          return .left
        case 202.5..<247.5:          return .upLeft
        case 247.5..<292.5:          return .up
        case 292.5..<337.5:          return .upRight
        default:                     return .right
        }
    }

    /// Sprite filename prefix for this direction — matches the oneko
    /// asset naming (e.g. "upleft1.png", "upleft2.png").
    var spriteFilenamePrefix: String {
        switch self {
        case .up:        return "up"
        case .down:      return "down"
        case .left:      return "left"
        case .right:     return "right"
        case .upLeft:    return "upleft"
        case .upRight:   return "upright"
        case .downLeft:  return "downleft"
        case .downRight: return "downright"
        }
    }
}

/// Loads pixel-art sprites from the app bundle and caches the NSImages
/// so we don't hit disk every 200ms animation tick.
enum NekoSpriteLibrary {

    /// Cache keyed by filename (without extension). Populated lazily.
    private static var imageCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    /// Load a sprite by its base filename (without `.png`). Returns nil
    /// if the asset is missing — caller falls back to a static idle sprite.
    static func sprite(named baseFilename: String) -> NSImage? {
        let cached: NSImage? = cacheLock.withLock { imageCache[baseFilename] }
        if let cached { return cached }

        guard let url = Bundle.main.url(
            forResource: baseFilename,
            withExtension: "png",
            subdirectory: "NekoSprites"
        ) ?? Bundle.main.url(
            // Fallback without subdirectory in case the Xcode sync group
            // flattens resources at the bundle root.
            forResource: baseFilename,
            withExtension: "png"
        ),
        let image = NSImage(contentsOf: url) else {
            return nil
        }

        cacheLock.withLock { imageCache[baseFilename] = image }
        return image
    }
}

/// The SwiftUI cursor view that replaces the blue triangle when the
/// user has enabled Neko mode. Derives direction + running state from
/// changes in the provided `position` over time.
struct NekoCursorView: View {

    /// Where on the overlay the neko should render, in SwiftUI
    /// local coordinates (same coordinate system as the triangle).
    let position: CGPoint

    /// Opacity of the neko (drives the overlay's transient fade).
    let opacity: Double

    /// Extra scale applied during bezier flight to the target — same
    /// pattern as the triangle's `buddyFlightScale`. Default 1.0.
    let flightScale: CGFloat

    /// Size the sprites render at. Neko sprites are 32×32 natively.
    /// 32pt (1× scale) keeps the cat at a cursor-scale presence
    /// without feeling oversized next to the on-screen UI it's
    /// supposed to be pointing at.
    private let spriteDisplaySize: CGFloat = 32

    /// Previous observed position — used to compute velocity and
    /// pick the current direction.
    @State private var previousPosition: CGPoint = .zero

    /// Direction the neko is currently facing. Sticky: we hold the
    /// last direction when idle so the cat doesn't snap to a default
    /// pose on stop.
    @State private var currentDirection: NekoDirection = .right

    /// Frame toggle for the 2-frame run animation (1 or 2).
    @State private var currentAnimationFrameIndex: Int = 1

    /// Seconds since the cursor last moved. After a few seconds of
    /// stillness we switch to the sleep sprites. Reset to 0 on any
    /// observable movement.
    @State private var secondsSinceLastMovement: Double = 0

    /// Animation tick rate — matches classic oneko's running cadence.
    private let animationTickIntervalSeconds: Double = 0.2

    /// How long the cat sits still (facing whichever direction it was
    /// last running in) after stopping, before it starts yawning /
    /// scratching and eventually sleeping.
    private let stationaryGraceSeconds: Double = 1.2

    /// Seconds of no movement before neko goes to sleep.
    private let sleepTimeoutSeconds: Double = 4.0

    var body: some View {
        TimelineView(.animation(minimumInterval: animationTickIntervalSeconds, paused: false)) { context in
            let spriteImage = currentSpriteImage()
            Group {
                if let spriteImage {
                    Image(nsImage: spriteImage)
                        .interpolation(.none)  // keep pixel-art crisp
                        .resizable()
                        .frame(width: spriteDisplaySize, height: spriteDisplaySize)
                } else {
                    // Asset missing — fall back to a subtle dot so the
                    // overlay isn't invisible. Diagnostic only.
                    Circle()
                        .fill(Color.pink.opacity(0.8))
                        .frame(width: 12, height: 12)
                }
            }
            .opacity(opacity)
            .scaleEffect(flightScale)
            .position(position)
            .onChange(of: context.date) { _, _ in
                advanceAnimationTick()
            }
        }
    }

    /// Called on every TimelineView tick (~200ms). Updates the
    /// direction, toggles the frame, and tracks idle time.
    private func advanceAnimationTick() {
        let velocityVector = CGVector(
            dx: position.x - previousPosition.x,
            dy: position.y - previousPosition.y
        )

        if let newDirection = NekoDirection.from(velocityVector: velocityVector) {
            currentDirection = newDirection
            secondsSinceLastMovement = 0
        } else {
            secondsSinceLastMovement += animationTickIntervalSeconds
        }

        currentAnimationFrameIndex = (currentAnimationFrameIndex == 1) ? 2 : 1
        previousPosition = position
    }

    /// Pick the sprite that matches the current state. Four tiers:
    ///   • Moving          → directional run frames (dir1/dir2 alternating)
    ///   • Just stopped    → "facing" pose (fp_dir) — cat sits still
    ///                       looking in the direction it was running.
    ///                       Fixes the "keeps running in place" bug.
    ///   • Longer idle     → scratch frames (cat grooms itself)
    ///   • Full idle       → sleep frames (zZz)
    private func currentSpriteImage() -> NSImage? {
        if secondsSinceLastMovement >= sleepTimeoutSeconds {
            return NekoSpriteLibrary.sprite(named: "sleep\(currentAnimationFrameIndex)")
        }
        if secondsSinceLastMovement >= stationaryGraceSeconds {
            return NekoSpriteLibrary.sprite(named: "scratch\(currentAnimationFrameIndex)")
        }
        if secondsSinceLastMovement > 0 {
            // Cat has stopped within the last grace window — sit still
            // and alert. Classic oneko's `fp_*` sprites are paw-print
            // cursor markers (not cat poses), so we use `awake.png`
            // which is the actual "cat sitting upright" pose.
            return NekoSpriteLibrary.sprite(named: "awake")
        }
        // Actively running — alternate frame 1 and frame 2.
        let spriteName = "\(currentDirection.spriteFilenamePrefix)\(currentAnimationFrameIndex)"
        return NekoSpriteLibrary.sprite(named: spriteName)
    }
}

/// Paw-print trail rendered BEHIND the running cat during a bezier
/// flight — replaces the blue fencing trail when Neko mode is active.
/// Each stored flight-trail point becomes an `fp_{direction}.png`
/// sprite; older prints fade out so the trail has a natural tail.
struct PawPrintTrailView: View {
    let trailPoints: [CGPoint]

    /// Render every Nth point so the prints don't overlap into a
    /// continuous smear. 3 gives a comfortable spacing at 60fps.
    private let spacingStride: Int = 3

    /// Size of each footprint sprite (native 32×32, shown smaller to
    /// read as "paw print" not "cat").
    private let footprintSize: CGFloat = 16

    var body: some View {
        ZStack {
            ForEach(Array(visibleFootprints.enumerated()), id: \.offset) { renderIndex, footprint in
                let ageRatio = Double(renderIndex) / Double(max(visibleFootprints.count - 1, 1))
                // Older footprints (lower renderIndex) fade toward 0;
                // newest footprint at the cat's tail is most opaque.
                let opacity = 0.15 + (0.55 * ageRatio)
                if let spriteImage = NekoSpriteLibrary.sprite(
                    named: "fp_\(footprint.direction.spriteFilenamePrefix)"
                ) {
                    Image(nsImage: spriteImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: footprintSize, height: footprintSize)
                        .opacity(opacity)
                        .position(footprint.point)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Each rendered footprint is a (point, direction) pair. Direction
    /// is derived from the velocity vector between this point and the
    /// preceding one in the trail buffer.
    private struct Footprint {
        let point: CGPoint
        let direction: NekoDirection
    }

    /// Build the (point, direction) list, applying the stride so the
    /// prints aren't stacked on top of each other.
    private var visibleFootprints: [Footprint] {
        guard trailPoints.count >= 2 else { return [] }
        var result: [Footprint] = []
        for index in stride(from: 1, to: trailPoints.count, by: spacingStride) {
            let previousPoint = trailPoints[index - 1]
            let currentPoint = trailPoints[index]
            let velocityVector = CGVector(
                dx: currentPoint.x - previousPoint.x,
                dy: currentPoint.y - previousPoint.y
            )
            let direction = NekoDirection.from(velocityVector: velocityVector, minimumMagnitude: 0.5)
                ?? .right
            result.append(Footprint(point: currentPoint, direction: direction))
        }
        return result
    }
}
