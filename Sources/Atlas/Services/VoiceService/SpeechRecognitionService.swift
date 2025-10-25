//
//  SpeechRecognitionService.swift
//  Atlas
//
//  Created by Atlas Team
//  Real-time Speech Recognition Service with Voice Activity Detection
//

import Foundation
import Speech
import AVFoundation
import Combine

/// Speech recognition errors
enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineFailure
    case recognitionRequestFailed
    case microphoneUnavailable
    case audioSessionConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the current locale."
        case .audioEngineFailure:
            return "Audio engine failed to start or process audio."
        case .recognitionRequestFailed:
            return "Failed to create recognition request."
        case .microphoneUnavailable:
            return "Microphone is not available."
        case .audioSessionConfigurationFailed:
            return "Failed to configure audio session."
        }
    }
}

/// Speech recognition authorization status
public enum SpeechAuthorizationStatus {
    case notDetermined
    case denied
    case restricted
    case authorized

    init(from status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorized: self = .authorized
        @unknown default: self = .notDetermined
        }
    }
}

/// Transcription result with metadata
public struct TranscriptionResult {
    let text: String
    let isFinal: Bool
    let confidence: Float
    let timestamp: Date
    let segments: [TranscriptionSegment]

    struct TranscriptionSegment {
        let text: String
        let confidence: Float
        let duration: TimeInterval
        let timestamp: TimeInterval
    }
}

/// Voice activity detection result
public struct VoiceActivityResult {
    let isSpeaking: Bool
    let audioLevel: Float
    let timestamp: Date
}

/// Protocol defining speech recognition capabilities
public protocol SpeechRecognitionProtocol {
    var transcriptionStream: AsyncStream<TranscriptionResult> { get }
    var voiceActivityStream: AsyncStream<VoiceActivityResult> { get }
    var isRecognizing: Bool { get }
    var authorizationStatus: SpeechAuthorizationStatus { get }

    func requestAuthorization() async -> SpeechAuthorizationStatus
    func startRecognition(locale: Locale) async throws
    func stopRecognition()
    func pauseRecognition()
    func resumeRecognition() throws
}

/// Real-time speech recognition service with voice activity detection
@MainActor
public final class SpeechRecognitionService: NSObject, SpeechRecognitionProtocol {

    // MARK: - Properties

    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var transcriptionContinuation: AsyncStream<TranscriptionResult>.Continuation?
    private var voiceActivityContinuation: AsyncStream<VoiceActivityResult>.Continuation?

    public let transcriptionStream: AsyncStream<TranscriptionResult>
    public let voiceActivityStream: AsyncStream<VoiceActivityResult>

    public private(set) var isRecognizing = false
    private var isPaused = false

    // Voice activity detection
    private var silenceTimer: Timer?
    private let silenceThreshold: Float = 0.1
    private let silenceDuration: TimeInterval = 2.0
    private var lastSpeechTime: Date?

    // Audio level tracking
    private var audioLevelPublisher: Timer.TimerPublisher?
    private var audioLevelCancellable: AnyCancellable?

    // Configuration
    private var currentLocale: Locale = .current
    private var continuousRecognition = false

    public var authorizationStatus: SpeechAuthorizationStatus {
        SpeechAuthorizationStatus(from: SFSpeechRecognizer.authorizationStatus())
    }

    // MARK: - Initialization

    public override init() {
        var transcriptionCont: AsyncStream<TranscriptionResult>.Continuation?
        self.transcriptionStream = AsyncStream { transcriptionCont = $0 }
        self.transcriptionContinuation = transcriptionCont

        var voiceActivityCont: AsyncStream<VoiceActivityResult>.Continuation?
        self.voiceActivityStream = AsyncStream { voiceActivityCont = $0 }
        self.voiceActivityContinuation = voiceActivityCont

        super.init()

        setupAudioEngine()
    }

    deinit {
        stopRecognition()
    }

    // MARK: - Authorization

