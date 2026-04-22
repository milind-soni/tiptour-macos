//
//  ScreenshotPerceptualHash.swift
//  leanring-buddy
//

//  Cheap perceptual hash (dHash) for skipping near-identical screenshots
//  before sending them to Gemini Live. The hash is a 64-bit fingerprint
//  computed from a 9x8 grayscale downscale; comparing two hashes by
//  Hamming distance gives a robust "is this scene meaningfully different"
//  signal that ignores cursor blinks, antialiasing jitter, and 1px scroll.
//
//  Why this exists: GeminiLiveSession sends a fresh JPEG every 3s. When the
//  user is reading a long document or watching something render, frames are
//  pixel-identical but we still pay the ScreenCaptureKit + JPEG encode +
//  WebSocket bandwidth + Gemini per-image input tokens. Skipping unchanged
//  frames cuts all of that without changing behavior on active screens.
//

import CoreGraphics
import Foundation
import ImageIO

enum ScreenshotPerceptualHash {

    /// Threshold (in Hamming distance bits, 0–64) under which two hashes
    /// are considered "the same scene." 5 bits is the conventional dHash
    /// threshold — robust to cursor twitches and antialiasing while still
    /// catching meaningful UI changes (a new dialog, scrolled content, etc).
    static let sameSceneHammingThreshold: Int = 5

    /// Compute a 64-bit dHash from JPEG image data. Returns nil if the
    /// JPEG can't be decoded — caller should treat that as "send the
    /// frame anyway" so we never silently drop a real screenshot due to
    /// a hashing failure.
    static func perceptualHash(forJPEGData jpegData: Data) -> UInt64? {
        guard let imageSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return perceptualHash(forCGImage: cgImage)
    }

    /// Compute a 64-bit dHash from a CGImage. Algorithm:
    ///   1. Downscale to 9x8 grayscale (72 pixels total).
    ///   2. For each row, compare each pixel with the next pixel to its right.
    ///      That gives 8 comparisons per row × 8 rows = 64 bits.
    ///   3. Pack the comparisons into a UInt64.
    /// Total cost: a single CGContext draw + 72 pixel reads + 64 bit ops.
    /// Typical runtime: 1–3ms per screenshot on Apple Silicon.
    static func perceptualHash(forCGImage cgImage: CGImage) -> UInt64? {
        let downscaledWidth = 9
        let downscaledHeight = 8
        let bytesPerRow = downscaledWidth // 1 byte per pixel for grayscale
        var pixelBuffer = [UInt8](repeating: 0, count: downscaledWidth * downscaledHeight)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixelBuffer,
            width: downscaledWidth,
            height: downscaledHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: downscaledWidth, height: downscaledHeight))

        var hash: UInt64 = 0
        for row in 0..<downscaledHeight {
            for column in 0..<(downscaledWidth - 1) {
                let leftPixelIndex = row * downscaledWidth + column
                let rightPixelIndex = leftPixelIndex + 1
                if pixelBuffer[leftPixelIndex] > pixelBuffer[rightPixelIndex] {
                    let bitPosition = row * (downscaledWidth - 1) + column
                    hash |= (UInt64(1) << bitPosition)
                }
            }
        }
        return hash
    }

    /// Hamming distance between two 64-bit hashes — number of bit positions
    /// at which they differ. Lower = more similar; 0 = identical.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    /// Convenience: are two hashes close enough to be treated as the same scene?
    static func isSameScene(_ a: UInt64, _ b: UInt64) -> Bool {
        return hammingDistance(a, b) <= sameSceneHammingThreshold
    }
}
