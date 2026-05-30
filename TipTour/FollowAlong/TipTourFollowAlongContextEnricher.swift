import Foundation

struct TipTourFollowAlongContextEnrichmentResult: Sendable {
    let frameExtraction: TipTourYouTubeFrameExtractionResult
    let enrichment: TipTourFollowAlongEnrichment
}

struct TipTourFollowAlongContextEnricher {
    private let visionClient = TipTourOpenRouterVisionClient()

    func enrich(
        youtubeURL: String,
        transcript: String,
        targetAppName: String?,
        openRouterAPIKey: String,
        maxFrames: Int = 8
    ) async throws -> TipTourFollowAlongContextEnrichmentResult {
        let frames = try await TipTourYouTubeFrameExtractor.extractReferenceFrames(
            from: youtubeURL,
            maxFrames: maxFrames
        )
        let enrichment = try await visionClient.enrichTutorialContext(
            transcript: transcript,
            targetAppName: targetAppName,
            frames: frames.frames,
            apiKey: openRouterAPIKey
        )
        return TipTourFollowAlongContextEnrichmentResult(
            frameExtraction: frames,
            enrichment: enrichment
        )
    }
}

