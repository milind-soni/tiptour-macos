//
//  RetryWithExponentialBackoff.swift
//  leanring-buddy
//
//  Generic retry helper with exponential backoff. Adapted from
//  github.com/paradigms-of-intelligence/swift-gemini-api/Sources/swift-gemini-api/Retry.swift
//  (Apache 2.0).
//
//  Used to harden the Gemini Live connect path: both fetchAPIKey() and
//  geminiClient.connect() previously threw on first failure, so a single
//  flaky network blip would kill the whole push-to-talk session. Now a
//  transient failure costs ~1s and the user sees the session come up.
//

import Foundation

enum RetryWithExponentialBackoff {

    /// Run `block` with exponential backoff between attempts. Throws the
    /// last error after `maxAttempts` attempts. Total wall clock cost in
    /// the worst case is roughly `initialDelay * (2^(maxAttempts-1) - 1)`,
    /// capped per-attempt by `maxDelay`.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total attempts including the first. 3 = one try
    ///     plus two retries. Must be >= 1.
    ///   - initialDelay: Delay before the first retry, in seconds.
    ///   - maxDelay: Per-attempt delay ceiling, in seconds.
    ///   - operationName: Free-form label used only for log lines —
    ///     makes it easy to grep which retry path actually fired.
    ///   - block: The async work to retry.
    static func run<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        operationName: String,
        _ block: @escaping () async throws -> T
    ) async throws -> T {
        precondition(maxAttempts >= 1, "maxAttempts must be at least 1")

        var attemptNumber = 0
        var nextDelay = initialDelay
        var lastError: Error?

        while attemptNumber < maxAttempts {
            attemptNumber += 1
            do {
                return try await block()
            } catch {
                lastError = error
                if attemptNumber >= maxAttempts {
                    print("[Retry:\(operationName)] all \(maxAttempts) attempts failed — \(error.localizedDescription)")
                    break
                }
                print("[Retry:\(operationName)] attempt \(attemptNumber) failed (\(error.localizedDescription)) — retrying in \(String(format: "%.1f", nextDelay))s")
                try await Task.sleep(nanoseconds: UInt64(nextDelay * 1_000_000_000))
                nextDelay = min(nextDelay * 2, maxDelay)
            }
        }

        // Should be unreachable — the loop either returned a value or set
        // lastError before breaking — but Swift can't prove that, so we
        // throw a safety net.
        throw lastError ?? NSError(domain: "RetryWithExponentialBackoff", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Retry exhausted with no recorded error"])
    }
}
