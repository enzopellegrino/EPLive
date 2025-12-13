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
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        #endif
    }
}
