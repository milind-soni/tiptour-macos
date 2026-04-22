import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreImage
import AppKit

/// Native on-device element detector using CoreML (YOLO) + Apple Vision (OCR).
/// Replaces the Python OmniParser server — no external dependencies needed.
///
/// YOLO detects UI element bounding boxes (buttons, icons, menus).
/// Vision framework detects text on screen (labels, menu items, button text).
/// Together they provide element location + text matching entirely on-device.
class NativeElementDetector {

    static let shared = NativeElementDetector()

    // MARK: - Public Types

    struct DetectedElement {
        let label: String
        let center: CGPoint
        let bbox: CGRect
        let confidence: Double
        let source: String // "yolo" or "ocr"
    }

    struct FoundElement {
        let label: String
        let center: CGPoint
        let bbox: CGRect
        let confidence: Double
        let cacheAgeMs: Int
    }

    /// How the match was produced — useful for logging/debugging.
    enum MatchSource {
        case labelOnly                  // no hint coord; pure label match
        case proximityWithLabelBoost    // hint coord + label agreement
        case proximityNearest           // hint coord; label didn't help
    }

    // MARK: - Private State

    private var yoloModel: VNCoreMLModel?
    private var feedTimer: Timer?
    private var lastScreenshotProvider: (() async -> CGImage?)?

    /// Cached detection results from the most recent scan
    private var cachedElements: [DetectedElement] = []
    private var cachedImageSize: CGSize = .zero
    private var cacheTimestamp: Date = .distantPast
    private let cacheLock = NSLock()

    /// Prevents overlapping detection scans from piling up
    private var isDetectionInProgress = false

    private let confidenceThreshold: Float = 0.25

    // MARK: - Initialization

    private init() {
        loadYOLOModel()
    }

    private func loadYOLOModel() {
        guard let modelURL = Bundle.main.url(forResource: "UIElementDetector", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "UIElementDetector", withExtension: "mlpackage") else {
            print("[NativeDetector] UIElementDetector model not found in bundle")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            yoloModel = try VNCoreMLModel(for: mlModel)
            print("[NativeDetector] YOLO model loaded successfully")
        } catch {
            print("[NativeDetector] Failed to load YOLO model: \(error.localizedDescription)")
        }
    }

    // MARK: - Live Feeding (keeps cache warm)

