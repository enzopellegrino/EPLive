//
//  SourceSelectionView.swift
//  EPLive
//
//  Initial splash view for selecting stream source
//

import SwiftUI

struct SourceSelectionView: View {
    @ObservedObject var viewModel: StreamViewModel
    @Binding var showLocalVideoPicker: Bool
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.3), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Settings button in top right
            VStack {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo/Title
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("EPLive")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Professional Streaming")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("v\(AppVersion.current)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Source selection buttons
                VStack(spacing: 20) {
                    Text("Seleziona Sorgente")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    // Camera button
                    Button(action: {
                        Task {
                            await viewModel.activateCameraSource()
                        }
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Camera")
                                    .font(.headline)
                                Text("Trasmetti in diretta dalla fotocamera")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(!viewModel.cameraPermissionGranted)
                    .opacity(viewModel.cameraPermissionGranted ? 1.0 : 0.5)
                    
                    // Local video button
                    Button(action: {
                        showLocalVideoPicker = true
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "film.fill")
                                .font(.system(size: 28))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Video Locale")
                                    .font(.headline)
                                Text("Trasmetti un file video dal dispositivo")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.8), Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // Permission warning
                    if !viewModel.cameraPermissionGranted {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Permessi camera non concessi")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Server info
                if let server = viewModel.currentServer {
                    VStack(spacing: 4) {
                        Text("Server: \(server.name)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text(server.url)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}

#Preview {
    SourceSelectionView(
        viewModel: StreamViewModel(),
        showLocalVideoPicker: .constant(false)
    )
}
