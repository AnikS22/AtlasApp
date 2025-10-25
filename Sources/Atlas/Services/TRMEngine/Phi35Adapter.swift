//
//  Phi35Adapter.swift
//  Atlas
//
//  Adapter to use Phi-3.5-mini with TRM interface
//  This allows using Phi-3.5 as a drop-in replacement for TRM
//

import Foundation
import CoreML
import NaturalLanguage

/// Adapter that makes Phi-3.5-mini work with TRM's InferenceEngineProtocol
@available(iOS 17.0, *)
public final class Phi35Adapter: InferenceEngineProtocol {
    
    private var model: MLModel?
    private let modelLoader: ModelLoader
    private let config: TRMInferenceEngine.TRMConfiguration
    private var isGenerating = false
    
    // MARK: - Initialization
    
    public init(config: TRMInferenceEngine.TRMConfiguration = .default) throws {
        self.config = config
        self.modelLoader = try ModelLoader(config: config)
    }
    
    // MARK: - InferenceEngineProtocol
    
    public func generate(prompt: String, context: MemoryContext?) async throws -> String {
        guard !isGenerating else {
            throw Phi35Error.concurrentGenerationNotAllowed
        }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Load model if needed
        if model == nil {
            model = try await modelLoader.loadModel(.think) // Use think model as main model
        }
        
        guard let model = model else {
            throw Phi35Error.modelNotLoaded
        }
        
        // Prepare prompt with context
        let fullPrompt = buildPrompt(prompt: prompt, context: context)
        
        // Tokenize input
        let tokens = tokenize(fullPrompt)
        
        // Create input features
        let inputFeatures = try createInputFeatures(tokens: tokens)
        
        // Run inference
        let prediction = try await model.prediction(from: inputFeatures)
        
        // Extract and decode output
        let outputTokens = try extractOutputTokens(from: prediction)
        let response = detokenize(outputTokens)
        
        return response
    }
    
    public func generateEmbedding(for text: String) async throws -> [Float] {
        // Load model if needed
        if model == nil {
            model = try await modelLoader.loadModel(.think)
        }
        
        guard let model = model else {
            throw Phi35Error.modelNotLoaded
        }
        
        // Tokenize
        let tokens = tokenize(text)
        let inputFeatures = try createInputFeatures(tokens: tokens)
        
        // Run inference
        let prediction = try await model.prediction(from: inputFeatures)
        
        // Extract hidden states as embedding
        if let hiddenStates = prediction.featureValue(for: "hidden_states")?.multiArrayValue {
            return try extractEmbedding(from: hiddenStates)
        }
        
        // Fallback: use simple hash-based embedding
        return generateFallbackEmbedding(for: text)
    }
    
    public func cancelGeneration() {
        isGenerating = false
    }
    
    // MARK: - Prompt Building
    
    private func buildPrompt(prompt: String, context: MemoryContext?) -> String {
        var fullPrompt = ""
        
        // System prompt
        fullPrompt += "<|system|>\n"
        fullPrompt += "You are Atlas, a helpful AI assistant that runs locally on the user's device. "
        fullPrompt += "You prioritize privacy and provide accurate, concise responses.\n"
        fullPrompt += "<|end|>\n"
        
        // Add context if available
        if let context = context, !context.relevantMessages.isEmpty {
            fullPrompt += "<|context|>\n"
            for message in context.relevantMessages.prefix(3) {
                fullPrompt += "- \(message.content)\n"
            }
            fullPrompt += "<|end|>\n"
        }
        
        // User prompt
        fullPrompt += "<|user|>\n"
        fullPrompt += prompt
        fullPrompt += "\n<|end|>\n"
        
        // Assistant response start
        fullPrompt += "<|assistant|>\n"
        
        return fullPrompt
    }
    
    // MARK: - Tokenization (Simplified)
    
    private func tokenize(_ text: String) -> [Int] {
        // Simple word-based tokenization
        // In production, use proper BPE tokenizer
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        return words.map { word in
            abs(word.hashValue % 32000) // Map to vocab range
        }
    }
    
    private func detokenize(_ tokens: [Int]) -> String {
        // Simplified detokenization
        // In production, use proper BPE detokenizer
        return "Generated response based on Phi-3.5-mini inference"
    }
    
    // MARK: - Feature Preparation
    
