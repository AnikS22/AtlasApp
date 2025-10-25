//
//  AIService.swift
//  Atlas
//
//  AI service that integrates TRM/Phi-3.5 inference with memory and context
//

import Foundation

@available(iOS 17.0, *)
public actor AIService {

    private let inferenceEngine: InferenceEngineProtocol

    // MARK: - Initialization

    public init(
        inferenceEngine: InferenceEngineProtocol? = nil
    ) {
        // Use provided engine or create default
        self.inferenceEngine = inferenceEngine ?? TRMEngineFactory.createEngine()

        print("🤖 AIService initialized with \(type(of: self.inferenceEngine))")
    }

    // MARK: - Message Generation

    /// Generate AI response for a user message with optional conversation context
    public func generateResponse(
        for userMessage: String,
        context: MemoryContext? = nil
    ) async throws -> String {

        // Generate response using inference engine
        let response = try await inferenceEngine.generate(
            prompt: userMessage,
            context: context
        )

        return response
    }

    /// Generate embedding for text (useful for semantic search)
    public func generateEmbedding(for text: String) async throws -> [Float] {
        return try await inferenceEngine.generateEmbedding(for: text)
    }

    /// Cancel any ongoing generation
    public func cancelGeneration() {
        inferenceEngine.cancelGeneration()
    }

    // MARK: - Context Management

    /// Build memory context from recent messages
    public func buildContext(
        from messages: [InferenceMessage],
        currentMessage: String
    ) async throws -> MemoryContext {

        // Generate embedding for the current message
        let messageEmbedding = try await inferenceEngine.generateEmbedding(for: currentMessage)

        // Calculate similarity score (simplified for now)
        let similarity: Float = messages.isEmpty ? 0.0 : 0.85

        return MemoryContext(
            embeddings: messageEmbedding,
            relevantMessages: messages,
            similarity: similarity
        )
    }

    // MARK: - Engine Information

    /// Get information about the current inference engine
    public func getEngineInfo() -> String {
        let engineType = String(describing: type(of: inferenceEngine))

        if engineType.contains("Phi35") {
            return "Phi-3.5-mini (3.8B parameters)"
        } else if engineType.contains("TRMInferenceEngine") {
            return "TRM (Tiny Recursive Model)"
        } else {
            return "Mock Engine (Testing)"
        }
    }
}

