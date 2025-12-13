//
//  StreamViewModel.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import Foundation
import AVFoundation
import Combine
import SRTHaishinKit
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

enum StreamingError: LocalizedError {
    case invalidURL
    case connectionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid streaming URL"
        case .connectionFailed:
            return "Failed to connect to server"
        }
    }
}

@MainActor
class StreamViewModel: ObservableObject {
    @Published var isStreaming = false
    @Published var isPreviewing = false
    @Published var isPreviewVisible = true  // Per nascondere preview e risparmiare batteria
    @Published var connectionStatus: String = "Disconnected"
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var cameraPermissionGranted = false
    @Published var currentServer: SRTServer?
    @Published var selectedQuality: VideoQuality = .medium
    
    // Advanced settings
    @Published var streamingSettings = StreamingSettings()
    
    let serverManager = ServerManager()
    let cameraManager = CameraManager()  // For permissions check
    
    // HaishinKit components - used for BOTH preview and streaming
    private var srtConnection: SRTConnection?
    @Published private(set) var srtStream: SRTStream?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    
    private var cancellables = Set<AnyCancellable>()
    private var orientationObserver: NSObjectProtocol?
    
    init() {
        currentServer = serverManager.defaultServer
        setupBindings()
        checkPermissions()
        setupOrientationObserver()
    }
    
