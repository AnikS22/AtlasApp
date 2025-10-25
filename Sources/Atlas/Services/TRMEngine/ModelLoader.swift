//
//  ModelLoader.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Core ML model loading and management for TRM inference
//

import Foundation
import CoreML
import os.log

/// Manages loading and caching of Core ML models
@available(iOS 17.0, *)
public final class ModelLoader {

    private let logger = Logger(subsystem: "io.atlas.trm", category: "ModelLoader")
    private let config: TRMInferenceEngine.TRMConfiguration

    // Model cache
    private var loadedModels: [ModelType: MLModel] = [:]
    private let cacheLock = NSLock()

    // MARK: - Model Types

    public enum ModelType: String {
        case think = "ThinkModel"
        case act = "ActModel"

        var filename: String {
            switch self {
            case .think: return "ThinkModel_4bit"
            case .act: return "ActModel_4bit"
            }
        }

        var fallbackFilename: String {
            switch self {
            case .think: return "ThinkModel_fp16"
            case .act: return "ActModel_fp16"
            }
        }
    }

    // MARK: - Initialization

    public init(config: TRMInferenceEngine.TRMConfiguration) throws {
        self.config = config
    }

    // MARK: - Model Loading

    /// Load a specific model type with caching
    public func loadModel(_ type: ModelType) async throws -> MLModel {
        // Check cache first
        cacheLock.lock()
        if let cached = loadedModels[type] {
            cacheLock.unlock()
            logger.info("Using cached \(type.rawValue) model")
            return cached
        }
        cacheLock.unlock()

        // Load model from bundle
        logger.info("Loading \(type.rawValue) model from bundle...")
        let loadStart = CFAbsoluteTimeGetCurrent()

        let model = try await loadModelFromBundle(type)

        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        logger.info("\(type.rawValue) model loaded in \(String(format: "%.2f", loadTime * 1000))ms")

        // Cache the loaded model
        cacheLock.lock()
        loadedModels[type] = model
        cacheLock.unlock()

        return model
    }

    /// Load model from app bundle with fallback strategy
    private func loadModelFromBundle(_ type: ModelType) async throws -> MLModel {
        // Try to load 4-bit quantized version first
        if let model = try? await loadModelFile(type.filename, type: type) {
            logger.info("Loaded 4-bit quantized \(type.rawValue) model")
            return model
        }

        // Fall back to FP16 version
        logger.warning("4-bit model not found, falling back to FP16 for \(type.rawValue)")
        if let model = try? await loadModelFile(type.fallbackFilename, type: type) {
            logger.info("Loaded FP16 \(type.rawValue) model")
            return model
        }

        // No model found
        logger.error("Failed to find \(type.rawValue) model in bundle")
        throw ModelLoaderError.modelNotFound(type: type)
    }

    /// Load specific model file
    private func loadModelFile(_ filename: String, type: ModelType) async throws -> MLModel {
        // Try .mlmodelc (compiled) first
        if let compiledURL = Bundle.main.url(forResource: filename, withExtension: "mlmodelc") {
            return try await loadFromURL(compiledURL)
        }

        // Try .mlpackage
        if let packageURL = Bundle.main.url(forResource: filename, withExtension: "mlpackage") {
            return try await loadFromURL(packageURL)
        }

        throw ModelLoaderError.modelFileNotFound(filename: filename)
    }

