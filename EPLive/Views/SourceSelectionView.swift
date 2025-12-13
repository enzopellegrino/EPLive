//
//  SourceSelectionView.swift
//  EPLive
//
//  View for selecting streaming source (Camera, Screen, Window)
//

import SwiftUI

struct SourceSelectionView: View {
    @ObservedObject var viewModel: StreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSourceType: StreamSourceType
    @State private var availableScreens: [ScreenInfo] = []
    @State private var availableWindows: [WindowInfo] = []
    @State private var selectedScreen: ScreenInfo?
    @State private var selectedWindow: WindowInfo?
    
    init(viewModel: StreamViewModel) {
        self.viewModel = viewModel
        _selectedSourceType = State(initialValue: viewModel.currentSourceType)
    }
    
    var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }
    
    #if os(macOS)
    private var macOSView: some View {
        VStack(spacing: 20) {
            Text("Seleziona Sorgente Streaming")
                .font(.title2)
                .fontWeight(.bold)
            
            // Source type picker
            Picker("Tipo Sorgente", selection: $selectedSourceType) {
                Text("📷 Camera").tag(StreamSourceType.camera)
                Text("🖥️ Schermo").tag(StreamSourceType.screen)
                Text("🪟 Finestra").tag(StreamSourceType.window)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedSourceType) { newValue in
                loadAvailableSources(for: newValue)
            }
            
            Divider()
            
            // Source-specific options
            Group {
                switch selectedSourceType {
                case .camera:
                    cameraOptionsView
                    
                case .screen:
                    screenOptionsView
                    
                case .window:
                    windowOptionsView
                }
            }
            .frame(minHeight: 200)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Applica") {
                    applySourceSelection()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadAvailableSources(for: selectedSourceType)
        }
    }
    #else
    private var iOSView: some View {
        NavigationView {
            Form {
                Section("Tipo Sorgente") {
                    Picker("Sorgente", selection: $selectedSourceType) {
                        Text("📷 Camera").tag(StreamSourceType.camera)
                    }
                    .pickerStyle(.menu)
                }
                
                Section {
                    cameraOptionsView
                }
            }
            .navigationTitle("Seleziona Sorgente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica") {
                        applySourceSelection()
                    }
                    .disabled(!canApply)
                }
            }
            .onAppear {
                loadAvailableSources(for: selectedSourceType)
            }
        }
    }
    #endif
    
    // MARK: - Source Options Views
    
    private var cameraOptionsView: some View {
        VStack {
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Camera")
                .font(.headline)
                .padding(.top, 8)
            
            Text("Streaming dalla fotocamera del dispositivo")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    #if os(macOS)
    private var screenOptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schermi Disponibili")
                .font(.headline)
            
            if availableScreens.isEmpty {
                Text("Nessuno schermo disponibile")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List(availableScreens) { screen in
                    HStack {
                        Image(systemName: screen.isMain ? "tv.fill" : "tv")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(screen.name)
                                .font(.body)
                            Text("\(Int(screen.width)) × \(Int(screen.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedScreen?.id == screen.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedScreen = screen
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var windowOptionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Finestre Disponibili")
                    .font(.headline)
                Spacer()
                Button(action: {
                    loadAvailableSources(for: .window)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            
            if availableWindows.isEmpty {
                Text("Nessuna finestra disponibile")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List(availableWindows) { window in
                    HStack {
                        Image(systemName: "macwindow")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(window.title)
                                .font(.body)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(window.ownerName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("\(Int(window.bounds.width)) × \(Int(window.bounds.height))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if selectedWindow?.id == window.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedWindow = window
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    #endif
    
    // MARK: - Helper Methods
    
    private func loadAvailableSources(for sourceType: StreamSourceType) {
        #if os(macOS)
        switch sourceType {
        case .screen:
            availableScreens = ScreenInfo.availableScreens()
            if selectedScreen == nil {
                selectedScreen = availableScreens.first(where: { $0.isMain }) ?? availableScreens.first
            }
            
        case .window:
            availableWindows = WindowInfo.availableWindows()
            
        case .camera:
            break
        }
        #endif
    }
    
    private var canApply: Bool {
        switch selectedSourceType {
        case .camera:
            return true
        case .screen:
            #if os(macOS)
            return selectedScreen != nil
            #else
            return false
            #endif
        case .window:
            #if os(macOS)
            return selectedWindow != nil
            #else
            return false
            #endif
        }
    }
    
    private func applySourceSelection() {
        Task {
            let config: StreamSourceConfig?
            
            switch selectedSourceType {
            case .camera:
                config = nil
                
            case .screen:
                #if os(macOS)
                if let screen = selectedScreen {
                    config = StreamSourceConfig(source: .screen(screen))
                } else {
                    config = nil
                }
                #else
                config = nil
                #endif
                
            case .window:
                #if os(macOS)
                if let window = selectedWindow {
                    config = StreamSourceConfig(source: .window(window))
                } else {
                    config = nil
                }
                #else
                config = nil
                #endif
            }
            
            await viewModel.switchSource(to: selectedSourceType, config: config)
            dismiss()
        }
    }
}

#Preview {
    SourceSelectionView(viewModel: StreamViewModel())
}
