//
//  EPLiveApp.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import SwiftUI

@main
struct EPLiveApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        #endif
    }
}
