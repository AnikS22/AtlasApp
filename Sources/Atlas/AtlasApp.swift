//
//  AtlasApp.swift
//  Atlas - Your Private AI Companion
//
//  Main app entry point with CoreData stack integration
//

import SwiftUI

@main
struct AtlasApp: App {
    // CoreData persistence controller
    let persistenceController = PersistenceController.shared

    // App state management
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appState)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        // Initialize app settings
        UserDefaults.standard.register(defaults: [
            "isFirstLaunch": true,
            "voiceInputEnabled": true,
            "autoSaveConversations": true,
            "privacyMode": true
        ])

        // Log app launch
        print("Atlas App launched - Version 1.0.0")
    }
}

// MARK: - App State Management
class AppState: ObservableObject {
    @Published var isShowingSettings = false
    @Published var currentConversationId: UUID?
    @Published var isRecording = false
    @Published var isProcessing = false

    init() {
        // Initialize app state
    }
}
