//
//  CameraManager.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import Foundation
import AVFoundation
import CoreVideo

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didEncounterError error: Error)
}

class CameraManager: NSObject, ObservableObject {
    weak var delegate: CameraManagerDelegate?
    
    @Published var isRunning = false
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?
    
    // Expose capture session for preview
    var captureSession: AVCaptureSession {
        return _captureSession
    }
    
    private let _captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.eplive.camera.session")
    
    override init() {
        super.init()
        configureSession()
        discoverCameras()
    }
    
    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self._captureSession.beginConfiguration()
            
            // Set session preset
            if self._captureSession.canSetSessionPreset(.hd1280x720) {
                self._captureSession.sessionPreset = .hd1280x720
            }
            
            // Configure video output
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.eplive.camera.video"))
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            
            if self._captureSession.canAddOutput(self.videoOutput) {
                self._captureSession.addOutput(self.videoOutput)
            }
            
            // Configure video connection (stabilization only available on iOS)
            #if os(iOS)
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                // Disabilita mirroring per frontale
                connection.isVideoMirrored = false
                // Orientamento
                if connection.isVideoOrientationSupported {
                    #if os(macOS)
                    connection.videoOrientation = .landscapeLeft
                    #else
                    connection.videoOrientation = .portrait
                    #endif
                }
            }
            #endif
            
            // TODO: Configure audio output (richiede AVCaptureAudioDataOutputSampleBufferDelegate)
            // self.audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.eplive.camera.audio"))
            // if self._captureSession.canAddOutput(self.audioOutput) {
            //     self._captureSession.addOutput(self.audioOutput)
            // }
            
            self._captureSession.commitConfiguration()
        }
    }
    
    private func discoverCameras() {
        #if os(macOS)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        #else
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        )
        #endif
        
        DispatchQueue.main.async {
            self.availableCameras = discoverySession.devices
            if let firstCamera = self.availableCameras.first {
                self.selectedCamera = firstCamera
                self.setupCamera(firstCamera)
            }
        }
    }
    
    func setupCamera(_ device: AVCaptureDevice) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self._captureSession.beginConfiguration()
            
            // Remove existing input
            if let currentInput = self.videoDeviceInput {
                self._captureSession.removeInput(currentInput)
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                if self._captureSession.canAddInput(input) {
                    self._captureSession.addInput(input)
                    self.videoDeviceInput = input
                    
                    DispatchQueue.main.async {
                        self.selectedCamera = device
                        self.currentCameraPosition = device.position
                    }
                }
                
                // TODO: Aggiungi input audio (richiede gestione separata)
                // if let audioDevice = AVCaptureDevice.default(for: .audio) {
                //     let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                //     if self._captureSession.canAddInput(audioInput) {
                //         self._captureSession.addInput(audioInput)
                //     }
                // }
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.cameraManager(self, didEncounterError: error)
                }
            }
            
            self._captureSession.commitConfiguration()
        }
    }
    
    func startCapture() {
        guard !isRunning else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self._captureSession.startRunning()
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }
    
    func stopCapture() {
        guard isRunning else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self._captureSession.stopRunning()
            
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }
    
    func switchCamera() {
        guard let currentCamera = selectedCamera else { return }
        
        #if os(iOS)
        let newPosition: AVCaptureDevice.Position = currentCamera.position == .back ? .front : .back
        
        if let newCamera = availableCameras.first(where: { $0.position == newPosition }) {
            setupCamera(newCamera)
        }
        #else
        // On macOS, cycle through available cameras
        if let currentIndex = availableCameras.firstIndex(of: currentCamera) {
            let nextIndex = (currentIndex + 1) % availableCameras.count
            setupCamera(availableCameras[nextIndex])
        }
        #endif
    }
    
    func requestPermissions() async -> Bool {
        // Request video permission
        let videoGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            videoGranted = true
        case .notDetermined:
            videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            videoGranted = false
        }
        
        // Request audio permission
        let audioGranted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            audioGranted = true
        case .notDetermined:
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            audioGranted = false
        }
        
        return videoGranted && audioGranted
    }
    
    // MARK: - Public API for Source Selection
    
    /// Get list of available cameras with ID and name
    func getAvailableCameras() -> [(id: String, name: String)] {
        return availableCameras.map { camera in
            (id: camera.uniqueID, name: camera.localizedName)
        }
    }
    
    /// Get current camera ID
    var currentCameraID: String? {
        return selectedCamera?.uniqueID
    }
    
    /// Switch to camera with specific ID
    func switchToCamera(withID cameraID: String) {
        if let camera = availableCameras.first(where: { $0.uniqueID == cameraID }) {
            setupCamera(camera)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
    }
}
