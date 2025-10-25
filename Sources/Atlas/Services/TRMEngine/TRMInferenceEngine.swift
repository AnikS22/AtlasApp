//
//  TRMInferenceEngine.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  TRM (Tiny Recursive Model) Inference Engine
//  Implements recursive think-act cycles for on-device AI inference
//

import Foundation
import CoreML
import Combine

/// Main inference engine for TRM model with recursive reasoning
@available(iOS 17.0, *)
public final class TRMInferenceEngine: InferenceEngineProtocol {

    // MARK: - Properties

    private let modelLoader: ModelLoader
    private let tokenProcessor: TokenProcessor
    private let memoryManager: TRMMemoryManager
    private let performanceMonitor: PerformanceMonitor
    private let config: TRMConfiguration

    private var thinkModel: MLModel?
    private var actModel: MLModel?

    private var currentTask: Task<String, Error>?
    private let taskQueue = DispatchQueue(label: "io.atlas.trm.inference", qos: .userInitiated)

    // Thread safety
    private let lock = NSLock()
    private var isGenerating = false

    // MARK: - Configuration

    public struct TRMConfiguration {
        let maxIterations: Int
        let confidenceThreshold: Float
        let inputDim: Int
        let hiddenDim: Int
        let maxSequenceLength: Int
        let useNeuralEngine: Bool
        let enableStreaming: Bool
        let memoryPoolSize: Int
        let targetTokensPerSecond: Int

        public static let `default` = TRMConfiguration(
            maxIterations: 16,
            confidenceThreshold: 0.95,
            inputDim: 256,
            hiddenDim: 512,
            maxSequenceLength: 2048,
            useNeuralEngine: true,
            enableStreaming: true,
            memoryPoolSize: 10,
            targetTokensPerSecond: 30
        )

        public static let lowPower = TRMConfiguration(
            maxIterations: 8,
            confidenceThreshold: 0.90,
            inputDim: 256,
            hiddenDim: 512,
            maxSequenceLength: 1024,
            useNeuralEngine: true,
            enableStreaming: false,
            memoryPoolSize: 5,
            targetTokensPerSecond: 20
        )
    }

    // MARK: - Initialization

    public init(
        config: TRMConfiguration = .default,
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
        self.memoryManager = TRMMemoryManager(poolSize: config.memoryPoolSize)
        self.performanceMonitor = PerformanceMonitor()

        // Pre-load models on initialization
        Task {
            try await warmUp()
        }
    }

    // MARK: - InferenceEngineProtocol Implementation

    /// Generate response using TRM recursive inference
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
            // Load models if needed
            try await ensureModelsLoaded()

            // Tokenize input
            let tokenizeStart = CFAbsoluteTimeGetCurrent()
            let tokens = try tokenProcessor.tokenize(prompt)
            let tokenizeTime = CFAbsoluteTimeGetCurrent() - tokenizeStart

            // Prepare input tensor
            let inputTensor = try prepareInputTensor(tokens: tokens, context: context)

            // Run recursive inference
            let inferenceResult = try await runRecursiveInference(input: inputTensor)

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

    /// Generate embedding for text
    public func generateEmbedding(for text: String) async throws -> [Float] {
        try await ensureModelsLoaded()

        let tokens = try tokenProcessor.tokenize(text)
        let inputTensor = try prepareInputTensor(tokens: tokens, context: nil)

        // Use think model's intermediate representation as embedding
        guard let thinkModel = thinkModel else {
            throw TRMError.modelNotLoaded
        }

        // Initialize memory states
        let yInit = try memoryManager.acquireMemory(
            shape: [1, tokens.count, config.hiddenDim],
            dataType: .float16
        )
        let zInit = try memoryManager.acquireMemory(
            shape: [1, tokens.count, config.hiddenDim],
            dataType: .float16
        )

        // Run one think step to get embedding
        let features = try createThinkFeatures(x: inputTensor, y: yInit, z: zInit)
        let prediction = try await thinkModel.prediction(from: features)

        guard let zOutput = prediction.featureValue(for: "z_new")?.multiArrayValue else {
            throw TRMError.invalidModelOutput
        }

        // Pool the output to get fixed-size embedding
        let embedding = try poolToEmbedding(zOutput)

        // Release memory
        memoryManager.releaseMemory(yInit)
        memoryManager.releaseMemory(zInit)

        return embedding
    }

    /// Cancel ongoing generation
    public func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil

