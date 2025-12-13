//
//  CameraPreviewView.swift
//  EPLive
//
//  Camera preview view using HaishinKit MTHKView
//

import SwiftUI
import AVFoundation
import HaishinKit

#if os(iOS)
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var viewModel: StreamViewModel
    
    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: MTHKView, context: Context) {
        // Attach stream when available
        if let stream = viewModel.srtStream {
            Task { @MainActor in
                await uiView.attachStream(stream)
            }
        }
    }
    
    static func dismantleUIView(_ uiView: MTHKView, coordinator: ()) {
        Task { @MainActor in
            await uiView.attachStream(nil)
        }
    }
}
#elseif os(macOS)
struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var viewModel: StreamViewModel
    
    func makeNSView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateNSView(_ nsView: MTHKView, context: Context) {
        // Attach stream when available
        if let stream = viewModel.srtStream {
            Task { @MainActor in
                await nsView.attachStream(stream)
            }
        }
    }
    
    static func dismantleNSView(_ nsView: MTHKView, coordinator: ()) {
        Task { @MainActor in
            await nsView.attachStream(nil)
        }
    }
}
#endif
