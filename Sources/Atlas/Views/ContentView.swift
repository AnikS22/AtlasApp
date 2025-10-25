//
//  ContentView.swift
//  Atlas
//
//  Main chat interface with conversation list and message input
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ConversationEntity.updatedAt, ascending: false)],
        animation: .default)
    private var conversations: FetchedResults<ConversationEntity>

    @State private var selectedConversation: ConversationEntity?
    @State private var showingNewConversation = false
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            // Conversation List Sidebar
            conversationList

            // Main Chat View
            if let conversation = selectedConversation {
                ConversationView(conversation: conversation)
            } else {
                emptyStateView
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }

    // MARK: - Conversation List
    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                ConversationRow(conversation: conversation)
                    .onTapGesture {
                        selectedConversation = conversation
                        appState.currentConversationId = conversation.id
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onDelete(perform: deleteConversations)
        }
        .navigationTitle("Atlas")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { appState.isShowingSettings.toggle() }) {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: createNewConversation) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .sheet(isPresented: $appState.isShowingSettings) {
            SettingsView()
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            Text("Welcome to Atlas")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your private AI companion")
                .font(.title3)
                .foregroundColor(.secondary)

            Button(action: createNewConversation) {
                Label("Start New Conversation", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    // MARK: - Filtered Conversations
    private var filteredConversations: [ConversationEntity] {
        if searchText.isEmpty {
            return Array(conversations)
        } else {
            return conversations.filter { conversation in
                conversation.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    // MARK: - Actions
    private func createNewConversation() {
        let newConversation = ConversationEntity(context: viewContext)
        newConversation.id = UUID()
        newConversation.title = "New Conversation"
        newConversation.createdAt = Date()
        newConversation.updatedAt = Date()

        do {
            try viewContext.save()
            selectedConversation = newConversation
            appState.currentConversationId = newConversation.id
        } catch {
            print("Error creating conversation: \(error.localizedDescription)")
        }
    }

    private func deleteConversation(_ conversation: ConversationEntity) {
        viewContext.delete(conversation)

        do {
            try viewContext.save()
            if selectedConversation?.id == conversation.id {
                selectedConversation = conversations.first
            }
        } catch {
            print("Error deleting conversation: \(error.localizedDescription)")
        }
    }

    private func deleteConversations(offsets: IndexSet) {
        withAnimation {
            offsets.map { conversations[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                print("Error deleting conversations: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: ConversationEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title ?? "Untitled")
                .font(.headline)

            if let lastMessage = conversation.lastMessagePreview {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Text(conversation.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(AppState())
    }
}
