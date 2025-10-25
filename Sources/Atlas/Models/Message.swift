//
//  Message.swift
//  Atlas
//
//  Message data model for in-memory representation
//

import Foundation

/// Represents a single message in a conversation
struct Message: Identifiable, Codable {
    let id: UUID
    var content: String
    let timestamp: Date
    let isFromUser: Bool
    var metadata: MessageMetadata?

    init(
        id: UUID = UUID(),
        content: String,
        timestamp: Date = Date(),
        isFromUser: Bool,
        metadata: MessageMetadata? = nil
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.isFromUser = isFromUser
        self.metadata = metadata
    }
}

/// Additional metadata for messages
struct MessageMetadata: Codable {
    var modelUsed: String?
    var processingTime: TimeInterval?
    var tokenCount: Int?
    var confidenceScore: Double?
    var voiceRecordingURL: URL?

    init(
        modelUsed: String? = nil,
        processingTime: TimeInterval? = nil,
        tokenCount: Int? = nil,
        confidenceScore: Double? = nil,
        voiceRecordingURL: URL? = nil
    ) {
        self.modelUsed = modelUsed
        self.processingTime = processingTime
        self.tokenCount = tokenCount
        self.confidenceScore = confidenceScore
        self.voiceRecordingURL = voiceRecordingURL
    }
}

// MARK: - Message Extensions
extension Message {
    /// Returns a preview of the message content
    var preview: String {
        let maxLength = 100
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }

    /// Checks if the message is a system message
    var isSystemMessage: Bool {
        return !isFromUser && (metadata?.modelUsed == nil || metadata?.modelUsed == "system")
    }

    /// Returns the message sender type
    var senderType: SenderType {
        return isFromUser ? .user : .assistant
    }
}

/// Enum representing message sender types
enum SenderType: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Sample Data
extension Message {
    static var sampleMessages: [Message] {
        [
            Message(
                content: "Hello! Can you help me with a coding problem?",
                timestamp: Date().addingTimeInterval(-300),
                isFromUser: true
            ),
            Message(
                content: "Of course! I'd be happy to help. What coding problem are you working on?",
                timestamp: Date().addingTimeInterval(-240),
                isFromUser: false,
                metadata: MessageMetadata(
                    modelUsed: "phi-3.5-mini",
                    processingTime: 1.2,
                    tokenCount: 23
                )
            ),
            Message(
                content: "I'm trying to implement a binary search tree in Swift.",
                timestamp: Date().addingTimeInterval(-180),
                isFromUser: true
            ),
            Message(
                content: "Great! A binary search tree is a fundamental data structure. Let me help you with that. Here's a basic implementation...",
                timestamp: Date().addingTimeInterval(-120),
                isFromUser: false,
                metadata: MessageMetadata(
                    modelUsed: "phi-3.5-mini",
                    processingTime: 2.5,
                    tokenCount: 156
                )
            )
        ]
    }
}