    /// Start periodic screenshot scanning to keep element cache warm.
    /// The provider closure should return a CGImage of the current screen.
    func startLiveFeeding(interval: TimeInterval = 1.5, screenshotProvider: @escaping () async -> CGImage?) {
        lastScreenshotProvider = screenshotProvider
        feedTimer?.invalidate()
        feedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, !self.isDetectionInProgress else { return }
            // Detach to a background thread so YOLO+OCR inference
            // doesn't block the main thread (avoids cursor jank).
            Task.detached(priority: .utility) {
                guard let provider = self.lastScreenshotProvider else { return }
                // Screenshot capture needs MainActor (ScreenCaptureKit requirement)
                guard let image = await provider() else { return }
                await self.detectElements(in: image)
            }
        }
        print("[NativeDetector] Live feeding started (\(interval)s interval)")
    }

    func stopLiveFeeding() {
        feedTimer?.invalidate()
        feedTimer = nil
        print("[NativeDetector] Live feeding stopped")
    }

    // MARK: - Detection (YOLO + OCR)

    /// Run full detection pipeline: YOLO bounding boxes + Vision OCR text.
    /// Results are cached automatically.
    @discardableResult
    func detectElements(in cgImage: CGImage) async -> [DetectedElement] {
        isDetectionInProgress = true
        defer { isDetectionInProgress = false }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        async let yoloResults = runYOLODetection(on: cgImage, imageWidth: imageWidth, imageHeight: imageHeight)
        async let ocrResults = runOCRDetection(on: cgImage, imageWidth: imageWidth, imageHeight: imageHeight)

        let allElements = await yoloResults + ocrResults

        cacheLock.lock()
        cachedElements = allElements
        cachedImageSize = CGSize(width: imageWidth, height: imageHeight)
        cacheTimestamp = Date()
        cacheLock.unlock()

        print("[NativeDetector] \(allElements.count) elements detected (YOLO: \(await yoloResults.count), OCR: \(await ocrResults.count))")

        return allElements
    }

    // MARK: - YOLO Detection

    private func runYOLODetection(on cgImage: CGImage, imageWidth: CGFloat, imageHeight: CGFloat) async -> [DetectedElement] {
        guard let model = yoloModel else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                guard error == nil,
                      let results = request.results as? [VNRecognizedObjectObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let elements: [DetectedElement] = results.compactMap { observation in
                    guard observation.confidence >= self.confidenceThreshold else { return nil }

                    // Vision returns normalized coordinates with origin at bottom-left.
                    // Convert to pixel coordinates with origin at top-left (matching screenshot coords).
                    let visionBBox = observation.boundingBox
                    let pixelX = visionBBox.origin.x * imageWidth
                    let pixelY = (1.0 - visionBBox.origin.y - visionBBox.height) * imageHeight
                    let pixelWidth = visionBBox.width * imageWidth
                    let pixelHeight = visionBBox.height * imageHeight

                    let bbox = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
                    let center = CGPoint(x: bbox.midX, y: bbox.midY)

                    return DetectedElement(
                        label: "",
                        center: center,
                        bbox: bbox,
                        confidence: Double(observation.confidence),
                        source: "yolo"
                    )
                }

                continuation.resume(returning: elements)
            }

            // Match the image size the model was trained on
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[NativeDetector] YOLO inference error: \(error.localizedDescription)")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - OCR Detection (Apple Vision)

    private func runOCRDetection(on cgImage: CGImage, imageWidth: CGFloat, imageHeight: CGFloat) async -> [DetectedElement] {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let elements: [DetectedElement] = results.compactMap { observation in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    // Accurate mode reports 0.5 for low confidence and 1.0 for high —
                    // drop only the genuinely low ones.
                    guard topCandidate.confidence >= 0.4 else { return nil }

                    // Convert from Vision's bottom-left normalized to top-left pixel coords
                    let visionBBox = observation.boundingBox
                    let pixelX = visionBBox.origin.x * imageWidth
                    let pixelY = (1.0 - visionBBox.origin.y - visionBBox.height) * imageHeight
                    let pixelWidth = visionBBox.width * imageWidth
                    let pixelHeight = visionBBox.height * imageHeight

                    let bbox = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
                    let center = CGPoint(x: bbox.midX, y: bbox.midY)

                    return DetectedElement(
                        label: topCandidate.string,
                        center: center,
                        bbox: bbox,
                        confidence: Double(topCandidate.confidence),
                        source: "ocr"
                    )
                }

                continuation.resume(returning: elements)
            }

            // Accurate mode extracts app-UI text cleanly at 1.00 confidence
            // — proven in testing against Blender (90 labels, all pristine:
            // File/Edit/Render/Layout/Modeling/Sculpting/etc.). Fast mode
            // returned 20 fragments with 0.50 confidence and mangled text
            // like "Ch rome" and "Next. js", which was the root cause of
            // YOLO label-match failures in apps without AX trees.
            // Trade-off: ~200ms extra latency, negligible for our use case.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.008

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[NativeDetector] OCR error: \(error.localizedDescription)")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Element Finding (query matching)

    /// Find an element by name — runs detection if needed, matches against OCR text
    /// and YOLO element positions. Returns the best match.
    func findElement(query: String, in cgImage: CGImage) async -> FoundElement? {
        // Run fresh detection
        let elements = await detectElements(in: cgImage)
        return matchElement(query: query, elements: elements)
    }

    /// Refine an LLM-suggested coordinate to the center of the actual
    /// clickable element the LLM was pointing at.
    ///
    /// The LLM gives approximately-right coordinates — often off by
    /// 100-300 pixels in visually-complex apps like Blender because
    /// the LLM reasons on a downscaled image internally. Our YOLO
    /// detections are pixel-perfect, so we use the LLM's coord as a
    /// proximity anchor and snap to the nearest clickable-looking
    /// YOLO box.
    ///
    /// Strategy:
    ///   1. If a YOLO box CONTAINS the hint, pick the smallest containing
    ///      box (tightest fit around the click target).
    ///   2. Otherwise pick the NEAREST YOLO box. No hard distance cap —
    ///      if Gemini is off by 300px in Blender, we still want to snap.
    ///      Label agreement with OCR-inside-box acts as a tiebreaker.
    ///
    /// OCR garbage (common on 3D/code apps) doesn't hurt us — when OCR
    /// can't read the screen, label scores are zero and we fall back to
    /// pure proximity, which still beats using the raw LLM coordinate.
    func refineCoordinate(hint: CGPoint, label: String) -> FoundElement? {
        cacheLock.lock()
        let elements = cachedElements
        let timestamp = cacheTimestamp
        cacheLock.unlock()

        let ageMs = Int(Date().timeIntervalSince(timestamp) * 1000)
        if ageMs > 5000 { return nil }

        let yoloBoxes = elements.filter { $0.source == "yolo" }
        let ocrElements = elements.filter { $0.source == "ocr" && !$0.label.isEmpty }
        guard !yoloBoxes.isEmpty else { return nil }

        // 1. Boxes that contain the hint point. Pick the smallest.
        let containingBoxes = yoloBoxes.filter { $0.bbox.contains(hint) }
        if let tightestBox = containingBoxes.min(by: { $0.bbox.area < $1.bbox.area }) {
            return FoundElement(
                label: labelForYoloBox(tightestBox, ocrElements: ocrElements) ?? label,
                center: tightestBox.center,
                bbox: tightestBox.bbox,
                confidence: tightestBox.confidence,
                cacheAgeMs: ageMs
            )
        }

        // 2. No box contains the hint — snap to the nearest one, with
        //    label agreement as a tiebreaker among similarly-close boxes.
        let normalizedQuery = Self.normalizeQuery(label)
        let scored = yoloBoxes.map { box -> (box: DetectedElement, score: Double, labelMatched: Bool) in
            let distance = hypot(box.center.x - hint.x, box.center.y - hint.y)
            let proximityScore = 1.0 / (1.0 + Double(distance) / 250.0)

            let boxLabels = ocrElements
                .filter { box.bbox.intersects($0.bbox) || box.bbox.contains($0.center) }
                .map { $0.label }
            var labelScore = 0.0
            for boxLabel in boxLabels {
                let normalizedLabel = Self.normalizeQuery(boxLabel)
                let shared = normalizedLabel.words.intersection(normalizedQuery.words)
                if !shared.isEmpty {
                    let coverage = Double(shared.count) / Double(max(normalizedQuery.words.count, 1))
                    labelScore = max(labelScore, coverage)
                }
            }
            // Weight YOLO's own confidence into the ranking. Low-
            // confidence detections (shadows, text artifacts, partial
            // icons) are often false positives; a slightly-further
            // 0.85-confidence box almost always beats a very-close
            // 0.3-confidence one. Scales proximity by 0.5 + conf/2 so a
            // 1.0-confidence box scores at full proximity weight and a
            // 0.0-confidence one at half.
            let confidenceFactor = 0.5 + box.confidence / 2.0
            let combinedScore = proximityScore * confidenceFactor + (labelScore * 0.5)
            return (box, combinedScore, labelScore > 0)
        }

        guard let best = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        // Sanity check: if no OCR label matched AND the closest box is
        // more than 400px from the LLM's hint, the label probably isn't
        // on screen at all (hidden in a menu, behind a dropdown, etc.).
        // Return nil so the caller falls back to raw LLM coords rather
        // than snapping to a random faraway box.
        let distanceFromHint = hypot(best.box.center.x - hint.x, best.box.center.y - hint.y)
        if !best.labelMatched && distanceFromHint > 400 {
            return nil
        }

        return FoundElement(
            label: labelForYoloBox(best.box, ocrElements: ocrElements) ?? label,
            center: best.box.center,
            bbox: best.box.bbox,
            confidence: best.box.confidence,
            cacheAgeMs: ageMs
        )
    }

    /// Pick the best OCR text overlapping a YOLO box, for labeling/logging.
    private func labelForYoloBox(_ yoloBox: DetectedElement, ocrElements: [DetectedElement]) -> String? {
        let overlapping = ocrElements.filter { yoloBox.bbox.intersects($0.bbox) }
        return overlapping.max(by: { $0.bbox.area < $1.bbox.area })?.label
    }

    /// Find from cache only (instant, no detection). Returns nil if cache is stale (>3s).
    ///
    /// `preferMatchesNearPixel` — optional anchor in SCREENSHOT-PIXEL
    /// coordinates. When multiple OCR matches score equally for the
    /// query (e.g., the word "New" appears in both an open File menu
    /// and a "New Tab" button elsewhere on screen), the candidate
    /// closest to this anchor wins. Callers use this to bias nested-
    /// menu resolution toward elements near the previously-clicked
    /// element.
    func findFromCache(query: String, preferMatchesNearPixel: CGPoint? = nil) -> FoundElement? {
        cacheLock.lock()
        let elements = cachedElements
        let timestamp = cacheTimestamp
        cacheLock.unlock()

        let ageMs = Int(Date().timeIntervalSince(timestamp) * 1000)
        if ageMs > 3000 { return nil }

        return matchElement(
            query: query,
            elements: elements,
            preferMatchesNearPixel: preferMatchesNearPixel
        )
    }

    /// Match a query string against detected elements.
    ///
    /// Strategy: find the best OCR text match, then (this is the important part)
    /// look for the smallest YOLO bounding box that contains the OCR text's
    /// bounding box. That YOLO box is the clickable element — its center is
    /// what we want the cursor to land on, not the center of the text itself.
    ///
    /// Why: buttons usually have padding/icons/etc. around their text, so the
    /// OCR text center is offset from the button's visual center. YOLO detects
    /// the whole button as one UI element and its box encloses the text.
    ///
    /// OCR-match priority (best → worst):
    ///   1. Exact case-insensitive match
    ///   2. Query contained in label, or label contained in query
    ///   3. Any word overlap
    /// Common English filler/descriptor words stripped before matching so
    /// descriptive labels like "the save button" still match OCR text "Save".
    private static let stopWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those",
        "button", "icon", "menu", "bar", "tab", "panel", "item", "option",
        "link", "field", "input", "box", "area", "section", "row", "cell"
    ]

    private static func normalizeQuery(_ text: String) -> (full: String, words: Set<String>) {
        let lower = text.lowercased()
        let rawWords = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let meaningfulWords = rawWords.filter { !stopWords.contains($0) }
        return (full: lower, words: Set(meaningfulWords.isEmpty ? rawWords : meaningfulWords))
    }

    /// Among candidates sharing the top score, pick the one closest to
    /// the proximity anchor (if any). Returns nil when the input is
    /// empty. When the anchor is nil or there's only one top-scored
    /// candidate, returns the first max-scored element (original
    /// behavior — preserves backward compatibility for callers that
    /// don't provide an anchor).
    private static func pickBestCandidate(
        from scoredMatches: [(element: DetectedElement, score: Int)],
        preferMatchesNearPixel: CGPoint?
    ) -> DetectedElement? {
        guard let topScore = scoredMatches.map(\.score).max() else { return nil }
        let topCandidates = scoredMatches.filter { $0.score == topScore }
        guard !topCandidates.isEmpty else { return nil }

        if let anchor = preferMatchesNearPixel, topCandidates.count > 1 {
            let closest = topCandidates.min { lhs, rhs in
                let distanceLhs = hypot(lhs.element.center.x - anchor.x, lhs.element.center.y - anchor.y)
                let distanceRhs = hypot(rhs.element.center.x - anchor.x, rhs.element.center.y - anchor.y)
                return distanceLhs < distanceRhs
            }
            if let closest {
                return closest.element
            }
        }
        return topCandidates.first?.element
    }

    private func matchElement(
        query: String,
        elements: [DetectedElement],
        preferMatchesNearPixel: CGPoint? = nil
    ) -> FoundElement? {
        let queryLower = query.lowercased()
        let normalizedQuery = Self.normalizeQuery(query)

        cacheLock.lock()
        let ageMs = Int(Date().timeIntervalSince(cacheTimestamp) * 1000)
        cacheLock.unlock()

        let ocrElements = elements.filter { $0.source == "ocr" && !$0.label.isEmpty }
        let yoloElements = elements.filter { $0.source == "yolo" }

        // Rank all OCR matches by quality, take the best one.
        //
        // Critical: OCR often returns single-letter fragments ("e", "a",
        // "l") from partial glyph recognition. Without a minimum-length
        // guard, "File".contains("e") == true would let a stray "e"
        // fragment outscore a real match. We require both sides of a
        // substring check to be at least 3 chars so only substantive
        // partial matches qualify.
        let minSubstringLength = 3
        let scoredOcrMatches: [(element: DetectedElement, score: Int)] = ocrElements.compactMap { ocrElement in
            let labelLower = ocrElement.label.lowercased()
            let normalizedLabel = Self.normalizeQuery(ocrElement.label)

            if labelLower == queryLower { return (ocrElement, 5) }
            if normalizedLabel.full == normalizedQuery.full { return (ocrElement, 4) }

            // Substring containment — guarded against tiny fragments.
            if labelLower.count >= minSubstringLength,
               queryLower.count >= minSubstringLength,
               (labelLower.contains(queryLower) || queryLower.contains(labelLower)) {
                return (ocrElement, 3)
            }

            // Meaningful-word overlap after stop-word stripping. Also guard
            // against overlap driven purely by single-character tokens.
            let meaningfulShared = normalizedLabel.words
                .intersection(normalizedQuery.words)
                .filter { $0.count >= minSubstringLength }
            if !meaningfulShared.isEmpty {
                let coverage = Double(meaningfulShared.count) / Double(max(normalizedQuery.words.count, 1))
                if coverage >= 1.0 { return (ocrElement, 2) }
                if coverage >= 0.5 { return (ocrElement, 1) }
            }
            return nil
        }

        // Pick the highest-scoring candidate. When a proximity anchor
        // is provided AND multiple candidates tie for the top score
        // (common for nested-menu resolution — "New" can appear in
        // both the just-opened File menu and in an unrelated button
        // elsewhere), pick the one closest to the anchor. Without an
        // anchor, fall back to the original "first max" behavior.
        guard let bestOcrMatch = Self.pickBestCandidate(
            from: scoredOcrMatches,
            preferMatchesNearPixel: preferMatchesNearPixel
        ) else {
            return nil
        }

        // Apple Vision likes to merge adjacent text on the same baseline
        // into ONE detection — so Blender's top menu bar comes back as a
        // single block "File Edit Render" with one giant bounding box.
        // When the query is a substring of that block, using the block's
        // center lands between Edit and Render, not on File. Compute
        // where the matched substring actually sits within the box,
        // proportional to character position, and shift the target X.
        let (refinedCenter, refinedBBox) = narrowedTarget(
            for: queryLower,
            in: bestOcrMatch
        )

        // Cross-reference: find the smallest YOLO box that contains the
        // refined (narrowed) center. That's the true clickable element.
        let containingYoloBoxes = yoloElements.filter { $0.bbox.contains(refinedCenter) }

        if let smallestContainingBox = containingYoloBoxes.min(by: { $0.bbox.area < $1.bbox.area }) {
            return FoundElement(
                label: bestOcrMatch.label,
                center: smallestContainingBox.center,
                bbox: smallestContainingBox.bbox,
                confidence: min(bestOcrMatch.confidence, smallestContainingBox.confidence),
                cacheAgeMs: ageMs
            )
        }

        return FoundElement(
            label: bestOcrMatch.label,
            center: refinedCenter,
            bbox: refinedBBox,
            confidence: bestOcrMatch.confidence,
            cacheAgeMs: ageMs
        )
    }

    /// If the query is a proper substring of the OCR label (common when
    /// Apple Vision merges neighbouring menu items into one detection),
    /// approximate where the substring sits inside the bounding box
    /// using proportional character indices. Assumes uniform character
    /// width — imperfect but dramatically better than returning the
    /// full box's center when the query matches only part of the text.
    private func narrowedTarget(
        for queryLower: String,
        in ocrElement: DetectedElement
    ) -> (center: CGPoint, bbox: CGRect) {
        let labelLower = ocrElement.label.lowercased()
        let fullBBox = ocrElement.bbox

        // If the query is the entire label (or vice versa), or the label
        // doesn't contain the query at all, just return the full center.
        guard labelLower != queryLower,
              let range = labelLower.range(of: queryLower) else {
            return (ocrElement.center, fullBBox)
        }

        let totalLength = labelLower.count
        guard totalLength > 0 else { return (ocrElement.center, fullBBox) }

        let startOffset = labelLower.distance(from: labelLower.startIndex, to: range.lowerBound)
        let endOffset = labelLower.distance(from: labelLower.startIndex, to: range.upperBound)

        let startFraction = CGFloat(startOffset) / CGFloat(totalLength)
        let endFraction = CGFloat(endOffset) / CGFloat(totalLength)

        let narrowedX = fullBBox.origin.x + fullBBox.width * startFraction
        let narrowedWidth = fullBBox.width * (endFraction - startFraction)

        let narrowedBBox = CGRect(
            x: narrowedX,
            y: fullBBox.origin.y,
            width: narrowedWidth,
            height: fullBBox.height
        )
        let narrowedCenter = CGPoint(x: narrowedBBox.midX, y: narrowedBBox.midY)

        return (narrowedCenter, narrowedBBox)
    }

    // MARK: - Cache Access (for overlay rendering)

    /// Get all cached elements for overlay rendering.
    /// Returns elements as dictionaries matching the format DetectionOverlayView expects.
    func getCachedElements() -> (elements: [[String: Any]], imageSize: [Int], cacheAgeMs: Int) {
        cacheLock.lock()
        let elements = cachedElements
        let imgSize = cachedImageSize
        let timestamp = cacheTimestamp
        cacheLock.unlock()

        let ageMs = Int(Date().timeIntervalSince(timestamp) * 1000)

        let dictElements: [[String: Any]] = elements.map { element in
            [
                "bbox": [Int(element.bbox.origin.x), Int(element.bbox.origin.y),
                         Int(element.bbox.origin.x + element.bbox.width), Int(element.bbox.origin.y + element.bbox.height)],
                "center": [Int(element.center.x), Int(element.center.y)],
                "conf": element.confidence,
                "label": element.label,
                "source": element.source
            ]
        }

        return (dictElements, [Int(imgSize.width), Int(imgSize.height)], ageMs)
    }

    /// Check if the detector is ready (model loaded).
    var isAvailable: Bool {
        return yoloModel != nil
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
