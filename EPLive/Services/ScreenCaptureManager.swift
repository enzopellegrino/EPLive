//
//  ScreenCaptureManager.swift
//  EPLive
//
//  Screen and window capture using ScreenCaptureKit (macOS 12.3+)
//

#if os(macOS)
import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo

@available(macOS 12.3, *)
protocol ScreenCaptureManagerDelegate: AnyObject {
    func screenCaptureManager(_ manager: ScreenCaptureManager, didOutput sampleBuffer: CMSampleBuffer)
    func screenCaptureManager(_ manager: ScreenCaptureManager, didEncounterError error: Error)
}

@available(macOS 12.3, *)
class ScreenCaptureManager: NSObject, ObservableObject {
    weak var delegate: ScreenCaptureManagerDelegate?
    
    @Published var isCapturing = false
    @Published var currentSource: ScreenCaptureSource?
    
    private var stream: SCStream?
    private var streamOutput: ScreenCaptureStreamOutput?
    
    // Configuration
    private let width: Int = 1920
    private let height: Int = 1080
    private let frameRate: Int = 30
    
    enum ScreenCaptureSource {
        case display(SCDisplay)
        case window(SCWindow)
        
        var displayName: String {
            switch self {
            case .display(let display):
                return "Schermo \(display.displayID)"
            case .window(let window):
                return window.title ?? window.owningApplication?.applicationName ?? "Finestra"
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Permissions
    
    func requestPermissions() async -> Bool {
        // Check if we can get screen content
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            print("Screen recording permission error: \(error)")
            return false
        }
    }
    
    // MARK: - Capture Control
    
    func startCapture(source: ScreenCaptureSource) async throws {
        guard !isCapturing else { return }
        
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        // Create filter based on source
        let filter: SCContentFilter
        switch source {
        case .display(let display):
            // Find the display in content
            guard let foundDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw ScreenCaptureError.displayNotFound
            }
            filter = SCContentFilter(display: foundDisplay, excludingWindows: [])
            
        case .window(let window):
            // Find the window in content
            guard let foundWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
                throw ScreenCaptureError.windowNotFound
            }
            filter = SCContentFilter(desktopIndependentWindow: foundWindow)
        }
        
        // Configure stream
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.showsCursor = true
        configuration.capturesAudio = false // Audio capture requires separate handling
        
        // Create stream
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        // Create output handler
        streamOutput = ScreenCaptureStreamOutput(delegate: self)
        
        // Add stream output
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.eplive.screencapture"))
        
        // Start capture
        try await stream?.startCapture()
        
        await MainActor.run {
            self.isCapturing = true
            self.currentSource = source
        }
    }
    
    func stopCapture() async throws {
        guard isCapturing, let stream = stream else { return }
        
        try await stream.stopCapture()
        
        await MainActor.run {
            self.isCapturing = false
            self.stream = nil
            self.streamOutput = nil
        }
    }
    
    // MARK: - Available Sources
    
    static func getAvailableDisplays() async -> [SCDisplay] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return content.displays
        } catch {
            print("Error getting displays: \(error)")
            return []
        }
    }
    
    static func getAvailableWindows() async -> [SCWindow] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Filter out small windows and system windows
            return content.windows.filter { window in
                guard let app = window.owningApplication,
                      window.frame.width >= 100,
                      window.frame.height >= 100 else {
                    return false
                }
                // Exclude system applications
                let systemBundleIDs = ["com.apple.dock", "com.apple.WindowManager", "com.apple.controlcenter"]
                return !systemBundleIDs.contains(app.bundleIdentifier)
            }
        } catch {
            print("Error getting windows: \(error)")
            return []
        }
    }
}

// MARK: - Stream Output Handler

@available(macOS 12.3, *)
private class ScreenCaptureStreamOutput: NSObject, SCStreamOutput {
    weak var delegate: ScreenCaptureManager?
    
    init(delegate: ScreenCaptureManager) {
        self.delegate = delegate
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        // Verify sample buffer is valid
        guard sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
        
        // Forward to delegate
        delegate?.delegate?.screenCaptureManager(delegate!, didOutput: sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Screen capture stream stopped with error: \(error)")
        delegate?.delegate?.screenCaptureManager(delegate!, didEncounterError: error)
    }
}

// MARK: - Errors

enum ScreenCaptureError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case captureNotSupported
    
    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Display non trovato"
        case .windowNotFound:
            return "Finestra non trovata"
        case .captureNotSupported:
            return "Screen capture non supportato su questo sistema"
        }
    }
}

#endif
