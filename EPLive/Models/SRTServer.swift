//
//  SRTServer.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import Foundation

struct SRTServer: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var bitrate: Int
    var isDefault: Bool
    
    init(id: UUID = UUID(), name: String, url: String, bitrate: Int = 2_500_000, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.bitrate = bitrate
        self.isDefault = isDefault
    }
    
    var host: String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }
    
    var port: Int? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.port
    }
    
    var isValid: Bool {
        guard let urlObj = URL(string: url),
              let scheme = urlObj.scheme,
              (scheme == "srt" || scheme == "udp" || scheme == "rtmp" || scheme == "rtmps") else {
            return false
        }
        // RTMP URLs might not have port (defaults to 1935)
        if scheme == "rtmp" || scheme == "rtmps" {
            return urlObj.host != nil
        }
        // SRT/UDP require explicit port
        return urlObj.host != nil && urlObj.port != nil
    }
}
