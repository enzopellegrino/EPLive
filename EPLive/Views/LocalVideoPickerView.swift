//
//  LocalVideoPickerView.swift
//  EPLive
//
//  View for selecting and managing local video files for streaming
//

import SwiftUI
import AVKit
import PhotosUI

struct LocalVideoPickerView: View {
    @ObservedObject var viewModel: StreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showFilePicker = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isLoadingVideo = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current video info
                if let url = viewModel.selectedVideoURL {
                    currentVideoSection(url: url)
                } else {
                    noVideoSection
                }
                
                Divider()
                
                // Video picker options
                VStack(spacing: 16) {
                    #if os(iOS)
                    // Photos Library picker
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .videos
                    ) {
                        Label("Scegli dalla Libreria Foto", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .onChange(of: selectedPhotoItem) { newItem in
                        Task {
                            await loadFromPhotosLibrary(item: newItem)
                        }
                    }
                    #endif
                    
                    // File picker
                    Button(action: { showFilePicker = true }) {
                        Label("Scegli da File", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                // Options
                if viewModel.selectedVideoURL != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Loop Video", isOn: $viewModel.loopLocalVideo)
                            .padding(.horizontal)
                        
                        Text("Quando attivo, il video ripartirà automaticamente alla fine")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.top)
                }
                
                Spacer()
                
                // Loading indicator
                if isLoadingVideo {
                    ProgressView("Caricamento video...")
                        .padding()
                }
                
                // Local video streamer status
                if viewModel.localVideoStreamer.isPlaying {
                    VStack(spacing: 8) {
                        Text("In riproduzione")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        ProgressView(value: viewModel.localVideoStreamer.progress)
                            .padding(.horizontal)
                        
                        Text(formatTime(viewModel.localVideoStreamer.currentTime) + " / " + formatTime(viewModel.localVideoStreamer.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                }
            }
            .navigationTitle("Video Locale")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    // MARK: - Sections
    
    private func currentVideoSection(url: URL) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "film.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            if viewModel.localVideoStreamer.duration > 0 {
                Text("Durata: \(formatTime(viewModel.localVideoStreamer.duration))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                // Torna alla selezione sorgente
                Button(action: {
                    Task {
                        await viewModel.deactivateSource()
                    }
                }) {
                    Label("Cambia Sorgente", systemImage: "arrow.left.circle")
                        .foregroundColor(.blue)
                }
                
                // Rimuovi video
                Button(action: {
                    Task {
                        await viewModel.deactivateSource()
                    }
                }) {
                    Label("Rimuovi", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .padding()
    }
    
    private var noVideoSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Nessun video selezionato")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Seleziona un video dalla libreria o dai file")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .padding(.vertical, 20)
    }
    
    // MARK: - Helpers
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                loadVideo(from: url)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }
    
    private func loadVideo(from url: URL) {
        isLoadingVideo = true
        Task {
            await viewModel.loadLocalVideo(from: url)
            isLoadingVideo = false
            // Chiudi il picker dopo aver caricato il video
            dismiss()
        }
    }
    
    #if os(iOS)
    private func loadFromPhotosLibrary(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        isLoadingVideo = true
        
        do {
            // Load the video data
            if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                await viewModel.loadLocalVideo(from: movie.url)
                // Chiudi il picker dopo aver caricato il video
                await MainActor.run {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
                viewModel.showError = true
            }
        }
        
        isLoadingVideo = false
    }
    #endif
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Video Transferable for PhotosPicker
#if os(iOS)
struct VideoTransferable: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to a temporary location
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}
#endif

#Preview {
    LocalVideoPickerView(viewModel: StreamViewModel())
}
