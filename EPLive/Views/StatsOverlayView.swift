//
//  StatsOverlayView.swift
//  EPLive
//
//  Overlay per statistiche streaming in tempo reale (stile Larix)
//

import SwiftUI

struct StatsOverlayView: View {
    @ObservedObject var stats: StreamingStats
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Barra compatta sempre visibile
            HStack(spacing: 12) {
                // Durata e stato
                HStack(spacing: 4) {
                    Circle()
                        .fill(stats.isHealthy ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(stats.durationString)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                
                // Bitrate
                Text(stats.bitrateString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                
                // FPS
                Text(stats.fpsString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                
                Spacer()
                
                // Pulsante espandi/comprimi
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(stats.isHealthy ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // Statistiche dettagliate espandibili
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    // Video
                    StatRow(
                        icon: "video.fill",
                        title: "Video",
                        value: "\(stats.videoFramesSent) frames",
                        detail: "Dropped: \(stats.dropRateString)"
                    )
                    
                    // Audio
                    StatRow(
                        icon: "waveform",
                        title: "Audio",
                        value: "\(stats.audioSamplesSent) samples",
                        detail: "Dropped: \(stats.audioSamplesDropped)"
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    // Bitrate medio
                    StatRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Avg Bitrate",
                        value: stats.averageBitrateString,
                        detail: nil
                    )
                    
                    // RTT
                    if stats.rtt > 0 {
                        StatRow(
                            icon: "timer",
                            title: "RTT",
                            value: stats.rttString,
                            detail: nil
                        )
                    }
                    
                    // Packet Loss
                    if stats.packetLoss > 0 {
                        StatRow(
                            icon: "exclamationmark.triangle.fill",
                            title: "Packet Loss",
                            value: stats.packetLossString,
                            detail: nil,
                            isWarning: stats.packetLoss > 1.0
                        )
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    // Dati totali
                    StatRow(
                        icon: "arrow.up.circle.fill",
                        title: "Total Data",
                        value: stats.totalDataString,
                        detail: nil
                    )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .foregroundColor(.white)
    }
}

// MARK: - Riga Statistica

private struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?
    var isWarning: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isWarning ? .orange : .white.opacity(0.7))
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isWarning ? .orange : .white)
                
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Preview

struct StatsOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            VStack {
                StatsOverlayView(stats: {
                    let stats = StreamingStats()
                    stats.start()
                    stats.currentBitrate = 4500
                    stats.averageBitrate = 4200
                    stats.currentFPS = 29.97
                    stats.videoFramesSent = 3456
                    stats.audioSamplesSent = 12789
                    stats.rtt = 42
                    stats.packetLoss = 0.12
                    stats.totalBytesSent = 125_000_000
                    return stats
                }())
                .padding()
                
                Spacer()
            }
        }
    }
}
