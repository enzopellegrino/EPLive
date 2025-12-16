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
    private var videoTrackOutput: AVAssetReaderOutput?
    private var audioTrackOutput: AVAssetReaderOutput?
    var asset: AVAsset? // Public per condividerlo con VideoPreviewView
    private var displayLink: CADisplayLink?
    private var streamTask: Task<Void, Never>?
    
    @Published private(set) var loopEnabled = true
    private var videoURL: URL?
    
    // Weak reference to avoid retain cycle
    private weak var srtStream: SRTStream?
    
    // Stats reference (weak to avoid retain cycle)
    weak var stats: StreamingStats?
    
    // Frame timing
    private(set) var videoFrameRate: Double = 30.0
    private var lastFrameTime: CFTimeInterval = 0
    
    // FPS tracking
    private var lastFPSUpdate: Date = Date()
    private var framesSinceLastUpdate: Int = 0
    
    // Cumulative timestamp offset for looping (SRT requires monotonically increasing timestamps)
    private var cumulativeTimeOffset: Double = 0
    
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
        
        // Crea l'asset ma NON caricare subito i metadati
        let asset = AVAsset(url: url)
        self.asset = asset
        
        print("📁 Video URL set: \(videoTitle)")
        
        // Carica metadati in background in parallelo (non blocca l'UI)
        Task {
            do {
                // Carica duration e frame rate in parallelo
                async let durationTask = asset.load(.duration)
                async let tracksTask = asset.loadTracks(withMediaType: .video)
                
                let (durationTime, videoTracks) = try await (durationTask, tracksTask)
                
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(durationTime)
                }
                
                if let videoTrack = videoTracks.first {
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    await MainActor.run {
                        self.videoFrameRate = Double(nominalFrameRate)
                    }
                }
                
                print("✅ Video metadata loaded: duration: \(self.duration)s, fps: \(self.videoFrameRate)")
            } catch {
                print("⚠️ Failed to load video metadata: \(error)")
                // Non bloccare - l'app può comunque funzionare
            }
        }
    }
    
    /// Start streaming the loaded video to the SRT stream
    func startStreaming(to stream: SRTStream, loop: Bool = true, startTime: Double = 0) async throws {
        guard let url = videoURL, let asset = self.asset else {
            throw LocalVideoError.noVideoLoaded
        }
        
        self.srtStream = stream
        self.loopEnabled = loop
        self.isPlaying = true
        
        // Reset FPS tracking
        framesSinceLastUpdate = 0
        lastFPSUpdate = Date()
        
        print("🎬 Starting video streaming to SRT - loop: \(loop), startTime: \(startTime)s")
        print("📊 Stream object: \(stream)")
        print("📊 Stats connected: \(stats != nil)")
        
        // Start the streaming task
        streamTask = Task { [weak self] in
            await self?.streamLoop(url: url, asset: asset, startTime: startTime)
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
        cumulativeTimeOffset = 0 // Reset offset when stopping
    }
    
    /// Seek to a specific time during streaming
    /// NOTA: Disabilitato durante lo streaming attivo per evitare interruzioni
    func seekTo(_ time: Double) async {
        // Non fare seek se stiamo streamando - causa interruzioni
        guard !isPlaying else {
            print("⚠️ Seek ignorato durante streaming attivo")
            return
        }
        
        guard let url = videoURL, let asset = self.asset else {
            return
        }
        
        print("⏩ Seeking to \(time)s")
        
        // Stop current streaming
        assetReader?.cancelReading()
        assetReader = nil
        videoTrackOutput = nil
        audioTrackOutput = nil
        
        // Restart from new position
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.streamLoop(url: url, asset: asset, startTime: time)
        }
    }
    
    /// Main streaming loop
    private func streamLoop(url: URL, asset: AVAsset, startTime: Double = 0) async {
        var currentStartTime = startTime
        var loopCount = 0
        
        while isPlaying && !Task.isCancelled {
            loopCount += 1
            print("🔁 Starting loop iteration #\(loopCount), loopEnabled: \(loopEnabled)")
            
            do {
                try await streamOnce(url: url, asset: asset, startTime: currentStartTime)
                
                print("✅ streamOnce completed, isPlaying: \(isPlaying), loopEnabled: \(loopEnabled), Task.isCancelled: \(Task.isCancelled)")
                
                // Cleanup prima di decidere se loopare
                self.assetReader = nil
                self.videoTrackOutput = nil
                self.audioTrackOutput = nil
                
                if !loopEnabled {
                    print("⏹️ Loop disabled, stopping")
                    await MainActor.run {
                        self.isPlaying = false
                    }
                    break
                }
                
                // Verifica che siamo ancora in stato di play prima di loopare
                guard isPlaying && !Task.isCancelled else {
                    print("⏹️ isPlaying=\(isPlaying) or cancelled, stopping loop")
                    break
                }
                
                // Reset for loop
                await MainActor.run {
                    self.currentTime = 0
                    self.progress = 0
                }
                currentStartTime = 0 // Always restart from beginning on loop
                
                print("🔄 Looping video... (iteration #\(loopCount + 1))")
                
                // Piccola pausa prima di ricominciare per evitare problemi di timing
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
            } catch {
                print("❌ streamOnce error: \(error)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isPlaying = false
                    }
                }
                break
            }
        }
        
        print("🏁 streamLoop ended after \(loopCount) iteration(s)")
    }
    
    /// Stream the video once
    private func streamOnce(url: URL, asset: AVAsset, startTime: Double = 0) async throws {
        // Create asset reader with start time
        let reader: AVAssetReader
        if startTime > 0 {
            let startCMTime = CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: startCMTime, duration: duration - startCMTime)
            reader = try AVAssetReader(asset: asset)
            reader.timeRange = timeRange
            print("⏩ Starting stream from \(startTime)s")
        } else {
            reader = try AVAssetReader(asset: asset)
        }
        self.assetReader = reader
        
        // Setup video track output WITH COMPOSITION per applicare trasformazioni
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        if let videoTrack = videoTracks.first {
            // Ottieni la trasformazione del video e le dimensioni naturali
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let naturalSize = try await videoTrack.load(.naturalSize)
            
            print("📐 Video natural size: \(naturalSize), transform: \(preferredTransform)")
            
            // Crea video composition per applicare la trasformazione
            let videoComposition = AVMutableVideoComposition()
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
            
            let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            transformer.setTransform(preferredTransform, at: .zero)
            instruction.layerInstructions = [transformer]
            
            videoComposition.instructions = [instruction]
            
            // Calcola le dimensioni corrette dopo la trasformazione
            let videoSize = naturalSize.applying(preferredTransform)
            let normalizedSize = CGSize(
                width: abs(videoSize.width),
                height: abs(videoSize.height)
            )
            
            videoComposition.renderSize = normalizedSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(videoFrameRate))
            
            print("✅ Video will be rendered at: \(normalizedSize)")
            
            // Usa VideoCompositionOutput invece di TrackOutput
            let videoSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            let videoOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: [videoTrack],
                videoSettings: videoSettings
            )
            videoOutput.videoComposition = videoComposition
            videoOutput.alwaysCopiesSampleData = false
            
            if reader.canAdd(videoOutput) {
                reader.add(videoOutput)
                self.videoTrackOutput = videoOutput
            }
        }
        
        // Setup audio track output - PCM format (AVAssetReader requires uncompressed)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            // Use Linear PCM (uncompressed) - HaishinKit will compress to AAC automatically
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
                print("✅ Audio track configured (PCM 44.1kHz 16-bit stereo)")
            }
        } else {
            print("⚠️ No audio track found in video")
        }
        
        // Start reading
        guard reader.startReading() else {
            throw LocalVideoError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
        }
        
        var videoFrameCount = 0
        var audioFrameCount = 0
        var lastVideoPTS: Double = 0
        var lastAudioPTS: Double = -1
        
        // Frame interval per il video (in nanosecondi)
        let frameIntervalNanos = UInt64(1_000_000_000.0 / videoFrameRate)
        
        print("🎥 Starting stream at \(String(format: "%.1f", videoFrameRate)) fps (interval: \(frameIntervalNanos/1_000_000)ms)")
        print("⏱️ Cumulative time offset: \(String(format: "%.1f", cumulativeTimeOffset))s")
        
        // ═══════════════════════════════════════════════════════════════════════
        // AUDIO FIRST: Pre-invia alcuni buffer audio PRIMA del video
        // Questo permette all'encoder AAC di HaishinKit di inizializzarsi
        // e garantisce che l'audio sia pronto quando arriva il primo frame video
        // ═══════════════════════════════════════════════════════════════════════
        let audioPreBufferCount = 3 // ~70ms di audio (3 buffer * 1024 samples / 44100Hz)
        
        if let audioOutput = audioTrackOutput {
            print("🔊 Pre-buffering \(audioPreBufferCount) audio buffers...")
            
            for i in 0..<audioPreBufferCount {
                guard let audioBuffer = audioOutput.copyNextSampleBuffer() else { break }
                let audioPTS = CMSampleBufferGetPresentationTimeStamp(audioBuffer)
                let audioTimeSeconds = CMTimeGetSeconds(audioPTS)
                
                let adjustedAudioBuffer = adjustTimestamp(of: audioBuffer, offset: cumulativeTimeOffset)
                let bufferToSend = adjustedAudioBuffer ?? audioBuffer
                srtStream?.append(bufferToSend)
                audioFrameCount += 1
                lastAudioPTS = audioTimeSeconds
                
                // Track stats - calcola dimensione audio (PCM 44.1kHz stereo 16-bit = ~1024 samples * 4 bytes)
                let audioBytes = 1024 * 4 // Dimensione approssimativa di un buffer audio PCM
                stats?.recordAudioSample(bytes: audioBytes)
                
                print("  🔊 Pre-buffer \(i+1): audio @ \(String(format: "%.3f", audioTimeSeconds))s")
            }
            
            print("✅ Audio pre-buffered: \(audioFrameCount) buffers, last PTS: \(String(format: "%.3f", lastAudioPTS))s")
        }
        
        // Piccola pausa per permettere all'encoder di processare l'audio
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Loop principale: AUDIO MASTER - il video si sincronizza con l'audio
        while reader.status == .reading && isPlaying && !Task.isCancelled {
            
            // 1. Leggi UN frame video
            guard let videoOutput = videoTrackOutput,
                  let videoBuffer = videoOutput.copyNextSampleBuffer() else {
                // Fine del video - esci dal loop
                print("📹 Video track finished")
                break
            }
            
            let videoPTS = CMSampleBufferGetPresentationTimeStamp(videoBuffer)
            let videoTimeSeconds = CMTimeGetSeconds(videoPTS)
            lastVideoPTS = videoTimeSeconds
            
            // 2. PRIMA dell'invio video: assicurati che l'audio sia "avanti" o allineato
            // Se l'audio è indietro rispetto al video, aspetta e invia più audio
            if let audioOutput = audioTrackOutput {
                // L'audio deve essere leggermente AVANTI rispetto al video per sync corretto
                let audioLeadTime: Double = 0.05 // 50ms di lead time per l'audio
                
                while lastAudioPTS < (videoTimeSeconds + audioLeadTime) {
                    guard let audioBuffer = audioOutput.copyNextSampleBuffer() else { break }
                    let audioPTS = CMSampleBufferGetPresentationTimeStamp(audioBuffer)
                    let audioTimeSeconds = CMTimeGetSeconds(audioPTS)
                    
                    let adjustedAudioBuffer = adjustTimestamp(of: audioBuffer, offset: cumulativeTimeOffset)
                    let bufferToSend = adjustedAudioBuffer ?? audioBuffer
                    srtStream?.append(bufferToSend)
                    audioFrameCount += 1
                    lastAudioPTS = audioTimeSeconds
                    
                    // Track stats - dimensione audio PCM
                    let audioBytes = 1024 * 4
                    stats?.recordAudioSample(bytes: audioBytes)
                }
            }
            
            // 3. ORA invia il frame video (l'audio è già stato inviato)
            let adjustedVideoBuffer = adjustTimestamp(of: videoBuffer, offset: cumulativeTimeOffset)
            let bufferToSend = adjustedVideoBuffer ?? videoBuffer
            srtStream?.append(bufferToSend)
            videoFrameCount += 1
            
            // Track stats - stima dimensione video frame
            // Per H.264 compressed frame, usiamo una stima basata su bitrate target
            // Bitrate tipico: 5-20 Mbps -> ~160-660 KB per frame @ 30fps
            let estimatedVideoBytes = 200_000 // ~200 KB per frame (stima conservativa)
            stats?.recordVideoFrame(bytes: estimatedVideoBytes)
            
            // Aggiorna FPS ogni secondo
            framesSinceLastUpdate += 1
            let now = Date()
            if now.timeIntervalSince(lastFPSUpdate) >= 1.0 {
                let actualFPS = Double(framesSinceLastUpdate) / now.timeIntervalSince(lastFPSUpdate)
                await MainActor.run {
                    stats?.updateFPS(framesInLastSecond: framesSinceLastUpdate)
                }
                framesSinceLastUpdate = 0
                lastFPSUpdate = now
            }
            
            if videoFrameCount % 30 == 0 {
                let globalTime = videoTimeSeconds + cumulativeTimeOffset
                let drift = lastAudioPTS - videoTimeSeconds
                print("📹 Video: \(videoFrameCount) frames @ \(String(format: "%.1f", videoTimeSeconds))s | Audio: \(audioFrameCount) @ \(String(format: "%.1f", lastAudioPTS))s | Drift: \(String(format: "%+.2f", drift))s")
            }
            
            // Aggiorna progresso (ogni 10 frame per ridurre overhead)
            if videoFrameCount % 10 == 0 {
                await MainActor.run {
                    self.currentTime = videoTimeSeconds
                    if self.duration > 0 {
                        self.progress = videoTimeSeconds / self.duration
                    }
                }
            }
            
            // 4. Aspetta il tempo del frame per mantenere il ritmo
            try? await Task.sleep(nanoseconds: frameIntervalNanos)
        }
        
        // Aggiorna offset cumulativo per il prossimo loop
        let previousOffset = cumulativeTimeOffset
        cumulativeTimeOffset += lastVideoPTS
        print("🎬 Stream completed - Video: \(videoFrameCount) frames, Audio: \(audioFrameCount) samples, Duration: \(String(format: "%.1f", lastVideoPTS))s")
        print("⏱️ Updated cumulative offset: \(String(format: "%.1f", previousOffset))s → \(String(format: "%.1f", cumulativeTimeOffset))s")
        
        // Cleanup
        reader.cancelReading()
    }
    
    /// Adjust the presentation timestamp of a CMSampleBuffer by adding an offset
    private func adjustTimestamp(of sampleBuffer: CMSampleBuffer, offset: Double) -> CMSampleBuffer? {
        guard offset > 0 else { return sampleBuffer }
        
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let offsetTime = CMTime(seconds: offset, preferredTimescale: originalPTS.timescale)
        let newPTS = CMTimeAdd(originalPTS, offsetTime)
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer).isValid ?
                CMTimeAdd(CMSampleBufferGetDecodeTimeStamp(sampleBuffer), offsetTime) : .invalid
        )
        
        var newSampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        
        if status == noErr, let newBuffer = newSampleBuffer {
            return newBuffer
        }
        return nil
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
