//
//  TRMMemoryManager.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Memory pooling manager for efficient MLMultiArray reuse
//

import Foundation
import CoreML
import os.log

/// Manages memory allocation and pooling for TRM inference
public final class TRMMemoryManager {

    private let logger = Logger(subsystem: "io.atlas.trm", category: "MemoryManager")

    // Memory pool
    private var arrayPool: [PoolKey: [MLMultiArray]] = [:]
    private let poolLock = NSLock()

    // Configuration
    private let maxPoolSize: Int
    private var currentPoolSize: Int = 0

    // Statistics
    private var allocationCount: Int = 0
    private var reuseCount: Int = 0
    private var peakMemoryUsage: UInt64 = 0

    // MARK: - Pool Key

    private struct PoolKey: Hashable {
        let shape: [Int]
        let dataType: MLMultiArrayDataType

        func hash(into hasher: inout Hasher) {
            hasher.combine(shape)
            hasher.combine(dataType.rawValue)
        }
    }

    // MARK: - Initialization

    public init(poolSize: Int = 10) {
        self.maxPoolSize = poolSize
        logger.info("MemoryManager initialized with pool size: \(poolSize)")
    }

    // MARK: - Memory Acquisition

    /// Acquire an MLMultiArray from the pool or create new
    public func acquireMemory(shape: [Int], dataType: MLMultiArrayDataType) throws -> MLMultiArray {
        let key = PoolKey(shape: shape, dataType: dataType)

        poolLock.lock()
        defer { poolLock.unlock() }

        // Try to reuse from pool
        if var arrays = arrayPool[key], !arrays.isEmpty {
            let array = arrays.removeLast()
            arrayPool[key] = arrays
            currentPoolSize -= 1

            reuseCount += 1
            logger.debug("Reused array from pool (\(self.reuseCount) reuses total)")

            // Clear the array before reuse
            clearArray(array)

            return array
        }

        // Create new array
        guard let array = try? MLMultiArray(shape: shape as [NSNumber], dataType: dataType) else {
            logger.error("Failed to allocate MLMultiArray with shape: \(shape)")
            throw MemoryManagerError.allocationFailed(shape: shape, dataType: dataType)
        }

        allocationCount += 1
        logger.debug("Allocated new array (\(self.allocationCount) allocations total)")

        // Update peak memory
        updatePeakMemory()

        return array
    }

    /// Release an MLMultiArray back to the pool
    public func releaseMemory(_ array: MLMultiArray) {
        let shape = array.shape.map { $0.intValue }
        let key = PoolKey(shape: shape, dataType: array.dataType)

        poolLock.lock()
        defer { poolLock.unlock() }

        // Check if pool is full
        guard currentPoolSize < maxPoolSize else {
            logger.debug("Pool full, discarding array")
            return
        }

        // Add to pool
        if arrayPool[key] == nil {
            arrayPool[key] = []
        }

        arrayPool[key]?.append(array)
        currentPoolSize += 1

        logger.debug("Released array to pool (pool size: \(self.currentPoolSize))")
    }

    // MARK: - Batch Operations

    /// Acquire multiple arrays efficiently
    public func acquireMemoryBatch(count: Int, shape: [Int], dataType: MLMultiArrayDataType) throws -> [MLMultiArray] {
        var arrays: [MLMultiArray] = []
        arrays.reserveCapacity(count)

        for _ in 0..<count {
            let array = try acquireMemory(shape: shape, dataType: dataType)
            arrays.append(array)
        }

        return arrays
    }

    /// Release multiple arrays
    public func releaseMemoryBatch(_ arrays: [MLMultiArray]) {
        for array in arrays {
            releaseMemory(array)
        }
    }

    // MARK: - Pool Management

    /// Clear all pooled arrays
    public func clearPool() {
        poolLock.lock()
        defer { poolLock.unlock() }

        let clearedCount = currentPoolSize
        arrayPool.removeAll()
        currentPoolSize = 0

        logger.info("Cleared memory pool (\(clearedCount) arrays released)")
    }

