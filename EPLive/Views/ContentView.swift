//
//  ContentView.swift
//  EPLive
//
//  Created on 12/12/2025.
//  Professional camera-style interface
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = StreamViewModel()
    @State private var showSettings = false
    @State private var showSourcePicker = false
    @State private var lastZoomScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                // Camera Preview - Full screen
                if viewModel.isPreviewVisible {
                    CameraPreviewView(viewModel: viewModel)
                        .ignoresSafeArea()
                        #if os(iOS)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    let newZoom = lastZoomScale * scale
                                    viewModel.setZoom(newZoom)
                                }
                                .onEnded { _ in
                                    lastZoomScale = viewModel.currentZoomFactor
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                // Toggle 1x <-> 2x (se supportato); altrimenti resta su 1x
                                let minZ = viewModel.minZoomFactor
                                let maxZ = viewModel.maxZoomFactor
                                let target: CGFloat
                                if abs(viewModel.currentZoomFactor - 2.0) < 0.01 || 2.0 > maxZ {
                                    target = 1.0
                                } else {
                                    target = min(max(2.0, minZ), maxZ)
                                }
                                viewModel.setZoom(target)
                                lastZoomScale = viewModel.currentZoomFactor
                            }
                        )
                        #endif
                } else {
                    // Black screen quando preview disabilitato
                    Color.black
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Preview Disabilitato")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Lo streaming continua in background")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                // Camera overlay UI
                VStack(spacing: 0) {
                    // Top bar - minimal info
                    TopBarView(
                        isStreaming: viewModel.isStreaming,
                        serverName: viewModel.currentServer?.name,
                        quality: viewModel.selectedQuality,
                        showSettings: $showSettings,
                        showSourcePicker: $showSourcePicker
                    )
                    
                    Spacer()
                    
                    #if os(iOS)
                    // Nessuna HUD qui: verrà mostrata come overlay in basso a destra
                    #endif
                    
                    Spacer()
                    
                    // Bottom controls - camera style
                    BottomControlsView(
                        isStreaming: viewModel.isStreaming,
                        isPreviewVisible: viewModel.isPreviewVisible,
                        onRecord: {
                            if viewModel.isStreaming {
                                viewModel.stopStreaming()
                            } else {
                                viewModel.startStreaming()
                            }
                        },
                        onTogglePreview: {
                            viewModel.isPreviewVisible.toggle()
                        },
                        onSwitchCamera: {
                            viewModel.switchCamera()
                            viewModel.resetZoom()
                            lastZoomScale = 1.0
                        },
                        onTorch: {
                            viewModel.toggleTorch()
                        },
                        isTorchOn: viewModel.streamingSettings.enableTorch,
                        isTorchAvailable: viewModel.isTorchAvailable
                    )
                }

                // Barra zoom verticale sulla destra - adattiva per landscape
                #if os(iOS)
                if viewModel.isPreviewVisible {
                    GeometryReader { geo in
                        let isLandscape = geo.size.width > geo.size.height
                        VerticalZoomSlider(
                            value: viewModel.currentZoomFactor,
                            min: viewModel.minZoomFactor,
                            max: viewModel.maxZoomFactor,
                            displayScale: viewModel.zoomDisplayScale,
                            compact: isLandscape,
                            onSet: { viewModel.setZoom($0); lastZoomScale = $0 },
                            onReset: { viewModel.resetZoom(); lastZoomScale = viewModel.currentZoomFactor }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                        .padding(.top, isLandscape ? 60 : 100)
                        .padding(.bottom, isLandscape ? 20 : 120)
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 600)
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        // TODO: Fix SourcePickerView compilation errors
        // .sheet(isPresented: $showSourcePicker) {
        //     SourcePickerView(viewModel: viewModel)
        // }
        .alert("Errore", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "Errore sconosciuto")
        }
        #if os(iOS)
        .statusBar(hidden: true)
        #endif
    }
}

// MARK: - Top Bar View (minimal)
struct TopBarView: View {
    let isStreaming: Bool
    let serverName: String?
    let quality: VideoQuality
    @Binding var showSettings: Bool
    @Binding var showSourcePicker: Bool
    