    /// Load model from URL with configuration
    private func loadFromURL(_ url: URL) async throws -> MLModel {
        let modelConfig = createModelConfiguration()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let model = try MLModel(contentsOf: url, configuration: modelConfig)
                    continuation.resume(returning: model)
                } catch {
                    continuation.resume(throwing: ModelLoaderError.loadFailed(underlyingError: error))
                }
            }
        }
    }

    /// Create optimized model configuration
    private func createModelConfiguration() -> MLModelConfiguration {
        let modelConfig = MLModelConfiguration()

        // Configure compute units based on settings
        if config.useNeuralEngine {
            modelConfig.computeUnits = .all  // CPU + GPU + Neural Engine
            logger.info("Model configured for Neural Engine acceleration")
        } else {
            modelConfig.computeUnits = .cpuAndGPU
            logger.info("Model configured for CPU+GPU only")
        }

        // Enable low precision accumulation for better performance
        modelConfig.allowLowPrecisionAccumulationOnGPU = true

        // Set preferred metal device (if available)
        #if !targetEnvironment(simulator)
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            modelConfig.preferredMetalDevice = metalDevice
        }
        #endif

        return modelConfig
    }

    // MARK: - Model Management

    /// Unload a specific model from cache
    public func unloadModel(_ type: ModelType) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if loadedModels.removeValue(forKey: type) != nil {
            logger.info("Unloaded \(type.rawValue) model from cache")
        }
    }

    /// Unload all cached models
    public func unloadAllModels() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let count = loadedModels.count
        loadedModels.removeAll()
        logger.info("Unloaded \(count) models from cache")
    }

    /// Check if a model is currently loaded
    public func isModelLoaded(_ type: ModelType) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return loadedModels[type] != nil
    }

    /// Get model metadata
    public func getModelMetadata(_ type: ModelType) async throws -> ModelMetadata {
        let model = try await loadModel(type)

        let description = model.modelDescription
        let inputDescriptions = description.inputDescriptionsByName
        let outputDescriptions = description.outputDescriptionsByName

        return ModelMetadata(
            type: type,
            inputDescriptions: inputDescriptions,
            outputDescriptions: outputDescriptions,
            metadata: description.metadata[MLModelMetadataKey.description] as? String ?? "No description"
        )
    }

    /// Estimate model memory footprint
    public func estimateMemoryUsage(_ type: ModelType) async throws -> MemoryEstimate {
        let model = try await loadModel(type)

        // Get initial memory usage
        let initialMemory = getMemoryUsage()

        // Create dummy input to trigger model initialization
        let inputDescriptions = model.modelDescription.inputDescriptionsByName
        var dummyInputs: [String: MLFeatureValue] = [:]

        for (name, description) in inputDescriptions {
            if let constraint = description.multiArrayConstraint {
                let shape = constraint.shape
                let dummyArray = try MLMultiArray(shape: shape, dataType: .float16)
                dummyInputs[name] = MLFeatureValue(multiArray: dummyArray)
            }
        }

        if !dummyInputs.isEmpty {
            let provider = try MLDictionaryFeatureProvider(dictionary: dummyInputs)
            _ = try model.prediction(from: provider)
        }

        // Get memory after initialization
        let finalMemory = getMemoryUsage()
        let modelMemory = finalMemory - initialMemory

        return MemoryEstimate(
            modelType: type,
            staticMemory: modelMemory,
            estimatedRuntimeMemory: modelMemory * 2, // Rough estimate
            totalEstimate: modelMemory * 3
        )
    }

    // MARK: - Utilities

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return kerr == KERN_SUCCESS ? info.resident_size : 0
    }
}

// MARK: - Supporting Types

public struct ModelMetadata {
    let type: ModelLoader.ModelType
    let inputDescriptions: [String: MLFeatureDescription]
    let outputDescriptions: [String: MLFeatureDescription]
    let metadata: String
}

public struct MemoryEstimate {
    let modelType: ModelLoader.ModelType
    let staticMemory: UInt64
    let estimatedRuntimeMemory: UInt64
    let totalEstimate: UInt64

    var staticMemoryMB: Double {
        Double(staticMemory) / 1024.0 / 1024.0
    }

    var runtimeMemoryMB: Double {
        Double(estimatedRuntimeMemory) / 1024.0 / 1024.0
    }

    var totalEstimateMB: Double {
        Double(totalEstimate) / 1024.0 / 1024.0
    }
}

// MARK: - Error Types

public enum ModelLoaderError: LocalizedError {
    case modelNotFound(type: ModelLoader.ModelType)
    case modelFileNotFound(filename: String)
    case loadFailed(underlyingError: Error)
    case compilationFailed(underlyingError: Error)
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let type):
            return "Model '\(type.rawValue)' not found in app bundle"
        case .modelFileNotFound(let filename):
            return "Model file '\(filename)' not found"
        case .loadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .compilationFailed(let error):
            return "Failed to compile model: \(error.localizedDescription)"
        case .invalidConfiguration:
            return "Invalid model configuration"
        }
    }
}
