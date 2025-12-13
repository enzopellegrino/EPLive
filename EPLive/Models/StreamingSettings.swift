//
//  StreamingSettings.swift
//  EPLive
//
//  Advanced streaming settings model
//

import Foundation
import Combine

// MARK: - App Version
struct AppVersion {
    static let current = "1.0.0"
    static let build = "1"
    
    static var fullVersion: String {
        "\(current) (\(build))"
    }
}

// MARK: - FPS Options
enum FPSOption: Int, CaseIterable, Identifiable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    
    var id: Int { rawValue }
    var displayName: String { "\(rawValue) fps" }
}

// MARK: - H.264 Profile
enum H264Profile: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case main = "Main"
    case high = "High"
    
    var id: String { rawValue }
    
    var profileLevel: String {
        switch self {
        case .baseline: return "H264_Baseline_3_1"
        case .main: return "H264_Main_3_1"
        case .high: return "H264_High_3_1"
        }
    }
    
    var description: String {
        switch self {
        case .baseline: return "Compatibilità massima, qualità base"
        case .main: return "Buon equilibrio qualità/compatibilità"
        case .high: return "Migliore qualità, meno compatibile"
        }
    }
}

// MARK: - Audio Bitrate
enum AudioBitrate: Int, CaseIterable, Identifiable {
    case low = 64000      // 64 kbps
    case medium = 128000  // 128 kbps
    case high = 192000    // 192 kbps
    case ultra = 256000   // 256 kbps
    
    var id: Int { rawValue }
    
    var displayName: String {
        "\(rawValue / 1000) kbps"
    }
    
    var description: String {
        switch self {
        case .low: return "Voce"
        case .medium: return "Standard"
        case .high: return "Musica"
        case .ultra: return "Alta qualità"
        }
    }
}

// MARK: - Audio Sample Rate
enum AudioSampleRate: Double, CaseIterable, Identifiable {
    case rate44100 = 44100
    case rate48000 = 48000
    
    var id: Double { rawValue }
    
    var displayName: String {
        "\(Int(rawValue / 1000)) kHz"
    }
}

// MARK: - SRT Latency
enum SRTLatency: Int, CaseIterable, Identifiable {
    case ultraLow = 120    // 120ms
    case low = 250         // 250ms
    case medium = 500      // 500ms
    case high = 1000       // 1000ms
    case veryHigh = 2000   // 2000ms
    
    var id: Int { rawValue }
    
    var displayName: String {
        "\(rawValue) ms"
    }
    
    var description: String {
        switch self {
        case .ultraLow: return "Tempo reale (rete ottima)"
        case .low: return "Bassa latenza (rete buona)"
        case .medium: return "Bilanciato"
        case .high: return "Stabile (rete media)"
        case .veryHigh: return "Molto stabile (rete scarsa)"
        }
    }
}

// MARK: - Keyframe Interval
enum KeyframeInterval: Int, CaseIterable, Identifiable {
    case sec1 = 1
    case sec2 = 2
    case sec3 = 3
    case sec4 = 4
    case sec5 = 5
    
    var id: Int { rawValue }
    var displayName: String { "\(rawValue) sec" }
    
    var description: String {
        switch self {
        case .sec1: return "Seeking veloce, file più grande"
        case .sec2: return "Bilanciato (consigliato)"
        case .sec3, .sec4: return "File più piccolo"
        case .sec5: return "Minima dimensione"
        }
    }
}

// MARK: - Camera Rotation
enum CameraRotation: Int, CaseIterable, Identifiable {
    case rotate0 = 0
    case rotate90 = 90
    case rotate180 = 180
    case rotate270 = 270
    
    var id: Int { rawValue }
    
    var displayName: String {
        switch self {
        case .rotate0: return "0°"
        case .rotate90: return "90°"
        case .rotate180: return "180°"
        case .rotate270: return "270°"
        }
    }
    
    var angle: Double {
        Double(rawValue)
    }
}

// MARK: - Custom Resolution
struct CustomResolution: Equatable {
    var width: Int
    var height: Int
    
