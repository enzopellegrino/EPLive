//
//  VideoPreviewView.swift
//  EPLive
//
//  Preview view for local video files with playback controls
//

import SwiftUI
import AVKit
import AVFoundation
import Combine

struct VideoPreviewView: View {
    @ObservedObject var viewModel: StreamViewModel
    @State private var player: AVPlayer?
    @State private var isLocallyPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if let url = viewModel.selectedVideoURL {
                // Video player sempre visibile
                if let player = player {
                    ZStack {
                        VideoPlayer(player: player) {
                            // Nessun overlay - usiamo i nostri controlli
                        }
                        .ignoresSafeArea()
                        
                        // Overlay trasparente per intercettare tap e usare i nostri controlli
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                    }
                } else {
                    // Loading
                    ProgressView("Caricamento video...")
                        .foregroundColor(.white)
                }
                
                // Controlli personalizzati
                VStack {
                    Spacer()
                    
                    // Pannello controlli in basso
                    VStack(spacing: 12) {
                        // Seek bar
                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { currentTime },
                                    set: { newValue in
                                        currentTime = newValue
                                        if isSeeking {
                                            seekTo(newValue)
                                        }
                                    }
                                ),
                                in: 0...max(duration, 1),
                                onEditingChanged: { editing in
                                    isSeeking = editing
                                    if !editing {
                                        seekTo(currentTime)
                                        // Se sta streamando, riavvia lo stream dalla nuova posizione
                                        if viewModel.isStreaming {
                                            Task {
                                                await viewModel.localVideoStreamer.seekTo(currentTime)
                                            }
                                        }
                                    }
                                }
                            )
                            .accentColor(.orange)
                            
                            // Tempi
                            HStack {
                                Text(timeString(currentTime))
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(timeString(duration))
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Play/Pause + Info
                        HStack(spacing: 16) {
                            // Nome file
                            HStack(spacing: 6) {
                                Image(systemName: "film.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Play/Pause (solo se non sta streamando)
                            if !viewModel.isStreaming {
                                Button(action: toggleLocalPlayback) {
                                    Image(systemName: isLocallyPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                }
                            } else {
                                // Indicatore streaming
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("LIVE")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 12)
                    .background(
                        Color.black.opacity(0.8)
                            .blur(radius: 10)
                    )
                    .padding(.bottom, 100) // Spazio per i controlli di streaming
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "film.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("Nessun video caricato")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
        .task {
            if let url = viewModel.selectedVideoURL {
                setupPlayer(url: url)
            }
        }
        .onChange(of: viewModel.selectedVideoURL) { newURL in
            if let url = newURL {
                setupPlayer(url: url)
            } else {
                cleanupPlayer()
            }
        }
        .onChange(of: viewModel.isStreaming) { streaming in
            // IMPORTANTE: Quando si fa streaming, FERMA il player locale
            // per evitare conflitti audio e doppia decodifica
            if streaming {
                // Ferma il player locale - lo streaming usa AVAssetReader separato
                stopLocalPlayback()
                // Metti in mute il player (sicurezza extra)
                player?.isMuted = true
            } else {
                // Streaming terminato - ripristina
                player?.isMuted = false
            }
        }
        // Sincronizza con il progresso del LocalVideoStreamer
        .onReceive(viewModel.localVideoStreamer.$currentTime) { time in
            if viewModel.isStreaming && !isSeeking {
                currentTime = time
            }
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func setupPlayer(url: URL) {
        cleanupPlayer()
        
        // Riusa l'asset già caricato dal LocalVideoStreamer invece di crearne uno nuovo
        let asset = viewModel.localVideoStreamer.asset ?? AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.actionAtItemEnd = .none
        
        // Usa la durata già caricata se disponibile
        if viewModel.localVideoStreamer.duration > 0 {
            duration = viewModel.localVideoStreamer.duration
        } else {
            // Altrimenti carica in background
            Task {
                do {
                    let durationTime = try await asset.load(.duration)
                    await MainActor.run {
                        duration = CMTimeGetSeconds(durationTime)
                    }
                } catch {
                    print("Error loading duration: \(error)")
                }
            }
        }
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            if isLocallyPlaying || viewModel.isStreaming {
                newPlayer?.play()
            }
        }
        
        // Time observer per aggiornare la seek bar
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let observer = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak newPlayer] time in
            if !isSeeking && !viewModel.isStreaming {
                currentTime = CMTimeGetSeconds(time)
            }
        }
        timeObserver = observer
        
        player = newPlayer
    }
    
    private func toggleLocalPlayback() {
        if isLocallyPlaying {
            stopLocalPlayback()
        } else {
            startLocalPlayback()
        }
    }
    
    private func startLocalPlayback() {
        player?.play()
        isLocallyPlaying = true
    }
    
    private func stopLocalPlayback() {
        player?.pause()
        isLocallyPlaying = false
    }
    
    private func seekTo(_ time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isLocallyPlaying = false
        currentTime = 0
        duration = 1
    }
    
    private func timeString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VideoPreviewView(viewModel: StreamViewModel())
}
