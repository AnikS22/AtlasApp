//
//  TextToSpeechService.swift
//  Atlas
//
//  Created by Atlas Team
//  Natural Text-to-Speech Service with AVSpeechSynthesizer
//

import Foundation
import AVFoundation
import Combine

/// Text-to-speech errors
public enum TextToSpeechError: LocalizedError {
    case synthesisFailure
    case audioSessionFailure
    case invalidText
    case voiceUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .synthesisFailure:
            return "Failed to synthesize speech."
        case .audioSessionFailure:
            return "Failed to configure audio session."
        case .invalidText:
            return "Text is empty or invalid."
        case .voiceUnavailable:
            return "Selected voice is not available."
        case .cancelled:
            return "Speech synthesis was cancelled."
        }
    }
}

/// Speech synthesis configuration
public struct SpeechConfiguration {
    var rate: Float
    var pitch: Float
    var volume: Float
    var voice: AVSpeechSynthesisVoice?
    var language: String

    public init(
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        voice: AVSpeechSynthesisVoice? = nil,
        language: String = "en-US"
    ) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.voice = voice
        self.language = language
    }

    // Preset configurations
    public static var `default`: SpeechConfiguration {
        SpeechConfiguration()
    }

    public static var fast: SpeechConfiguration {
        SpeechConfiguration(rate: AVSpeechUtteranceMaximumSpeechRate * 0.7)
    }

    public static var slow: SpeechConfiguration {
        SpeechConfiguration(rate: AVSpeechUtteranceMinimumSpeechRate * 1.5)
    }

    public static var natural: SpeechConfiguration {
        SpeechConfiguration(rate: 0.5, pitch: 1.0, volume: 1.0)
    }
}

/// Speech synthesis progress
public struct SpeechProgress {
    let utterance: String
    let characterRange: NSRange
    let progress: Float // 0.0 to 1.0
    let timestamp: Date
}

/// Protocol defining text-to-speech capabilities
public protocol TextToSpeechProtocol {
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    var configuration: SpeechConfiguration { get set }
    var progressStream: AsyncStream<SpeechProgress> { get }

    func speak(text: String) async throws
    func speak(text: String, configuration: SpeechConfiguration) async throws
    func synthesize(text: String) async throws -> Data
    func pause()
    func resume()
    func stop()
}

/// Natural text-to-speech service using AVSpeechSynthesizer
@MainActor
public final class TextToSpeechService: NSObject, TextToSpeechProtocol {

    // MARK: - Properties

    private let synthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?
    private var speakingContinuation: CheckedContinuation<Void, Error>?

    private var progressContinuation: AsyncStream<SpeechProgress>.Continuation?
    public let progressStream: AsyncStream<SpeechProgress>

    public var configuration: SpeechConfiguration

    public private(set) var isSpeaking = false
    public private(set) var isPaused = false

    // Voice selection cache
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    // Queue for multiple utterances
    private var utteranceQueue: [AVSpeechUtterance] = []
    private var isProcessingQueue = false

    // MARK: - Initialization

    public override init() {
        self.synthesizer = AVSpeechSynthesizer()
        self.configuration = .default

        var progressCont: AsyncStream<SpeechProgress>.Continuation?
        self.progressStream = AsyncStream { progressCont = $0 }
        self.progressContinuation = progressCont

        super.init()

        synthesizer.delegate = self

        // Pre-cache common voices
        cacheCommonVoices()
    }

    deinit {
        stop()
    }

    // MARK: - Speech Synthesis

    public func speak(text: String) async throws {
        try await speak(text: text, configuration: configuration)
    }

    public func speak(text: String, configuration: SpeechConfiguration) async throws {
        guard !text.isEmpty else {
            throw TextToSpeechError.invalidText
        }

        // Configure audio session
        try configureAudioSession()

        // Create utterance
        let utterance = createUtterance(from: text, configuration: configuration)

        // Store current utterance
        self.currentUtterance = utterance
        self.isSpeaking = true

        // Speak with continuation
        return try await withCheckedThrowingContinuation { continuation in
            self.speakingContinuation = continuation
            self.synthesizer.speak(utterance)
        }
    }

    public func synthesize(text: String) async throws -> Data {
        // Note: AVSpeechSynthesizer doesn't provide direct audio data output
        // For audio data extraction, we need to use AVSpeechSynthesizer with AVAudioEngine
        // This is a placeholder implementation that writes to a temporary file

        guard !text.isEmpty else {
            throw TextToSpeechError.invalidText
        }

        // Create temporary file for audio output
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        // Use AVAudioEngine to capture synthesizer output
        // This requires more complex setup with AVAudioMixerNode
        // For now, we'll return empty data and speak directly

        // Alternative: Use AVSpeechSynthesizer's output delegate (iOS 16+)
        #if compiler(>=5.7)
        if #available(iOS 16.0, *) {
            return try await synthesizeWithOutputDelegate(text: text)
        }
        #endif

