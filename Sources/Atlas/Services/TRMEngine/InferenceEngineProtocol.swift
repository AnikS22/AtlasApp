//
//  InferenceEngineProtocol.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Protocol definition for inference engines
//

import Foundation

/// Protocol for AI inference engines
public protocol InferenceEngineProtocol: Sendable {
    /// Generate text response from prompt
    func generate(prompt: String, context: MemoryContext?) async throws -> String

    /// Generate embedding vector for text
    func generateEmbedding(for text: String) async throws -> [Float]

    /// Cancel ongoing generation
    func cancelGeneration()
}

/// Memory context for retrieval-augmented generation
public struct MemoryContext: Sendable {
    public let embeddings: [Float]
    public let relevantMessages: [InferenceMessage]
    public let similarity: Float

    public init(embeddings: [Float], relevantMessages: [InferenceMessage], similarity: Float) {
        self.embeddings = embeddings
        self.relevantMessages = relevantMessages
        self.similarity = similarity
    }
}

/// Message structure for TRM inference context
public struct InferenceMessage: Sendable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    public enum MessageRole: String, Sendable {
        case user
        case assistant
        case system
    }
}
