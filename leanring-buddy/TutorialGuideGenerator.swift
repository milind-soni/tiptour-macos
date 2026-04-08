import Foundation

/// A single step in a tutorial guide
struct TutorialStep: Codable, Identifiable {
    let id: String
    let timestamp: Double
    let action: String
    let element: String
    let elementRole: String?
    let hint: String
    let narration: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, action, element
        case elementRole = "element_role"
        case hint, narration
    }
}

/// A complete tutorial guide generated from a YouTube video
struct TutorialGuide: Codable {
    let title: String
    let app: String
    var steps: [TutorialStep]
    let videoURL: String

    enum CodingKeys: String, CodingKey {
        case title, app, steps
        case videoURL = "video_url"
    }
}

/// Generates a TutorialGuide from a YouTube video URL using Gemini
class TutorialGuideGenerator {

    /// Worker proxy URL — matches CompanionManager.workerBaseURL
    private static let workerBaseURL = "http://localhost:8787"

    /// Generate a guide from a YouTube URL
    static func generate(
        youtubeURL: String,
        onStatus: @escaping (String) -> Void
    ) async throws -> TutorialGuide {

        // 1. Extract video ID
        guard let videoID = extractVideoID(from: youtubeURL) else {
            throw GuideError.invalidURL
        }

        // 2. Fetch transcript
        onStatus("Fetching transcript...")
        let transcript = try await fetchTranscript(videoID: videoID)
        onStatus("Got transcript (\(transcript.count) chars)")

        // 3. Send to Gemini
        print("[GuideGen] Transcript (\(transcript.count) chars):\n\(transcript.prefix(500))")
        onStatus("Analyzing with AI (\(transcript.count) chars)...")
        let guide = try await analyzeWithGemini(transcript: transcript, videoURL: youtubeURL)
        onStatus("Done — \(guide.steps.count) steps extracted")

        return guide
    }

    // MARK: - Video ID

    private static func extractVideoID(from url: String) -> String? {
        // Handle: youtube.com/watch?v=ID, youtu.be/ID, youtube.com/embed/ID
        if let components = URLComponents(string: url) {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
            if components.host == "youtu.be" {
                return String(components.path.dropFirst()) // remove leading /
            }
        }
        return nil
    }

    // MARK: - Transcript (via YouTube's timedtext API)

    private static func fetchTranscript(videoID: String) async throws -> String {
        // Fetch transcript via worker proxy (avoids sandbox network issues)
        let url = URL(string: "\(workerBaseURL)/transcript")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["videoID": videoID])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GuideError.transcriptFailed("Worker returned \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawTranscript = json["transcript"] as? String else {
            throw GuideError.transcriptFailed("Invalid response from worker")
        }

        // Try parsing as XML first, then VTT
        let xmlParsed = parseTimedText(xml: rawTranscript)
        if !xmlParsed.isEmpty { return xmlParsed }

        let vttParsed = parseVTT(text: rawTranscript)
        if !vttParsed.isEmpty { return vttParsed }

