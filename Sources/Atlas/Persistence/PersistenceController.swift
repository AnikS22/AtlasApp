//
//  PersistenceController.swift
//  Atlas
//
//  CoreData persistence controller with encryption support
//

import CoreData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    // Preview instance for SwiftUI previews
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample data for previews
        for i in 0..<5 {
            let conversation = ConversationEntity(context: viewContext)
            conversation.id = UUID()
            conversation.title = "Sample Conversation \(i + 1)"
            conversation.createdAt = Date().addingTimeInterval(-Double(i * 3600))
            conversation.updatedAt = Date().addingTimeInterval(-Double(i * 1800))

            // Add sample messages
            for j in 0..<3 {
                let message = MessageEntity(context: viewContext)
                message.id = UUID()
                message.content = "Sample message \(j + 1) in conversation \(i + 1)"
                message.timestamp = Date().addingTimeInterval(-Double(j * 600))
                message.isFromUser = j % 2 == 0
                message.conversation = conversation
            }

            conversation.lastMessagePreview = "Sample message 3 in conversation \(i + 1)"
        }

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Atlas")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            #if os(iOS)
            // Enable encryption for the persistent store (iOS only)
            container.persistentStoreDescriptions.first?.setOption(
                FileProtectionType.complete as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
            #endif
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // In production, handle this error appropriately
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save Context
    func save() {
        let context = container.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // MARK: - Batch Operations
    func deleteAllData() async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            // Delete all messages
            let messageFetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
            let messageDeleteRequest = NSBatchDeleteRequest(fetchRequest: messageFetchRequest)
            try context.execute(messageDeleteRequest)

            // Delete all conversations
            let conversationFetchRequest: NSFetchRequest<NSFetchRequestResult> = ConversationEntity.fetchRequest()
            let conversationDeleteRequest = NSBatchDeleteRequest(fetchRequest: conversationFetchRequest)
            try context.execute(conversationDeleteRequest)

            try context.save()
        }
    }

    func exportAllData() async throws -> Data {
        let context = container.viewContext

        return try await context.perform {
            let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ConversationEntity.createdAt, ascending: true)]

            let conversations = try context.fetch(fetchRequest)

            // Convert to exportable format
            let exportData = conversations.map { conversation in
                ExportConversation(
                    id: conversation.id ?? UUID(),
                    title: conversation.title ?? "Untitled",
                    createdAt: conversation.createdAt ?? Date(),
                    updatedAt: conversation.updatedAt ?? Date(),
                    messages: (conversation.messages?.allObjects as? [MessageEntity] ?? []).map { message in
                        ExportMessage(
                            id: message.id ?? UUID(),
                            content: message.content ?? "",
                            timestamp: message.timestamp ?? Date(),
                            isFromUser: message.isFromUser
                        )
                    }
                )
            }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            return try encoder.encode(exportData)
        }
    }

    func importData(from data: Data) async throws {
        let context = container.newBackgroundContext()

        try await context.perform {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let exportData = try decoder.decode([ExportConversation].self, from: data)

            for exportConversation in exportData {
                let conversation = ConversationEntity(context: context)
                conversation.id = exportConversation.id
                conversation.title = exportConversation.title
                conversation.createdAt = exportConversation.createdAt
                conversation.updatedAt = exportConversation.updatedAt

                for exportMessage in exportConversation.messages {
                    let message = MessageEntity(context: context)
                    message.id = exportMessage.id
                    message.content = exportMessage.content
                    message.timestamp = exportMessage.timestamp
                    message.isFromUser = exportMessage.isFromUser
                    message.conversation = conversation
                }

                if let lastMessage = exportConversation.messages.last {
                    conversation.lastMessagePreview = lastMessage.content
                }
            }

            try context.save()
        }
    }

    // MARK: - Statistics
    func getDatabaseStatistics() async -> DatabaseStatistics {
        let context = container.viewContext

        return await context.perform {
            let conversationCount = (try? context.count(for: ConversationEntity.fetchRequest())) ?? 0
            let messageCount = (try? context.count(for: MessageEntity.fetchRequest())) ?? 0

            // Calculate database size
            let storeURL = self.container.persistentStoreDescriptions.first?.url
            var dbSize: Int64 = 0

            if let url = storeURL,
               let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                dbSize = fileSize
            }

            return DatabaseStatistics(
                conversationCount: conversationCount,
                messageCount: messageCount,
                databaseSize: dbSize
            )
        }
    }
}

// MARK: - Export Models
struct ExportConversation: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [ExportMessage]
}

struct ExportMessage: Codable {
    let id: UUID
    let content: String
    let timestamp: Date
    let isFromUser: Bool
}

// MARK: - Database Statistics
struct DatabaseStatistics {
    let conversationCount: Int
    let messageCount: Int
    let databaseSize: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file)
    }
}
