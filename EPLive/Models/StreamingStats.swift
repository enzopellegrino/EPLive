//
//  StreamingStats.swift
//  EPLive
//
//  Statistiche streaming in tempo reale (come Larix)
//

import Foundation

/// Statistiche streaming in tempo reale
@MainActor
class StreamingStats: ObservableObject {
    
    // MARK: - Statistiche Video
    @Published var videoFramesSent: Int = 0
    @Published var videoFramesDropped: Int = 0
    @Published var currentFPS: Double = 0.0
    @Published var targetFPS: Double = 30.0
    
    // MARK: - Statistiche Audio
    @Published var audioSamplesSent: Int = 0
    @Published var audioSamplesDropped: Int = 0
    
    // MARK: - Bitrate
    @Published var currentBitrate: Double = 0.0 // Kbps
    @Published var averageBitrate: Double = 0.0 // Kbps
    @Published var videoBitrate: Double = 0.0 // Kbps
    @Published var audioBitrate: Double = 0.0 // Kbps
    
    // MARK: - Rete (SRT/RTMP)
    @Published var rtt: Double = 0.0 // Round Trip Time in ms
    @Published var packetLoss: Double = 0.0 // Percentuale
    @Published var bufferHealth: Double = 100.0 // 0-100%
    
    // MARK: - Durata e Bytes
    @Published var streamingDuration: TimeInterval = 0.0
    @Published var bytesSent: Int64 = 0
    @Published var totalBytesSent: Int64 = 0
    
    // MARK: - Status
    @Published var isHealthy: Bool = true
    @Published var lastUpdateTime: Date = Date()
    
    // MARK: - Tracking interno
    private var startTime: Date?
    private var lastStatsUpdate: Date = Date()
    private var bytesWindow: [Int64] = [] // Finestra per calcolare bitrate istantaneo
    private var windowSize: Int = 10 // 10 campioni
    
    // MARK: - Inizializzazione
    
    func start() {
        reset()
        startTime = Date()
        lastStatsUpdate = Date()
    }
    
    func stop() {
        startTime = nil
    }
    
    func reset() {
        videoFramesSent = 0
        videoFramesDropped = 0
        audioSamplesSent = 0
        audioSamplesDropped = 0
        currentBitrate = 0.0
        averageBitrate = 0.0
        videoBitrate = 0.0
        audioBitrate = 0.0
        rtt = 0.0
        packetLoss = 0.0
        bufferHealth = 100.0
        streamingDuration = 0.0
        bytesSent = 0
        totalBytesSent = 0
        bytesWindow.removeAll()
        isHealthy = true
    }
    
    // MARK: - Update Methods
    
    /// Aggiorna frame video inviato
    func recordVideoFrame(bytes: Int) {
        videoFramesSent += 1
        recordBytes(Int64(bytes))
    }
    
    /// Aggiorna frame video droppato
    func recordDroppedVideoFrame() {
        videoFramesDropped += 1
        updateHealth()
    }
    
    /// Aggiorna sample audio inviato
    func recordAudioSample(bytes: Int) {
        audioSamplesSent += 1
        recordBytes(Int64(bytes))
    }
    
    /// Aggiorna sample audio droppato
    func recordDroppedAudioSample() {
        audioSamplesDropped += 1
        updateHealth()
    }
    
    /// Registra bytes inviati
    private func recordBytes(_ bytes: Int64) {
        bytesSent += bytes
        totalBytesSent += bytes
        
        // Aggiorna finestra per bitrate istantaneo
        bytesWindow.append(bytes)
        if bytesWindow.count > windowSize {
            bytesWindow.removeFirst()
        }
    }
    
    /// Calcola FPS in tempo reale
    func updateFPS(framesInLastSecond: Int) {
        currentFPS = Double(framesInLastSecond)
    }
    
    /// Aggiorna statistiche di rete (da SRTStream/RTMP)
    func updateNetworkStats(rtt: Double? = nil, packetLoss: Double? = nil, bufferHealth: Double? = nil) {
        if let rtt = rtt {
            self.rtt = rtt
        }
        if let packetLoss = packetLoss {
            self.packetLoss = packetLoss
        }
        if let bufferHealth = bufferHealth {
            self.bufferHealth = bufferHealth
        }
        updateHealth()
    }
    
    /// Aggiorna bitrate istantaneo e medio (chiamato dal timer)
    func updateBitrates() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastStatsUpdate)
        
        guard elapsed > 0 else { return }
        
        // Bitrate istantaneo: bytes inviati dall'ultimo update
        if bytesSent > 0 {
            let bits = Double(bytesSent) * 8.0
            currentBitrate = (bits / elapsed) / 1000.0 // Kbps
            bytesSent = 0 // Reset per il prossimo intervallo
        } else {
            currentBitrate = 0
        }
        
        // Bitrate medio: dall'inizio dello stream
        if let start = startTime {
            let totalElapsed = now.timeIntervalSince(start)
            if totalElapsed > 0 {
                let totalBits = Double(totalBytesSent) * 8.0
                averageBitrate = (totalBits / totalElapsed) / 1000.0 // Kbps
            }
        }
        
        lastStatsUpdate = now
    }
    
    /// Aggiorna durata streaming
    func updateDuration() {
        if let start = startTime {
            streamingDuration = Date().timeIntervalSince(start)
        }
    }
    
    /// Valuta lo stato di salute dello stream
    private func updateHealth() {
        // Considera lo stream non salutare se:
        // - Troppi frame droppati (>5%)
        // - Packet loss troppo alto (>2%)
        // - Buffer troppo basso (<30%)
        
        let totalFrames = videoFramesSent + videoFramesDropped
        let dropRate = totalFrames > 0 ? Double(videoFramesDropped) / Double(totalFrames) : 0.0
        
        isHealthy = dropRate < 0.05 && packetLoss < 2.0 && bufferHealth > 30.0
    }
    
    // MARK: - Formattazione per UI
    
    var bitrateString: String {
        if currentBitrate >= 1000 {
            return String(format: "%.1f Mbps", currentBitrate / 1000.0)
        } else {
            return String(format: "%.0f Kbps", currentBitrate)
        }
    }
    
    var averageBitrateString: String {
        if averageBitrate >= 1000 {
            return String(format: "%.1f Mbps", averageBitrate / 1000.0)
        } else {
            return String(format: "%.0f Kbps", averageBitrate)
        }
    }
    
    var fpsString: String {
        String(format: "%.1f fps", currentFPS)
    }
    
    var rttString: String {
        String(format: "%.0f ms", rtt)
    }
    
    var packetLossString: String {
        String(format: "%.2f%%", packetLoss)
    }
    
    var durationString: String {
        let hours = Int(streamingDuration) / 3600
        let minutes = (Int(streamingDuration) % 3600) / 60
        let seconds = Int(streamingDuration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    var totalDataString: String {
        let mb = Double(totalBytesSent) / (1024.0 * 1024.0)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }
    
    var dropRateString: String {
        let total = videoFramesSent + videoFramesDropped
        guard total > 0 else { return "0.00%" }
        let rate = Double(videoFramesDropped) / Double(total) * 100.0
        return String(format: "%.2f%%", rate)
    }
}
