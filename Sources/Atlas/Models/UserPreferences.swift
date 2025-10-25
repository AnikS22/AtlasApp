//
//  UserPreferences.swift
//  Atlas
//
//  User preferences and settings data model
//

import Foundation
import SwiftUI

/// Represents user preferences and settings
struct UserPreferences: Codable {
    // Privacy Settings
    var privacyMode: Bool
    var autoSaveConversations: Bool
    var exportWithMetadata: Bool

    // Voice Input Settings
    var voiceInputEnabled: Bool
    var voiceLanguage: String
    var voiceAutoSend: Bool

    // AI Model Settings
    var modelSelection: String
    var maxContextLength: Int
    var temperature: Double
    var topP: Double
    var topK: Int

    // UI Settings
    var theme: Theme
    var fontSize: FontSize
    var messageGrouping: Bool
    var showTimestamps: Bool
    var compactMode: Bool

    // Notification Settings
    var notificationsEnabled: Bool
    var soundEffects: Bool
    var hapticFeedback: Bool

    // Advanced Settings
    var developerMode: Bool
    var debugLogging: Bool
    var cacheEnabled: Bool
    var maxCacheSize: Int

    init(
        privacyMode: Bool = true,
        autoSaveConversations: Bool = true,
        exportWithMetadata: Bool = true,
        voiceInputEnabled: Bool = true,
        voiceLanguage: String = "en-US",
        voiceAutoSend: Bool = true,
        modelSelection: String = "phi-3.5-mini",
        maxContextLength: Int = 2048,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        theme: Theme = .system,
        fontSize: FontSize = .medium,
        messageGrouping: Bool = true,
        showTimestamps: Bool = true,
        compactMode: Bool = false,
        notificationsEnabled: Bool = true,
        soundEffects: Bool = true,
        hapticFeedback: Bool = true,
        developerMode: Bool = false,
        debugLogging: Bool = false,
        cacheEnabled: Bool = true,
        maxCacheSize: Int = 500
    ) {
        self.privacyMode = privacyMode
        self.autoSaveConversations = autoSaveConversations
        self.exportWithMetadata = exportWithMetadata
        self.voiceInputEnabled = voiceInputEnabled
        self.voiceLanguage = voiceLanguage
        self.voiceAutoSend = voiceAutoSend
        self.modelSelection = modelSelection
        self.maxContextLength = maxContextLength
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.theme = theme
        self.fontSize = fontSize
        self.messageGrouping = messageGrouping
        self.showTimestamps = showTimestamps
        self.compactMode = compactMode
        self.notificationsEnabled = notificationsEnabled
        self.soundEffects = soundEffects
        self.hapticFeedback = hapticFeedback
        self.developerMode = developerMode
        self.debugLogging = debugLogging
        self.cacheEnabled = cacheEnabled
        self.maxCacheSize = maxCacheSize
    }
}

// MARK: - Theme Enum
enum Theme: String, Codable, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

// MARK: - Font Size Enum
enum FontSize: String, Codable, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"

    var scale: CGFloat {
        switch self {
        case .small:
            return 0.9
        case .medium:
            return 1.0
        case .large:
            return 1.1
        case .extraLarge:
            return 1.2
        }
    }
}

// MARK: - User Preferences Manager
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()

    @Published var preferences: UserPreferences {
        didSet {
            save()
        }
    }

    private let userDefaultsKey = "userPreferences"

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = UserPreferences()
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    func reset() {
        preferences = UserPreferences()
        save()
    }

    // MARK: - Convenience Methods

    func updateTheme(_ theme: Theme) {
        preferences.theme = theme
    }

    func updateFontSize(_ fontSize: FontSize) {
        preferences.fontSize = fontSize
    }

    func updateModel(_ model: String) {
        preferences.modelSelection = model
    }

    func togglePrivacyMode() {
        preferences.privacyMode.toggle()
    }

    func toggleVoiceInput() {
        preferences.voiceInputEnabled.toggle()
    }

    func toggleDeveloperMode() {
        preferences.developerMode.toggle()
    }
}

// MARK: - Available Models
struct AvailableModels {
    static let models: [ModelInfo] = [
        ModelInfo(
            id: "phi-3.5-mini",
            name: "Phi-3.5 Mini",
            description: "Fast and efficient, ideal for general conversations",
            size: "2.1 GB",
            maxContextLength: 4096,
            recommendedFor: ["General chat", "Quick responses", "Low latency"]
        ),
        ModelInfo(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B",
            description: "Lightweight model with good performance",
            size: "1.2 GB",
            maxContextLength: 2048,
            recommendedFor: ["Resource-constrained devices", "Fast responses"]
        ),
        ModelInfo(
            id: "llama-3.2-3b",
            name: "Llama 3.2 3B",
            description: "Balanced performance and quality",
            size: "3.5 GB",
            maxContextLength: 4096,
            recommendedFor: ["Complex reasoning", "Detailed responses"]
        ),
        ModelInfo(
            id: "gemma-2-2b",
            name: "Gemma 2 2B",
            description: "Optimized for on-device inference",
            size: "2.3 GB",
            maxContextLength: 2048,
            recommendedFor: ["Privacy-focused", "Efficient processing"]
        )
    ]

    static func modelInfo(for id: String) -> ModelInfo? {
        return models.first { $0.id == id }
    }
}

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let description: String
    let size: String
    let maxContextLength: Int
    let recommendedFor: [String]
}

// MARK: - Voice Languages
struct VoiceLanguages {
    static let languages: [LanguageInfo] = [
        LanguageInfo(code: "en-US", name: "English (US)", flag: "🇺🇸"),
        LanguageInfo(code: "en-GB", name: "English (UK)", flag: "🇬🇧"),
        LanguageInfo(code: "es-ES", name: "Spanish", flag: "🇪🇸"),
        LanguageInfo(code: "fr-FR", name: "French", flag: "🇫🇷"),
        LanguageInfo(code: "de-DE", name: "German", flag: "🇩🇪"),
        LanguageInfo(code: "it-IT", name: "Italian", flag: "🇮🇹"),
        LanguageInfo(code: "pt-BR", name: "Portuguese (Brazil)", flag: "🇧🇷"),
        LanguageInfo(code: "ja-JP", name: "Japanese", flag: "🇯🇵"),
        LanguageInfo(code: "ko-KR", name: "Korean", flag: "🇰🇷"),
        LanguageInfo(code: "zh-CN", name: "Chinese (Simplified)", flag: "🇨🇳")
    ]

    static func languageInfo(for code: String) -> LanguageInfo? {
        return languages.first { $0.code == code }
    }
}

struct LanguageInfo: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let flag: String
}