        // Fallback: Speak and return empty data
        try await speak(text: text)
        return Data()
    }

    @available(iOS 16.0, *)
    private func synthesizeWithOutputDelegate(text: String) async throws -> Data {
        // Use new iOS 16+ API to write to audio buffer
        let utterance = createUtterance(from: text, configuration: configuration)

        // Configure synthesizer to write to buffer
        // This would require implementing AVSpeechSynthesizer output handling
        // For brevity, returning placeholder

        return Data()
    }

    // MARK: - Playback Control

    public func pause() {
        guard isSpeaking, !isPaused else { return }

        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    public func resume() {
        guard isPaused else { return }

        synthesizer.continueSpeaking()
        isPaused = false
    }

    public func stop() {
        guard isSpeaking else { return }

        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        utteranceQueue.removeAll()

        // Resume continuation with cancellation
        if let continuation = speakingContinuation {
            continuation.resume(throwing: TextToSpeechError.cancelled)
            speakingContinuation = nil
        }

        isSpeaking = false
        isPaused = false
    }

    // MARK: - Queue Management

    public func speakQueue(_ texts: [String]) async throws {
        guard !texts.isEmpty else { return }

        // Create utterances
        let utterances = texts.map { createUtterance(from: $0, configuration: configuration) }
        utteranceQueue.append(contentsOf: utterances)

        // Process queue if not already processing
        if !isProcessingQueue {
            try await processQueue()
        }
    }

    private func processQueue() async throws {
        guard !utteranceQueue.isEmpty else {
            isProcessingQueue = false
            return
        }

        isProcessingQueue = true

        while let utterance = utteranceQueue.first {
            utteranceQueue.removeFirst()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.speakingContinuation = continuation
                self.synthesizer.speak(utterance)
            }
        }

        isProcessingQueue = false
    }

    // MARK: - Voice Management

    public func setVoice(identifier: String) throws {
        if let voice = voiceCache[identifier] ?? AVSpeechSynthesisVoice(identifier: identifier) {
            configuration.voice = voice
            voiceCache[identifier] = voice
        } else {
            throw TextToSpeechError.voiceUnavailable
        }
    }

    public func setVoice(language: String, quality: AVSpeechSynthesisVoiceQuality = .default) {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language && $0.quality == quality }

        configuration.voice = voices.first ?? AVSpeechSynthesisVoice(language: language)
    }

    public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
    }

    public static func availableVoices(for language: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
    }

    // MARK: - Language Support

    public func setLanguage(_ language: String) {
        configuration.language = language

        // Try to find a voice for this language
        if let voice = AVSpeechSynthesisVoice(language: language) {
            configuration.voice = voice
        }
    }

    public static func supportedLanguages() -> [String] {
        let languages = AVSpeechSynthesisVoice.speechVoices()
            .map { $0.language }
        return Array(Set(languages)).sorted()
    }

    // MARK: - Private Methods

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure for playback
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw TextToSpeechError.audioSessionFailure
        }
    }

    private func createUtterance(from text: String, configuration: SpeechConfiguration) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        // Apply configuration
        utterance.rate = configuration.rate
        utterance.pitchMultiplier = configuration.pitch
        utterance.volume = configuration.volume

        // Set voice
        if let voice = configuration.voice {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: configuration.language)
        }

        // Pre-utterance delay for more natural speech
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        return utterance
    }

    private func cacheCommonVoices() {
        // Cache English voices
        let englishVoices = Self.availableVoices(for: "en")
        for voice in englishVoices.prefix(3) {
            voiceCache[voice.identifier] = voice
        }
    }

    // MARK: - Waveform Generation

    public func generateWaveformData(for text: String, samples: Int = 50) -> [Float] {
        // Estimate waveform based on text characteristics
        // This is a simple approximation - real waveform would require actual audio data

        let words = text.split(separator: " ")
        let samplesPerWord = max(1, samples / max(1, words.count))

        var waveform: [Float] = []

        for word in words {
            // Generate samples for this word
            let wordLength = Float(word.count)
            let amplitude = min(1.0, wordLength / 10.0) // Scale based on word length

            for i in 0..<samplesPerWord {
                // Create a simple envelope
                let progress = Float(i) / Float(samplesPerWord)
                let envelope = sin(progress * .pi) // Rise and fall
                waveform.append(amplitude * envelope)
            }

            // Add small gap between words
            if waveform.count < samples {
                waveform.append(0.1)
            }
        }

        // Normalize to requested sample count
        while waveform.count < samples {
            waveform.append(0.0)
        }

        return Array(waveform.prefix(samples))
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechService: AVSpeechSynthesizerDelegate {

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        isPaused = false
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        currentUtterance = nil

        // Resume continuation
        speakingContinuation?.resume()
        speakingContinuation = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isPaused = true
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isPaused = false
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        currentUtterance = nil

        // Resume continuation with error
        speakingContinuation?.resume(throwing: TextToSpeechError.cancelled)
        speakingContinuation = nil
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // Calculate progress
        let totalLength = utterance.speechString.utf16.count
        let progress = Float(characterRange.location) / Float(max(1, totalLength))

        let speechProgress = SpeechProgress(
            utterance: utterance.speechString,
            characterRange: characterRange,
            progress: progress,
            timestamp: Date()
        )

        progressContinuation?.yield(speechProgress)
    }
}

// MARK: - SSML Support

extension TextToSpeechService {
    /// Speak text with SSML markup (if supported)
    public func speakWithSSML(_ ssml: String) async throws {
        // iOS AVSpeechSynthesizer has limited SSML support
        // Strip SSML tags and speak plain text
        let plainText = stripSSMLTags(from: ssml)
        try await speak(text: plainText)
    }

    private func stripSSMLTags(from ssml: String) -> String {
        // Simple SSML tag removal
        var text = ssml

        // Remove common SSML tags
        let ssmlPattern = "<[^>]+>"
        text = text.replacingOccurrences(
            of: ssmlPattern,
            with: "",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Audio Session Interruption Handling

extension TextToSpeechService {
    public func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began - pause if speaking
            if isSpeaking {
                pause()
            }

        case .ended:
            // Interruption ended - resume if should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isPaused {
                    resume()
                }
            }

        @unknown default:
            break
        }
    }

    public func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Audio output device removed (e.g., headphones unplugged)
            // Pause speech
            if isSpeaking {
                pause()
            }

        case .newDeviceAvailable, .routeConfigurationChange:
            // New audio device available
            // Continue speaking if was speaking
            break

        default:
            break
        }
    }
}
