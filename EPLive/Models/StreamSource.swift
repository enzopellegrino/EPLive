//
//  StreamSource.swift
//  EPLive
//
//  Multiple stream sources support
//

import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Stream Source Type
public enum StreamSourceType: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case screen = "Schermo Intero"
    case window = "Finestra Specifica"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .screen: return "rectangle.on.rectangle"
        case .window: return "macwindow"
        }
    }
    
    var description: String {
        switch self {
        case .camera: return "Cattura dalla webcam"
        case .screen: return "Cattura tutto lo schermo"
        case .window: return "Cattura una finestra specifica"
        }
    }
}

// MARK: - Screen/Window Info
#if os(macOS)
public struct ScreenInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    
    static func availableScreens() -> [ScreenInfo] {
        var screens: [ScreenInfo] = []
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        if CGGetActiveDisplayList(16, &displays, &displayCount) == .success {
            for i in 0..<Int(displayCount) {
                let display = displays[i]
                let bounds = CGDisplayBounds(display)
                let name = getDisplayName(display) ?? "Display \(i + 1)"
                screens.append(ScreenInfo(id: display, name: name, bounds: bounds))
            }
        }
        
        return screens
    }
    
    private static func getDisplayName(_ displayID: CGDirectDisplayID) -> String? {
        if CGDisplayIsMain(displayID) {
            return "Schermo Principale"
        }
        return "Schermo Esterno"
    }
}

public struct WindowInfo: Identifiable, Hashable {
    let id: Int
    let windowNumber: Int
    let ownerName: String
    let windowName: String?
    let bounds: CGRect
    
    var displayName: String {
        if let name = windowName, !name.isEmpty {
            return "\(ownerName) - \(name)"
        }
        return ownerName
    }
    
    static func availableWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }
        
        for (index, windowDict) in windowList.enumerated() {
            guard let windowNumber = windowDict[kCGWindowNumber as String] as? Int,
                  let ownerName = windowDict[kCGWindowOwnerName as String] as? String,
                  let boundsDict = windowDict[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            
            // Skip system windows and very small windows
            if ownerName == "Window Server" || ownerName == "Dock" {
                continue
            }
            
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            // Skip very small windows (likely not content windows)
            if bounds.width < 100 || bounds.height < 100 {
                continue
            }
            
            let windowName = windowDict[kCGWindowName as String] as? String
            
            windows.append(WindowInfo(
                id: index,
                windowNumber: windowNumber,
                ownerName: ownerName,
                windowName: windowName,
                bounds: bounds
            ))
        }
        
        return windows
    }
}
#endif

// MARK: - Stream Source Configuration
public struct StreamSourceConfig: Identifiable {
    let id = UUID()
    let type: StreamSourceType
    var cameraDeviceID: String?
    #if os(macOS)
    var screenID: CGDirectDisplayID?
    var windowNumber: Int?
    #endif
    
    var displayName: String {
        switch type {
        case .camera:
            return cameraDeviceID ?? "Webcam"
        case .screen:
            #if os(macOS)
            if let screenID = screenID {
                return "Schermo \(screenID)"
            }
            #endif
            return "Schermo Intero"
        case .window:
            #if os(macOS)
            if let windowNumber = windowNumber {
                return "Finestra #\(windowNumber)"
            }
            #endif
            return "Finestra"
        }
    }
}
