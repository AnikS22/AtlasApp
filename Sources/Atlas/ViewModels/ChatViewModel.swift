//
//  ChatViewModel.swift
//  Atlas
//
//  Connects AI, voice, and integration services to the UI
//  Orchestrates the complete conversation flow
//

import Foundation
import Combine
import AVFoundation

/// Main view model for chat functionality
@MainActor
@available(iOS 17.0, *)
public class ChatViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var isProcessing = false
    @Published public var isSpeaking = false
    @Published public var currentResponse = ""
    @Published public var errorMessage: String?
    @Published public var integrationStatus: IntegrationStatus = .notConnected
    
    // MARK: - Services
    
    private let trmEngine: InferenceEngineProtocol
    private let ttsService: TextToSpeechService
    private let sttService: SpeechRecognitionService
    private let memoryService: MemoryService
    private var integrationCoordinator: IntegrationCoordinator?
    
    // MARK: - Configuration
    
    public struct Configuration {
        let enableVoiceResponse: Bool
        let enableMemory: Bool
        let enableIntegrations: Bool
        
        public static let `default` = Configuration(
            enableVoiceResponse: true,
            enableMemory: true,
            enableIntegrations: true
        )
    }
    
    private let config: Configuration
    
    // MARK: - Initialization
    
    public init(config: Configuration = .default) {
        self.config = config
        
        // Initialize services
        self.trmEngine = TRMEngineFactory.createEngine()
        self.ttsService = TextToSpeechService()
        self.sttService = SpeechRecognitionService()
        self.memoryService = MemoryService()
        
        // Initialize integrations asynchronously
        Task {
            await initializeIntegrations()
        }
    }
    
    private func initializeIntegrations() async {
        guard config.enableIntegrations else { return }
        
        do {
            integrationCoordinator = try await IntegrationCoordinator()
            integrationStatus = .connected
            print("✅ Integration coordinator initialized")
        } catch {
            integrationStatus = .error(error.localizedDescription)
            print("⚠️ Integration coordinator failed: \(error)")
        }
    }
    
    // MARK: - Main Message Flow
    
    /// Send a text message and get AI response
    public func sendMessage(_ text: String, conversationId: UUID? = nil) async -> String? {
        guard !text.isEmpty else { return nil }
        
        isProcessing = true
        errorMessage = nil
        currentResponse = ""
        
        defer {
            isProcessing = false
        }
        
        do {
            // Step 1: Get conversation context if memory enabled
            var context: MemoryContext?
            if config.enableMemory {
                context = try await getConversationContext()
            }
            
            // Step 2: Check if integration needed
            let response: String
            if config.enableIntegrations, let coordinator = integrationCoordinator {
                // Use integration coordinator for queries that might need cloud data
                response = try await coordinator.processQuery(text, context: context)
            } else {
                // Direct TRM inference
                response = try await trmEngine.generate(prompt: text, context: context)
            }
            
            currentResponse = response
            
            // Step 3: Store in memory
            if config.enableMemory {
                try await storeInteraction(query: text, response: response)
            }
            
            // Step 4: Speak response if enabled
            if config.enableVoiceResponse {
                await speakResponse(response)
            }
            
            return response
            
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            print("❌ Message processing failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Voice Transcription
    
    /// Transcribe audio file to text
    public func transcribeAudio(_ audioURL: URL) async -> String? {
        do {
            let result = try await sttService.transcribeAudioFile(audioURL)
            print("✅ Transcribed: \(result.transcript)")
            return result.transcript
        } catch {
            errorMessage = "Transcription error: \(error.localizedDescription)"
            print("❌ Transcription failed: \(error)")
            return nil
        }
    }
    
    /// Start real-time voice recognition
    public func startVoiceRecognition() async throws -> AsyncStream<String> {
        return try await sttService.startRecognition()
    }
    
    // MARK: - Text-to-Speech
    
    /// Speak text response
    public func speakResponse(_ text: String) async {
        guard !text.isEmpty else { return }
        
        isSpeaking = true
        defer { isSpeaking = false }
        
        do {
            try await ttsService.speak(text: text)
            print("✅ Spoke response")
        } catch {
            print("⚠️ Speech synthesis failed: \(error)")
        }
    }
    
    /// Stop current speech
    public func stopSpeaking() {
        ttsService.stop()
        isSpeaking = false
    }
    
    // MARK: - Memory Management
    
    private func getConversationContext() async throws -> MemoryContext? {
        // Get recent conversation context
        let context = try await memoryService.getCurrentContext(maxTokens: 2048)
        
        // Convert to MemoryContext if we have relevant memories
        if !context.isEmpty {
            // For now, return nil as we need embeddings
            // In production, this would fetch relevant embeddings
            return nil
        }
        
        return nil
    }
    
    private func storeInteraction(query: String, response: String) async throws {
        let metadata = MemoryMetadata(
            category: .conversation,
            importance: .medium,
            tags: [],
            timestamp: Date()
        )
        
        try await memoryService.store(
            query: query,
            response: response,
            metadata: metadata
        )
        
        print("✅ Stored interaction in memory")
    }
    
    // MARK: - Integration Queries
    
    /// Fetch and summarize emails
    public func fetchEmails(query: String) async -> String? {
        guard let coordinator = integrationCoordinator else {
            return "Gmail not connected. Please connect in Settings."
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let summary = try await coordinator.fetchAndSummarizeEmails(query: query)
            
            if config.enableVoiceResponse {
                await speakResponse(summary)
            }
            
            return summary
        } catch {
            let errorMsg = "Error fetching emails: \(error.localizedDescription)"
            errorMessage = errorMsg
            return errorMsg
        }
    }
    
    /// Search and analyze Drive files
    public func searchDriveFiles(query: String) async -> String? {
        guard let coordinator = integrationCoordinator else {
            return "Google Drive not connected. Please connect in Settings."
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let summary = try await coordinator.searchAndSummarizeDriveFiles(query: query)
            
            if config.enableVoiceResponse {
                await speakResponse(summary)
            }
            
            return summary
        } catch {
            let errorMsg = "Error searching Drive: \(error.localizedDescription)"
            errorMessage = errorMsg
            return errorMsg
        }
    }
    
    // MARK: - Utility
    
    /// Clear error message
    public func clearError() {
        errorMessage = nil
    }
    
    /// Get performance metrics
    public func getMetrics() -> PerformanceMetrics? {
        if let engine = trmEngine as? TRMInferenceEngine {
            return engine.getPerformanceMetrics()
        }
        return nil
    }
}

// MARK: - Supporting Types

public enum IntegrationStatus {
    case notConnected
    case connecting
    case connected
    case error(String)
    
    public var description: String {
        switch self {
        case .notConnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }
}

public struct MemoryMetadata {
    let category: MemoryCategory
    let importance: MemoryImportance
    let tags: [String]
    let timestamp: Date
    
    public enum MemoryCategory: String {
        case conversation
        case integration
        case system
    }
    
    public enum MemoryImportance: Int {
        case low = 1
        case medium = 2
        case high = 3
    }
}