    public func requestAuthorization() async -> SpeechAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authStatus = SpeechAuthorizationStatus(from: status)
                continuation.resume(returning: authStatus)
            }
        }
    }

    // MARK: - Recognition Control

    public func startRecognition(locale: Locale = .current) async throws {
        // Stop any ongoing recognition
        stopRecognition()

        // Check authorization
        guard authorizationStatus == .authorized else {
            throw SpeechRecognitionError.notAuthorized
        }

        // Initialize recognizer for locale
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        guard recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        self.speechRecognizer = recognizer
        self.currentLocale = locale

        // Configure audio session
        try configureAudioSession()

        // Start recognition
        try await startRecognitionTask()

        isRecognizing = true
        isPaused = false
    }

    public func stopRecognition() {
        guard isRecognizing else { return }

        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        // Cancel recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        // Stop voice activity detection
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioLevelCancellable?.cancel()
        audioLevelCancellable = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecognizing = false
        isPaused = false
    }

    public func pauseRecognition() {
        guard isRecognizing, !isPaused else { return }

        if audioEngine.isRunning {
            audioEngine.pause()
        }

        isPaused = true
    }

    public func resumeRecognition() throws {
        guard isRecognizing, isPaused else { return }

        guard !audioEngine.isRunning else {
            isPaused = false
            return
        }

        do {
            try audioEngine.start()
            isPaused = false
        } catch {
            throw SpeechRecognitionError.audioEngineFailure
        }
    }

    // MARK: - Private Methods

    private func setupAudioEngine() {
        // Audio engine will be configured when recognition starts
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure for voice chat to support both recording and playback
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionError.audioSessionConfigurationFailed
        }
    }

    private func startRecognitionTask() async throws {
        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // Privacy-first: on-device only

        // Enable context awareness for better accuracy
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }

        self.recognitionRequest = request

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Verify format
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechRecognitionError.audioEngineFailure
        }

        // Install tap for audio processing
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Send buffer to recognition request
            self.recognitionRequest?.append(buffer)

            // Voice activity detection
            Task { @MainActor in
                self.processAudioBuffer(buffer, at: time)
            }
        }

        // Prepare and start audio engine
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            throw SpeechRecognitionError.audioEngineFailure
        }

        // Start recognition task
        guard let recognizer = speechRecognizer else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            Task { @MainActor in
                self.handleRecognitionResult(result, error: error)
            }
        }

        // Start voice activity monitoring
        startVoiceActivityMonitoring()
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("Speech recognition error: \(error.localizedDescription)")

            // Handle specific errors
            if (error as NSError).domain == "kLSRErrorDomain" {
                // Recognition session timeout or other recoverable error
                // Attempt restart if continuous mode
                if continuousRecognition {
                    Task {
                        try? await restartRecognition()
                    }
                }
            }
            return
        }

        guard let result = result else { return }

        let transcription = result.bestTranscription
        let isFinal = result.isFinal

        // Calculate average confidence
        let averageConfidence = transcription.segments.isEmpty ? 0.0 :
            transcription.segments.map { $0.confidence }.reduce(0, +) / Float(transcription.segments.count)

        // Build segments
        let segments = transcription.segments.map { segment in
            TranscriptionResult.TranscriptionSegment(
                text: segment.substring,
                confidence: segment.confidence,
                duration: segment.duration,
                timestamp: segment.timestamp
            )
        }

        let transcriptionResult = TranscriptionResult(
            text: transcription.formattedString,
            isFinal: isFinal,
            confidence: averageConfidence,
            timestamp: Date(),
            segments: segments
        )

        // Yield result to stream
        transcriptionContinuation?.yield(transcriptionResult)

        // Track speech activity
        lastSpeechTime = Date()

        // Restart recognition if final and continuous mode
        if isFinal && continuousRecognition {
            Task {
                try? await restartRecognition()
            }
        }
    }

    private func restartRecognition() async throws {
        // Brief pause before restart
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // End current request
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        // Start new task
        try await startRecognitionTask()
    }

    // MARK: - Voice Activity Detection

    private func startVoiceActivityMonitoring() {
        // Monitor for silence
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.checkForSilence()
            }
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // Calculate RMS audio level
        let level = calculateRMS(from: buffer)

        // Determine if speaking
        let isSpeaking = level > silenceThreshold

        let voiceActivity = VoiceActivityResult(
            isSpeaking: isSpeaking,
            audioLevel: level,
            timestamp: Date()
        )

        voiceActivityContinuation?.yield(voiceActivity)
    }

    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let channelDataValue = channelData.pointee
        let channelDataArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }

        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        return rms
    }

    private func checkForSilence() {
        guard let lastSpeech = lastSpeechTime else { return }

        let silenceDuration = Date().timeIntervalSince(lastSpeech)

        if silenceDuration > self.silenceDuration {
            // Silence detected - could trigger automatic stop or pause
            // For now, just report via voice activity
            let silenceResult = VoiceActivityResult(
                isSpeaking: false,
                audioLevel: 0.0,
                timestamp: Date()
            )
            voiceActivityContinuation?.yield(silenceResult)
        }
    }

    // MARK: - Continuous Recognition

    public func enableContinuousRecognition(_ enabled: Bool) {
        continuousRecognition = enabled
    }

    // MARK: - Language Support

    public static func supportedLocales() -> Set<Locale> {
        return SFSpeechRecognizer.supportedLocales()
    }

    public static func isLocaleSupported(_ locale: Locale) -> Bool {
        return supportedLocales().contains(locale)
    }
}

// MARK: - Waveform Data Generation

extension SpeechRecognitionService {
    /// Generate waveform data for UI visualization
    public func generateWaveformData(from buffer: AVAudioPCMBuffer, samples: Int = 50) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return [] }

        let samplesPerPoint = max(1, frameLength / samples)
        var waveformData: [Float] = []

        for i in 0..<samples {
            let startIndex = i * samplesPerPoint
            let endIndex = min(startIndex + samplesPerPoint, frameLength)

            guard endIndex > startIndex else { continue }

            var sum: Float = 0.0
            for j in startIndex..<endIndex {
                sum += abs(channelDataValue[j])
            }

            let average = sum / Float(endIndex - startIndex)
            waveformData.append(average)
        }

        return waveformData
    }
}

// MARK: - Audio Session Interruption Handling

extension SpeechRecognitionService {
    public func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                // Interruption began - pause recognition
                pauseRecognition()

            case .ended:
                // Interruption ended - resume if should resume
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        try? resumeRecognition()
                    }
                }

            @unknown default:
                break
            }
        }
    }

    public func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        Task { @MainActor in
            switch reason {
            case .oldDeviceUnavailable:
                // Audio device removed (e.g., headphones unplugged)
                stopRecognition()

            case .newDeviceAvailable, .routeConfigurationChange:
                // New audio device available - could auto-restart
                break

            default:
                break
            }
        }
    }
}
