//
//  VoiceServiceTests.swift
//  AtlasTests
//
//  Unit tests for voice services
//

import XCTest
import AVFoundation
@testable import Atlas

@MainActor
final class VoiceServiceTests: XCTestCase {

    var ttsService: TextToSpeechService?

    override func setUpWithError() throws {
        ttsService = TextToSpeechService()
    }

    override func tearDownWithError() throws {
        ttsService?.stop()
        ttsService = nil
    }

    // MARK: - Text-to-Speech Tests

    func testTTSInitialization() throws {
        XCTAssertNotNil(ttsService, "TTS service should initialize")
        XCTAssertFalse(ttsService!.isSpeaking, "Should not be speaking initially")
        XCTAssertFalse(ttsService!.isPaused, "Should not be paused initially")
    }

    func testTTSConfiguration() throws {
        let config = SpeechConfiguration(
            rate: 0.5,
            pitch: 1.2,
            volume: 0.8,
            language: "en-US"
        )

        ttsService?.configuration = config

        XCTAssertEqual(ttsService?.configuration.rate, 0.5)
        XCTAssertEqual(ttsService?.configuration.pitch, 1.2)
        XCTAssertEqual(ttsService?.configuration.volume, 0.8)
        XCTAssertEqual(ttsService?.configuration.language, "en-US")
    }

    func testTTSPresetConfigurations() throws {
        let fastConfig = SpeechConfiguration.fast
        let slowConfig = SpeechConfiguration.slow
        let naturalConfig = SpeechConfiguration.natural

        XCTAssertNotEqual(fastConfig.rate, slowConfig.rate, "Fast and slow configs should have different rates")
        XCTAssertEqual(naturalConfig.pitch, 1.0, "Natural config should have default pitch")
    }

    func testAvailableVoices() throws {
        let voices = TextToSpeechService.availableVoices()
        XCTAssertFalse(voices.isEmpty, "Should have available voices")
    }

    func testAvailableLanguages() throws {
        let languages = TextToSpeechService.supportedLanguages()
        XCTAssertFalse(languages.isEmpty, "Should have supported languages")
        XCTAssertTrue(languages.contains(where: { $0.hasPrefix("en") }), "Should support English")
    }

    func testLanguageSpecificVoices() throws {
        let englishVoices = TextToSpeechService.availableVoices(for: "en")
        XCTAssertFalse(englishVoices.isEmpty, "Should have English voices")
    }

    func testWaveformGeneration() throws {
        let text = "Hello world this is a test"
        let waveform = ttsService?.generateWaveformData(for: text, samples: 50)

        XCTAssertNotNil(waveform)
        XCTAssertEqual(waveform?.count, 50, "Should generate requested number of samples")
    }

    func testSSMLStripping() async throws {
        let ssml = "<speak><p>Hello <break time=\"500ms\"/> world</p></speak>"
        // The speak method will strip SSML tags internally
        // We're just testing that it doesn't crash
        XCTAssertNoThrow(try await ttsService?.speakWithSSML(ssml))
    }

    // MARK: - Speech Recognition Tests

    func testSpeechRecognitionLocaleSupport() throws {
        let supportedLocales = SpeechRecognitionService.supportedLocales()
        XCTAssertFalse(supportedLocales.isEmpty, "Should have supported locales")

        let englishSupported = SpeechRecognitionService.isLocaleSupported(Locale(identifier: "en-US"))
        XCTAssertTrue(englishSupported, "English should be supported")
    }
}
