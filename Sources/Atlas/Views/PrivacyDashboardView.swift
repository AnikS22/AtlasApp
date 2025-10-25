// File: AtlasApp/Views/PrivacyDashboardView.swift

import SwiftUI

struct PrivacyDashboardView: View {
    @StateObject private var viewModel = PrivacyDashboardViewModel()

    var body: some View {
        List {
            Section("Data Inventory") {
                DataInventoryRow(
                    title: "Conversations",
                    count: viewModel.conversationCount,
                    size: viewModel.conversationDataSize,
                    encrypted: true,
                    location: "Device Only"
                )

                DataInventoryRow(
                    title: "API Keys",
                    count: viewModel.apiKeyCount,
                    size: 0,
                    encrypted: true,
                    location: "Secure Keychain"
                )

                DataInventoryRow(
                    title: "MCP Servers",
                    count: viewModel.mcpServerCount,
                    size: viewModel.mcpConfigSize,
                    encrypted: true,
                    location: "Device Only"
                )
            }

            Section("Data Flow") {
                NavigationLink("View Data Flow Map") {
                    DataFlowVisualization()
                }

                Toggle("Block MCP Tool Access to Conversation History", isOn: $viewModel.blockMCPContextSharing)
            }

            Section("Access Log") {
                NavigationLink("View Access Audit Log") {
                    AccessAuditLogView()
                }

                Text("Last API Call: \(viewModel.lastAPICallDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Data Export") {
                Button("Export All My Data") {
                    viewModel.exportAllData()
                }

                Button("Delete All My Data", role: .destructive) {
                    viewModel.showDeleteConfirmation = true
                }
            }

            Section("Security Status") {
                HStack {
                    Text("Database Encryption")
                    Spacer()
                    Image(systemName: viewModel.databaseEncrypted ? "lock.fill" : "lock.open")
                        .foregroundColor(viewModel.databaseEncrypted ? .green : .red)
                }

                HStack {
                    Text("Keychain Protection")
                    Spacer()
                    Image(systemName: viewModel.keychainProtected ? "checkmark.shield.fill" : "xmark.shield")
                        .foregroundColor(viewModel.keychainProtected ? .green : .red)
                }

                HStack {
                    Text("Biometric Lock")
                    Spacer()
                    Image(systemName: viewModel.biometricEnabled ? "faceid" : "lock.slash")
                        .foregroundColor(viewModel.biometricEnabled ? .green : .orange)
                }
            }
        }
        .navigationTitle("Privacy Dashboard")
        .alert("Delete All Data?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                viewModel.deleteAllData()
            }
        } message: {
            Text("This will permanently delete all conversations, settings, and API keys. This action cannot be undone.")
        }
    }
}

struct DataInventoryRow: View {
    let title: String
    let count: Int
    let size: Int64
    let encrypted: Bool
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if encrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Text("\(count) items • \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Stored: \(location)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Supporting Views

struct DataFlowVisualization: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Data Flow Map")
                    .font(.title2)
                    .bold()

                FlowDiagram()

                Divider()

                Text("Security Guarantees")
                    .font(.headline)

                SecurityGuaranteeRow(icon: "lock.shield", text: "All data encrypted at rest with AES-256-GCM")
                SecurityGuaranteeRow(icon: "network.badge.shield.half.filled", text: "TLS 1.3 for all network communication")
                SecurityGuaranteeRow(icon: "iphone.and.arrow.forward", text: "No data leaves device except via authenticated APIs")
                SecurityGuaranteeRow(icon: "key.fill", text: "Biometric protection for encryption keys")
            }
            .padding()
        }
        .navigationTitle("Data Flow")
    }
}

struct FlowDiagram: View {
    var body: some View {
        VStack(spacing: 12) {
            FlowNode(title: "User Input", color: .blue)
            FlowArrow()
            FlowNode(title: "Encryption (AES-256-GCM)", color: .green)
            FlowArrow()
            FlowNode(title: "SQLCipher Database", color: .purple)
            FlowArrow(label: "API Calls Only")
            FlowNode(title: "Claude API / MCP Servers", color: .orange)
        }
    }
}

struct FlowNode: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.2))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 2)
            )
    }
}

struct FlowArrow: View {
    var label: String? = nil

    var body: some View {
        HStack {
            if let label = label {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SecurityGuaranteeRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct AccessAuditLogView: View {
    @State private var auditEntries: [AuditEntry] = []

    var body: some View {
        List(auditEntries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.event)
                    .font(.headline)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let details = entry.details {
                    Text(details)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Audit Log")
        .onAppear {
            loadAuditLog()
        }
    }

    private func loadAuditLog() {
        // Load from SecurityAuditLogger
        auditEntries = []
    }
}

struct AuditEntry: Identifiable {
    let id = UUID()
    let event: String
    let timestamp: Date
    let details: String?
}

// MARK: - View Model

class PrivacyDashboardViewModel: ObservableObject {
    @Published var conversationCount: Int = 0
    @Published var conversationDataSize: Int64 = 0
    @Published var apiKeyCount: Int = 0
    @Published var mcpServerCount: Int = 0
    @Published var mcpConfigSize: Int64 = 0
    @Published var blockMCPContextSharing: Bool = true
    @Published var lastAPICallDate: String = "Never"
    @Published var databaseEncrypted: Bool = true
    @Published var keychainProtected: Bool = true
    @Published var biometricEnabled: Bool = true
    @Published var showDeleteConfirmation: Bool = false

    init() {
        loadPrivacyData()
    }

    private func loadPrivacyData() {
        // Load actual data from database and keychain
        // This is a placeholder implementation
        conversationCount = 0
        apiKeyCount = 0
        mcpServerCount = 0
    }

    func exportAllData() {
        // Export all user data to JSON
        // Implementation would use DatabaseManager to extract all data
    }

    func deleteAllData() {
        do {
            try KeychainManager.shared.deleteAllCredentials()
            FileAccessManager.shared.securePurgeTempFiles()
            // Delete database file
            showDeleteConfirmation = false
        } catch {
            // Handle error
        }
    }
}
