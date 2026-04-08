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

    // Set via TutorialGuideGenerator.apiKey before first use
    static var apiKey: String = ""
    private static let geminiModel = "gemini-2.5-flash"

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
        onStatus("Analyzing with AI...")
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
        // Try YouTube's auto-generated captions via the timedtext endpoint
        // This is a simplified approach — for production, use youtube-transcript-api or innertube API
        let pageURL = "https://www.youtube.com/watch?v=\(videoID)"

        var request = URLRequest(url: URL(string: pageURL)!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw GuideError.transcriptFailed("Could not load page")
        }

        // Extract the captions player response JSON
        guard let captionsStart = html.range(of: "\"captions\":") else {
            throw GuideError.transcriptFailed("No captions found — video may not have subtitles")
        }

        // Find the timedtext URL in the player response
        let searchArea = String(html[captionsStart.lowerBound...].prefix(5000))
        guard let urlStart = searchArea.range(of: "\"baseUrl\":\""),
              let urlEnd = searchArea[urlStart.upperBound...].range(of: "\"") else {
            throw GuideError.transcriptFailed("Could not find caption URL")
        }

        var captionURL = String(searchArea[urlStart.upperBound..<urlEnd.lowerBound])
        captionURL = captionURL.replacingOccurrences(of: "\\u0026", with: "&")

        // Fetch the actual transcript XML
        let (captionData, _) = try await URLSession.shared.data(for: URLRequest(url: URL(string: captionURL)!))
        guard let captionXML = String(data: captionData, encoding: .utf8) else {
            throw GuideError.transcriptFailed("Could not parse captions")
        }

        // Parse XML to extract text with timestamps
        return parseTimedText(xml: captionXML)
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
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(geminiModel):generateContent?key=\(apiKey)")!

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

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 65536]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GuideError.geminiError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(body.prefix(200))")
        }

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
