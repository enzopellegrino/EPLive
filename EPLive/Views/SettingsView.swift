//
//  SettingsView.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StreamViewModel
    @State private var showServerList = false
    @State private var showAdvanced = false
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Server Section
                Section(header: Text("SRT Server")) {
                    if let server = viewModel.currentServer {
                        ServerInfoRow(server: server)
                    } else {
                        Text("No server selected")
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: { showServerList = true }) {
                        Label("Manage Servers", systemImage: "server.rack")
                    }
                    .disabled(viewModel.isStreaming)
                }
                
                // MARK: - Video Quality Section
                Section(header: Text("Video")) {
                    Picker("Risoluzione", selection: $viewModel.selectedQuality) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                    
                    Picker("Frame Rate", selection: $viewModel.streamingSettings.selectedFPS) {
                        ForEach(FPSOption.allCases) { fps in
                            Text(fps.displayName).tag(fps)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                    
                    // Bitrate
                    Toggle("Bitrate Personalizzato", isOn: $viewModel.streamingSettings.useCustomBitrate)
                        .disabled(viewModel.isStreaming)
                    
                    if viewModel.streamingSettings.useCustomBitrate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Bitrate")
                                Spacer()
                                Text(viewModel.streamingSettings.bitrateFormatted)
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: $viewModel.streamingSettings.bitrateInMbps,
                                in: 0.5...25,
                                step: 0.5
                            )
                        }
                        .disabled(viewModel.isStreaming)
                    } else {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text("\(viewModel.selectedQuality.bitrate / 1_000_000) Mbps")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Picker("Profilo H.264", selection: $viewModel.streamingSettings.h264Profile) {
                        ForEach(H264Profile.allCases) { profile in
                            VStack(alignment: .leading) {
                                Text(profile.rawValue)
                            }
                            .tag(profile)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                    
                    Picker("Keyframe Interval", selection: $viewModel.streamingSettings.keyframeInterval) {
                        ForEach(KeyframeInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                }
                
                // MARK: - Audio Section
                Section(header: Text("Audio")) {
                    Toggle("Abilita Audio", isOn: $viewModel.streamingSettings.enableAudio)
                        .disabled(viewModel.isStreaming)
                    
                    if viewModel.streamingSettings.enableAudio {
                        Picker("Bitrate Audio", selection: $viewModel.streamingSettings.audioBitrate) {
                            ForEach(AudioBitrate.allCases) { bitrate in
                                HStack {
                                    Text(bitrate.displayName)
                                    Spacer()
                                    Text(bitrate.description)
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .tag(bitrate)
                            }
                        }
                        .disabled(viewModel.isStreaming)
                        
                        Picker("Sample Rate", selection: $viewModel.streamingSettings.audioSampleRate) {
                            ForEach(AudioSampleRate.allCases) { rate in
                                Text(rate.displayName).tag(rate)
                            }
                        }
                        .disabled(viewModel.isStreaming)
                    }
                }
                
                // MARK: - Camera Section
                Section(header: Text("Camera")) {
                    Picker("Seleziona Camera", selection: Binding(
                        get: { viewModel.availableCameras.first },
                        set: { if let camera = $0 { viewModel.selectCamera(camera) } }
                    )) {
                        ForEach(viewModel.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName)
                                .tag(camera as AVCaptureDevice?)
                        }
                    }
                    
                    if viewModel.isTorchAvailable {
                        Toggle("Torcia", isOn: Binding(
                            get: { viewModel.streamingSettings.enableTorch },
                            set: { newValue in
                                viewModel.streamingSettings.enableTorch = newValue
                                viewModel.toggleTorch()
                            }
                        ))
                        
                        if viewModel.streamingSettings.enableTorch {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Intensità")
                                    Spacer()
                                    Text("\(Int(viewModel.streamingSettings.torchLevel * 100))%")
                                        .foregroundColor(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { viewModel.streamingSettings.torchLevel },
                                        set: { viewModel.setTorchLevel($0) }
                                    ),
                                    in: 0.1...1.0
                                )
                            }
                        }
                    }
                }
                
                // MARK: - SRT Settings Section
                Section(header: Text("SRT")) {
                    Picker("Latenza", selection: $viewModel.streamingSettings.srtLatency) {
                        ForEach(SRTLatency.allCases) { latency in
                            VStack(alignment: .leading) {
                                Text(latency.displayName)
                                Text(latency.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(latency)
                        }
                    }
                    .disabled(viewModel.isStreaming)
                    
                    Toggle("Crittografia", isOn: $viewModel.streamingSettings.enableEncryption)
                        .disabled(viewModel.isStreaming)
                    
                    if viewModel.streamingSettings.enableEncryption {
                        SecureField("Passphrase", text: $viewModel.streamingSettings.srtPassphrase)
                            .disabled(viewModel.isStreaming)
                    }
                }
                
                // MARK: - Advanced Section
                Section(header: Text("Avanzate")) {
                    Toggle("Mostra Opzioni Avanzate", isOn: $showAdvanced)
                    
                    if showAdvanced {
                        Toggle("Bitrate Adattivo", isOn: $viewModel.streamingSettings.adaptiveBitrate)
                            .disabled(viewModel.isStreaming)
                        
                        Toggle("Modalità Bassa Latenza", isOn: $viewModel.streamingSettings.lowLatencyMode)
                            .disabled(viewModel.isStreaming)
                        
                        Toggle("Stabilizzazione Video", isOn: $viewModel.streamingSettings.enableStabilization)
                            .disabled(viewModel.isStreaming)
                    }
                }
                
                // MARK: - Info Section
                Section(header: Text("Informazioni")) {
                    InfoRow(title: "Stato", value: viewModel.connectionStatus)
                    InfoRow(title: "Permessi Camera", 
                           value: viewModel.cameraPermissionGranted ? "Concessi" : "Non Concessi",
                           valueColor: viewModel.cameraPermissionGranted ? .green : .red)
                    
                    if let server = viewModel.currentServer {
                        InfoRow(title: "Server Valido",
                               value: server.isValid ? "Sì" : "No",
                               valueColor: server.isValid ? .green : .red)
                    }
                    
                    InfoRow(title: "Versione", value: "1.0")
                    InfoRow(title: "Protocollo", value: "SRT / UDP")
                }
                
                // MARK: - Reset Section
                Section {
                    Button(action: resetToDefaults) {
                        Label("Ripristina Impostazioni Default", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.red)
                    }
                    .disabled(viewModel.isStreaming)
                }
            }
            .navigationTitle("Impostazioni")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showServerList) {
                ServerListView(
                    serverManager: viewModel.serverManager,
                    selectedServer: $viewModel.currentServer
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 700)
        #endif
    }
    
    private func resetToDefaults() {
        viewModel.selectedQuality = .medium
        viewModel.streamingSettings.selectedFPS = .fps30
        viewModel.streamingSettings.useCustomBitrate = false
        viewModel.streamingSettings.customBitrate = 4_000_000
        viewModel.streamingSettings.h264Profile = .baseline
        viewModel.streamingSettings.keyframeInterval = .sec2
        viewModel.streamingSettings.enableAudio = true
        viewModel.streamingSettings.audioBitrate = .medium
        viewModel.streamingSettings.audioSampleRate = .rate44100
        viewModel.streamingSettings.srtLatency = .medium
        viewModel.streamingSettings.enableEncryption = false
        viewModel.streamingSettings.srtPassphrase = ""
        viewModel.streamingSettings.enableTorch = false
        viewModel.streamingSettings.adaptiveBitrate = false
        viewModel.streamingSettings.lowLatencyMode = false
        viewModel.streamingSettings.enableStabilization = true
    }
}

// MARK: - Helper Views

struct ServerInfoRow: View {
    let server: SRTServer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                    
                    Text(server.url)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("\(server.bitrate / 1000) kbps")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if server.isDefault {
                    Text("DEFAULT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = .gray
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
        }
    }
}

#Preview {
    SettingsView(viewModel: StreamViewModel())
}
