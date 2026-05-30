import Foundation

struct TipTourOpenRouterVisionClient {
    private struct ChatCompletionRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    private enum ContentBlock: Encodable {
        case text(String)
        case imageData(mimeType: String, base64: String)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        enum ImageURLCodingKeys: String, CodingKey {
            case url
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageData(let mimeType, let base64):
                try container.encode("image_url", forKey: .type)
                var imageContainer = container.nestedContainer(keyedBy: ImageURLCodingKeys.self, forKey: .imageURL)
                try imageContainer.encode("data:\(mimeType);base64,\(base64)", forKey: .url)
            }
        }
    }

    private struct ChatCompletionResponse: Decodable {
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let message: ResponseMessage
        }

        struct ResponseMessage: Decodable {
            let content: ResponseContent?
        }

        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
            let totalTokens: Int?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
            }
        }
    }

    private enum ResponseContent: Decodable {
        case text(String)
        case blocks([ResponseContentBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            self = .blocks(try container.decode([ResponseContentBlock].self))
        }

        var text: String {
            switch self {
            case .text(let text):
                return text
            case .blocks(let blocks):
                return blocks.compactMap(\.text).joined(separator: "\n")
            }
        }
    }

    private struct ResponseContentBlock: Decodable {
        let type: String?
        let text: String?
    }

    private struct EnrichmentPayload: Decodable {
        let summary: String?
        let steps: [TipTourFollowAlongVisualStep]?
        let manualCheckpoints: [String]?

        enum CodingKeys: String, CodingKey {
            case summary
            case steps
            case manualCheckpoints = "manual_checkpoints"
        }
    }

    func enrichTutorialContext(
        transcript: String,
        targetAppName: String?,
        frames: [TipTourFollowAlongFrameReference],
        apiKey: String,
        model: String = "qwen/qwen3-vl-8b-instruct"
    ) async throws -> TipTourFollowAlongEnrichment {
        let prompt = Self.enrichmentPrompt(
            transcript: transcript,
            targetAppName: targetAppName,
            frameCount: frames.count
        )
        var contentBlocks: [ContentBlock] = [.text(prompt)]
        for frame in frames.prefix(8) {
            let data = try Data(contentsOf: frame.fileURL)
            contentBlocks.append(.imageData(mimeType: "image/jpeg", base64: data.base64EncodedString()))
        }

        let body = ChatCompletionRequest(
            model: model,
            messages: [Message(role: "user", content: contentBlocks)],
            temperature: 0.1,
            maxTokens: 2600
        )

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://tiptour.local", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("TipTour Follow Along", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "OpenRouter vision enrichment request",
            errorDomain: "TipTourOpenRouterVisionClient"
        )

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let responseText = decoded.choices.first?.message.content?.text ?? ""
        let enrichment = decodeEnrichment(
            from: responseText,
            model: model,
            frameCount: frames.count
        )
        return enrichment
    }

    private func decodeEnrichment(
        from responseText: String,
        model: String,
        frameCount: Int
    ) -> TipTourFollowAlongEnrichment {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonObject = Self.extractFirstJSONObject(from: trimmed),
           let data = jsonObject.data(using: .utf8),
           let payload = try? JSONDecoder().decode(EnrichmentPayload.self, from: data) {
            return TipTourFollowAlongEnrichment(
                model: model,
                summary: payload.summary ?? "",
                steps: payload.steps ?? [],
                manualCheckpoints: payload.manualCheckpoints ?? [],
                frameCount: frameCount,
                rawResponseText: trimmed
            )
        }

        return TipTourFollowAlongEnrichment(
            model: model,
            summary: trimmed,
            steps: [],
            manualCheckpoints: [],
            frameCount: frameCount,
            rawResponseText: trimmed
        )
    }

    private static func enrichmentPrompt(
        transcript: String,
        targetAppName: String?,
        frameCount: Int
    ) -> String {
        """
        You are enriching a desktop app tutorial so TipTour can follow it accurately.

        Target app:
        \(targetAppName ?? "unknown")

        You will receive \(frameCount) sampled video frames plus the transcript. Extract visual context that helps a later planner choose safe one-action TipTour steps.

        Return only JSON. No Markdown and no prose.

        Schema:
        {
          "summary": "one compact paragraph about the UI/app state and tutorial objective",
          "steps": [
            {
              "transcript_hint": "short transcript phrase this visual clue supports",
              "visual_region": "top_menu | submenu | viewport | properties_panel | timeline | shader_editor | unknown",
              "visible_labels": ["labels or UI text visible near the action"],
              "live_grounding_query": "best short query TipTour should use on the live screen, e.g. Torus, Add, Mesh, Object, Physics Properties",
              "action_kind": "click | key | type | set_value | scroll | manual | verify",
              "confidence": 0.0,
              "notes": "why this helps or what must be verified"
            }
          ],
          "manual_checkpoints": ["visual tasks that need user/agent inspection instead of blind execution"]
        }

        Rules:
        - Do not invent raw screen coordinates.
        - Prefer visible labels and regions that can be matched later by OCR/YOLO/local perception.
        - For Blender tutorials, distinguish top menus, submenus, the 3D viewport, properties tabs, timeline, and editors.
        - Mark mesh-face/edge sculpting operations as manual when a specific geometry selection is impossible from generic UI labels.
        - Include corrections for speech transcription mistakes, e.g. Taurus usually means Torus in Blender.
        - Keep the output compact: at most 40 visual steps.

        Transcript:
        \(transcript)
        """
    }

    private static func extractFirstJSONObject(from text: String) -> String? {
        var depth = 0
        var startIndex: String.Index?
        var isInsideString = false
        var previousWasEscape = false

        for index in text.indices {
            let character = text[index]
            if character == "\"" && !previousWasEscape {
                isInsideString.toggle()
            }
            previousWasEscape = character == "\\" && !previousWasEscape

            guard !isInsideString else { continue }
            if character == "{" {
                if depth == 0 { startIndex = index }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
            if character != "\\" {
                previousWasEscape = false
            }
        }
        return nil
    }
}