        // Return raw if nothing parsed
        return rawTranscript
    }

    /// Parse WebVTT format captions
    private static func parseVTT(text: String) -> String {
        var result: [String] = []
        let lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            // Look for timestamp lines like "00:00:42.000 --> 00:00:45.000"
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                guard let startStr = parts.first?.trimmingCharacters(in: .whitespaces) else { continue }

                // Parse timestamp
                let timeParts = startStr.components(separatedBy: ":")
                var seconds: Double = 0
                if timeParts.count == 3 {
                    seconds = (Double(timeParts[0]) ?? 0) * 3600 + (Double(timeParts[1]) ?? 0) * 60 + (Double(timeParts[2].components(separatedBy: ".").first ?? "0") ?? 0)
                } else if timeParts.count == 2 {
                    seconds = (Double(timeParts[0]) ?? 0) * 60 + (Double(timeParts[1].components(separatedBy: ".").first ?? "0") ?? 0)
                }

                // Get the caption text (next non-empty line)
                if i + 1 < lines.count {
                    let captionText = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !captionText.isEmpty && !captionText.contains("-->") {
                        let mins = Int(seconds) / 60
                        let secs = Int(seconds) % 60
                        result.append("[\(mins):\(String(format: "%02d", secs))] \(captionText)")
                    }
                }
            }
        }

        return result.joined(separator: "\n")
    }

    private static func parseTimedText(xml: String) -> String {
        var result: [String] = []
        let pattern = #"<text start="([^"]+)"[^>]*>([^<]*)</text>"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges >= 3 {
                let startStr = nsString.substring(with: match.range(at: 1))
                let text = nsString.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty, let startTime = Double(startStr) else { continue }

                let mins = Int(startTime) / 60
                let secs = Int(startTime) % 60
                result.append("[\(mins):\(String(format: "%02d", secs))] \(text)")
            }
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Gemini Analysis

    private static func analyzeWithGemini(transcript: String, videoURL: String) async throws -> TutorialGuide {
        let url = URL(string: "\(workerBaseURL)/generate-guide")!

        let prompt = """
        You are analyzing a YouTube software tutorial transcript. Extract every user action into a structured guide.

        TRANSCRIPT:
        \(String(transcript.prefix(12000)))

        For each action the user performs, output:
        - timestamp (seconds)
        - action: "click", "type", "drag", "scroll", or "observe"
        - element: the UI element name
        - element_role: the type ("menu_bar_item", "menu_item", "button", "text_field", "toolbar_button", etc.)
        - hint: instruction for the user
        - narration: what the narrator says

        Output ONLY valid JSON:
        {"title": "...", "app": "...", "steps": [{"timestamp": 42, "action": "click", "element": "Filter", "element_role": "menu_bar_item", "hint": "Click Filter menu", "narration": "..."}]}

        Rules:
        - Include EVERY click, menu selection, keyboard shortcut, tool selection
        - Be precise about element names
        - For nested menus, make each level a SEPARATE step
        - Skip narration-only moments
        - Output raw JSON only, no markdown
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Send transcript to worker proxy which forwards to Gemini
        let requestBody: [String: Any] = ["transcript": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GuideError.geminiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body.prefix(200))")
        }

        // Worker returns raw Gemini response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var textOutput = ""
        if let candidates = json?["candidates"] as? [[String: Any]] {
            for candidate in candidates {
                if let content = candidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]] {
                    for part in parts {
                        textOutput += part["text"] as? String ?? ""
                    }
                }
            }
        }

        print("[GuideGen] Gemini raw (\(textOutput.count) chars):\n\(textOutput.prefix(300))")

        // Clean markdown fences
        textOutput = textOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if textOutput.hasPrefix("```") {
            textOutput = textOutput.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        }
        if textOutput.hasSuffix("```") {
            textOutput = textOutput.components(separatedBy: "\n").dropLast().joined(separator: "\n")
        }
        textOutput = textOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse the JSON
        guard let jsonData = textOutput.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw GuideError.parseFailed("Could not parse Gemini response")
        }

        let title = parsed["title"] as? String ?? "Tutorial"
        let app = parsed["app"] as? String ?? "Unknown"
        let rawSteps = parsed["steps"] as? [[String: Any]] ?? []

        let steps: [TutorialStep] = rawSteps.enumerated().map { index, dict in
            TutorialStep(
                id: "step-\(index + 1)",
                timestamp: dict["timestamp"] as? Double ?? 0,
                action: dict["action"] as? String ?? "click",
                element: dict["element"] as? String ?? "",
                elementRole: dict["element_role"] as? String,
                hint: dict["hint"] as? String ?? "",
                narration: dict["narration"] as? String
            )
        }

        return TutorialGuide(title: title, app: app, steps: steps, videoURL: videoURL)
    }

    // MARK: - Errors

    enum GuideError: LocalizedError {
        case invalidURL
        case transcriptFailed(String)
        case geminiError(String)
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid YouTube URL"
            case .transcriptFailed(let msg): return "Transcript: \(msg)"
            case .geminiError(let msg): return "AI: \(msg)"
            case .parseFailed(let msg): return "Parse: \(msg)"
            }
        }
    }
}
