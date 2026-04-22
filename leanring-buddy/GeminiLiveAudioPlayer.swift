//
//  GeminiLiveAudioPlayer.swift
//  TipTour
//
//  Streams PCM16 audio chunks from Gemini Live to the speakers in real time.
//  Uses AVAudioEngine with a scheduled buffer queue so chunks play back
//  gaplessly as they arrive from the WebSocket.
//
//  Why not AVAudioPlayer: it requires a complete audio file. Gemini streams
//  audio in ~40ms chunks over the WebSocket — we need to queue each chunk
//  for playback the instant it arrives.
//

import AVFoundation
import Foundation

@MainActor
final class GeminiLiveAudioPlayer {

    // MARK: - State

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// Gemini streams PCM16 mono at 24kHz — this is the format we schedule buffers in.
    private let streamAudioFormat: AVAudioFormat

    /// Whether the engine and player node are running and ready for buffers.
    private var isEngineRunning = false

    init() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: GeminiLiveClient.outputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("[GeminiLiveAudio] Could not create 24kHz PCM16 format — this should never happen")
        }
        self.streamAudioFormat = format

        audioEngine.attach(playerNode)
    }

    // MARK: - Lifecycle

    /// Prepare the engine for playback. Call once before the first audio chunk.
    func startEngine() {
        guard !isEngineRunning else { return }

        // Connect the player node to the main mixer. We let AVAudioEngine
        // handle sample rate conversion from 24kHz source to whatever the
        // output device wants — much simpler than doing it ourselves.
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: streamAudioFormat)

        do {
            try audioEngine.start()
            playerNode.play()
            isEngineRunning = true
            print("[GeminiLiveAudio] Engine started")
        } catch {
            print("[GeminiLiveAudio] Failed to start engine: \(error.localizedDescription)")
        }
    }

    /// Clear queued audio without tearing down the engine.
    /// Used on barge-in so the next model turn can start playing instantly.
    /// The engine and player node stay running so there's no restart latency.
    func clearQueuedAudio() {
        guard isEngineRunning else { return }
        playerNode.stop()
        // Restart the player node immediately so it's ready for new buffers.
        playerNode.play()
        print("[GeminiLiveAudio] Audio queue cleared")
    }

    /// Fully tear down the engine. Called on session disconnect.
    func stopAndClearQueue() {
        guard isEngineRunning else { return }
        playerNode.stop()
        audioEngine.stop()
        isEngineRunning = false
        print("[GeminiLiveAudio] Engine stopped and queue cleared")
    }

    // MARK: - Audio Chunk Playback

    /// Schedule a PCM16 24kHz audio chunk for playback.
    /// Chunks play back in order — AVAudioPlayerNode handles the queueing.
    func enqueueAudioChunk(_ pcm16Data: Data) {
        guard isEngineRunning else {
            // Auto-start the engine if this is the first chunk
            startEngine()
            guard isEngineRunning else { return }
            enqueueAudioChunk(pcm16Data)
            return
        }

        guard let audioBuffer = makeAudioBuffer(from: pcm16Data) else {
            print("[GeminiLiveAudio] Could not create buffer from \(pcm16Data.count)-byte chunk")
            return
        }

        playerNode.scheduleBuffer(audioBuffer, completionHandler: nil)
    }

    /// Convert a raw PCM16 Data chunk into an AVAudioPCMBuffer that
    /// AVAudioPlayerNode can schedule.
    private func makeAudioBuffer(from pcm16Data: Data) -> AVAudioPCMBuffer? {
        let bytesPerFrame = Int(streamAudioFormat.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return nil }
        // PCM16 mono => byte count must be divisible by 2. If Gemini ever
        // sends a different format (stereo, PCM24, server-side change),
        // the raw bytes will produce scrambled audio or a silently-dropped
        // buffer. Reject and log instead of schedule-and-hope.
        guard pcm16Data.count % bytesPerFrame == 0 else {
            print("[GeminiLiveAudio] ⚠ dropped \(pcm16Data.count)-byte chunk — not a multiple of \(bytesPerFrame) bytes/frame. Audio format may have changed upstream.")
            return nil
        }
        let frameCount = pcm16Data.count / bytesPerFrame
        guard frameCount > 0 else { return nil }

        guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: streamAudioFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }

        audioBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy the raw PCM16 bytes straight into the buffer's int16ChannelData.
        guard let destinationBuffer = audioBuffer.int16ChannelData?[0] else { return nil }
        pcm16Data.withUnsafeBytes { rawSourcePointer in
            guard let sourceInt16Pointer = rawSourcePointer.baseAddress?.assumingMemoryBound(to: Int16.self) else {
                return
            }
            destinationBuffer.update(from: sourceInt16Pointer, count: frameCount)
        }

        return audioBuffer
    }

    /// Whether the engine is currently running and has audio scheduled.
    var isPlaying: Bool {
        return isEngineRunning && playerNode.isPlaying
    }
}
