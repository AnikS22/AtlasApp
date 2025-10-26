//
//  ConversationStore.swift
//  Atlas
//
//  Observable store for managing conversations and messages
//

import Foundation
import Combine

@MainActor
class ConversationStore: ObservableObject {
    @Published var conversations: [Conversation] = []
    
    init() {
        // Load from storage or start empty
        loadConversations()
    }
    
    func createConversation() -> Conversation {
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        saveConversations()
        return conversation
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        saveConversations()
    }
    
    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            saveConversations()
        }
    }
    
    func addMessage(to conversationId: UUID, _ message: Message) {
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            var conversation = conversations[index]
            conversation.addMessage(message)
            conversations[index] = conversation
            saveConversations()
        }
    }
    
    private func loadConversations() {
        // TODO: Load from SQLite DatabaseManager
        // For now, start with sample data
        conversations = []
    }
    
    private func saveConversations() {
        // TODO: Save to SQLite DatabaseManager
        // For now, just in-memory
    }
}

