//
//  PerformanceMonitor.swift
//  Atlas
//
//  Created by Atlas Development Team
//  Copyright © 2025 Atlas. All rights reserved.
//
//  Performance monitoring and metrics tracking for TRM inference
//

import Foundation
import os.log

/// Monitors and tracks TRM inference performance metrics
public final class PerformanceMonitor {

    private let logger = Logger(subsystem: "io.atlas.trm", category: "Performance")

    // Metrics storage
    private var inferenceMetrics: [InferenceMetrics] = []
    private var stepMetrics: [StepMetrics] = []
    private var errorLog: [ErrorRecord] = []

    private let metricsLock = NSLock()

    // Configuration
    private let maxStoredMetrics: Int = 100
    private let maxStoredSteps: Int = 1000
    private let maxStoredErrors: Int = 50

    // Aggregated statistics
    private var totalInferences: Int = 0
    private var totalErrors: Int = 0
    private var modelLoadDuration: TimeInterval = 0

    // MARK: - Initialization

    public init() {
        logger.info("PerformanceMonitor initialized")
    }

    // MARK: - Recording Methods

    /// Record inference metrics
    public func recordInference(_ metrics: InferenceMetrics) {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        inferenceMetrics.append(metrics)
        totalInferences += 1

        // Trim if needed
        if inferenceMetrics.count > maxStoredMetrics {
            inferenceMetrics.removeFirst(inferenceMetrics.count - maxStoredMetrics)
        }

        // Log if performance is below target
        if metrics.tokensPerSecond < 30.0 {
            logger.warning("⚠️ Low performance: \(String(format: "%.1f", metrics.tokensPerSecond)) tokens/sec")
        }

        logger.debug("Inference completed: \(String(format: "%.2f", metrics.totalTime * 1000))ms, \(String(format: "%.1f", metrics.tokensPerSecond)) tok/s")
    }

    /// Record individual step metrics (think-act cycle)
    public func recordStep(iteration: Int, thinkTime: TimeInterval, actTime: TimeInterval, confidence: Float) {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let step = StepMetrics(
            iteration: iteration,
            thinkTime: thinkTime,
            actTime: actTime,
            confidence: confidence,
            timestamp: Date()
        )

        stepMetrics.append(step)

        // Trim if needed
        if stepMetrics.count > maxStoredSteps {
            stepMetrics.removeFirst(stepMetrics.count - maxStoredSteps)
        }

        logger.debug("Step \(iteration): think=\(String(format: "%.2f", thinkTime * 1000))ms, act=\(String(format: "%.2f", actTime * 1000))ms, conf=\(String(format: "%.2f", confidence))")
    }

    /// Record error occurrence
    public func recordError(_ error: Error) {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let record = ErrorRecord(
            error: error,
            timestamp: Date(),
            description: error.localizedDescription
        )

        errorLog.append(record)
        totalErrors += 1

        // Trim if needed
        if errorLog.count > maxStoredErrors {
            errorLog.removeFirst(errorLog.count - maxStoredErrors)
        }

        logger.error("Error recorded: \(error.localizedDescription)")
    }

    /// Record model loading time
    public func recordModelLoad(duration: TimeInterval) {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        modelLoadDuration = duration
        logger.info("Model loaded in \(String(format: "%.2f", duration * 1000))ms")
    }

    // MARK: - Statistics Retrieval

    /// Get current performance metrics
    public func getCurrentMetrics() -> PerformanceMetrics {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let avgInferenceTime = calculateAverageInferenceTime()
        let avgTokensPerSecond = calculateAverageTokensPerSecond()
        let avgIterations = calculateAverageIterations()
        let convergenceRate = calculateConvergenceRate()
        let peakMemory = getPeakMemoryUsage()

        return PerformanceMetrics(
            averageInferenceTime: avgInferenceTime,
            averageTokensPerSecond: avgTokensPerSecond,
            averageIterations: avgIterations,
            convergenceRate: convergenceRate,
            totalInferences: totalInferences,
            errorCount: totalErrors,
            peakMemoryUsage: peakMemory
        )
    }

    /// Get detailed step metrics for recent inferences
    public func getRecentStepMetrics(count: Int = 10) -> [StepMetrics] {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let recentCount = min(count, stepMetrics.count)
        return Array(stepMetrics.suffix(recentCount))
    }

    /// Get error history
    public func getRecentErrors(count: Int = 10) -> [ErrorRecord] {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let recentCount = min(count, errorLog.count)
        return Array(errorLog.suffix(recentCount))
    }

