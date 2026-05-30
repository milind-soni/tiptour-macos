import Foundation

struct TipTourYouTubeFrameExtractionResult: Sendable {
    let directory: URL
    let sourceVideoURL: URL
    let frames: [TipTourFollowAlongFrameReference]
}

enum TipTourYouTubeFrameExtractor {
    static func extractReferenceFrames(
        from urlString: String,
        maxFrames: Int = 8
    ) async throws -> TipTourYouTubeFrameExtractionResult {
        guard URL(string: urlString) != nil else {
            throw failure("Enter a valid YouTube URL before enriching video context.")
        }
        guard let ytDlp = TipTourFollowAlongToolLocator.executable(named: "yt-dlp") else {
            throw failure("yt-dlp is not installed. Install with: brew install yt-dlp ffmpeg")
        }
        guard let ffmpeg = TipTourFollowAlongToolLocator.executable(named: "ffmpeg") else {
            throw failure("ffmpeg is not installed. Install with: brew install ffmpeg")
        }

        let directory = try workingDirectory()
        let outputTemplate = directory.appendingPathComponent("source.%(ext)s").path
        _ = try await TipTourFollowAlongProcessRunner.run(
            executablePath: ytDlp,
            arguments: [
                "--no-playlist",
                "-f", "bv*[height<=720][ext=mp4]/bv*[height<=720]/bestvideo[height<=720]/best[height<=720]",
                "--merge-output-format", "mp4",
                "-o", outputTemplate,
                urlString
            ],
            timeoutSeconds: 1_200
        )

        guard let sourceVideoURL = try firstFile(in: directory, extensions: ["mp4", "webm", "mkv", "mov"]) else {
            throw failure("yt-dlp finished but no video file was found.")
        }

        let frameLimit = max(1, min(maxFrames, 12))
        let framePattern = directory.appendingPathComponent("frame-%03d.jpg").path
        _ = try await TipTourFollowAlongProcessRunner.run(
            executablePath: ffmpeg,
            arguments: [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-i", sourceVideoURL.path,
                "-vf", "fps=1/5,scale='min(960,iw)':-2,format=yuvj420p",
                "-frames:v", String(frameLimit),
                framePattern
            ],
            timeoutSeconds: 600
        )

        let frameURLs = try frameFiles(in: directory)
        guard !frameURLs.isEmpty else {
            throw failure("ffmpeg finished but no video frames were extracted.")
        }
        let frames = frameURLs.enumerated().map { index, fileURL in
            TipTourFollowAlongFrameReference(fileURL: fileURL, index: index + 1)
        }
        return TipTourYouTubeFrameExtractionResult(
            directory: directory,
            sourceVideoURL: sourceVideoURL,
            frames: frames
        )
    }

    private static func workingDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TipTour/follow-along-frames", isDirectory: true)
        .appendingPathComponent("run_\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func frameFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("frame-") && $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func firstFile(in directory: URL, extensions: [String]) throws -> URL? {
        let allowedExtensions = Set(extensions.map { $0.lowercased() })
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .first
    }

    private static func failure(_ message: String) -> NSError {
        NSError(
            domain: "TipTourYouTubeFrameExtractor",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
