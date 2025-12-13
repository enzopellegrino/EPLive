//
//  ServerEditView.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import SwiftUI

struct ServerEditView: View {
    @ObservedObject var serverManager: ServerManager
    let server: SRTServer?
    
    @State private var name: String
    @State private var url: String
    @State private var bitrate: Double
    @State private var isDefault: Bool
    @State private var showValidation = false
    
    @Environment(\.dismiss) private var dismiss
    
    init(serverManager: ServerManager, server: SRTServer? = nil) {
        self.serverManager = serverManager
        self.server = server
        
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: server?.url ?? "srt://")
        _bitrate = State(initialValue: Double(server?.bitrate ?? 2_500_000))
        _isDefault = State(initialValue: server?.isDefault ?? false)
    }
    
    var isEditing: Bool {
        server != nil
    }
    
    var isValid: Bool {
        !name.isEmpty && isValidURL
    }
    
    var isValidURL: Bool {
        guard let urlObj = URL(string: url),
              let scheme = urlObj.scheme,
              (scheme == "srt" || scheme == "udp"),
              urlObj.host != nil,
              urlObj.port != nil else {
            return false
        }
        return true
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Details")) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("URL (srt://host:port or udp://host:port)", text: $url)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                    
                    if showValidation && !isValidURL {
                        Text("Invalid URL. Use format: srt://host:port or udp://host:port")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Quality Settings")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text("\(Int(bitrate) / 1000) kbps")
                                .foregroundColor(.gray)
                        }
                        
                        Slider(value: $bitrate, in: 500_000...10_000_000, step: 100_000)
                        
                        HStack {
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section {
                    Toggle("Set as Default Server", isOn: $isDefault)
                }
                
                Section(header: Text("Examples")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("RTMP: rtmp://192.168.1.100/live/stream")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("SRT: srt://192.168.1.100:8888")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("Remote: rtmp://stream.example.com/live/mykey")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Server" : "Add Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") {
                        saveServer()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func saveServer() {
        showValidation = true
        
        guard isValid else { return }
        
        if let existingServer = server {
            // Update existing server
            let updated = SRTServer(
                id: existingServer.id,
                name: name,
                url: url,
                bitrate: Int(bitrate),
                isDefault: isDefault
            )
            serverManager.updateServer(updated)
        } else {
            // Add new server
            let newServer = SRTServer(
                name: name,
                url: url,
                bitrate: Int(bitrate),
                isDefault: isDefault
            )
            serverManager.addServer(newServer)
        }
        
        dismiss()
    }
}

#Preview {
    ServerEditView(serverManager: ServerManager())
}