    deinit {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupOrientationObserver() {
        #if os(iOS)
        // Enable device orientation notifications
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateVideoOrientation()
            }
        }
        #endif
    }
    
    private func updateVideoOrientation() {
        guard let stream = srtStream else { return }
        
        #if os(iOS)
        let orientation = UIDevice.current.orientation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch orientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            // Device rotated left = video should be rotated right
            videoOrientation = .landscapeRight
        case .landscapeRight:
            // Device rotated right = video should be rotated left
            videoOrientation = .landscapeLeft
        default:
            // Keep current orientation for flat/unknown
            return
        }
        
        stream.videoOrientation = videoOrientation
        
        // Applica anche la nuova risoluzione per l'orientamento
        applyVideoQuality()
        #else
        // macOS: usa sempre landscape
        stream.videoOrientation = .landscapeRight
        #endif
    }
    
    private func setupBindings() {
        serverManager.$servers
            .sink { [weak self] servers in
                Task { @MainActor in
                    if let current = self?.currentServer,
                       !servers.contains(where: { $0.id == current.id }) {
                        self?.currentServer = self?.serverManager.defaultServer
                    } else if self?.currentServer == nil {
                        self?.currentServer = self?.serverManager.defaultServer
                    }
                }
            }
            .store(in: &cancellables)
        
        // Observer per cambi di qualità video
        $selectedQuality
            .dropFirst() // Ignora il valore iniziale
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyVideoQuality()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Applica le impostazioni video correnti allo stream
    private func applyVideoQuality() {
        guard let stream = srtStream else { return }
        
        let quality = selectedQuality
        let settings = streamingSettings
        let width = CGFloat(quality.resolution.width)
        let height = CGFloat(quality.resolution.height)
        
        // Determina se siamo in portrait
        #if os(iOS)
        let orientation = UIDevice.current.orientation
        let isPortrait = orientation == .portrait || orientation == .portraitUpsideDown ||
                        (!orientation.isLandscape && !orientation.isPortrait) // Default portrait se flat
        #else
        let isPortrait = false // macOS always landscape
        #endif
        
        let videoSize: CGSize
        if isPortrait {
            videoSize = CGSize(width: min(width, height), height: max(width, height))
        } else {
            videoSize = CGSize(width: max(width, height), height: min(width, height))
        }
        
        // Usa bitrate custom se abilitato, altrimenti usa quello del preset
        let bitrate = settings.useCustomBitrate ? Int(settings.customBitrate) : Int(quality.bitrate)
        
        // Seleziona il profilo H.264 basato sulla risoluzione
        // Level 3.1 supporta fino a 720p, Level 4.0/4.1 fino a 1080p, Level 5.1 per 4K
        let profileLevel: String
        let maxDimension = max(width, height)
        
        switch settings.h264Profile {
        case .baseline:
            if maxDimension > 1920 {
                profileLevel = kVTProfileLevel_H264_Baseline_5_1 as String
            } else if maxDimension > 1280 {
                profileLevel = kVTProfileLevel_H264_Baseline_4_1 as String
            } else {
                profileLevel = kVTProfileLevel_H264_Baseline_3_1 as String
            }
        case .main:
            if maxDimension > 1920 {
                profileLevel = kVTProfileLevel_H264_Main_5_1 as String
            } else if maxDimension > 1280 {
                profileLevel = kVTProfileLevel_H264_Main_4_1 as String
            } else {
                profileLevel = kVTProfileLevel_H264_Main_3_1 as String
            }
        case .high:
            if maxDimension > 1920 {
                profileLevel = kVTProfileLevel_H264_High_5_1 as String
            } else if maxDimension > 1280 {
                profileLevel = kVTProfileLevel_H264_High_4_1 as String
            } else {
                profileLevel = kVTProfileLevel_H264_High_3_1 as String
            }
        }
        
        stream.videoSettings = .init(
            videoSize: videoSize,
            bitRate: bitrate,
            profileLevel: profileLevel,
            maxKeyFrameIntervalDuration: Int32(settings.keyframeInterval.rawValue)
        )
        
        // FPS: usa custom se diverso dal preset
        stream.frameRate = Float64(settings.selectedFPS.rawValue)
        
        // Audio settings
        if settings.enableAudio {
            stream.audioSettings = .init(
                bitRate: settings.audioBitrate.rawValue
            )
        }
        
        print("Applied video quality: \(quality.displayName) - \(videoSize) @ \(settings.selectedFPS.rawValue)fps, \(bitrate/1_000_000)Mbps, profile: \(profileLevel)")
    }
    
    private func checkPermissions() {
        Task {
            cameraPermissionGranted = await cameraManager.requestPermissions()
            if cameraPermissionGranted {
                await setupHaishinKitPreview()
            }
        }
    }
    
    // MARK: - Preview (uses HaishinKit stream without connection)
    
    private func setupHaishinKitPreview() async {
        // Setup AVAudioSession (iOS only)
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup error: \(error)")
        }
        #endif
        
        // Create connection and stream for preview
        srtConnection = SRTConnection()
        srtStream = SRTStream(connection: srtConnection!)
        
        // Apply all video/audio settings
        applyVideoQuality()
        
        // Attach camera for preview
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) {
            do {
                try await srtStream?.attachCamera(camera)
                
                // Apply torch if enabled
                if streamingSettings.enableTorch && camera.hasTorch {
                    try camera.lockForConfiguration()
                    try camera.setTorchModeOn(level: streamingSettings.torchLevel)
                    camera.unlockForConfiguration()
                }
            } catch {
                print("Error attaching camera: \(error)")
            }
        }
        
        // Set initial video orientation
        updateVideoOrientation()
        
        // Attach microphone
        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                try await srtStream?.attachAudio(mic)
            } catch {
                print("Error attaching audio: \(error)")
            }
        }
        
        isPreviewing = true
    }
    
    func startPreview() {
        guard cameraPermissionGranted else {
            errorMessage = "Camera permission not granted"
            showError = true
            return
        }
        
        guard !isPreviewing else { return }
        
        Task {
            await setupHaishinKitPreview()
        }
    }
    
    func stopPreview() {
        guard isPreviewing, !isStreaming else { return }
        
        Task {
            await srtStream?.attachCamera(nil)
            await srtStream?.attachAudio(nil)
            srtStream = nil
            srtConnection = nil
        }
        isPreviewing = false
    }
    
    // MARK: - Streaming (connects the existing stream)
    
    func startStreaming() {
        guard cameraPermissionGranted else {
            errorMessage = "Camera permission not granted"
            showError = true
            return
        }
        
        guard let server = currentServer else {
            errorMessage = "No server selected"
            showError = true
            return
        }
        
        guard server.isValid else {
            errorMessage = "Invalid server URL: \(server.url)"
            showError = true
            return
        }
        
        connectionStatus = "Connecting..."
        
        Task {
            do {
                // Setup stream if not already done
                if srtStream == nil {
                    await setupHaishinKitPreview()
                }
                
                guard let urlObj = URL(string: server.url) else {
                    throw StreamingError.invalidURL
                }
                
                // Connect and publish
                try await srtConnection?.open(urlObj)
                await srtStream?.publish()
                
                isStreaming = true
                connectionStatus = "Streaming"
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                connectionStatus = "Error"
            }
        }
    }
    
    func stopStreaming() {
        Task {
            // Stop publishing but keep stream alive for preview
            await srtStream?.close()
            await srtConnection?.close()
            
            // Re-setup for preview
            await setupHaishinKitPreview()
        }
        
        connectionStatus = "Disconnected"
        isStreaming = false
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() {
        Task {
            // Toggle between front and back camera
            let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back
            
            if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) {
                do {
                    try await srtStream?.attachCamera(camera)
                    currentCameraPosition = newPosition
                    
                    // Torch is only available on back camera
                    if newPosition == .front {
                        streamingSettings.enableTorch = false
                    }
                } catch {
                    print("Error switching camera: \(error)")
                }
            }
        }
    }
    
    private func getCurrentCameraPosition() -> AVCaptureDevice.Position {
        return currentCameraPosition
    }
    
    var availableCameras: [AVCaptureDevice] {
        #if os(iOS)
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        #else
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        #endif
    }
    
    func selectCamera(_ camera: AVCaptureDevice) {
        Task {
            do {
                try await srtStream?.attachCamera(camera)
                currentCameraPosition = camera.position
            } catch {
                print("Error selecting camera: \(error)")
            }
        }
    }
    
    // MARK: - Torch Control
    
    func toggleTorch() {
        guard currentCameraPosition == .back,
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              camera.hasTorch else { return }
        
        do {
            try camera.lockForConfiguration()
            if streamingSettings.enableTorch {
                try camera.setTorchModeOn(level: streamingSettings.torchLevel)
            } else {
                camera.torchMode = .off
            }
            camera.unlockForConfiguration()
        } catch {
            print("Error toggling torch: \(error)")
        }
    }
    
    func setTorchLevel(_ level: Float) {
        guard currentCameraPosition == .back,
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              camera.hasTorch,
              streamingSettings.enableTorch else { return }
        
        do {
            try camera.lockForConfiguration()
            try camera.setTorchModeOn(level: level)
            camera.unlockForConfiguration()
            streamingSettings.torchLevel = level
        } catch {
            print("Error setting torch level: \(error)")
        }
    }
    
    var isTorchAvailable: Bool {
        guard currentCameraPosition == .back,
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return false
        }
        return camera.hasTorch
    }
    
    // MARK: - Zoom Control
    
    @Published var currentZoomFactor: CGFloat = 1.0
    
    var minZoomFactor: CGFloat {
        #if os(iOS)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            return 1.0
        }
        return camera.minAvailableVideoZoomFactor
        #else
        return 1.0
        #endif
    }
    
    var maxZoomFactor: CGFloat {
        #if os(iOS)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            return 1.0
        }
        // Limita a 10x per evitare zoom eccessivo
        return min(camera.maxAvailableVideoZoomFactor, 10.0)
        #else
        return 1.0
        #endif
    }
    
    func setZoom(_ factor: CGFloat) {
        #if os(iOS)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            return
        }
        
        let clampedFactor = max(minZoomFactor, min(factor, maxZoomFactor))
        
        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = clampedFactor
            camera.unlockForConfiguration()
            currentZoomFactor = clampedFactor
        } catch {
            print("Error setting zoom: \(error)")
        }
        #endif
    }
    
    func handlePinchZoom(scale: CGFloat) {
        let newZoom = currentZoomFactor * scale
        setZoom(newZoom)
    }
    
    func resetZoom() {
        setZoom(1.0)
    }
}
