//
//  Llama32Adapter.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Adapter for Llama 3.2 1B model to work with TRM inference engine
//

import Foundation
import CoreML
import Combine

/// Adapter that enables Llama 3.2 1B to work with the TRM inference pipeline
@available(iOS 17.0, *)
public final class Llama32Adapter: InferenceEngineProtocol, @unchecked Sendable {

    // MARK: - Properties

    private nonisolated(unsafe) let modelLoader: ModelLoader
    private nonisolated(unsafe) let tokenProcessor: TokenProcessor
    private nonisolated(unsafe) let performanceMonitor: PerformanceMonitor
    private nonisolated(unsafe) let config: TRMInferenceEngine.TRMConfiguration

    private var llamaModel: MLModel?
    private var currentTask: Task<String, Error>?

    // Thread safety
    private let lock = NSLock()
    private var isGenerating = false

    // MARK: - Initialization

    public init(
        config: TRMInferenceEngine.TRMConfiguration = .default,
        modelLoader: ModelLoader? = nil,
        tokenProcessor: TokenProcessor? = nil
    ) throws {
        self.config = config
        if let loader = modelLoader {
            self.modelLoader = loader
        } else {
            self.modelLoader = try ModelLoader(config: config)
        }
        if let processor = tokenProcessor {
            self.tokenProcessor = processor
        } else {
            self.tokenProcessor = try TokenProcessor()
        }
        self.performanceMonitor = PerformanceMonitor()

        // Pre-load model
        Task {
            try await warmUp()
        }
    }

    // MARK: - InferenceEngineProtocol Implementation

    public func generate(prompt: String, context: MemoryContext?) async throws -> String {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Check if already generating
        lock.lock()
        guard !isGenerating else {
            lock.unlock()
            throw TRMError.concurrentGenerationNotAllowed
        }
        isGenerating = true
        lock.unlock()

        defer {
            lock.lock()
            isGenerating = false
            lock.unlock()
        }

        do {
            // Load model if needed
            try await ensureModelLoaded()

            // Tokenize input
            let tokenizeStart = CFAbsoluteTimeGetCurrent()
            let tokens = try tokenProcessor.tokenize(prompt)
            let tokenizeTime = CFAbsoluteTimeGetCurrent() - tokenizeStart

            // Prepare input tensor
            let inputTensor = try prepareInputTensor(tokens: tokens, context: context)

            // Run inference
            let inferenceResult = try await runLlamaInference(input: inputTensor)

            // Detokenize output
            let detokenizeStart = CFAbsoluteTimeGetCurrent()
            let response = try tokenProcessor.detokenize(inferenceResult.outputTokens)
            let detokenizeTime = CFAbsoluteTimeGetCurrent() - detokenizeStart

            let totalTime = CFAbsoluteTimeGetCurrent() - startTime

            // Record metrics
            let metrics = InferenceMetrics(
                totalTime: totalTime,
                tokenizationTime: tokenizeTime,
                inferenceTime: inferenceResult.inferenceTime,
                detokenizationTime: detokenizeTime,
                iterations: inferenceResult.iterations,
                tokensGenerated: inferenceResult.outputTokens.count,
                converged: inferenceResult.converged
            )

            performanceMonitor.recordInference(metrics)

            return response

        } catch {
            performanceMonitor.recordError(error)
            throw TRMError.inferenceFailed(underlyingError: error)
        }
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        try await ensureModelLoaded()

        let tokens = try tokenProcessor.tokenize(text)
        let inputTensor = try prepareInputTensor(tokens: tokens, context: nil)

        guard let llamaModel = llamaModel else {
            throw TRMError.modelNotLoaded
        }

        // Run one forward pass to get embeddings
        let features = try createFeatures(input: inputTensor)
        let prediction = try await llamaModel.prediction(from: features)

        // Extract embeddings from model output
        // Note: This depends on Llama model's output format
        guard let output = prediction.featureValue(for: "output")?.multiArrayValue ??
                         prediction.featureValue(for: "last_hidden_state")?.multiArrayValue else {
            throw TRMError.invalidModelOutput
        }

        // Pool the output to get fixed-size embedding
        let embedding = try poolToEmbedding(output)

        return embedding
    }

    public func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil

