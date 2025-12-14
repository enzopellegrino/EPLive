//
//  LocalVideoStreamer.swift
//  EPLive
//
//  Service for streaming local video files via SRT
//

import Foundation
import AVFoundation
import Combine
import CoreMedia

#if canImport(HaishinKit)
import HaishinKit
#endif
#if canImport(SRTHaishinKit)
import SRTHaishinKit
#endif

/// Manages reading and streaming of local video files
@MainActor
class LocalVideoStreamer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var progress: Double = 0
    @Published var videoTitle: String = ""
    @Published var errorMessage: String?
    
    private var assetReader: AVAssetReader?
    private var videoTrackOutput: AVAssetReaderTrackOutput?
    private var audioTrackOutput: AVAssetReaderTrackOutput?
    private var asset: AVAsset?
    private var displayLink: CADisplayLink?
    private var streamTask: Task<Void, Never>?
    
    private var loopEnabled = true
    private var videoURL: URL?
    
    // Weak reference to avoid retain cycle
    private weak var srtStream: SRTStream?
    
    // Frame timing
    private var videoFrameRate: Double = 30.0
    private var lastFrameTime: CFTimeInterval = 0
    
    /// Load a video file for streaming
    func loadVideo(from url: URL) async throws {
        self.videoURL = url
        self.videoTitle = url.lastPathComponent
        
        // Start accessing security-scoped resource if needed
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVAsset(url: url)
        self.asset = asset
        
        // Get duration
        let durationTime = try await asset.load(.duration)
        self.duration = CMTimeGetSeconds(durationTime)
        
        // Get video track info for frame rate
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let videoTrack = videoTracks.first {
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            self.videoFrameRate = Double(nominalFrameRate)
        }
        
        print("✅ Video loaded: \(videoTitle), duration: \(duration)s, fps: \(videoFrameRate)")
    }
    
    /// Start streaming the loaded video to the SRT stream
    func startStreaming(to stream: SRTStream, loop: Bool = true) async throws {
        guard let url = videoURL, let asset = self.asset else {
            throw LocalVideoError.noVideoLoaded
        }
        
        self.srtStream = stream
        self.loopEnabled = loop
        self.isPlaying = true
        
        // Start the streaming task
        streamTask = Task { [weak self] in
            await self?.streamLoop(url: url, asset: asset)
        }
    }
    
    /// Stop streaming
    func stopStreaming() {
        isPlaying = false
        streamTask?.cancel()
        streamTask = nil
        assetReader?.cancelReading()
        assetReader = nil
        videoTrackOutput = nil
        audioTrackOutput = nil
        currentTime = 0
        progress = 0
    }
    
    /// Main streaming loop
    private func streamLoop(url: URL, asset: AVAsset) async {
        while isPlaying && !Task.isCancelled {
            do {
                try await streamOnce(url: url, asset: asset)
                
                if !loopEnabled {
                    await MainActor.run {
                        self.isPlaying = false
                    }
                    break
                }
                
                // Reset for loop
                await MainActor.run {
                    self.currentTime = 0
                    self.progress = 0
                }
                
                print("🔄 Looping video...")
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isPlaying = false
                    }
                }
                break
            }
        }
    }
    
    /// Stream the video once
    private func streamOnce(url: URL, asset: AVAsset) async throws {
        // Create asset reader
        let reader = try AVAssetReader(asset: asset)
        self.assetReader = reader
        
        // Setup video track output
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let videoTrack = videoTracks.first {
            let videoSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoSettings)
            videoOutput.alwaysCopiesSampleData = false
            
            if reader.canAdd(videoOutput) {
                reader.add(videoOutput)
                self.videoTrackOutput = videoOutput
            }
        }
        
        // Setup audio track output
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioSettings)
            audioOutput.alwaysCopiesSampleData = false
            
            if reader.canAdd(audioOutput) {
                reader.add(audioOutput)
                self.audioTrackOutput = audioOutput
            }
        }
        
        // Start reading
        guard reader.startReading() else {
            throw LocalVideoError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }
        
        // Calculate frame interval
        let frameInterval = 1.0 / videoFrameRate
        var lastVideoTime: CFTimeInterval = CACurrentMediaTime()
        
        // Read and send frames
        while reader.status == .reading && isPlaying && !Task.isCancelled {
            let currentMediaTime = CACurrentMediaTime()
            
            // Video frame timing
            if currentMediaTime - lastVideoTime >= frameInterval {
                if let videoOutput = videoTrackOutput,
                   let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                    // Get presentation time for progress
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let time = CMTimeGetSeconds(pts)
                    
                    await MainActor.run {
                        self.currentTime = time
                        if self.duration > 0 {
                            self.progress = time / self.duration
                        }
                    }
                    
                    // Append to stream
                    if let stream = srtStream {
                        stream.append(sampleBuffer)
                    }
                    
                    lastVideoTime = currentMediaTime
                }
            }
            
            // Audio - read all available
            if let audioOutput = audioTrackOutput,
               let audioBuffer = audioOutput.copyNextSampleBuffer() {
                if let stream = srtStream {
                    stream.append(audioBuffer)
                }
            }
            
            // Small sleep to prevent CPU spinning
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        // Cleanup
        reader.cancelReading()
    }
    
    /// Seek to a specific time (for preview, not during streaming)
    func seek(to time: Double) {
        // This would require restarting the reader at a specific time
        // Complex to implement properly - leaving as future enhancement
    }
}

// MARK: - Errors
enum LocalVideoError: LocalizedError {
    case noVideoLoaded
    case readerFailed(String)
    case trackNotFound
    case streamNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .noVideoLoaded:
            return "Nessun video caricato"
        case .readerFailed(let reason):
            return "Errore lettura video: \(reason)"
        case .trackNotFound:
            return "Traccia video non trovata"
        case .streamNotAvailable:
            return "Stream non disponibile"
        }
    }
}
