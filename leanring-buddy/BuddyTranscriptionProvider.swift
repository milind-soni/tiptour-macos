//
//  BuddyTranscriptionProvider.swift
//  TipTour
//
//  Transcription protocol surface. Gemini Live (the primary voice mode)
//  does its own in-stream STT, so this is only exercised in the legacy
//  Claude + ElevenLabs pipeline — kept alive as a fallback mode but no
//  longer the critical path. AssemblyAI + OpenAI STT providers have
//  been removed; Apple Speech (on-device, free, no network) is now the
//  only implementation.
//

import AVFoundation
import Foundation

protocol BuddyStreamingTranscriptionSession: AnyObject {
    var finalTranscriptFallbackDelaySeconds: TimeInterval { get }
    func appendAudioBuffer(_ audioBuffer: AVAudioPCMBuffer)
    func requestFinalTranscript()
    func cancel()
}

protocol BuddyTranscriptionProvider {
    var displayName: String { get }
    var requiresSpeechRecognitionPermission: Bool { get }
    var isConfigured: Bool { get }
    var unavailableExplanation: String? { get }

    func startStreamingSession(
        keyterms: [String],
        onTranscriptUpdate: @escaping (String) -> Void,
        onFinalTranscriptReady: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws -> any BuddyStreamingTranscriptionSession
}

enum BuddyTranscriptionProviderFactory {
    static func makeDefaultProvider() -> any BuddyTranscriptionProvider {
        let provider = AppleSpeechTranscriptionProvider()
        print("🎙️ Transcription: using \(provider.displayName)")
        return provider
    }
}
