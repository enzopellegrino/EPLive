//
//  VideoQuality.swift
//  EPLive
//
//  Video quality presets for streaming
//

import Foundation

enum VideoQuality: String, CaseIterable, Identifiable {
    case low = "360p"
    case medium = "720p"
    case high = "1080p"
    case ultra = "4K"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .low: return "360p (Basso)"
        case .medium: return "720p HD (Medio)"
        case .high: return "1080p Full HD (Alto)"
        case .ultra: return "4K Ultra HD"
        }
    }
    
    var resolution: (width: Int32, height: Int32) {
        switch self {
        case .low: return (640, 360)
        case .medium: return (1280, 720)
        case .high: return (1920, 1080)
        case .ultra: return (3840, 2160)
        }
    }
    
    var bitrate: Int32 {
        switch self {
        case .low: return 1_500_000      // 1.5 Mbps
        case .medium: return 4_000_000   // 4 Mbps
        case .high: return 8_000_000     // 8 Mbps
        case .ultra: return 20_000_000   // 20 Mbps
        }
    }
    
    var fps: Int32 {
        switch self {
        case .low, .medium: return 30
        case .high: return 60
        case .ultra: return 60
        }
    }
    
    var description: String {
        let res = resolution
        return "\(displayName) - \(res.width)×\(res.height) @ \(fps)fps, \(bitrate / 1_000_000)Mbps"
    }
}
