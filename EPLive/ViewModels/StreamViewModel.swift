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
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let selectedQuality = "viewmodel.selectedQuality"
    }
    
    private let defaults = UserDefaults.standard
    
    @Published var isStreaming = false
    @Published var isPreviewing = false
    @Published var isPreviewVisible = true  // Per nascondere preview e risparmiare batteria
    @Published var connectionStatus: String = "Disconnected"
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var cameraPermissionGranted = false
    @Published var currentServer: SRTServer?
    @Published var selectedQuality: VideoQuality = .ultra {
        didSet {
            defaults.set(selectedQuality.rawValue, forKey: Keys.selectedQuality)
        }
    }
    
    // Stream source - NON salvare automaticamente, utente sceglie ogni volta
    @Published var selectedSourceType: StreamSourceType? = nil
    @Published var isSourceActive = false  // Indica se una sorgente è stata attivata
    @Published var selectedVideoURL: URL?
    @Published var loopLocalVideo: Bool = true
    
    // Local video streamer
    let localVideoStreamer = LocalVideoStreamer()
    
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
        // Load saved quality
        if let qualityRaw = defaults.string(forKey: Keys.selectedQuality),
           let quality = VideoQuality(rawValue: qualityRaw) {
            selectedQuality = quality
        }
        
        // NON caricare la sorgente - l'utente deve scegliere ogni volta
        
        currentServer = serverManager.defaultServer
        setupBindings()
        checkPermissions()
        setupOrientationObserver()
        
        // NON attivare automaticamente la camera all'avvio
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
        // macOS: applica la rotazione basata sulle impostazioni
        applyStreamRotation()
        #endif
    }
    
    /// Applica la rotazione della camera allo stream (per il video trasmesso)
    func applyStreamRotation() {
        guard let stream = srtStream else { return }
        
        // Converti la rotazione utente in AVCaptureVideoOrientation
        let rotation = streamingSettings.cameraRotation
        let videoOrientation: AVCaptureVideoOrientation
        
        switch rotation {
        case .rotate0:
            videoOrientation = .portrait
        case .rotate90:
            videoOrientation = .landscapeRight
        case .rotate180:
            videoOrientation = .portraitUpsideDown
        case .rotate270:
            videoOrientation = .landscapeLeft
        }
        
        stream.videoOrientation = videoOrientation
        print("Applied stream rotation: \(rotation.displayName) -> orientation \(videoOrientation.rawValue)")
    }
    
    private func setupBindings() {
        // Propaga i cambiamenti di StreamingSettings verso la ViewModel
        streamingSettings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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
        
        // Observer per cambi di rotazione camera (iOS e macOS)
        streamingSettings.$cameraRotation
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyStreamRotation()
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
    
    // MARK: - Source Activation
    
    /// Attiva la sorgente camera
    func activateCameraSource() async {
        guard cameraPermissionGranted else {
            errorMessage = "Permessi camera non concessi"
            showError = true
            return
        }
        
        // Ferma il video locale se attivo
        if selectedSourceType == .localVideo {
            localVideoStreamer.stopStreaming()
        }
        
        selectedSourceType = .camera
        selectedVideoURL = nil
        isSourceActive = true
        
        // Setup camera preview
        await setupHaishinKitPreview()
    }
    
    /// Attiva la sorgente video locale
    func activateLocalVideoSource(url: URL) async {
        do {
            print("🎥 Activating local video source: \(url.lastPathComponent)")
            
            // Stop streaming se attivo
            if isStreaming {
                print("⏹️ Stopping active streaming before switching to video")
                stopStreaming()
                // Aspetta che lo streaming si fermi completamente
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
            
            // Scollega completamente la camera se attiva
            if selectedSourceType == .camera {
                print("📷 Detaching camera before loading video")
                try? await srtStream?.attachCamera(nil)
                try? await srtStream?.attachAudio(nil)
                isPreviewing = false
                srtStream = nil // Reset stream
            }
            
            // Carica il video
            print("📥 Loading video file...")
            try await localVideoStreamer.loadVideo(from: url)
            
            // Aggiorna lo stato
            selectedSourceType = .localVideo
            selectedVideoURL = url
            isSourceActive = true
            isPreviewVisible = true // Abilita preview
            
            print("✅ Video source activated - ready for preview")
            
            // Setup stream per video locale (senza camera)
            await setupStreamForLocalVideo()
            
        } catch {
            print("❌ Error activating video source: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    /// Disattiva la sorgente corrente
    func deactivateSource() {
        print("🔙 Deactivating current source: \(selectedSourceType?.rawValue ?? "none")")
        
        // Stop streaming se attivo
        if isStreaming {
            print("⏹️ Stopping active streaming")
            stopStreaming()
        }
        
        // Stop video locale se attivo
        if selectedSourceType == .localVideo {
            print("⏹️ Stopping local video streamer")
            localVideoStreamer.stopStreaming()
        }
        
        // Reset source state
        selectedSourceType = nil
        selectedVideoURL = nil
        isSourceActive = false
        isPreviewing = false
        isPreviewVisible = true // Reset preview visibility
        
        print("🧹 Cleaning up stream resources")
        
        // Cleanup stream completamente
        Task {
            await MainActor.run {
                // Scollega camera e audio
                Task {
                    try? await srtStream?.attachCamera(nil)
                    try? await srtStream?.attachAudio(nil)
                }
                
                // Reset stream
                srtStream = nil
                print("✅ Source deactivated and cleaned up")
            }
        }
    }
    
    // MARK: - Preview (uses HaishinKit stream without connection)
    
    /// Setup stream per video locale (senza camera)
    private func setupStreamForLocalVideo() async {
        print("🔧 Setting up stream for LOCAL VIDEO - NO CAMERA")
        
        // Setup AVAudioSession (iOS only) - configurazione per playback e registrazione
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Usa playback per permettere l'audio del video
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("✅ AVAudioSession configured for video playback with audio")
        } catch {
            print("❌ AVAudioSession setup error: \(error)")
        }
        #endif
        
        // Create connection and stream if needed
        if srtConnection == nil {
            srtConnection = SRTConnection()
            srtStream = SRTStream(connection: srtConnection!)
            applyVideoQuality()
        }
        
        // IMPORTANTE: Assicurati che la camera NON sia attaccata
        try? await srtStream?.attachCamera(nil)
        try? await srtStream?.attachAudio(nil)
        
        print("✅ Stream ready for local video - camera explicitly detached")
    }
    
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
        
        // SOLO per camera - non controllare selectedSourceType
        
        // Attach camera for preview
        // Su macOS, preferisci webcam esterne (hanno .unspecified position)
        #if os(macOS)
        let externalCamera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first
        
        if let camera = externalCamera {
            do {
                try await srtStream?.attachCamera(camera)
                print("Attached camera: \(camera.localizedName)")
            } catch {
                print("Error attaching camera: \(error)")
            }
        }
        #else
        // iOS: usa la camera migliore (triple > dual > wide) per supportare zoom 0.5x-15x
        if let camera = getBestCamera(for: currentCameraPosition) {
            do {
                try await srtStream?.attachCamera(camera)
                calibrateZoomScale()
                
                // Apply torch if enabled
                if streamingSettings.enableTorch && camera.hasTorch {
                    try camera.lockForConfiguration()
                    try camera.setTorchModeOn(level: streamingSettings.torchLevel)
                    camera.unlockForConfiguration()
                }
                
                // Imposta zoom iniziale a 1x reale (wide lens)
                setupInitialZoom()
                
                print("Attached camera: \(camera.localizedName)")
            } catch {
                print("Error attaching camera: \(error)")
            }
        }
        #endif
        
        // Set initial video orientation
        #if os(iOS)
        // iOS: imposta sempre portrait come default iniziale
        srtStream?.videoOrientation = .portrait
        #else
        // macOS: applica la rotazione dalle impostazioni
        applyStreamRotation()
        #endif
        
        // Attach microphone (sempre, anche per video locale)
        if let mic = AVCaptureDevice.default(for: .audio) {
            do {
                try await srtStream?.attachAudio(mic)
            } catch {
                print("Error attaching audio: \(error)")
            }
        }
        
        isPreviewing = true
    }
    
    /// Cambia sorgente tra camera e video locale
    func switchToCamera() async {
        selectedSourceType = .camera
        localVideoStreamer.stopStreaming()
        await setupHaishinKitPreview()
    }
    
    func switchToLocalVideo() async {
        guard selectedVideoURL != nil else { return }
        selectedSourceType = .localVideo
        // Scollega la camera
        try? await srtStream?.attachCamera(nil)
        print("Switched to local video source")
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
        // For local video, we don't need camera permission
        if selectedSourceType == .camera {
            guard cameraPermissionGranted else {
                errorMessage = "Camera permission not granted"
                showError = true
                return
            }
        }
        
        if selectedSourceType == .localVideo {
            guard selectedVideoURL != nil else {
                errorMessage = "Nessun video selezionato"
                showError = true
                return
            }
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
                print("🚀 Starting streaming - source: \(selectedSourceType?.rawValue ?? "none")")
                
                // Setup stream if not already done - USA LA FUNZIONE GIUSTA IN BASE ALLA SORGENTE
                if srtStream == nil {
                    print("🔧 Setting up stream for \(selectedSourceType?.rawValue ?? "unknown")")
                    if selectedSourceType == .localVideo {
                        await setupStreamForLocalVideo()
                    } else {
                        await setupHaishinKitPreview()
                    }
                }
                
                // IMPORTANTE: Se stiamo streamando video locale, assicurati che la camera NON sia attaccata
                if selectedSourceType == .localVideo {
                    print("🎥 Ensuring camera is detached for local video streaming")
                    try? await srtStream?.attachCamera(nil)
                    try? await srtStream?.attachAudio(nil)
                }
                
                guard let urlObj = URL(string: server.url) else {
                    throw StreamingError.invalidURL
                }
                
                print("🔗 Connecting to SRT server: \(server.url)")
                
                // Connect and publish
                try await srtConnection?.open(urlObj)
                await srtStream?.publish()
                
                print("✅ SRT connection established and publishing")
                
                // If streaming local video, start the video streamer
                if selectedSourceType == .localVideo, let stream = srtStream {
                    print("🎬 Starting local video streaming...")
                    try await localVideoStreamer.startStreaming(to: stream, loop: loopLocalVideo)
                    print("✅ Local video streaming started")
                }
                
                isStreaming = true
                connectionStatus = "Streaming"
                print("✅ Streaming active")
            } catch {
                print("❌ Streaming error: \(error)")
                errorMessage = error.localizedDescription
                showError = true
                connectionStatus = "Error"
            }
        }
    }
    
    func stopStreaming() {
        Task {
            // Stop local video streaming if active
            if selectedSourceType == .localVideo {
                localVideoStreamer.stopStreaming()
            }
            
            // Stop publishing but keep stream alive for preview
            await srtStream?.close()
            await srtConnection?.close()
            
            // Re-setup for preview
            await setupHaishinKitPreview()
        }
        
        connectionStatus = "Disconnected"
        isStreaming = false
    }
    
    // MARK: - Local Video
    
    /// Load a local video file for streaming (usa activateLocalVideoSource)
    func loadLocalVideo(from url: URL) async {
        await activateLocalVideoSource(url: url)
    }
    
    // MARK: - Camera Controls
    
    func switchCamera() {
        Task {
            #if os(iOS)
            // Toggle between front and back camera
            let newPosition: AVCaptureDevice.Position = (currentCameraPosition == .back) ? .front : .back
            
            // Usa la camera migliore (triple/dual/wide) per supportare zoom 0.5x-15x
            if let camera = getBestCamera(for: newPosition) {
                do {
                    try await srtStream?.attachCamera(camera)
                    currentCameraPosition = newPosition
                    calibrateZoomScale()
                    
                    // Dopo flip, imposta 1x reale (wide lens)
                    setupInitialZoom()
                    
                    // Torch is only available on back camera
                    if newPosition == .front {
                        streamingSettings.enableTorch = false
                    }
                    
                    print("Switched to \(newPosition == .front ? "front" : "back") camera: \(camera.localizedName)")
                } catch {
                    print("Error switching camera: \(error)")
                }
            }
            #else
            // macOS: cycle through available cameras
            let cameras = availableCameras
            if let currentIndex = cameras.firstIndex(where: { $0.position == currentCameraPosition || currentCameraPosition == .unspecified }) {
                let nextIndex = (currentIndex + 1) % cameras.count
                let nextCamera = cameras[nextIndex]
                do {
                    try await srtStream?.attachCamera(nextCamera)
                    currentCameraPosition = nextCamera.position
                    applyStreamRotation()
                    print("Switched to camera: \(nextCamera.localizedName)")
                } catch {
                    print("Error switching camera: \(error)")
                }
            }
            #endif
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
    
    /// Ottiene la camera migliore per la posizione specificata (triple > dual > wide)
    /// Questo permette lo zoom continuo da 0.5x a 15x sui dispositivi supportati
    private func getBestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        #if os(iOS)
        // Preferiamo le virtual device cameras che supportano lo zoom continuo
        // incluso il passaggio automatico tra le lenti
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            return triple
        }
        if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            return dual
        }
        // Fallback alla wide angle camera standard
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
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
        #if os(iOS)
        guard currentCameraPosition == .back else {
            streamingSettings.enableTorch = false
            return
        }
        
        // Trova la camera attiva
        let camera: AVCaptureDevice?
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            camera = triple
        } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            camera = dual
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        
        guard let device = camera, device.hasTorch else {
            streamingSettings.enableTorch = false
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            if device.torchMode == .off {
                try device.setTorchModeOn(level: streamingSettings.torchLevel)
                streamingSettings.enableTorch = true
            } else {
                device.torchMode = .off
                streamingSettings.enableTorch = false
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error toggling torch: \(error)")
            // Sincronizza lo stato con il dispositivo reale
            streamingSettings.enableTorch = device.torchMode != .off
        }
        #endif
    }
    
    func setTorchLevel(_ level: Float) {
        #if os(iOS)
        guard currentCameraPosition == .back,
              streamingSettings.enableTorch else { return }
        
        let camera: AVCaptureDevice?
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            camera = triple
        } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            camera = dual
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        
        guard let device = camera, device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            try device.setTorchModeOn(level: level)
            device.unlockForConfiguration()
            streamingSettings.torchLevel = level
        } catch {
            print("Error setting torch level: \(error)")
        }
        #endif
    }
    
    var isTorchAvailable: Bool {
        #if os(iOS)
        guard currentCameraPosition == .back else { return false }
        
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return triple.hasTorch
        } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dual.hasTorch
        } else if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return wide.hasTorch
        }
        return false
        #else
        return false
        #endif
    }
    
    // MARK: - Zoom Control
    
    @Published var currentZoomFactor: CGFloat = 1.0
    // Scala di visualizzazione: usa i valori raw (1.0 = 1x)
    @Published var zoomDisplayScale: CGFloat = 1.0
    
    var minZoomFactor: CGFloat {
        #if os(iOS)
        // Usa virtual device per supportare zoom sotto 1x (ultra-wide 0.5x)
        let camera: AVCaptureDevice?
        if currentCameraPosition == .back {
            if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                camera = triple
            } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                camera = dual
            } else {
                camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        let minRaw = camera?.minAvailableVideoZoomFactor ?? 1.0
        return minRaw
        #else
        return 1.0
        #endif
    }
    
    var maxZoomFactor: CGFloat {
        #if os(iOS)
        let camera: AVCaptureDevice?
        if currentCameraPosition == .back {
            if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                camera = triple
            } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                camera = dual
            } else {
                camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        // Limita a 15x per evitare zoom eccessivo (iPhone supporta fino a 15x)
        return min(camera?.maxAvailableVideoZoomFactor ?? 1.0, 15.0)
        #else
        return 1.0
        #endif
    }
    
    func setZoom(_ factor: CGFloat) {
        #if os(iOS)
        let camera: AVCaptureDevice?
        if currentCameraPosition == .back {
            if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                camera = triple
            } else if let dual = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                camera = dual
            } else {
                camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }
        } else {
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
        
        guard let device = camera else { return }
        
        let clampedFactor = max(device.minAvailableVideoZoomFactor, min(factor, min(device.maxAvailableVideoZoomFactor, 15.0)))
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
            currentZoomFactor = clampedFactor
        } catch {
            print("Error setting zoom: \(error)")
        }
        #endif
    }

    private func calibrateZoomScale() {
        #if os(iOS)
        // Su virtual device (triple/dual camera), raw 2.0 = 1x visuale, quindi scala = 0.5
        // Su device normali, raw 1.0 = 1x visuale, scala = 1.0
        if let camera = getBestCamera(for: currentCameraPosition) {
            let isVirtualDevice = camera.deviceType == .builtInTripleCamera || camera.deviceType == .builtInDualWideCamera
            zoomDisplayScale = isVirtualDevice ? 0.5 : 1.0
        } else {
            zoomDisplayScale = 1.0
        }
        #else
        zoomDisplayScale = 1.0
        #endif
    }

    /// Imposta lo zoom iniziale in modo che la lente wide corrisponda a 1x visuale
    private func setupInitialZoom() {
        #if os(iOS)
        // Su virtual device, imposta raw 2.0 per avere 1x visuale
        // Su device normali, imposta raw 1.0
        if let camera = getBestCamera(for: currentCameraPosition) {
            let isVirtualDevice = camera.deviceType == .builtInTripleCamera || camera.deviceType == .builtInDualWideCamera
            let targetRaw: CGFloat = isVirtualDevice ? 2.0 : 1.0
            setZoom(targetRaw)
        } else {
            setZoom(1.0)
        }
        #endif
    }
    
    func handlePinchZoom(scale: CGFloat) {
        let newZoom = currentZoomFactor * scale
        setZoom(newZoom)
    }
    
    func resetZoom() {
        // Imposta 1x "visuale" (wide), mappato su fattore raw
        setupInitialZoom()
    }

    // MARK: - Zoom Display mapping
    func setZoomDisplay(_ displayFactor: CGFloat) {
        let raw = displayFactor / max(zoomDisplayScale, 0.0001)
        setZoom(raw)
    }
    
    var currentDisplayZoomFactor: CGFloat {
        currentZoomFactor * zoomDisplayScale
    }
}