    static let presets: [CustomResolution] = [
        CustomResolution(width: 640, height: 360),
        CustomResolution(width: 854, height: 480),
        CustomResolution(width: 1280, height: 720),
        CustomResolution(width: 1920, height: 1080),
        CustomResolution(width: 2560, height: 1440),
        CustomResolution(width: 3840, height: 2160)
    ]
    
    var displayName: String {
        "\(width)×\(height)"
    }
}

// MARK: - Streaming Settings Container
class StreamingSettings: ObservableObject {
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let customBitrate = "settings.customBitrate"
        static let selectedFPS = "settings.selectedFPS"
        static let h264Profile = "settings.h264Profile"
        static let keyframeInterval = "settings.keyframeInterval"
        static let useCustomBitrate = "settings.useCustomBitrate"
        static let audioBitrate = "settings.audioBitrate"
        static let audioSampleRate = "settings.audioSampleRate"
        static let enableAudio = "settings.enableAudio"
        static let srtLatency = "settings.srtLatency"
        static let srtPassphrase = "settings.srtPassphrase"
        static let enableEncryption = "settings.enableEncryption"
        static let enableTorch = "settings.enableTorch"
        static let torchLevel = "settings.torchLevel"
        static let enableStabilization = "settings.enableStabilization"
        static let cameraRotation = "settings.cameraRotation"
        static let adaptiveBitrate = "settings.adaptiveBitrate"
        static let lowLatencyMode = "settings.lowLatencyMode"
    }
    
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    // Video
    @Published var customBitrate: Double = 4_000_000 // 4 Mbps default
    @Published var selectedFPS: FPSOption = .fps30
    @Published var h264Profile: H264Profile = .baseline
    @Published var keyframeInterval: KeyframeInterval = .sec2
    @Published var useCustomBitrate: Bool = false
    
    // Audio
    @Published var audioBitrate: AudioBitrate = .medium
    @Published var audioSampleRate: AudioSampleRate = .rate44100
    @Published var enableAudio: Bool = true
    
    // SRT
    @Published var srtLatency: SRTLatency = .medium
    @Published var srtPassphrase: String = ""
    @Published var enableEncryption: Bool = false
    
    // Camera
    @Published var enableTorch: Bool = false
    @Published var torchLevel: Float = 0.5
    @Published var enableStabilization: Bool = true
    @Published var cameraRotation: CameraRotation = .rotate0
    
    // Advanced
    @Published var adaptiveBitrate: Bool = false
    @Published var lowLatencyMode: Bool = false
    
    var bitrateInMbps: Double {
        get { customBitrate / 1_000_000 }
        set { customBitrate = newValue * 1_000_000 }
    }
    
    var bitrateFormatted: String {
        String(format: "%.1f Mbps", bitrateInMbps)
    }
    
    // MARK: - Initialization
    init() {
        loadSettings()
        setupAutoSave()
    }
    
    // MARK: - Load Settings
    private func loadSettings() {
        // Video
        if defaults.object(forKey: Keys.customBitrate) != nil {
            customBitrate = defaults.double(forKey: Keys.customBitrate)
        }
        if let fpsValue = defaults.object(forKey: Keys.selectedFPS) as? Int,
           let fps = FPSOption(rawValue: fpsValue) {
            selectedFPS = fps
        }
        if let profileValue = defaults.string(forKey: Keys.h264Profile),
           let profile = H264Profile(rawValue: profileValue) {
            h264Profile = profile
        }
        if let keyframeValue = defaults.object(forKey: Keys.keyframeInterval) as? Int,
           let keyframe = KeyframeInterval(rawValue: keyframeValue) {
            keyframeInterval = keyframe
        }
        if defaults.object(forKey: Keys.useCustomBitrate) != nil {
            useCustomBitrate = defaults.bool(forKey: Keys.useCustomBitrate)
        }
        
        // Audio
        if let audioBitrateValue = defaults.object(forKey: Keys.audioBitrate) as? Int,
           let bitrate = AudioBitrate(rawValue: audioBitrateValue) {
            audioBitrate = bitrate
        }
        if let sampleRateValue = defaults.object(forKey: Keys.audioSampleRate) as? Double,
           let rate = AudioSampleRate(rawValue: sampleRateValue) {
            audioSampleRate = rate
        }
        if defaults.object(forKey: Keys.enableAudio) != nil {
            enableAudio = defaults.bool(forKey: Keys.enableAudio)
        }
        
        // SRT
        if let latencyValue = defaults.object(forKey: Keys.srtLatency) as? Int,
           let latency = SRTLatency(rawValue: latencyValue) {
            srtLatency = latency
        }
        if let passphrase = defaults.string(forKey: Keys.srtPassphrase) {
            srtPassphrase = passphrase
        }
        if defaults.object(forKey: Keys.enableEncryption) != nil {
            enableEncryption = defaults.bool(forKey: Keys.enableEncryption)
        }
        
        // Camera
        if defaults.object(forKey: Keys.enableTorch) != nil {
            enableTorch = defaults.bool(forKey: Keys.enableTorch)
        }
        if defaults.object(forKey: Keys.torchLevel) != nil {
            torchLevel = defaults.float(forKey: Keys.torchLevel)
        }
        if defaults.object(forKey: Keys.enableStabilization) != nil {
            enableStabilization = defaults.bool(forKey: Keys.enableStabilization)
        }
        if let rotationValue = defaults.object(forKey: Keys.cameraRotation) as? Int,
           let rotation = CameraRotation(rawValue: rotationValue) {
            cameraRotation = rotation
        }
        
        // Advanced
        if defaults.object(forKey: Keys.adaptiveBitrate) != nil {
            adaptiveBitrate = defaults.bool(forKey: Keys.adaptiveBitrate)
        }
        if defaults.object(forKey: Keys.lowLatencyMode) != nil {
            lowLatencyMode = defaults.bool(forKey: Keys.lowLatencyMode)
        }
    }
    
    // MARK: - Auto Save
    private func setupAutoSave() {
        // Video
        $customBitrate
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.customBitrate)
            }
            .store(in: &cancellables)
        
        $selectedFPS
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.selectedFPS)
            }
            .store(in: &cancellables)
        
        $h264Profile
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.h264Profile)
            }
            .store(in: &cancellables)
        
        $keyframeInterval
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.keyframeInterval)
            }
            .store(in: &cancellables)
        
        $useCustomBitrate
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.useCustomBitrate)
            }
            .store(in: &cancellables)
        
        // Audio
        $audioBitrate
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.audioBitrate)
            }
            .store(in: &cancellables)
        
        $audioSampleRate
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.audioSampleRate)
            }
            .store(in: &cancellables)
        
        $enableAudio
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.enableAudio)
            }
            .store(in: &cancellables)
        
        // SRT
        $srtLatency
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.srtLatency)
            }
            .store(in: &cancellables)
        
        $srtPassphrase
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.srtPassphrase)
            }
            .store(in: &cancellables)
        
        $enableEncryption
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.enableEncryption)
            }
            .store(in: &cancellables)
        
        // Camera
        $enableTorch
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.enableTorch)
            }
            .store(in: &cancellables)
        
        $torchLevel
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.torchLevel)
            }
            .store(in: &cancellables)
        
        $enableStabilization
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.enableStabilization)
            }
            .store(in: &cancellables)
        
        $cameraRotation
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value.rawValue, forKey: Keys.cameraRotation)
            }
            .store(in: &cancellables)
        
        // Advanced
        $adaptiveBitrate
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.adaptiveBitrate)
            }
            .store(in: &cancellables)
        
        $lowLatencyMode
            .dropFirst()
            .sink { [weak self] value in
                self?.defaults.set(value, forKey: Keys.lowLatencyMode)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Reset to Defaults
    func resetToDefaults() {
        customBitrate = 4_000_000
        selectedFPS = .fps30
        h264Profile = .baseline
        keyframeInterval = .sec2
        useCustomBitrate = false
        audioBitrate = .medium
        audioSampleRate = .rate44100
        enableAudio = true
        srtLatency = .medium
        srtPassphrase = ""
        enableEncryption = false
        enableTorch = false
        torchLevel = 0.5
        enableStabilization = true
        cameraRotation = .rotate0
        adaptiveBitrate = false
        lowLatencyMode = false
    }
}
