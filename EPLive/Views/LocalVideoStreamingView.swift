//
//  LocalVideoStreamingView.swift
//  EPLive
//
//  Schermata dedicata durante lo streaming di video locale
//  Mostra solo informazioni essenziali senza il player video
//

import SwiftUI

struct LocalVideoStreamingView: View {
    @ObservedObject var viewModel: StreamViewModel
    
    // Timer per aggiornare il tempo di streaming
    @State private var streamingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var streamStartTime: Date?
    
    var body: some View {
        ZStack {
            // Background scuro
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Icona streaming animata
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 90, height: 90)
                    
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                }
                
                // Stato streaming
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .shadow(color: .red, radius: 4)
                    
                    Text("STREAMING IN CORSO")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                // Informazioni video
                VStack(spacing: 16) {
                    // Nome file
                    if let videoName = viewModel.selectedVideoURL?.lastPathComponent {
                        StreamInfoRow(icon: "film.fill", title: "Video", value: videoName, color: .orange)
                    }
                    
                    // Server
                    if let server = viewModel.currentServer {
                        StreamInfoRow(icon: "server.rack", title: "Server", value: server.name, color: .blue)
                    }
                    
                    // Loop
                    StreamInfoRow(
                        icon: viewModel.localVideoStreamer.loopEnabled ? "repeat" : "arrow.right",
                        title: "Loop",
                        value: viewModel.localVideoStreamer.loopEnabled ? "Attivo" : "Disattivo",
                        color: viewModel.localVideoStreamer.loopEnabled ? .green : .gray
                    )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                )
                .padding(.horizontal, 24)
                
                // Progress bar video
                VStack(spacing: 8) {
                    // Barra progresso
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * viewModel.localVideoStreamer.progress)
                                .animation(.linear(duration: 0.1), value: viewModel.localVideoStreamer.progress)
                        }
                    }
                    .frame(height: 8)
                    
                    // Tempi
                    HStack {
                        Text(formatTime(viewModel.localVideoStreamer.currentTime))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(viewModel.localVideoStreamer.duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 32)
                
                // Tempo streaming totale
                VStack(spacing: 4) {
                    Text("Tempo streaming")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(formatDuration(streamingDuration))
                        .font(.system(size: 36, weight: .light, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.top, 16)
                
                Spacer()
                
                // Pulsante STOP
                Button(action: {
                    viewModel.stopStreaming()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                        Text("FERMA STREAMING")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color.red)
                    )
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }
    
    private func startTimer() {
        streamStartTime = Date()
        streamingDuration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = streamStartTime {
                streamingDuration = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Stream Info Row Component
struct StreamInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    LocalVideoStreamingView(viewModel: StreamViewModel())
}
