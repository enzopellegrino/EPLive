//
//  ServerEditView.swift
//  EPLive
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
        #if os(macOS)
        macOSView
        #else
        iOSView
        #endif
    }
    
    #if os(macOS)
    private var macOSView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isEditing ? "Edit Server" : "Add Server")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Update" : "Add") {
                    saveServer()
                }
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox(label: Label("Server Details", systemImage: "server.rack")) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("URL (srt://host:port or udp://host:port)", text: $url)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                            
                            if showValidation && !isValidURL {
                                Text("Invalid URL. Use format: srt://host:port or udp://host:port")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    GroupBox(label: Label("Quality Settings", systemImage: "speedometer")) {
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
                        .padding(.vertical, 8)
                    }
                    
                    GroupBox {
                        Toggle("Set as Default Server", isOn: $isDefault)
                            .padding(.vertical, 4)
                    }
                    
                    GroupBox(label: Label("Examples", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SRT: srt://192.168.1.100:8888")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("UDP: udp://192.168.1.100:1234")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 550, height: 600)
    }
    #endif
    
    private var iOSView: some View {
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
                        Text("SRT: srt://192.168.1.100:8888")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text("UDP: udp://192.168.1.100:1234")
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
                    Button("Cancel") { dismiss() }
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
            let updated = SRTServer(
                id: existingServer.id,
                name: name,
                url: url,
                bitrate: Int(bitrate),
                isDefault: isDefault
            )
            serverManager.updateServer(updated)
        } else {
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