        lock.lock()
        isGenerating = false
        lock.unlock()
    }

    // MARK: - Recursive Inference Implementation

    private struct InferenceResult {
        let outputTokens: [Int]
        let iterations: Int
        let converged: Bool
        let inferenceTime: TimeInterval
    }

    /// Core recursive inference loop implementing think-act cycles
    private func runRecursiveInference(input: MLMultiArray) async throws -> InferenceResult {
        let inferenceStart = CFAbsoluteTimeGetCurrent()

        guard let thinkModel = thinkModel, let actModel = actModel else {
            throw TRMError.modelNotLoaded
        }

        // Initialize memory states (y: solution, z: scratchpad)
        var y = try initializeSolution(inputShape: input.shape)
        var z = try initializeScratchpad(inputShape: input.shape)

        var iterations = 0
        var converged = false
        var outputTokens: [Int] = []

        // Recursive reasoning loop (adaptive halting: 1-16 iterations)
        for step in 0..<config.maxIterations {
            iterations = step + 1

            // Think step: z ← f(x, y, z) - latent reasoning
            let thinkStepStart = CFAbsoluteTimeGetCurrent()
            let thinkFeatures = try createThinkFeatures(x: input, y: y, z: z)
            let thinkPrediction = try await thinkModel.prediction(from: thinkFeatures)

            guard let zNew = thinkPrediction.featureValue(for: "z_new")?.multiArrayValue else {
                throw TRMError.invalidModelOutput
            }
            z = zNew
            let thinkTime = CFAbsoluteTimeGetCurrent() - thinkStepStart

            // Act step: y ← g(y, z) - solution refinement
            let actStepStart = CFAbsoluteTimeGetCurrent()
            let actFeatures = try createActFeatures(y: y, z: z)
            let actPrediction = try await actModel.prediction(from: actFeatures)

            guard let yNew = actPrediction.featureValue(for: "y_new")?.multiArrayValue,
                  let confidenceValue = actPrediction.featureValue(for: "confidence")?.multiArrayValue else {
                throw TRMError.invalidModelOutput
            }
            y = yNew

            // Extract confidence score
            let confidence = Float(confidenceValue[0].floatValue)
            let actTime = CFAbsoluteTimeGetCurrent() - actStepStart

            // Record step metrics
            performanceMonitor.recordStep(
                iteration: step,
                thinkTime: thinkTime,
                actTime: actTime,
                confidence: confidence
            )

            // Stream token if enabled
            if config.enableStreaming {
                let token = try extractCurrentToken(from: y)
                outputTokens.append(token)
            }

            // Adaptive halting: stop if confident enough
            if confidence >= config.confidenceThreshold {
                converged = true
                break
            }

            // Check for task cancellation
            if Task.isCancelled {
                throw TRMError.generationCancelled
            }
        }

        // Extract final output tokens if not streaming
        if !config.enableStreaming {
            outputTokens = try extractTokens(from: y)
        }

        // Release memory
        memoryManager.releaseMemory(y)
        memoryManager.releaseMemory(z)

        let inferenceTime = CFAbsoluteTimeGetCurrent() - inferenceStart

        return InferenceResult(
            outputTokens: outputTokens,
            iterations: iterations,
            converged: converged,
            inferenceTime: inferenceTime
        )
    }

    // MARK: - Model Management

    private func ensureModelsLoaded() async throws {
        if thinkModel == nil || actModel == nil {
            try await loadModels()
        }
    }

    private func loadModels() async throws {
        let loadStart = CFAbsoluteTimeGetCurrent()

        // Load think and act models concurrently
        async let thinkTask = modelLoader.loadModel(.think)
        async let actTask = modelLoader.loadModel(.act)

        let (think, act) = try await (thinkTask, actTask)

        self.thinkModel = think
        self.actModel = act

        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        performanceMonitor.recordModelLoad(duration: loadTime)
    }

    public func warmUp() async throws {
        try await ensureModelsLoaded()

        // Run dummy inference to warm up Neural Engine
        let dummyPrompt = "Hello"
        _ = try await generate(prompt: dummyPrompt, context: nil)
    }

    public func unloadModels() {
        thinkModel = nil
        actModel = nil
        memoryManager.clearPool()
    }

    // MARK: - Memory Initialization

    private func initializeSolution(inputShape: [NSNumber]) throws -> MLMultiArray {
        let shape = [1, inputShape[1].intValue, config.hiddenDim] as [NSNumber]
        let array = try memoryManager.acquireMemory(shape: shape.map { $0.intValue }, dataType: .float16)

        // Initialize with zeros (or learned initialization if available)
        for i in 0..<array.count {
            array[i] = 0.0
        }

        return array
    }

    private func initializeScratchpad(inputShape: [NSNumber]) throws -> MLMultiArray {
        let shape = [1, inputShape[1].intValue, config.hiddenDim] as [NSNumber]
        let array = try memoryManager.acquireMemory(shape: shape.map { $0.intValue }, dataType: .float16)

        // Initialize scratchpad
        for i in 0..<array.count {
            array[i] = 0.0
        }

        return array
    }

    // MARK: - Feature Preparation

    private func prepareInputTensor(tokens: [Int], context: MemoryContext?) throws -> MLMultiArray {
        let seqLength = min(tokens.count, config.maxSequenceLength)
        let shape = [1, seqLength, config.inputDim] as [NSNumber]

        let inputArray = try memoryManager.acquireMemory(
            shape: shape.map { $0.intValue },
            dataType: .float16
        )

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

    private func createThinkFeatures(x: MLMultiArray, y: MLMultiArray, z: MLMultiArray) throws -> MLFeatureProvider {
        let features: [String: MLFeatureValue] = [
            "x_input": MLFeatureValue(multiArray: x),
            "y_prev": MLFeatureValue(multiArray: y),
            "z_prev": MLFeatureValue(multiArray: z)
        ]
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func createActFeatures(y: MLMultiArray, z: MLMultiArray) throws -> MLFeatureProvider {
        let features: [String: MLFeatureValue] = [
            "y_prev": MLFeatureValue(multiArray: y),
            "z_current": MLFeatureValue(multiArray: z)
        ]
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    // MARK: - Token Extraction

    private func extractTokens(from solution: MLMultiArray) throws -> [Int] {
        var tokens: [Int] = []
        let seqLength = solution.shape[1].intValue
        let hiddenDim = solution.shape[2].intValue

        for seqIdx in 0..<seqLength {
            // Extract hidden state at position
            var hiddenState: [Float] = []
            for dimIdx in 0..<hiddenDim {
                let index = [0, seqIdx, dimIdx] as [NSNumber]
                hiddenState.append(solution[index].floatValue)
            }

            // Convert hidden state to token
            let token = try tokenProcessor.hiddenToToken(hiddenState)
            tokens.append(token)

            // Stop at end-of-sequence token
            if token == tokenProcessor.eosToken {
                break
            }
        }

        return tokens
    }

    private func extractCurrentToken(from solution: MLMultiArray) throws -> Int {
        // Extract the most recent token from solution
        let seqLength = solution.shape[1].intValue
        let lastIdx = seqLength - 1

        var hiddenState: [Float] = []
        for dimIdx in 0..<solution.shape[2].intValue {
            let index = [0, lastIdx, dimIdx] as [NSNumber]
            hiddenState.append(solution[index].floatValue)
        }

        return try tokenProcessor.hiddenToToken(hiddenState)
    }

    private func poolToEmbedding(_ multiArray: MLMultiArray) throws -> [Float] {
        let seqLength = multiArray.shape[1].intValue
        let hiddenDim = multiArray.shape[2].intValue

        var embedding = [Float](repeating: 0.0, count: hiddenDim)

        // Mean pooling across sequence dimension
        for seqIdx in 0..<seqLength {
            for dimIdx in 0..<hiddenDim {
                let index = [0, seqIdx, dimIdx] as [NSNumber]
                embedding[dimIdx] += multiArray[index].floatValue
            }
        }

        // Normalize
        for idx in 0..<hiddenDim {
            embedding[idx] /= Float(seqLength)
        }

        return embedding
    }

    private func incorporateContext(_ context: MemoryContext, into input: MLMultiArray) throws {
        // Blend context embeddings into input
        // Implementation depends on specific context integration strategy
        // For now, we'll add context as a weighted sum

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

// MARK: - Supporting Types

public struct InferenceMetrics {
    let totalTime: TimeInterval
    let tokenizationTime: TimeInterval
    let inferenceTime: TimeInterval
    let detokenizationTime: TimeInterval
    let iterations: Int
    let tokensGenerated: Int
    let converged: Bool

    var tokensPerSecond: Double {
        guard inferenceTime > 0 else { return 0 }
        return Double(tokensGenerated) / inferenceTime
    }

    var iterationsPerSecond: Double {
        guard inferenceTime > 0 else { return 0 }
        return Double(iterations) / inferenceTime
    }
}

public struct PerformanceMetrics {
    let averageInferenceTime: TimeInterval
    let averageTokensPerSecond: Double
    let averageIterations: Double
    let convergenceRate: Double
    let totalInferences: Int
    let errorCount: Int
    let peakMemoryUsage: UInt64
}

// MARK: - Error Types

public enum TRMError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(underlyingError: Error)
    case invalidModelOutput
    case invalidInput
    case tokenizationFailed(underlyingError: Error)
    case detokenizationFailed(underlyingError: Error)
    case inferenceFailed(underlyingError: Error)
    case memoryAllocationFailed
    case concurrentGenerationNotAllowed
    case generationCancelled
    case configurationError(message: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "TRM model is not loaded. Please initialize the inference engine."
        case .modelLoadFailed(let error):
            return "Failed to load TRM model: \(error.localizedDescription)"
        case .invalidModelOutput:
            return "Model produced invalid output format."
        case .invalidInput:
            return "Input data is invalid or malformed."
        case .tokenizationFailed(let error):
            return "Failed to tokenize input: \(error.localizedDescription)"
        case .detokenizationFailed(let error):
            return "Failed to detokenize output: \(error.localizedDescription)"
        case .inferenceFailed(let error):
            return "Inference failed: \(error.localizedDescription)"
        case .memoryAllocationFailed:
            return "Failed to allocate memory for inference."
        case .concurrentGenerationNotAllowed:
            return "Cannot start generation while another is in progress."
        case .generationCancelled:
            return "Generation was cancelled."
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
