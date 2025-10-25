//
//  ConversationView.swift
//  Atlas
//
//  Message display and interaction view
//

import SwiftUI
import CoreData

struct ConversationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var appState: AppState

    let conversation: ConversationEntity

    @FetchRequest private var messages: FetchedResults<MessageEntity>

    @State private var messageText = ""
    @State private var isShowingVoiceInput = false
    @State private var scrollProxy: ScrollViewProxy?

    init(conversation: ConversationEntity) {
        self.conversation = conversation

        // Fetch messages for this conversation
        _messages = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: true)],
            predicate: NSPredicate(format: "conversation == %@", conversation),
            animation: .default
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                }
                .onChange(of: messages.count) { _ in
                    scrollToBottom()
                }
            }

            Divider()

            // Input Area
            messageInputView
        }
        .navigationTitle(conversation.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: renameConversation) {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(action: exportConversation) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive, action: clearConversation) {
                        Label("Clear Messages", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isShowingVoiceInput) {
            VoiceInputView(onTranscriptionComplete: handleVoiceInput)
        }
    }

    // MARK: - Message Input View
    private var messageInputView: some View {
        HStack(spacing: 12) {
            // Voice Input Button
            Button(action: { isShowingVoiceInput = true }) {
                Image(systemName: appState.isRecording ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundColor(appState.isRecording ? .red : .accentColor)
            }
            .disabled(appState.isProcessing)

            // Text Input
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .disabled(appState.isProcessing)

            // Send Button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(messageText.isEmpty ? .gray : .accentColor)
            }
            .disabled(messageText.isEmpty || appState.isProcessing)
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Message Bubble
    struct MessageBubble: View {
        let message: MessageEntity

        var body: some View {
            HStack {
                if message.isFromUser {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                    Text(message.content ?? "")
                        .padding(12)
                        .background(message.isFromUser ? Color.accentColor : Color(UIColor.secondarySystemBackground))
                        .foregroundColor(message.isFromUser ? .white : .primary)
                        .cornerRadius(16)

                    Text(message.timestamp?.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !message.isFromUser {
                    Spacer(minLength: 60)
                }
            }
        }
    }

    // MARK: - Actions
    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let userMessage = createMessage(content: messageText, isFromUser: true)
        messageText = ""

        // Simulate AI response (in production, this would call the Rust backend)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.isProcessing = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let aiResponse = createMessage(
                    content: "This is a simulated AI response. The actual implementation will integrate with the Rust backend for real AI processing.",
                    isFromUser: false
                )
                appState.isProcessing = false
            }
        }
    }

    private func handleVoiceInput(transcription: String) {
        messageText = transcription
        sendMessage()
    }

    private func createMessage(content: String, isFromUser: Bool) -> MessageEntity {
        let message = MessageEntity(context: viewContext)
        message.id = UUID()
        message.content = content
        message.timestamp = Date()
        message.isFromUser = isFromUser
        message.conversation = conversation

        conversation.updatedAt = Date()
        conversation.lastMessagePreview = content

        do {
            try viewContext.save()
        } catch {
            print("Error saving message: \(error.localizedDescription)")
        }

        return message
    }

    private func scrollToBottom() {
        guard let lastMessage = messages.last else { return }
        withAnimation {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    private func renameConversation() {
        // TODO: Implement rename dialog
        print("Rename conversation")
    }

    private func exportConversation() {
        // TODO: Implement export functionality
        print("Export conversation")
    }

    private func clearConversation() {
        messages.forEach { viewContext.delete($0) }

        do {
            try viewContext.save()
        } catch {
            print("Error clearing messages: \(error.localizedDescription)")
        }
    }
}
