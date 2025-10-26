//
//  Phi35Adapter.swift
//  Atlas
//
//  Adapter for Phi-3.5-mini CoreML model to work with TRM interface
//

import Foundation
import CoreML

@available(iOS 17.0, *)
public final class Phi35Adapter: InferenceEngineProtocol, @unchecked Sendable {
    
    private let modelLock = NSLock()
    private var _model: MLModel?
    private var model: MLModel? {
        get {
            modelLock.lock()
            defer { modelLock.unlock() }
            return _model
        }
        set {
            modelLock.lock()
            defer { modelLock.unlock() }
            _model = newValue
        }
    }
    
    private let isGeneratingLock = NSLock()
    private var _isGenerating = false
    private var isGenerating: Bool {
        get {
            isGeneratingLock.lock()
            defer { isGeneratingLock.unlock() }
            return _isGenerating
        }
        set {
            isGeneratingLock.lock()
            defer { isGeneratingLock.unlock() }
            _isGenerating = newValue
        }
    }
    
    public init() throws {
        try loadModel()
    }
    
    private func loadModel() throws {
        // Try to load Phi-3.5-mini from bundle
        if let modelURL = Bundle.main.url(forResource: "phi-3-mini-4k-instruct", withExtension: "mlmodelc") ??
                          Bundle.main.url(forResource: "phi-3-mini-4k-instruct", withExtension: "mlpackage") {
            let config = MLModelConfiguration()
            config.computeUnits = .all // Use Neural Engine
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
        } else {
            throw Phi35Error.modelNotFound
        }
    }
    
    public func generate(prompt: String, context: MemoryContext?) async throws -> String {
        guard let model = model else {
            throw Phi35Error.modelNotLoaded
        }
        
        guard !isGenerating else {
            throw Phi35Error.concurrentGenerationNotAllowed
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Prepare input with context if available
        var fullPrompt = prompt
        if let context = context, !context.relevantMessages.isEmpty {
            fullPrompt = buildContextualPrompt(prompt: prompt, context: context)
        }
        
        // Run inference (implementation depends on Phi-3.5 input format)
        // This is a placeholder - actual implementation depends on the model
        let response = try await runInference(prompt: fullPrompt, model: model)
        
        return response
    }
    
    public func generateEmbedding(for text: String) async throws -> [Float] {
        // Phi-3.5 can generate embeddings from hidden states
        // Simplified implementation
        guard let model = model else {
            throw Phi35Error.modelNotLoaded
        }
        
        // This would use the model's intermediate representations
        // For now, return deterministic embedding
        let hash = abs(text.hashValue)
        var embedding = [Float](repeating: 0.0, count: 384)
        
        for i in 0..<384 {
            let seed = Float(hash + i)
            embedding[i] = sin(seed / 100.0) * 0.5
        }
        
        return embedding
    }
    
    public func cancelGeneration() {
        isGenerating = false
    }
    
    private func buildContextualPrompt(prompt: String, context: MemoryContext) -> String {
        var contextText = "Previous conversation:\n"
        for msg in context.relevantMessages.prefix(5) {
            contextText += "- \(msg.content)\n"
        }
        return "\(contextText)\nCurrent question: \(prompt)"
    }
    
    private func runInference(prompt: String, model: MLModel) async throws -> String {
        // This is a simplified implementation
        // Actual implementation depends on Phi-3.5 model's input/output format
        
        // For now, return a placeholder that indicates Phi-3.5 would process this
        return "Phi-3.5 response to: \(prompt)"
    }
}

public enum Phi35Error: LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case concurrentGenerationNotAllowed
    case inferenceFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Phi-3.5-mini model not found in app bundle"
        case .modelNotLoaded:
            return "Phi-3.5-mini model not loaded"
        case .concurrentGenerationNotAllowed:
            return "Cannot start generation while another is in progress"
        case .inferenceFailed(let error):
            return "Inference failed: \(error.localizedDescription)"
        }
    }
}
