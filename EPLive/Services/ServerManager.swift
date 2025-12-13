//
//  ServerManager.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import Foundation
import Combine

class ServerManager: ObservableObject {
    @Published var servers: [SRTServer] = []
    
    private let serversKey = "com.eplive.servers"
    
    init() {
        loadServers()
        
        // Add default server if none exist
        if servers.isEmpty {
            let defaultServer = SRTServer(
                name: "Local Test Server",
                url: "udp://192.168.1.100:8888",
                bitrate: 2_500_000,
                isDefault: true
            )
            servers.append(defaultServer)
            saveServers()
        }
    }
    
    var defaultServer: SRTServer? {
        servers.first { $0.isDefault } ?? servers.first
    }
    
    func addServer(_ server: SRTServer) {
        var newServer = server
        
        // If this is the first server or marked as default, make it default
        if servers.isEmpty || newServer.isDefault {
            servers.indices.forEach { servers[$0].isDefault = false }
            newServer.isDefault = true
        }
        
        servers.append(newServer)
        saveServers()
    }
    
    func updateServer(_ server: SRTServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            let updatedServer = server
            
            // Handle default status
            if updatedServer.isDefault {
                servers.indices.forEach { servers[$0].isDefault = false }
            }
            
            servers[index] = updatedServer
            saveServers()
        }
    }
    
    func deleteServer(_ server: SRTServer) {
        servers.removeAll { $0.id == server.id }
        
        // If we deleted the default server, make the first one default
        if !servers.contains(where: { $0.isDefault }), let _ = servers.first {
            servers[0].isDefault = true
        }
        
        saveServers()
    }
    
    func setDefaultServer(_ server: SRTServer) {
        servers.indices.forEach { servers[$0].isDefault = false }
        
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isDefault = true
            saveServers()
        }
    }
    
    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey),
              let decoded = try? JSONDecoder().decode([SRTServer].self, from: data) else {
            return
        }
        servers = decoded
    }
    
    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: serversKey)
        }
    }
}
