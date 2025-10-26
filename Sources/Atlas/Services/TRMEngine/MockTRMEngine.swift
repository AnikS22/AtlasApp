//
//  MockTRMEngine.swift
//  Atlas
//
//  Mock TRM engine for testing without real model files
//  Replace with real TRMInferenceEngine once models are available
//

import Foundation
import CoreML

/// Mock TRM engine that simulates AI responses without requiring model files
@available(iOS 17.0, *)
public final class MockTRMEngine: InferenceEngineProtocol, @unchecked Sendable {
    
    private let isGeneratingLock = NSLock()
    private var _isGenerating = false
    private var isGenerating: Bool {
        get {
            isGeneratingLock.lock()
            defer { isGeneratingLock.unlock() }
            return _isGenerating
        }
        set {
            isGeneratingLock.lock()
            defer { isGeneratingLock.unlock() }
            _isGenerating = newValue
        }
    }
    private let responseDelay: TimeInterval
    
    public init(responseDelay: TimeInterval = 0.5) {
        self.responseDelay = responseDelay
    }
    
    // MARK: - InferenceEngineProtocol Implementation
    
    public func generate(prompt: String, context: MemoryContext?) async throws -> String {
        guard !isGenerating else {
            throw MockTRMError.concurrentGenerationNotAllowed
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Simulate processing time
        try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        
        // Generate contextual mock response
        let response = generateMockResponse(for: prompt, context: context)
        
        return response
    }
    
    public func generateEmbedding(for text: String) async throws -> [Float] {
        // Simulate embedding generation delay
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Generate deterministic embedding based on text
        let hash = abs(text.hashValue)
        var embedding = [Float](repeating: 0.0, count: 384)
        
        for i in 0..<384 {
            let seed = Float(hash + i)
            embedding[i] = sin(seed / 100.0) * 0.5
        }
        
        return embedding
    }
    
    public func cancelGeneration() {
        isGenerating = false
    }
    
    // MARK: - Mock Response Generation
    
    private func generateMockResponse(for prompt: String, context: MemoryContext?) -> String {
        let lowercased = prompt.lowercased()
        
        // Contextual responses based on prompt content
        if lowercased.contains("hello") || lowercased.contains("hi") {
            return "Hello! I'm Atlas, your local AI assistant. I'm currently running in mock mode while we load the TRM model. How can I help you today?"
        }
        
        if lowercased.contains("what") && lowercased.contains("name") {
            return "I'm Atlas, a privacy-first AI assistant that runs entirely on your device. All processing happens locally on your iPhone."
        }
        
        if lowercased.contains("how") && lowercased.contains("work") {
            return "I use a Tiny Recursive Model (TRM) that runs completely on your device. This means your conversations never leave your phone, ensuring complete privacy."
        }
        
        if lowercased.contains("email") {
            return "I can help you manage your emails once you connect your Gmail account in Settings. All email processing happens locally on your device."
        }
        
        if lowercased.contains("file") || lowercased.contains("drive") {
            return "I can access your Google Drive files once you connect your account. I'll fetch the files and analyze them locally on your device."
        }
        
        if lowercased.contains("weather") {
            return "I'm a local AI assistant, so I don't have real-time weather data. However, once you integrate weather APIs, I can help you understand weather information."
        }
        
        if lowercased.contains("code") || lowercased.contains("program") {
            return "I can help you with coding questions! I understand multiple programming languages including Swift, Python, JavaScript, and more."
        }
        
        if lowercased.contains("math") || containsNumbers(lowercased) {
            return "I can help with math! For example, if you ask '2+2', the answer is 4. Ask me any calculation and I'll help."
        }
        
        if lowercased.contains("privacy") || lowercased.contains("data") {
            return "Privacy is my core principle. Everything I process stays on your device. Your conversations, voice recordings, and data never leave your iPhone unless you explicitly choose to sync them."
        }
        
        if lowercased.contains("thank") {
            return "You're welcome! I'm here to help anytime. Remember, I'm running locally on your device for maximum privacy."
        }
        
        // Include context if available
        var response = "I understand you're asking about: '\(prompt)'. "
        
        if let context = context, !context.relevantMessages.isEmpty {
            response += "Based on our conversation history, I can see we've discussed related topics. "
        }
        
        response += "I'm currently in mock mode (TRM model not loaded yet), but I'm designed to provide intelligent, context-aware responses while keeping everything private on your device."
        
        return response
    }
    
    private func containsNumbers(_ text: String) -> Bool {
        return text.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

// MARK: - Mock Error Types

public enum MockTRMError: LocalizedError {
    case concurrentGenerationNotAllowed
    
    public var errorDescription: String? {
        switch self {
        case .concurrentGenerationNotAllowed:
            return "Cannot start generation while another is in progress."
        }
    }
}

// MARK: - Factory for Easy Switching

@available(iOS 17.0, *)
public enum TRMEngineFactory {
    /// Create TRM engine - automatically selects best available model
    /// Priority: Phi-3.5 → Real TRM → Mock
    public static func createEngine() -> InferenceEngineProtocol {
        // Try Phi-3.5 first (best for testing and general use)
        if let phi35 = try? Phi35Adapter() {
            print("✅ Using Phi-3.5-mini for inference")
            return phi35
        }

        // Try to create real TRM engine
        if let realEngine = try? TRMInferenceEngine() {
            print("✅ Using TRM for inference")
            return realEngine
        }

        // Fall back to mock
        print("⚠️ Models not found, using mock engine")
        return MockTRMEngine()
    }

    /// Force Phi-3.5 engine (for testing Phi-3.5 specifically)
    public static func createPhi35Engine() throws -> InferenceEngineProtocol {
        print("✅ Forcing Phi-3.5-mini engine")
        return try Phi35Adapter()
    }

    /// Force mock engine (for testing)
    public static func createMockEngine() -> InferenceEngineProtocol {
        print("⚠️ Using mock engine (forced)")
        return MockTRMEngine()
    }

    /// Force real TRM engine (will throw if models missing)
    public static func createRealEngine() throws -> InferenceEngineProtocol {
        print("✅ Using real TRM engine (forced)")
        return try TRMInferenceEngine()
    }
}

