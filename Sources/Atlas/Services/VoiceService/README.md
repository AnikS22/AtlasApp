# Voice Services

Real-time speech recognition and text-to-speech for Atlas.

## Components
- `SpeechRecognitionService.swift` - STT using iOS Speech framework
- `TextToSpeechService.swift` - TTS using AVSpeechSynthesizer

## Features
- <300ms latency for STT/TTS
- 100% on-device processing
- Real-time transcription with async streams
- Multiple language support
- Natural voice synthesis

## Usage
```swift
// Speech Recognition
let sttService = SpeechRecognitionService()
for try await result in sttService.startRecognition() {
    print("Transcript: \(result.transcript)")
}

// Text-to-Speech
let ttsService = TextToSpeechService()
try await ttsService.speak("Hello, I am Atlas")
```