    /// Trim pool to reduce memory usage
    public func trimPool(targetSize: Int = 0) {
        poolLock.lock()
        defer { poolLock.unlock() }

        var removedCount = 0

        for (key, var arrays) in arrayPool {
            let excessCount = arrays.count - targetSize
            if excessCount > 0 {
                arrays.removeLast(min(excessCount, arrays.count))
                arrayPool[key] = arrays
                removedCount += excessCount
                currentPoolSize -= excessCount
            }
        }

        logger.info("Trimmed pool: removed \(removedCount) arrays (new size: \(self.currentPoolSize))")
    }

    /// Optimize pool for low memory situations
    public func optimizeForLowMemory() {
        logger.warning("Low memory detected, optimizing pool...")

        // Trim to minimal size
        trimPool(targetSize: 2)

        // Force memory release
        arrayPool.removeAll(keepingCapacity: false)
        currentPoolSize = 0

        // Suggest garbage collection
        autoreleasepool {
            // Empty autoreleasepool to release memory
        }

        logger.info("Memory optimization complete")
    }

    // MARK: - Statistics

    public func getStatistics() -> MemoryStatistics {
        poolLock.lock()
        defer { poolLock.unlock() }

        return MemoryStatistics(
            totalAllocations: allocationCount,
            totalReuses: reuseCount,
            currentPoolSize: currentPoolSize,
            maxPoolSize: maxPoolSize,
            reuseRate: calculateReuseRate(),
            peakMemoryUsage: peakMemoryUsage
        )
    }

    public func resetStatistics() {
        poolLock.lock()
        defer { poolLock.unlock() }

        allocationCount = 0
        reuseCount = 0
        peakMemoryUsage = 0

        logger.info("Memory statistics reset")
    }

    // MARK: - Private Utilities

    private func clearArray(_ array: MLMultiArray) {
        // Zero out the array for security and consistency
        let count = array.count

        switch array.dataType {
        case .float16, .float32, .float64:
            for i in 0..<count {
                array[i] = 0.0
            }
        case .int32:
            for i in 0..<count {
                array[i] = 0
            }
        @unknown default:
            logger.warning("Unknown data type, skipping array clear")
        }
    }

    private func calculateReuseRate() -> Double {
        let total = allocationCount + reuseCount
        guard total > 0 else { return 0.0 }
        return Double(reuseCount) / Double(total)
    }

    private func updatePeakMemory() {
        let currentMemory = getMemoryUsage()
        if currentMemory > peakMemoryUsage {
            peakMemoryUsage = currentMemory
        }
    }

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

    // MARK: - Memory Pressure Handling

    public func handleMemoryWarning() {
        logger.warning("Memory warning received")
        optimizeForLowMemory()
    }

    deinit {
        clearPool()
        logger.info("MemoryManager deinitialized")
    }
}

// MARK: - Supporting Types

public struct MemoryStatistics {
    public let totalAllocations: Int
    public let totalReuses: Int
    public let currentPoolSize: Int
    public let maxPoolSize: Int
    public let reuseRate: Double
    public let peakMemoryUsage: UInt64

    public var peakMemoryMB: Double {
        Double(peakMemoryUsage) / 1024.0 / 1024.0
    }

    public var description: String {
        """
        Memory Statistics:
          Total Allocations: \(totalAllocations)
          Total Reuses: \(totalReuses)
          Reuse Rate: \(String(format: "%.1f%%", reuseRate * 100))
          Current Pool Size: \(currentPoolSize)/\(maxPoolSize)
          Peak Memory: \(String(format: "%.2f", peakMemoryMB)) MB
        """
    }
}

public enum MemoryManagerError: LocalizedError {
    case allocationFailed(shape: [Int], dataType: MLMultiArrayDataType)
    case poolExhausted
    case invalidArrayShape

    public var errorDescription: String? {
        switch self {
        case .allocationFailed(let shape, let dataType):
            return "Failed to allocate MLMultiArray with shape \(shape) and type \(dataType)"
        case .poolExhausted:
            return "Memory pool exhausted, cannot allocate more arrays"
        case .invalidArrayShape:
            return "Invalid array shape provided"
        }
    }
}
