//
//  SettingsView.swift
//  EPLive
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StreamViewModel
    @State private var showServerList = false
    @State private var showAdvanced = false
    
    var body: some View {
        #if os(macOS)
        macOSSettings
        #else
        iOSSettings
        #endif
    }
    
    // MARK: - macOS Settings
    #if os(macOS)
    private var macOSSettings: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Impostazioni")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Fine") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Server
                    GroupBox(label: Label("SRT Server", systemImage: "server.rack")) {
                        VStack(alignment: .leading, spacing: 12) {
                            if let server = viewModel.currentServer {
                                ServerInfoRow(server: server)
                            } else {
                                Text("Nessun server selezionato")
                                    .foregroundColor(.gray)
                            }
                            Button(action: { showServerList = true }) {
                                Label("Gestisci Server", systemImage: "folder")
                            }
                            .disabled(viewModel.isStreaming)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Video
                    GroupBox(label: Label("Video", systemImage: "video")) {
                        VStack(alignment: .leading, spacing: 12) {
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
                            
                            Toggle("Bitrate Personalizzato", isOn: $viewModel.streamingSettings.useCustomBitrate)
                                .disabled(viewModel.isStreaming)
                            
                            if viewModel.streamingSettings.useCustomBitrate {
                                HStack {
                                    Text("Bitrate")
                                    Spacer()
                                    Text(viewModel.streamingSettings.bitrateFormatted)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $viewModel.streamingSettings.bitrateInMbps, in: 0.5...25, step: 0.5)
                                    .disabled(viewModel.isStreaming)
                            }
                            
                            Picker("Profilo H.264", selection: $viewModel.streamingSettings.h264Profile) {
                                ForEach(H264Profile.allCases) { profile in
                                    Text(profile.rawValue).tag(profile)
                                }
                            }
                            .disabled(viewModel.isStreaming)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Audio
                    GroupBox(label: Label("Audio", systemImage: "speaker.wave.2")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Abilita Audio", isOn: $viewModel.streamingSettings.enableAudio)
                                .disabled(viewModel.isStreaming)
                            
                            if viewModel.streamingSettings.enableAudio {
                                Picker("Bitrate Audio", selection: $viewModel.streamingSettings.audioBitrate) {
                                    ForEach(AudioBitrate.allCases) { bitrate in
                                        Text(bitrate.displayName).tag(bitrate)
                                    }
                                }
                                .disabled(viewModel.isStreaming)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Camera
                    GroupBox(label: Label("Camera", systemImage: "camera")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Seleziona Camera", selection: Binding(
                                get: { viewModel.availableCameras.first },
                                set: { if let camera = $0 { viewModel.selectCamera(camera) } }
                            )) {
                                ForEach(viewModel.availableCameras, id: \.uniqueID) { camera in
                                    Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // SRT
                    GroupBox(label: Label("SRT", systemImage: "network")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Latenza", selection: $viewModel.streamingSettings.srtLatency) {
                                ForEach(SRTLatency.allCases) { latency in
                                    Text(latency.displayName).tag(latency)
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
                        .padding(.vertical, 8)
                    }
                    
                    // Info
                    GroupBox(label: Label("Info", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "Stato", value: viewModel.connectionStatus)
                            InfoRow(title: "Permessi Camera", 
                                   value: viewModel.cameraPermissionGranted ? "Concessi" : "Non Concessi",
                                   valueColor: viewModel.cameraPermissionGranted ? .green : .red)
                            InfoRow(title: "Versione", value: "1.0")
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Button(action: resetToDefaults) {
                        Label("Ripristina Impostazioni Default", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.red)
                    }
                    .disabled(viewModel.isStreaming)
                }
                .padding(20)
            }
        }
        .frame(width: 550, height: 650)
        .sheet(isPresented: $showServerList) {
            ServerListView(serverManager: viewModel.serverManager, selectedServer: $viewModel.currentServer)
        }
    }
    #endif
    
    // MARK: - iOS Settings
    private var iOSSettings: some View {
        NavigationView {
            Form {
                Section(header: Text("SRT Server")) {
                    if let server = viewModel.currentServer {
                        ServerInfoRow(server: server)
                    } else {
                        Text("Nessun server selezionato").foregroundColor(.gray)
                    }
                    Button(action: { showServerList = true }) {
                        Label("Gestisci Server", systemImage: "server.rack")
                    }
                    .disabled(viewModel.isStreaming)
                }
                
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
                    
                    Toggle("Bitrate Personalizzato", isOn: $viewModel.streamingSettings.useCustomBitrate)
                        .disabled(viewModel.isStreaming)
                    
                    if viewModel.streamingSettings.useCustomBitrate {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text(viewModel.streamingSettings.bitrateFormatted)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.streamingSettings.bitrateInMbps, in: 0.5...25, step: 0.5)
                            .disabled(viewModel.isStreaming)
                        
                        Picker("Profilo H.264", selection: $viewModel.streamingSettings.h264Profile) {
                            ForEach(H264Profile.allCases) { profile in
                                Text(profile.rawValue).tag(profile)
                            }
                        }
                        .disabled(viewModel.isStreaming)
                    }
                }
                
                Section(header: Text("Audio")) {
                    Toggle("Abilita Audio", isOn: $viewModel.streamingSettings.enableAudio)
                        .disabled(viewModel.isStreaming)
                    
                    if viewModel.streamingSettings.enableAudio {
                        Picker("Bitrate Audio", selection: $viewModel.streamingSettings.audioBitrate) {
                            ForEach(AudioBitrate.allCases) { bitrate in
                                Text(bitrate.displayName).tag(bitrate)
                            }
                        }
                        .disabled(viewModel.isStreaming)
                    }
                }
                
                Section(header: Text("Camera")) {
                    Picker("Seleziona Camera", selection: Binding(
                        get: { viewModel.availableCameras.first },
                        set: { if let camera = $0 { viewModel.selectCamera(camera) } }
                    )) {
                        ForEach(viewModel.availableCameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                        }
                    }
                }
                
                Section(header: Text("SRT")) {
                    Picker("Latenza", selection: $viewModel.streamingSettings.srtLatency) {
                        ForEach(SRTLatency.allCases) { latency in
                            Text(latency.displayName).tag(latency)
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
                
                Section(header: Text("Informazioni")) {
                    InfoRow(title: "Stato", value: viewModel.connectionStatus)
                    InfoRow(title: "Permessi Camera", 
                           value: viewModel.cameraPermissionGranted ? "Concessi" : "Non Concessi",
                           valueColor: viewModel.cameraPermissionGranted ? .green : .red)
                    InfoRow(title: "Versione", value: "1.0")
                }
                
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
                    Button("Fine") { dismiss() }
                }
            }
            .sheet(isPresented: $showServerList) {
                ServerListView(serverManager: viewModel.serverManager, selectedServer: $viewModel.currentServer)
            }
        }
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
                    Text(server.name).font(.headline)
                    Text(server.url).font(.subheadline).foregroundColor(.gray)
                    Text("\(server.bitrate / 1000) kbps").font(.caption).foregroundColor(.gray)
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
            Text(value).foregroundColor(valueColor)
        }
    }
}

#Preview {
    SettingsView(viewModel: StreamViewModel())
}