    /// Get comprehensive performance report
    public func getPerformanceReport() -> PerformanceReport {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        let currentMetrics = PerformanceMetrics(
            averageInferenceTime: calculateAverageInferenceTime(),
            averageTokensPerSecond: calculateAverageTokensPerSecond(),
            averageIterations: calculateAverageIterations(),
            convergenceRate: calculateConvergenceRate(),
            totalInferences: totalInferences,
            errorCount: totalErrors,
            peakMemoryUsage: getPeakMemoryUsage()
        )

        let thinkActBreakdown = calculateThinkActBreakdown()
        let confidenceDistribution = calculateConfidenceDistribution()
        let bottlenecks = identifyBottlenecks()

        return PerformanceReport(
            metrics: currentMetrics,
            modelLoadTime: modelLoadDuration,
            thinkTimeAverage: thinkActBreakdown.thinkTime,
            actTimeAverage: thinkActBreakdown.actTime,
            confidenceDistribution: confidenceDistribution,
            bottlenecks: bottlenecks,
            recommendations: generateRecommendations(currentMetrics)
        )
    }

    // MARK: - Reset Methods

    /// Reset all metrics
    public func reset() {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        inferenceMetrics.removeAll()
        stepMetrics.removeAll()
        errorLog.removeAll()
        totalInferences = 0
        totalErrors = 0

        logger.info("Performance metrics reset")
    }

    /// Clear error log
    public func clearErrors() {
        metricsLock.lock()
        defer { metricsLock.unlock() }

        errorLog.removeAll()
        totalErrors = 0

        logger.info("Error log cleared")
    }

    // MARK: - Analysis Methods

    private func calculateAverageInferenceTime() -> TimeInterval {
        guard !inferenceMetrics.isEmpty else { return 0 }
        let total = inferenceMetrics.reduce(0.0) { $0 + $1.inferenceTime }
        return total / Double(inferenceMetrics.count)
    }

    private func calculateAverageTokensPerSecond() -> Double {
        guard !inferenceMetrics.isEmpty else { return 0 }
        let total = inferenceMetrics.reduce(0.0) { $0 + $1.tokensPerSecond }
        return total / Double(inferenceMetrics.count)
    }

    private func calculateAverageIterations() -> Double {
        guard !inferenceMetrics.isEmpty else { return 0 }
        let total = inferenceMetrics.reduce(0) { $0 + $1.iterations }
        return Double(total) / Double(inferenceMetrics.count)
    }

    private func calculateConvergenceRate() -> Double {
        guard !inferenceMetrics.isEmpty else { return 0 }
        let converged = inferenceMetrics.filter { $0.converged }.count
        return Double(converged) / Double(inferenceMetrics.count)
    }

    private func calculateThinkActBreakdown() -> (thinkTime: TimeInterval, actTime: TimeInterval) {
        guard !stepMetrics.isEmpty else { return (0, 0) }

        let totalThink = stepMetrics.reduce(0.0) { $0 + $1.thinkTime }
        let totalAct = stepMetrics.reduce(0.0) { $0 + $1.actTime }

        return (
            thinkTime: totalThink / Double(stepMetrics.count),
            actTime: totalAct / Double(stepMetrics.count)
        )
    }

    private func calculateConfidenceDistribution() -> ConfidenceDistribution {
        guard !stepMetrics.isEmpty else {
            return ConfidenceDistribution(low: 0, medium: 0, high: 0, average: 0)
        }

        var low = 0
        var medium = 0
        var high = 0
        var total: Float = 0

        for step in stepMetrics {
            total += step.confidence

            if step.confidence < 0.7 {
                low += 1
            } else if step.confidence < 0.9 {
                medium += 1
            } else {
                high += 1
            }
        }

        return ConfidenceDistribution(
            low: low,
            medium: medium,
            high: high,
            average: total / Float(stepMetrics.count)
        )
    }

    private func identifyBottlenecks() -> [String] {
        var bottlenecks: [String] = []

        // Check average tokens per second
        let avgTPS = calculateAverageTokensPerSecond()
        if avgTPS < 30.0 {
            bottlenecks.append("Low tokens/sec: \(String(format: "%.1f", avgTPS)) (target: 30+)")
        }

        // Check convergence rate
        let convRate = calculateConvergenceRate()
        if convRate < 0.7 {
            bottlenecks.append("Low convergence rate: \(String(format: "%.1f%%", convRate * 100)) (target: 70%+)")
        }

        // Check think-act balance
        let breakdown = calculateThinkActBreakdown()
        let thinkRatio = breakdown.thinkTime / (breakdown.thinkTime + breakdown.actTime)
        if thinkRatio > 0.6 || thinkRatio < 0.4 {
            bottlenecks.append("Imbalanced think-act ratio: \(String(format: "%.1f%%", thinkRatio * 100)) think")
        }

        // Check error rate
        let errorRate = Double(totalErrors) / max(Double(totalInferences), 1.0)
        if errorRate > 0.05 {
            bottlenecks.append("High error rate: \(String(format: "%.1f%%", errorRate * 100))")
        }

        return bottlenecks
    }

