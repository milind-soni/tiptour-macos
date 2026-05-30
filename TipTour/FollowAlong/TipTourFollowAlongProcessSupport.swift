import Foundation

enum TipTourFollowAlongToolLocator {
    static func executable(named name: String) -> String? {
        var searchPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        searchPaths.insert(contentsOf: environmentPaths, at: 0)

        var checkedPaths = Set<String>()
        for path in searchPaths {
            let executablePath = URL(fileURLWithPath: path)
                .appendingPathComponent(name)
                .path
            guard !checkedPaths.contains(executablePath) else { continue }
            checkedPaths.insert(executablePath)
            if FileManager.default.isExecutableFile(atPath: executablePath) {
                return executablePath
            }
        }
        return nil
    }
}

enum TipTourFollowAlongProcessRunner {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tiptour-follow-process-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let stdoutURL = outputDirectory.appendingPathComponent("stdout.txt")
            let stderrURL = outputDirectory.appendingPathComponent("stderr.txt")
            _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            let stderrHandle = try FileHandle(forWritingTo: stderrURL)
            defer {
                try? stdoutHandle.close()
                try? stderrHandle.close()
                try? FileManager.default.removeItem(at: outputDirectory)
            }

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutHandle
            process.standardError = stderrHandle

            var environment = ProcessInfo.processInfo.environment
            let userLocalBin = "\(NSHomeDirectory())/.local/bin"
            let commonPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = "\(environment["PATH"] ?? ""):\(userLocalBin):\(commonPath)"
            process.environment = environment

            try process.run()
            let startDate = Date()
            while process.isRunning {
                if Date().timeIntervalSince(startDate) > timeoutSeconds {
                    process.terminate()
                    throw NSError(
                        domain: "TipTourFollowAlongProcessRunner",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executablePath).lastPathComponent) timed out."]
                    )
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            try? stdoutHandle.close()
            try? stderrHandle.close()
            let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
            let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "TipTourFollowAlongProcessRunner",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executablePath).lastPathComponent) failed: \(stderr.isEmpty ? stdout : stderr)"
                    ]
                )
            }

            return Result(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }
        .value
    }
}
