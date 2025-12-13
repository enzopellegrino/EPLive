//
//  StreamingSettings.swift
//  EPLive
//
//  Advanced streaming settings model
//

import Foundation
import Combine

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
}
