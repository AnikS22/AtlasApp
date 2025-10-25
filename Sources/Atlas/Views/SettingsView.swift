//
//  SettingsView.swift
//  Atlas
//
//  Privacy and configuration settings
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = true
    @AppStorage("autoSaveConversations") private var autoSaveConversations = true
    @AppStorage("privacyMode") private var privacyMode = true
    @AppStorage("modelSelection") private var modelSelection = "phi-3.5-mini"
    @AppStorage("maxContextLength") private var maxContextLength = 2048.0
    @AppStorage("temperature") private var temperature = 0.7

    var body: some View {
        NavigationView {
            Form {
                // Privacy Section
                Section {
                    Toggle("Privacy Mode", isOn: $privacyMode)
                    Toggle("Auto-save Conversations", isOn: $autoSaveConversations)

                    NavigationLink {
                        PrivacyDetailsView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Privacy mode ensures all data stays on your device. No data is sent to external servers.")
                }

                // Voice Input Section
                Section {
                    Toggle("Voice Input Enabled", isOn: $voiceInputEnabled)

                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        Label("Voice Settings", systemImage: "mic.fill")
                    }
                } header: {
                    Text("Voice Input")
                } footer: {
                    Text("Voice processing uses on-device Whisper model for complete privacy.")
                }

                // AI Model Section
                Section {
                    Picker("Model", selection: $modelSelection) {
                        Text("Phi-3.5 Mini").tag("phi-3.5-mini")
                        Text("Llama 3.2 1B").tag("llama-3.2-1b")
                        Text("Llama 3.2 3B").tag("llama-3.2-3b")
                        Text("Gemma 2 2B").tag("gemma-2-2b")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Context: \(Int(maxContextLength)) tokens")
                            .font(.subheadline)
                        Slider(value: $maxContextLength, in: 512...8192, step: 512)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Temperature: \(temperature, specifier: "%.2f")")
                            .font(.subheadline)
                        Slider(value: $temperature, in: 0...1, step: 0.1)
                    }
                } header: {
                    Text("AI Model")
                } footer: {
                    Text("All models run locally on your device using CoreML optimization.")
                }

                // Storage Section
                Section {
                    NavigationLink {
                        StorageManagementView()
                    } label: {
                        HStack {
                            Label("Storage", systemImage: "internaldrive")
                            Spacer()
                            Text("4.2 GB")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        clearAllData()
                    } label: {
                        Label("Clear All Data", systemImage: "trash")
                    }
                } header: {
                    Text("Storage")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About Atlas", systemImage: "info.circle")
                    }

                    Link(destination: URL(string: "https://github.com/yourusername/atlas")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }

    private func clearAllData() {
        // TODO: Implement data clearing with confirmation dialog
        print("Clear all data requested")
    }
}

// MARK: - Privacy Details View
struct PrivacyDetailsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Privacy First")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Atlas is designed with privacy at its core:")
                        .font(.headline)

                    PrivacyFeature(
                        icon: "lock.shield.fill",
                        title: "On-Device Processing",
                        description: "All AI processing happens locally on your device. Your conversations never leave your iPhone."
                    )

                    PrivacyFeature(
                        icon: "network.slash",
                        title: "No Network Required",
                        description: "Atlas works completely offline. No internet connection needed for conversations."
                    )

                    PrivacyFeature(
                        icon: "externaldrive.fill",
                        title: "Local Storage Only",
                        description: "All data is stored securely on your device using CoreData encryption."
                    )

                    PrivacyFeature(
                        icon: "eye.slash.fill",
                        title: "No Tracking",
                        description: "We don't collect analytics, telemetry, or any user data. Ever."
                    )
                }

                Divider()
                    .padding(.vertical)

                Group {
                    Text("Your Data, Your Control")
                        .font(.headline)

                    Text("You have complete control over your data:")
                        .foregroundColor(.secondary)

                    BulletPoint("Export conversations at any time")
                    BulletPoint("Delete individual messages or entire conversations")
                    BulletPoint("Clear all data with one tap")
                    BulletPoint("No cloud sync, no backups without your permission")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Privacy Feature Component
struct PrivacyFeature: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Bullet Point Component
struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Voice Settings View
struct VoiceSettingsView: View {
    @AppStorage("voiceLanguage") private var voiceLanguage = "en-US"
    @AppStorage("voiceAutoSend") private var voiceAutoSend = true

    var body: some View {
        Form {
            Picker("Language", selection: $voiceLanguage) {
                Text("English (US)").tag("en-US")
                Text("English (UK)").tag("en-GB")
                Text("Spanish").tag("es-ES")
                Text("French").tag("fr-FR")
                Text("German").tag("de-DE")
            }

            Toggle("Auto-send after recording", isOn: $voiceAutoSend)
        }
        .navigationTitle("Voice Settings")
    }
}

// MARK: - Storage Management View
struct StorageManagementView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Conversations")
                    Spacer()
                    Text("1.2 GB")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Voice Recordings")
                    Spacer()
                    Text("850 MB")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Model Cache")
                    Spacer()
                    Text("2.1 GB")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Storage Breakdown")
            }

            Section {
                Button("Clear Conversation Cache") {
                    // TODO: Implement
                }

                Button("Clear Voice Recordings") {
                    // TODO: Implement
                }

                Button(role: .destructive) {
                    // TODO: Implement
                } label: {
                    Text("Clear All Storage")
                }
            }
        }
        .navigationTitle("Storage")
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)

                Text("Atlas")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your Private AI Companion")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("Version 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Built with:")
                        .font(.headline)

                    TechnologyRow(name: "SwiftUI", description: "Modern iOS interface")
                    TechnologyRow(name: "Rust", description: "High-performance AI backend")
                    TechnologyRow(name: "CoreML", description: "On-device machine learning")
                    TechnologyRow(name: "Whisper", description: "Voice transcription")
                    TechnologyRow(name: "Phi-3.5", description: "Conversational AI")
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

struct TechnologyRow: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            VStack(alignment: .leading) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
