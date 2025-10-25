//
//  VoiceInputView.swift
//  Atlas
//
//  Voice recording UI with real-time waveform visualization
//

import SwiftUI
import AVFoundation

struct VoiceInputView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @StateObject private var voiceRecorder = VoiceRecorder()

    let onTranscriptionComplete: (String) -> Void

    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Status Text
                Text(isRecording ? "Recording..." : "Tap to record")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Recording Duration
                if isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.system(.title, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Waveform Visualization
                WaveformView(amplitude: voiceRecorder.currentAmplitude)
                    .frame(height: 100)
                    .padding(.horizontal)

                Spacer()

                // Recording Button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.accentColor)
                            .frame(width: 80, height: 80)

                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    .shadow(radius: 10)
                }

                // Action Buttons
                if isRecording {
                    HStack(spacing: 40) {
                        Button(action: cancelRecording) {
                            VStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title)
                                Text("Cancel")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }

                        Button(action: completeRecording) {
                            VStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                Text("Send")
                                    .font(.caption)
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.bottom, 30)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                voiceRecorder.requestPermission()
            }
            .onDisappear {
                if isRecording {
                    voiceRecorder.stopRecording()
                }
            }
        }
    }

    // MARK: - Actions
    private func toggleRecording() {
        if isRecording {
            completeRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        voiceRecorder.startRecording()
        isRecording = true
        appState.isRecording = true
        recordingDuration = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
        }
    }

    private func completeRecording() {
        timer?.invalidate()
        timer = nil

        if let audioURL = voiceRecorder.stopRecording() {
            isRecording = false
            appState.isRecording = false

            // Simulate transcription (in production, this would call the Rust backend)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let transcription = "This is a simulated transcription of your voice input. The actual implementation will use the Whisper model in the Rust backend."
                onTranscriptionComplete(transcription)
                dismiss()
            }
        }
    }

    private func cancelRecording() {
        timer?.invalidate()
        timer = nil
        voiceRecorder.stopRecording()
        isRecording = false
        appState.isRecording = false
        dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let amplitude: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<50, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 4, height: barHeight(for: index, maxHeight: geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        let randomFactor = CGFloat.random(in: 0.3...1.0)
        return maxHeight * amplitude * randomFactor
    }
}

// MARK: - Voice Recorder
class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var currentAmplitude: CGFloat = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = .sharedInstance()
    private var amplitudeTimer: Timer?

    func requestPermission() {
        audioSession.requestRecordPermission { allowed in
            if allowed {
                print("Microphone permission granted")
            } else {
                print("Microphone permission denied")
            }
        }
    }

    func startRecording() {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            startAmplitudeMonitoring()
        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() -> URL? {
        amplitudeTimer?.invalidate()
        amplitudeTimer = nil
        currentAmplitude = 0.0

        guard let recorder = audioRecorder, recorder.isRecording else {
            return nil
        }

        let url = recorder.url
        recorder.stop()

        do {
            try audioSession.setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }

        return url
    }

    private func startAmplitudeMonitoring() {
        amplitudeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }

            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalizedPower = self.normalizePower(power)

            DispatchQueue.main.async {
                self.currentAmplitude = normalizedPower
            }
        }
    }

    private func normalizePower(_ power: Float) -> CGFloat {
        let minDb: Float = -60
        let maxDb: Float = 0

        let clampedPower = max(minDb, min(power, maxDb))
        let normalized = (clampedPower - minDb) / (maxDb - minDb)

        return CGFloat(normalized)
    }
}

struct VoiceInputView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceInputView { transcription in
            print("Transcription: \(transcription)")
        }
        .environmentObject(AppState())
    }
}
