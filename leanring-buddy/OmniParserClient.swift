import Foundation

/// Client for the local OmniParser YOLO+OCR server
/// Finds UI elements on screen by name — no Claude API call needed
class OmniParserClient {

    static let shared = OmniParserClient()
    private let baseURL = "http://localhost:8765"

    struct FoundElement {
        let label: String
        let center: CGPoint  // pixel coords in screenshot
        let bbox: CGRect
        let confidence: Double
    }

    /// Find a specific element by name in a screenshot
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
            return FoundElement(
                label: element["label"] as? String ?? query,
                center: CGPoint(x: center[0], y: center[1]),
                bbox: CGRect(x: bbox[0], y: bbox[1], width: bbox[2] - bbox[0], height: bbox[3] - bbox[1]),
                confidence: element["conf"] as? Double ?? 0
            )
        } catch {
            print("[OmniParser] Error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if the server is running
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/parse") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"image\":\"\"}".data(using: .utf8)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 400 // 400 = "No image" = server is alive
        } catch {
            return false
        }
    }
}
