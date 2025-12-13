//
//  ServerListView.swift
//  EPLive
//
//  Created on 12/12/2025.
//

import SwiftUI

struct ServerListView: View {
    @ObservedObject var serverManager: ServerManager
    @Binding var selectedServer: SRTServer?
    @State private var showAddServer = false
    @State private var editingServer: SRTServer?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                if serverManager.servers.isEmpty {
                    emptyStateView
                } else {
                    ForEach(serverManager.servers) { server in
                        ServerRowView(
                            server: server,
                            isSelected: selectedServer?.id == server.id,
                            onSelect: {
                                selectedServer = server
                            },
                            onEdit: {
                                editingServer = server
                            },
                            onSetDefault: {
                                serverManager.setDefaultServer(server)
                            }
                        )
                    }
                    .onDelete(perform: deleteServers)
                }
            }
            .navigationTitle("SRT Servers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddServer = true }) {
                        Image(systemName: "plus")
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddServer = true }) {
                        Image(systemName: "plus")
                    }
                }
                #endif
                
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                #endif
            }
            .sheet(isPresented: $showAddServer) {
                ServerEditView(serverManager: serverManager)
            }
            .sheet(item: $editingServer) { server in
                ServerEditView(serverManager: serverManager, server: server)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Servers")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a server to start streaming")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: { showAddServer = true }) {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .listRowBackground(Color.clear)
    }
    
    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = serverManager.servers[index]
            serverManager.deleteServer(server)
        }
    }
}

struct ServerRowView: View {
    let server: SRTServer
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onSetDefault: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(server.name)
                            .font(.headline)
                        
                        if server.isDefault {
                            Text("DEFAULT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(server.url)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text("\(server.bitrate / 1000) kbps")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.large)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            
            if !server.isDefault {
                Button(action: onSetDefault) {
                    Label("Set as Default", systemImage: "star.fill")
                }
            }
        }
    }
}

#Preview {
    ServerListView(
        serverManager: ServerManager(),
        selectedServer: .constant(nil)
    )
}