        lock.lock()
        isGenerating = false
        lock.unlock()
    }

    // MARK: - Model Management

    private func ensureModelLoaded() async throws {
        if llamaModel == nil {
            try await loadLlamaModel()
        }
    }

    private func loadLlamaModel() async throws {
        let loadStart = CFAbsoluteTimeGetCurrent()

        // Load Llama 3.2 1B model from bundle
        guard let modelURL = Bundle.main.url(forResource: "Llama3.21B2Gb/model", withExtension: nil) else {
            // Try alternative path
            if let modelsPath = Bundle.main.resourcePath {
                let fullPath = modelsPath + "/Models/Llama3.21B2Gb/model"
                if FileManager.default.fileExists(atPath: fullPath) {
                    let url = URL(fileURLWithPath: fullPath)
                    self.llamaModel = try await loadFromURL(url)
                    let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
                    performanceMonitor.recordModelLoad(duration: loadTime)
                    return
                } else {
                    throw TRMError.modelLoadFailed(underlyingError: ModelLoaderError.modelNotFound(type: .think))
                }
            } else {
                throw TRMError.modelLoadFailed(underlyingError: ModelLoaderError.modelNotFound(type: .think))
            }
        }

        if llamaModel == nil {
            self.llamaModel = try await loadFromURL(modelURL)
        }

        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        performanceMonitor.recordModelLoad(duration: loadTime)
    }

    private func loadFromURL(_ url: URL) async throws -> MLModel {
        let modelConfig = createModelConfiguration()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let model = try MLModel(contentsOf: url, configuration: modelConfig)
                    continuation.resume(returning: model)
                } catch {
                    continuation.resume(throwing: TRMError.modelLoadFailed(underlyingError: error))
                }
            }
        }
    }

    private func createModelConfiguration() -> MLModelConfiguration {
        let modelConfig = MLModelConfiguration()

        if config.useNeuralEngine {
            modelConfig.computeUnits = .all
        } else {
            modelConfig.computeUnits = .cpuAndGPU
        }

        modelConfig.allowLowPrecisionAccumulationOnGPU = true

        return modelConfig
    }

    public func warmUp() async throws {
        try await ensureModelLoaded()

        // Run dummy inference
        let dummyPrompt = "Hello"
        _ = try await generate(prompt: dummyPrompt, context: nil)
    }

    public func unloadModels() {
        llamaModel = nil
    }

    // MARK: - Inference Implementation

    private struct InferenceResult {
        let outputTokens: [Int]
        let iterations: Int
        let converged: Bool
        let inferenceTime: TimeInterval
    }

    private func runLlamaInference(input: MLMultiArray) async throws -> InferenceResult {
        let inferenceStart = CFAbsoluteTimeGetCurrent()

        guard let llamaModel = llamaModel else {
            throw TRMError.modelNotLoaded
        }

        var outputTokens: [Int] = []
        let maxTokens = min(config.maxSequenceLength, 512)

        // Autoregressive generation
        for iteration in 0..<maxTokens {
            // Create input features
            let features = try createFeatures(input: input)

            // Run inference
            let prediction = try await llamaModel.prediction(from: features)

            // Extract next token
            guard let output = extractNextToken(from: prediction) else {
                throw TRMError.invalidModelOutput
            }

            outputTokens.append(output)

            // Check for end of sequence
            if output == tokenProcessor.eosToken {
                break
            }

            // Check for cancellation
            if Task.isCancelled {
                throw TRMError.generationCancelled
            }
        }

        let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStart

        return InferenceResult(
            outputTokens: outputTokens,
            iterations: outputTokens.count,
            converged: true,
            inferenceTime: inferenceTime
        )
    }

    // MARK: - Feature Preparation

    private func prepareInputTensor(tokens: [Int], context: MemoryContext?) throws -> MLMultiArray {
        let seqLength = min(tokens.count, config.maxSequenceLength)
        let shape = [1, seqLength, config.inputDim] as [NSNumber]

        let inputArray = try MLMultiArray(shape: shape, dataType: .float16)

        // Convert tokens to embeddings
        for (idx, token) in tokens.prefix(seqLength).enumerated() {
            let embedding = try tokenProcessor.getEmbedding(for: token)

            for (embIdx, value) in embedding.enumerated() {
                let index = [0, idx, embIdx] as [NSNumber]
                inputArray[index] = NSNumber(value: value)
            }
        }

        // Incorporate context if available
        if let context = context {
            try incorporateContext(context, into: inputArray)
        }

        return inputArray
    }

    private func createFeatures(input: MLMultiArray) throws -> MLFeatureProvider {
        let features: [String: MLFeatureValue] = [
            "input_ids": MLFeatureValue(multiArray: input)
        ]
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func extractNextToken(from prediction: MLFeatureProvider) -> Int? {
        // Try common output names for Llama models
        let outputNames = ["logits", "output", "next_token", "token_ids"]

        for name in outputNames {
            if let output = prediction.featureValue(for: name)?.multiArrayValue {
                // Get the argmax (most likely token)
                var maxValue: Float = -Float.infinity
                var maxIndex = 0

                for i in 0..<output.count {
                    let value = output[i].floatValue
                    if value > maxValue {
                        maxValue = value
                        maxIndex = i
                    }
                }

                return maxIndex
            }
        }

        return nil
    }

    private func poolToEmbedding(_ multiArray: MLMultiArray) throws -> [Float] {
        let totalElements = multiArray.count
        let hiddenDim = min(config.hiddenDim, totalElements)

        var embedding = [Float](repeating: 0.0, count: hiddenDim)

        // Mean pooling
        for i in 0..<hiddenDim {
            embedding[i] = multiArray[i].floatValue
        }

        // Normalize
        let norm = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if norm > 0 {
            for i in 0..<hiddenDim {
                embedding[i] /= norm
            }
        }

        return embedding
    }

    private func incorporateContext(_ context: MemoryContext, into input: MLMultiArray) throws {
        if context.embeddings.isEmpty { return }

        let contextWeight: Float = 0.3
        let hiddenDim = min(config.inputDim, context.embeddings.count)

        for seqIdx in 0..<input.shape[1].intValue {
            for dimIdx in 0..<hiddenDim {
                let index = [0, seqIdx, dimIdx] as [NSNumber]
                let currentValue = input[index].floatValue
                let contextValue = context.embeddings[dimIdx]
                input[index] = NSNumber(value: currentValue + contextWeight * contextValue)
            }
        }
    }

    // MARK: - Performance Monitoring

    public func getPerformanceMetrics() -> PerformanceMetrics {
        return performanceMonitor.getCurrentMetrics()
    }

    public func resetMetrics() {
        performanceMonitor.reset()
    }
}

// MARK: - Factory Extension

extension TRMEngineFactory {
    /// Create Llama 3.2 1B adapter engine
    static func createLlamaEngine(config: TRMInferenceEngine.TRMConfiguration = .default) -> InferenceEngineProtocol {
        do {
            return try Llama32Adapter(config: config)
        } catch {
            print("⚠️ Failed to create Llama adapter: \(error). Falling back to mock engine.")
            return MockTRMEngine()
        }
    }
}
