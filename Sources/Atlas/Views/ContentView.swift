//
//  ContentView.swift
//  Atlas
//
//  Main chat interface with conversation list and message input
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var conversationStore = ConversationStore()

    @State private var selectedConversation: Conversation?
    @State private var showingNewConversation = false
    @State private var searchText = ""

    #if os(iOS)
    private var toolbarLeadingPlacement: ToolbarItemPlacement { .navigationBarLeading }
    private var toolbarTrailingPlacement: ToolbarItemPlacement { .navigationBarTrailing }
    #else
    private var toolbarLeadingPlacement: ToolbarItemPlacement { .automatic }
    private var toolbarTrailingPlacement: ToolbarItemPlacement { .automatic }
    #endif

    var body: some View {
        NavigationView {
            // Conversation List Sidebar
            conversationList

            // Main Chat View
            if let index = conversationStore.conversations.firstIndex(where: { $0.id == selectedConversation?.id }) {
                ConversationView(conversation: $conversationStore.conversations[index])
            } else {
                emptyStateView
            }
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
    }

    // MARK: - Conversation List
    private var conversationList: some View {
        List {
            ForEach(conversationStore.conversations) { conversation in
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
        }
        .navigationTitle("Atlas")
        .toolbar {
            ToolbarItem(placement: toolbarLeadingPlacement) {
                Button(action: { appState.isShowingSettings.toggle() }) {
                    Image(systemName: "gear")
                }
            }

            ToolbarItem(placement: toolbarTrailingPlacement) {
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
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversationStore.conversations
        } else {
            return conversationStore.conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Actions
    private func createNewConversation() {
        let newConversation = conversationStore.createConversation()
        selectedConversation = newConversation
        appState.currentConversationId = newConversation.id
    }

    private func deleteConversation(_ conversation: Conversation) {
        conversationStore.deleteConversation(conversation)
        if selectedConversation?.id == conversation.id {
            selectedConversation = conversationStore.conversations.first
        }
    }
}

// MARK: - Conversation Row
struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline)

            if let lastMessage = conversation.lastMessagePreview {
                Text(lastMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
