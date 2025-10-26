//
//  ChatViewModel.swift
//  Atlas
//
//  Connects AI services to UI
//

import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var currentResponse = ""
    @Published var error: String?
    
    private let trmEngine: InferenceEngineProtocol
    private let ttsService: TextToSpeechService
    private let sttService: SpeechRecognitionService
    
    init() {
        // Use factory to automatically select best available engine
        self.trmEngine = TRMEngineFactory.createEngine()
        self.ttsService = TextToSpeechService()
        self.sttService = SpeechRecognitionService()
        
        print("✅ ChatViewModel initialized with TRM engine")
    }
    
    /// Process user message and generate AI response
    func sendMessage(_ text: String, conversation: inout Conversation) async {
        isProcessing = true
        error = nil
        
        do {
            // Add user message
            let userMessage = Message(
                content: text,
                isFromUser: true
            )
            conversation.addMessage(userMessage)
            
            // Generate AI response
            let response = try await trmEngine.generate(prompt: text, context: nil)
            
            // Add AI message
            let aiMessage = Message(
                content: response,
                isFromUser: false,
                metadata: MessageMetadata(
                    modelUsed: "local-trm",
                    processingTime: 0.5
                )
            )
            conversation.addMessage(aiMessage)
            
            currentResponse = response
            
            // Speak response
            try await ttsService.speak(text: response)
            
        } catch {
            self.error = error.localizedDescription
            print("❌ Error generating response: \(error)")
        }
        
        isProcessing = false
    }
    
    /// Transcribe voice input to text
    func transcribeVoice(_ audioURL: URL) async -> String? {
        do {
            // Use speech recognition service
            let result = try await sttService.transcribeAudioFile(audioURL)
            return result.transcript
        } catch {
            self.error = error.localizedDescription
            print("❌ Transcription error: \(error)")
            return nil
        }
    }
    
    /// Speak text using TTS
    func speakText(_ text: String) async {
        do {
            try await ttsService.speak(text: text)
        } catch {
            print("❌ TTS error: \(error)")
        }
    }
}

