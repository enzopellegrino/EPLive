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
import MediaPlayer
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
    @Published var showBackgroundWarning = false  // Warning quando app va in background
    @Published var isAutoResuming = false  // Indica che sta riprendendo automaticamente
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
    
    // Statistiche streaming in tempo reale
    @Published var stats = StreamingStats()
    
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
    
    // BACKGROUND TASK - Mantiene lo streaming attivo in background
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var keepAliveTimer: Timer?  // Timer per mantenere SRT attivo in background
    
    // AUTO-RESUME STATE - Salva lo stato per riprendere dopo background
    private var wasStreamingBeforeBackground = false
    private var savedVideoTime: Double = 0
    #endif
    
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
        setupBackgroundObservers()  // OSSERVA QUANDO L'APP VA IN BACKGROUND
        
        // NON attivare automaticamente la camera all'avvio
    }
    
    deinit {
        // Il timer si fermerà automaticamente grazie al weak self
        // Non possiamo chiamare stopStatsUpdateTimer() qui perché è @MainActor
        
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
        // Setup AVAudioSession (iOS only) - BACKGROUND VIDEO STREAMING ENABLED
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // USA VIDEOCHAT MODE per dire a iOS che stiamo facendo video streaming
            // Questo mantiene attivo il video encoder anche in background
            try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            print("✅ AVAudioSession configured for VIDEO STREAMING in background")
            print("   Mode: videoChat (keeps video encoder active)")
        } catch {
            print("❌ AVAudioSession setup error: \(error)")
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
                    localVideoStreamer.stats = stats  // Collega le statistiche
                    try await localVideoStreamer.startStreaming(to: stream, loop: loopLocalVideo)
                    print("✅ Local video streaming started")
                }
                
                isStreaming = true
                connectionStatus = "Streaming"
                stats.start()
                startStatsUpdateTimer()
                startBackgroundTask()  // MANTIENE LO STREAMING IN BACKGROUND
                setupNowPlayingInfo()  // INDICATORE LOCK SCREEN
                
                // DISABILITA IDLE TIMER per mantenere app attiva
                #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = true
                print("✅ Idle timer disabled - screen won't auto-lock")
                #endif
                
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
        // IMPORTANTE: ferma PRIMA il timer e le stats per evitare race conditions
        connectionStatus = "Disconnected"
        isStreaming = false
        stopStatsUpdateTimer()
        stats.stop()
        endBackgroundTask()  // TERMINA IL BACKGROUND TASK
        clearNowPlayingInfo()  // RIMUOVI INDICATORE LOCK SCREEN
        
        // RIABILITA IDLE TIMER
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        stopKeepAliveTimer()  // FERMA KEEP-ALIVE TIMER
        print("✅ Idle timer re-enabled")
        #endif
        
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
    
    // MARK: - Statistics Update Timer
    
    private var statsTimer: Timer?
    
    private func startStatsUpdateTimer() {
        stopStatsUpdateTimer()
        
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.updateStats()
            }
        }
        // Aggiungi al RunLoop corrente per evitare che venga deallocato
        RunLoop.main.add(statsTimer!, forMode: .common)
    }
    
    private func stopStatsUpdateTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func updateStats() {
        // Controlli di sicurezza: esci se non stiamo streamando o se gli oggetti sono nil
        guard isStreaming else { 
            stopStatsUpdateTimer()
            return 
        }
        
        guard let sourceType = selectedSourceType else {
            return
        }
        
        // Aggiorna durata
        stats.updateDuration()
        
        // Per camera/screen: stima bytes in base a bitrate e tempo trascorso
        if sourceType == .camera || sourceType == .screen {
            // Calcola quanti frame dovrebbero essere stati inviati
            let fps = Double(selectedQuality.fps)
            let framesShouldBeSent = Int(stats.streamingDuration * fps)
            
            // Aggiorna contatori se necessario (stima)
            if stats.videoFramesSent < framesShouldBeSent {
                let framesToAdd = framesShouldBeSent - stats.videoFramesSent
                let bitrateBytes = Double(selectedQuality.bitrate)
                let bytesPerFrame = Int(bitrateBytes / 8.0 / fps)
                
                for _ in 0..<framesToAdd {
                    stats.recordVideoFrame(bytes: bytesPerFrame)
                }
            }
            
            // Audio: stima 48kHz stereo 16-bit AAC
            let audioSamplesShouldBeSent = Int(stats.streamingDuration * 48000.0 / 1024.0)
            if stats.audioSamplesSent < audioSamplesShouldBeSent {
                let samplesToAdd = audioSamplesShouldBeSent - stats.audioSamplesSent
                for _ in 0..<samplesToAdd {
                    stats.recordAudioSample(bytes: 2048)
                }
            }
        }
        
        // Aggiorna bitrate (calcola dai bytes accumulati)
        stats.updateBitrates()
        
        // Debug logging ogni 5 secondi
        if Int(stats.streamingDuration) % 5 == 0 && stats.streamingDuration > 0 {
            print("📊 Stats Update - Duration: \(stats.durationString), Bitrate: \(stats.bitrateString), FPS: \(stats.fpsString)")
            print("   Video: \(stats.videoFramesSent) frames, Audio: \(stats.audioSamplesSent) samples")
            print("   Total: \(stats.totalDataString)")
        }
        
        // Aggiorna FPS in base alla sorgente
        if sourceType == .localVideo {
            // Per video locale: il LocalVideoStreamer aggiorna già i FPS reali ogni secondo
            // Non facciamo nulla qui per evitare di sovrascrivere
        } else if sourceType == .camera || sourceType == .screen {
            // Camera/Screen: usa il target fps della qualità
            stats.updateFPS(framesInLastSecond: Int(selectedQuality.fps))
        }
        
        // Aggiorna info sulla lock screen ogni secondo
        updateNowPlayingInfo()
    }
    
    // MARK: - Background Task Management
    
    #if canImport(UIKit)
    private func startBackgroundTask() {
        endBackgroundTask()  // Assicurati di terminare eventuali task precedenti
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Chiamato quando iOS sta per terminare il background task
            print("⚠️ Background task expiring, iOS will suspend app soon")
            self?.endBackgroundTask()
        }
        
        print("🌙 Background task started (ID: \(backgroundTaskID.rawValue))")
        print("   App can now stream in background for ~180 seconds")
        print("   Audio session + Background Modes will extend this indefinitely")
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            print("🌙 Ending background task (ID: \(backgroundTaskID.rawValue))")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    #else
    // macOS non ha background tasks
    private func startBackgroundTask() {}
    private func endBackgroundTask() {}
    #endif
    
    // MARK: - Lock Screen Integration (Now Playing)
    
    #if canImport(UIKit)
    private func setupNowPlayingInfo() {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        
        // Titolo principale
        nowPlayingInfo[MPMediaItemPropertyTitle] = "🔴 Live Streaming"
        
        // Server di destinazione
        if let server = currentServer {
            nowPlayingInfo[MPMediaItemPropertyArtist] = server.name
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = server.url
        }
        
        // Immagine icona (opzionale - puoi usare l'icona dell'app)
        if let appIcon = UIImage(named: "AppIcon") {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: appIcon.size) { _ in appIcon }
        }
        
        // Durata (inizialmente 0)
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        
        // Configura i controlli remoti
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Disabilita play/pause (non ha senso per streaming live)
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.isEnabled = false
        
        // Abilita stop command per fermare lo streaming dalla lock screen
        commandCenter.stopCommand.isEnabled = true
        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopStreaming()
            }
            return .success
        }
        
        print("🔒 Lock screen info configured")
        print("   User can now see streaming status on lock screen")
        print("   Press STOP on lock screen to end stream")
    }
    
    private func updateNowPlayingInfo() {
        guard isStreaming else { return }
        
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [String: Any]()
        
        // Aggiorna titolo con statistiche live
        let sourceEmoji: String
        switch selectedSourceType {
        case .camera: 
            sourceEmoji = "📹"
        case .screen: 
            sourceEmoji = "🖥️"
        case .window:
            sourceEmoji = "🪟"
        case .localVideo: 
            sourceEmoji = "🎬"
        case .none: 
            sourceEmoji = "🔴"
        }
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = "\(sourceEmoji) Live Streaming"
        
        // Sottotitolo con bitrate e FPS
        let subtitle = "\(stats.bitrateString) • \(stats.fpsString)"
        nowPlayingInfo[MPMediaItemPropertyArtist] = subtitle
        
        // Durata aggiornata
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = stats.streamingDuration
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Rimuovi i command handlers
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.stopCommand.isEnabled = false
        commandCenter.stopCommand.removeTarget(nil)
        
        print("🔒 Lock screen info cleared")
    }
    #else
    // macOS non ha MPNowPlayingInfoCenter
    private func setupNowPlayingInfo() {}
    private func updateNowPlayingInfo() {}
    private func clearNowPlayingInfo() {}
    #endif
    
    // MARK: - Background/Foreground Observers
    
    #if canImport(UIKit)
    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        print("🌙 App entered background - streaming: \(isStreaming)")
        
        guard isStreaming else { return }
        
        // SOLUZIONE: STOP automatico quando va in background
        // Verrà riavviato automaticamente quando torna in foreground
        
        print("🛑 AUTO-STOPPING streaming (iOS cannot encode video in background)")
        
        // Salva lo stato per auto-resume
        wasStreamingBeforeBackground = true
        
        // Salva posizione video se stiamo streamando video locale
        if selectedSourceType == .localVideo {
            savedVideoTime = localVideoStreamer.currentTime
            print("   📍 Saved video position: \(savedVideoTime)s")
        }
        
        // Mostra warning
        showBackgroundWarning = true
        
        // STOP lo streaming (ma mantieni il setup)
        Task { @MainActor in
            // Ferma solo la parte streaming, non resettare la sorgente
            connectionStatus = "Paused (Background)"
            isStreaming = false
            stopStatsUpdateTimer()
            stats.stop()
            
            // Stop local video se attivo
            if selectedSourceType == .localVideo {
                localVideoStreamer.stopStreaming()
            }
            
            // Close SRT connection
            await srtStream?.close()
            await srtConnection?.close()
            
            print("   ✅ Streaming stopped cleanly")
            print("   Will auto-resume when app returns to foreground")
        }
    }
    
    @objc private func appWillEnterForeground() {
        print("☀️ App will enter foreground")
        
        // Nascondi il warning
        showBackgroundWarning = false
        
        // AUTO-RESUME se stava streamando prima di andare in background
        guard wasStreamingBeforeBackground else {
            print("   No streaming to resume")
            return
        }
        
        wasStreamingBeforeBackground = false
        isAutoResuming = true  // Mostra feedback all'utente
        
        print("🔄 AUTO-RESUMING streaming after background pause")
        
        Task { @MainActor in
            // Piccolo delay per lasciare che l'app si stabilizzi
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            
            // Re-setup dello stream
            if selectedSourceType == .localVideo {
                await setupStreamForLocalVideo()
            } else {
                await setupHaishinKitPreview()
            }
            
            // Piccolo altro delay
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            
            // Riavvia lo streaming
            guard let server = currentServer else {
                print("   ❌ No server configured")
                isAutoResuming = false
                return
            }
            
            guard let urlObj = URL(string: server.url) else {
                print("   ❌ Invalid server URL")
                isAutoResuming = false
                return
            }
            
            do {
                print("   🔗 Reconnecting to SRT server: \(server.url)")
                
                // Connect
                try await srtConnection?.open(urlObj)
                await srtStream?.publish()
                
                // Se video locale, riavvia da dove si era fermato
                if selectedSourceType == .localVideo, let stream = srtStream {
                    print("   🎬 Resuming local video from \(savedVideoTime)s")
                    localVideoStreamer.stats = stats
                    try await localVideoStreamer.startStreaming(
                        to: stream,
                        loop: loopLocalVideo,
                        startTime: savedVideoTime
                    )
                }
                
                // Riavvia tutto
                isStreaming = true
                connectionStatus = "Streaming"
                stats.start()
                startStatsUpdateTimer()
                setupNowPlayingInfo()
                
                #if os(iOS)
                UIApplication.shared.isIdleTimerDisabled = true
                #endif
                
                isAutoResuming = false
                print("   ✅ Streaming AUTO-RESUMED successfully!")
                
            } catch {
                print("   ❌ Failed to auto-resume streaming: \(error)")
                isAutoResuming = false
                errorMessage = "Auto-resume fallito: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    // Keep-alive timer per mantenere SRT attivo in background
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        
        var lastFrameCount = 0
        var stuckCount = 0
        
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isStreaming else { return }
            
            Task { @MainActor in
                // Controlla se i frame stanno aumentando
                let currentFrames = self.stats.videoFramesSent
                
                if currentFrames == lastFrameCount {
                    stuckCount += 1
                    print("⚠️ Video encoder appears stuck in background")
                    print("   Frames not increasing: \(currentFrames)")
                    print("   This is an iOS limitation for background video encoding")
                    
                    if stuckCount >= 3 {
                        // Dopo 6 secondi di freeze, prova a "svegliare" l'encoder
                        print("🔄 Attempting to wake up video encoder...")
                        
                        // Forza una piccola operazione sull'asset reader per svegliare l'encoder
                        if self.selectedSourceType == .localVideo {
                            // Il LocalVideoStreamer continua a girare, ma l'encoder è sospeso
                            // Purtroppo iOS blocca il video encoding in background
                            print("   VIDEO ENCODING SUSPENDED BY iOS")
                            print("   Will resume automatically when app returns to foreground")
                        }
                        stuckCount = 0
                    }
                } else {
                    // Frame stanno aumentando - tutto ok!
                    stuckCount = 0
                    if Int(self.stats.streamingDuration) % 10 == 0 {
                        print("✅ Background streaming working: \(currentFrames) frames sent")
                    }
                }
                
                lastFrameCount = currentFrames
                
                // Controlla anche connessione SRT
                if let connection = self.srtConnection, !connection.connected {
                    print("⚠️ SRT connection lost in background!")
                }
            }
        }
        
        RunLoop.main.add(keepAliveTimer!, forMode: .common)
        print("⏰ Keep-alive monitor started (2s interval)")
        print("   Will detect if video encoding stops in background")
    }
    
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    #else
    private func setupBackgroundObservers() {}
    #endif

}