    var body: some View {
        HStack {
            // Stato streaming
            HStack(spacing: 6) {
                Circle()
                    .fill(isStreaming ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(isStreaming ? "LIVE" : "IDLE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // Server e qualità
            HStack(spacing: 10) {
                if let name = serverName {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text(quality.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
            
            // Azioni
            HStack(spacing: 12) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.6), Color.clear]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Vertical Zoom Slider (destra schermo)
struct VerticalZoomSlider: View {
    let value: CGFloat
    let min: CGFloat
    let max: CGFloat
    let displayScale: CGFloat  // 0.5 per virtual device, 1.0 per altri
    var compact: Bool = false  // modalità compatta per landscape
    let onSet: (CGFloat) -> Void
    let onReset: () -> Void
    
    private var sliderHeight: CGFloat { compact ? 120 : 200 }
    
    // Valori visualizzati (0.5x, 1x, 2x, etc)
    private var displayValue: CGFloat { value * displayScale }
    private var displayMin: CGFloat { min * displayScale }
    private var displayMax: CGFloat { max * displayScale }
    
    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            // Pulsante +
            Button(action: { step(0.2) }) {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // Slider verticale
            ZStack(alignment: .bottom) {
                // Track sfondo
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: sliderHeight)
                
                // Track riempimento
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.yellow)
                    .frame(width: 6, height: fillHeight)
                
                // Indicatore 1x (solo se non compact)
                if !compact {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 14, height: 2)
                        Text("1x")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(y: -oneXOffset)
                }
            }
            .frame(width: compact ? 40 : 50, height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = sliderHeight - drag.location.y
                        let clamped = Swift.max(0, Swift.min(y, sliderHeight))
                        let progress = clamped / sliderHeight
                        let newValue = min + (max - min) * progress
                        onSet(newValue)
                    }
            )
            
            // Pulsante -
            Button(action: { step(-0.2) }) {
                Image(systemName: "minus")
                    .font(.system(size: compact ? 14 : 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            // Valore corrente e reset
            Button(action: onReset) {
                Text(format(displayValue))
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, compact ? 6 : 10)
                    .padding(.vertical, compact ? 4 : 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, compact ? 4 : 8)
        .padding(.horizontal, compact ? 4 : 6)
        .background(Color.black.opacity(0.3))
        .cornerRadius(compact ? 16 : 20)
    }
    
    private var fillHeight: CGFloat {
        let progress = (value - min) / (max - min)
        return sliderHeight * Swift.max(0, Swift.min(progress, 1))
    }
    
    private var oneXOffset: CGFloat {
        // Posizione del marker 1x sulla barra (raw = 1/displayScale per avere 1x visuale)
        let oneXRaw = 1.0 / displayScale
        let progress = (oneXRaw - min) / (max - min)
        return sliderHeight * Swift.max(0, Swift.min(progress, 1))
    }
    
    private func step(_ delta: CGFloat) {
        // delta è in unità visuali, converti in raw
        let rawDelta = delta / displayScale
        let next = Swift.max(min, Swift.min(value + rawDelta, max))
        onSet(next)
    }
    
    private func format(_ v: CGFloat) -> String {
        return String(format: "%.1fx", v)
    }
}

// MARK: - Bottom Controls View (camera style)
struct BottomControlsView: View {
    let isStreaming: Bool
    let isPreviewVisible: Bool
    let onRecord: () -> Void
    let onTogglePreview: () -> Void
    let onSwitchCamera: () -> Void
    let onTorch: () -> Void
    let isTorchOn: Bool
    let isTorchAvailable: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - Preview toggle & Torch
            HStack(spacing: 20) {
                // Preview toggle (eye)
                Button(action: onTogglePreview) {
                    VStack(spacing: 4) {
                        Image(systemName: isPreviewVisible ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 24))
                        Text(isPreviewVisible ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(isPreviewVisible ? .white : .gray)
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                
                #if os(iOS)
                // Torch - iOS only (Macs don't have torch)
                if isTorchAvailable {
                    Button(action: onTorch) {
                        VStack(spacing: 4) {
                            Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 24))
                            Text(isTorchOn ? "ON" : "OFF")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(isTorchOn ? .yellow : .gray)
                        .frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            .frame(maxWidth: .infinity)
            
            // Center - Main record button (camera style)
            Button(action: onRecord) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    // Inner button
                    if isStreaming {
                        // Stop square when recording
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        // Red circle when not recording
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Right side - Switch Camera
            HStack(spacing: 20) {
                #if os(iOS)
                // Switch camera - only on iOS devices with multiple cameras
                Button(action: onSwitchCamera) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 24))
                        Text("FLIP")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                #endif
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#Preview {
    ContentView()
}