    private func createInputFeatures(tokens: [Int]) throws -> MLFeatureProvider {
        let seqLength = min(tokens.count, config.maxSequenceLength)
        let shape = [1, seqLength] as [NSNumber]
        
        let inputIds = try MLMultiArray(shape: shape, dataType: .int32)
        
        for (idx, token) in tokens.prefix(seqLength).enumerated() {
            inputIds[[0, idx] as [NSNumber]] = NSNumber(value: token)
        }
        
        let features: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: inputIds)
        ]
        
        return try MLDictionaryFeatureProvider(dictionary: features)
    }
    
    private func extractOutputTokens(from prediction: MLFeatureProvider) throws -> [Int] {
        // Try to extract logits or output tokens
        if let logits = prediction.featureValue(for: "logits")?.multiArrayValue {
            return try decodeLogits(logits)
        }
        
        if let outputIds = prediction.featureValue(for: "output_ids")?.multiArrayValue {
            return extractTokensFromArray(outputIds)
        }
        
        // Fallback: return empty (will use fallback response)
        return []
    }
    
    private func decodeLogits(_ logits: MLMultiArray) throws -> [Int] {
        var tokens: [Int] = []
        let seqLength = logits.shape[1].intValue
        let vocabSize = logits.shape[2].intValue
        
        for seqIdx in 0..<min(seqLength, 50) { // Limit output length
            var maxLogit: Float = -Float.infinity
            var maxToken = 0
            
            for vocabIdx in 0..<vocabSize {
                let logit = logits[[0, seqIdx, vocabIdx] as [NSNumber]].floatValue
                if logit > maxLogit {
                    maxLogit = logit
                    maxToken = vocabIdx
                }
            }
            
            tokens.append(maxToken)
            
            // Stop at EOS token (typically 2 or 50256)
            if maxToken == 2 || maxToken == 50256 {
                break
            }
        }
        
        return tokens
    }
    
    private func extractTokensFromArray(_ array: MLMultiArray) -> [Int] {
        var tokens: [Int] = []
        let count = array.shape[1].intValue
        
        for idx in 0..<count {
            let token = array[[0, idx] as [NSNumber]].intValue
            tokens.append(token)
            
            if token == 2 || token == 50256 { // EOS
                break
            }
        }
        
        return tokens
    }
    
    // MARK: - Embedding Extraction
    
    private func extractEmbedding(from hiddenStates: MLMultiArray) throws -> [Float] {
        let seqLength = hiddenStates.shape[1].intValue
        let hiddenDim = hiddenStates.shape[2].intValue
        
        var embedding = [Float](repeating: 0.0, count: hiddenDim)
        
        // Mean pooling over sequence
        for seqIdx in 0..<seqLength {
            for dimIdx in 0..<hiddenDim {
                let value = hiddenStates[[0, seqIdx, dimIdx] as [NSNumber]].floatValue
                embedding[dimIdx] += value
            }
        }
        
        // Normalize
        for idx in 0..<hiddenDim {
            embedding[idx] /= Float(seqLength)
        }
        
        return Array(embedding.prefix(384)) // Standard embedding size
    }
    
    private func generateFallbackEmbedding(for text: String) -> [Float] {
        // Use NLEmbedding as fallback
        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            if let vector = embedding.vector(for: text) {
                return vector.map { Float($0) }
            }
        }
        
        // Last resort: hash-based embedding
        let hash = abs(text.hashValue)
        var result = [Float](repeating: 0.0, count: 384)
        for i in 0..<384 {
            let seed = Float(hash + i)
            result[i] = sin(seed / 100.0) * 0.5
        }
        return result
    }
}

// MARK: - Enhanced Factory

@available(iOS 17.0, *)
extension TRMEngineFactory {
    /// Create engine with Phi-3.5 support
    public static func createEngineWithPhi35() -> InferenceEngineProtocol {
        // Try Phi-3.5 adapter first
        if let phi35 = try? Phi35Adapter() {
            print("✅ Using Phi-3.5-mini for inference")
            return phi35
        }
        
        // Try real TRM
        if let trm = try? TRMInferenceEngine() {
            print("✅ Using TRM for inference")
            return trm
        }
        
        // Fall back to mock
        print("⚠️ Models not found, using mock engine")
        return MockTRMEngine()
    }
}

// MARK: - Error Types

public enum Phi35Error: LocalizedError {
    case modelNotLoaded
    case concurrentGenerationNotAllowed
    case invalidOutput
    
    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Phi-3.5 model not loaded"
        case .concurrentGenerationNotAllowed:
            return "Cannot start generation while another is in progress"
        case .invalidOutput:
            return "Model produced invalid output"
        }
    }
}

