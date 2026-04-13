import Foundation
import CoreGraphics

/// Client for the local TipTour YOLO+OCR server.
/// Sends screenshots periodically to keep the cache fresh.
/// Element lookups are instant when cache is warm.
class OmniParserClient {

    static let shared = OmniParserClient()
    private let baseURL = "http://localhost:8765"
    private var feedTimer: Timer?
    private var lastScreenshotProvider: (() async -> String?)?

    struct FoundElement {
        let label: String
        let center: CGPoint
        let bbox: CGRect
        let confidence: Double
        let cacheAgeMs: Int
    }

    /// Start feeding screenshots every interval to keep the cache warm
    func startLiveFeeding(interval: TimeInterval = 1.5, screenshotProvider: @escaping () async -> String?) {
        lastScreenshotProvider = screenshotProvider
        feedTimer?.invalidate()
        feedTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                guard let self = self, let provider = self.lastScreenshotProvider else { return }
                guard let b64 = await provider() else { return }
                // Fire and forget — just update the cache
                await self.sendScan(imageBase64: b64)
            }
        }
        print("[OmniParser] Live feeding started (\(interval)s interval)")
    }

    func stopLiveFeeding() {
        feedTimer?.invalidate()
        feedTimer = nil
        print("[OmniParser] Live feeding stopped")
    }

    /// Send a screenshot to update the server's cache (fire and forget)
    private func sendScan(imageBase64: String) async {
        guard let url = URL(string: "\(baseURL)/scan") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["image": imageBase64])

        _ = try? await URLSession.shared.data(for: request)
    }

    /// Find an element by name — uses cache if fresh, re-scans if stale
    func findElement(query: String, imageBase64: String) async -> FoundElement? {
        guard let url = URL(string: "\(baseURL)/find") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = ["image": imageBase64, "query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = json["found"] as? Bool, found,
                  let element = json["element"] as? [String: Any],
                  let center = element["center"] as? [Int],
                  center.count == 2 else {
                return nil
            }

            let bbox = element["bbox"] as? [Int] ?? [0, 0, 0, 0]
            let cacheAge = json["cache_age_ms"] as? Int ?? -1

            return FoundElement(
                label: element["label"] as? String ?? query,
                center: CGPoint(x: center[0], y: center[1]),
                bbox: CGRect(x: bbox[0], y: bbox[1], width: bbox[2] - bbox[0], height: bbox[3] - bbox[1]),
                confidence: element["conf"] as? Double ?? 0,
                cacheAgeMs: cacheAge
            )
        } catch {
            print("[OmniParser] Error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Quick check — find from cache only (no image needed, instant)
    func findFromCache(query: String) async -> FoundElement? {
        guard let url = URL(string: "\(baseURL)/find") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let found = json["found"] as? Bool, found,
                  let element = json["element"] as? [String: Any],
                  let center = element["center"] as? [Int],
                  center.count == 2 else {
                return nil
            }

            let bbox = element["bbox"] as? [Int] ?? [0, 0, 0, 0]
            let cacheAge = json["cache_age_ms"] as? Int ?? -1

            // Only trust cache if it's fresh (< 3 seconds)
            if cacheAge > 3000 { return nil }

            return FoundElement(
                label: element["label"] as? String ?? query,
                center: CGPoint(x: center[0], y: center[1]),
                bbox: CGRect(x: bbox[0], y: bbox[1], width: bbox[2] - bbox[0], height: bbox[3] - bbox[1]),
                confidence: element["conf"] as? Double ?? 0,
                cacheAgeMs: cacheAge
            )
        } catch {
            return nil
        }
    }

    /// Check if server is running
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/cache") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
