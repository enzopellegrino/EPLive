//
//  SourcePickerView.swift
//  EPLive
//
//  View for selecting streaming sources (camera, screen, window)
//

import SwiftUI
#if os(macOS)
import AppKit
import ScreenCaptureKit
#endif

struct SourcePickerView: View {
    @ObservedObject var viewModel: StreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedType: StreamSourceType = .camera
    @State private var availableCameras: [(id: String, name: String)] = []
    
    #if os(macOS)
    @available(macOS 12.3, *)
    @State private var availableScreens: [SCDisplay] = []
    @available(macOS 12.3, *)
    @State private var availableWindows: [SCWindow] = []
    #endif
     
    var body: some View {
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }
    
    // MARK: - macOS View
    #if os(macOS)
    private var macOSView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Seleziona Sorgente Streaming")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Source type picker
            Picker("Tipo Sorgente", selection: $selectedType) {
                ForEach(StreamSourceType.allCases, id: \.self) { type in
                    HStack {
                        Image(systemName: type.icon)
                        Text(type.description)
                    }
                    .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Source list based on selected type
            ScrollView {
                VStack(spacing: 12) {
                    switch selectedType {
                    case .camera:
                        cameraList
                    case .screen:
                        screenList
                    case .window:
                        windowList
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Annulla") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Aggiorna Lista") {
                    refreshSources()
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            refreshSources()
        }
    }
    
    private var cameraList: some View {
        ForEach(availableCameras, id: \.id) { camera in
            Button(action: {
                selectCamera(camera.id)
            }) {
                HStack {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(camera.name)
                            .font(.headline)
                        Text(camera.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if viewModel.cameraManager.currentCameraID == camera.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var screenList: some View {
        Group {
            if #available(macOS 12.3, *) {
                ForEach(availableScreens, id: \.displayID) { screen in
                    Button(action: {
                        selectScreen(screen)
                    }) {
                        HStack {
                            Image(systemName: "display")
                                .font(.title2)
                                .foregroundColor(.purple)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Schermo \(screen.displayID)")
                                    .font(.headline)
                                Text("\(Int(screen.width)) × \(Int(screen.height))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Screen capture richiede macOS 12.3+")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var windowList: some View {
        Group {
            if #available(macOS 12.3, *) {
                ForEach(availableWindows, id: \.windowID) { window in
                    Button(action: {
                        selectWindow(window)
                    }) {
                        HStack {
                            Image(systemName: "macwindow")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(window.owningApplication?.applicationName ?? "Sconosciuto")
                                    .font(.headline)
                                if let windowTitle = window.title, !windowTitle.isEmpty {
                                    Text(windowTitle)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Text("\(Int(window.frame.width)) × \(Int(window.frame.height))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Window capture richiede macOS 12.3+")
                    .foregroundColor(.secondary)
            }
        }
    }
    #endif
    
    // MARK: - iOS View
    #if os(iOS)
    private var iOSView: some View {
        NavigationView {
            List {
                Section(header: Text("Fotocamere Disponibili")) {
                    ForEach(availableCameras, id: \.id) { camera in
                        Button(action: {
                            selectCamera(camera.id)
                        }) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading) {
                                    Text(camera.name)
                                        .font(.headline)
                                    Text(camera.id)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if viewModel.cameraManager.currentCameraID == camera.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Seleziona Sorgente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Aggiorna") {
                        refreshSources()
                    }
                }
            }
            .onAppear {
                refreshSources()
            }
        }
    }
    #endif
    
    // MARK: - Actions
    private func refreshSources() {
        // Refresh cameras
        availableCameras = viewModel.cameraManager.getAvailableCameras()
        
        #if os(macOS)
        if #available(macOS 12.3, *) {
            // Refresh screens using ScreenCaptureKit
            Task {
                let screens = await ScreenCaptureManager.getAvailableDisplays()
                await MainActor.run {
                    availableScreens = screens
                }
            }
            
            // Refresh windows using ScreenCaptureKit
            Task {
                let windows = await ScreenCaptureManager.getAvailableWindows()
                await MainActor.run {
                    availableWindows = windows
                }
            }
        }
        #endif
    }
    
    private func selectCamera(_ cameraID: String) {
        viewModel.switchToCamera(cameraID)
        dismiss()
    }
    
    #if os(macOS)
    @available(macOS 12.3, *)
    private func selectScreen(_ screen: SCDisplay) {
        // Create ScreenInfo from SCDisplay for compatibility
        let screenInfo = ScreenInfo(
            displayID: screen.displayID,
            name: "Schermo \(screen.displayID)",
            bounds: CGRect(x: 0, y: 0, width: screen.width, height: screen.height)
        )
        viewModel.switchToScreen(screenInfo)
        dismiss()
    }
    
    @available(macOS 12.3, *)
    private func selectWindow(_ window: SCWindow) {
        // Create WindowInfo from SCWindow for compatibility
        let windowInfo = WindowInfo(
            id: Int(window.windowID),
            windowNumber: Int(window.windowID),
            ownerName: window.owningApplication?.applicationName ?? "Sconosciuto",
            windowName: window.title,
            bounds: window.frame
        )
        viewModel.switchToWindow(windowInfo)
        dismiss()
    }
    #endif
}