    private func generateRecommendations(_ metrics: PerformanceMetrics) -> [String] {
        var recommendations: [String] = []

        // Performance recommendations
        if metrics.averageTokensPerSecond < 30.0 {
            recommendations.append("Enable Neural Engine acceleration for better performance")
            recommendations.append("Consider using 4-bit quantized models")
            recommendations.append("Implement memory pooling to reduce allocation overhead")
        }

        // Convergence recommendations
        if metrics.convergenceRate < 0.7 {
            recommendations.append("Adjust confidence threshold to improve convergence")
            recommendations.append("Fine-tune model for better adaptive halting")
        }

        // Memory recommendations
        let memoryMB = Double(metrics.peakMemoryUsage) / 1024.0 / 1024.0
        if memoryMB > 100.0 {
            recommendations.append("High memory usage detected (\(String(format: "%.1f", memoryMB))MB), consider optimization")
        }

        // Error recommendations
        if metrics.errorCount > 10 {
            recommendations.append("Review error log for recurring issues")
            recommendations.append("Implement additional error handling")
        }

        return recommendations
    }

    private func getPeakMemoryUsage() -> UInt64 {
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

public struct StepMetrics {
    public let iteration: Int
    public let thinkTime: TimeInterval
    public let actTime: TimeInterval
    public let confidence: Float
    public let timestamp: Date

    public var totalTime: TimeInterval {
        thinkTime + actTime
    }
}

public struct ErrorRecord {
    public let error: Error
    public let timestamp: Date
    public let description: String
}

public struct ConfidenceDistribution {
    public let low: Int      // < 0.7
    public let medium: Int   // 0.7 - 0.9
    public let high: Int     // > 0.9
    public let average: Float
}

public struct PerformanceReport {
    public let metrics: PerformanceMetrics
    public let modelLoadTime: TimeInterval
    public let thinkTimeAverage: TimeInterval
    public let actTimeAverage: TimeInterval
    public let confidenceDistribution: ConfidenceDistribution
    public let bottlenecks: [String]
    public let recommendations: [String]

    public var formattedReport: String {
        var report = """

        ═══════════════════════════════════════════════════════
        TRM INFERENCE ENGINE - PERFORMANCE REPORT
        ═══════════════════════════════════════════════════════

        OVERALL METRICS:
        ───────────────────────────────────────────────────────
        Total Inferences:        \(metrics.totalInferences)
        Average Inference Time:  \(String(format: "%.2f", metrics.averageInferenceTime * 1000))ms
        Average Tokens/Second:   \(String(format: "%.1f", metrics.averageTokensPerSecond))
        Average Iterations:      \(String(format: "%.1f", metrics.averageIterations))
        Convergence Rate:        \(String(format: "%.1f%%", metrics.convergenceRate * 100))
        Error Count:             \(metrics.errorCount)

        TIMING BREAKDOWN:
        ───────────────────────────────────────────────────────
        Model Load Time:         \(String(format: "%.2f", modelLoadTime * 1000))ms
        Average Think Time:      \(String(format: "%.2f", thinkTimeAverage * 1000))ms
        Average Act Time:        \(String(format: "%.2f", actTimeAverage * 1000))ms

        CONFIDENCE DISTRIBUTION:
        ───────────────────────────────────────────────────────
        High (>0.9):             \(confidenceDistribution.high)
        Medium (0.7-0.9):        \(confidenceDistribution.medium)
        Low (<0.7):              \(confidenceDistribution.low)
        Average:                 \(String(format: "%.2f", confidenceDistribution.average))

        MEMORY:
        ───────────────────────────────────────────────────────
        Peak Memory Usage:       \(String(format: "%.2f", Double(metrics.peakMemoryUsage) / 1024.0 / 1024.0))MB

        """

        if !bottlenecks.isEmpty {
            report += """

            BOTTLENECKS DETECTED:
            ───────────────────────────────────────────────────────

            """
            for (idx, bottleneck) in bottlenecks.enumerated() {
                report += "\(idx + 1). \(bottleneck)\n"
            }
        }

        if !recommendations.isEmpty {
            report += """

            RECOMMENDATIONS:
            ───────────────────────────────────────────────────────

            """
            for (idx, recommendation) in recommendations.enumerated() {
                report += "\(idx + 1). \(recommendation)\n"
            }
        }

        report += """

        ═══════════════════════════════════════════════════════

        """

        return report
    }
}
