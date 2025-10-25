//
//  Conversation.swift
//  Atlas
//
//  Conversation data model for in-memory representation
//

import Foundation

/// Represents a conversation containing multiple messages
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var metadata: ConversationMetadata?

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: ConversationMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

/// Additional metadata for conversations
struct ConversationMetadata: Codable {
    var tags: [String]?
    var modelConfiguration: ModelConfiguration?
    var totalTokensUsed: Int?
    var averageResponseTime: TimeInterval?
    var isPinned: Bool?

    init(
        tags: [String]? = nil,
        modelConfiguration: ModelConfiguration? = nil,
        totalTokensUsed: Int? = nil,
        averageResponseTime: TimeInterval? = nil,
        isPinned: Bool? = nil
    ) {
        self.tags = tags
        self.modelConfiguration = modelConfiguration
        self.totalTokensUsed = totalTokensUsed
        self.averageResponseTime = averageResponseTime
        self.isPinned = isPinned
    }
}

/// Model configuration settings
struct ModelConfiguration: Codable {
    var modelName: String
    var maxContextLength: Int
    var temperature: Double
    var topP: Double?
    var topK: Int?

    init(
        modelName: String = "phi-3.5-mini",
        maxContextLength: Int = 2048,
        temperature: Double = 0.7,
        topP: Double? = nil,
        topK: Int? = nil
    ) {
        self.modelName = modelName
        self.maxContextLength = maxContextLength
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
    }
}

// MARK: - Conversation Extensions
extension Conversation {
    /// Returns the last message in the conversation
    var lastMessage: Message? {
        return messages.last
    }

    /// Returns a preview of the last message
    var lastMessagePreview: String? {
        return lastMessage?.preview
    }

    /// Returns the total number of messages
    var messageCount: Int {
        return messages.count
    }

    /// Returns the number of user messages
    var userMessageCount: Int {
        return messages.filter { $0.isFromUser }.count
    }

    /// Returns the number of assistant messages
    var assistantMessageCount: Int {
        return messages.filter { !$0.isFromUser }.count
    }

    /// Adds a new message to the conversation
    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()

        // Update metadata
        if var meta = metadata {
            if let tokens = message.metadata?.tokenCount {
                meta.totalTokensUsed = (meta.totalTokensUsed ?? 0) + tokens
            }
            metadata = meta
        }
    }

    /// Removes a message from the conversation
    mutating func removeMessage(withId id: UUID) {
        messages.removeAll { $0.id == id }
        updatedAt = Date()
    }

    /// Clears all messages from the conversation
    mutating func clearMessages() {
        messages.removeAll()
        updatedAt = Date()
        metadata?.totalTokensUsed = 0
    }

    /// Updates the conversation title based on the first message
    mutating func generateTitle() {
        guard let firstMessage = messages.first(where: { $0.isFromUser }) else {
            return
        }

        let content = firstMessage.content
        let maxLength = 50

        if content.count <= maxLength {
            title = content
        } else {
            title = String(content.prefix(maxLength)) + "..."
        }
    }

    /// Exports conversation to JSON
    func exportToJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    /// Exports conversation to markdown
    func exportToMarkdown() -> String {
        var markdown = "# \(title)\n\n"
        markdown += "Created: \(createdAt.formatted())\n"
        markdown += "Updated: \(updatedAt.formatted())\n\n"
        markdown += "---\n\n"

        for message in messages {
            let sender = message.isFromUser ? "**You**" : "**Atlas**"
            let timestamp = message.timestamp.formatted(date: .omitted, time: .shortened)

            markdown += "\(sender) (\(timestamp)):\n\n"
            markdown += "\(message.content)\n\n"
            markdown += "---\n\n"
        }

        return markdown
    }
}

// MARK: - Sample Data
extension Conversation {
    static var sampleConversation: Conversation {
        Conversation(
            title: "Binary Search Tree Implementation",
            messages: Message.sampleMessages,
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: Date().addingTimeInterval(-120),
            metadata: ConversationMetadata(
                tags: ["coding", "swift", "data-structures"],
                modelConfiguration: ModelConfiguration(),
                totalTokensUsed: 450,
                averageResponseTime: 1.85
            )
        )
    }

    static var sampleConversations: [Conversation] {
        [
            sampleConversation,
            Conversation(
                title: "SwiftUI Layout Questions",
                messages: [
                    Message(
                        content: "How do I center a view in SwiftUI?",
                        timestamp: Date().addingTimeInterval(-7200),
                        isFromUser: true
                    )
                ],
                createdAt: Date().addingTimeInterval(-7200),
                updatedAt: Date().addingTimeInterval(-7200)
            ),
            Conversation(
                title: "Debugging Network Requests",
                messages: [],
                createdAt: Date().addingTimeInterval(-14400),
                updatedAt: Date().addingTimeInterval(-14400)
            )
        ]
    }
}
