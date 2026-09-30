//
//  KyraSpeechInputController.swift
//  AstraStyle
//
//  Records only after an explicit microphone tap and transcribes locally.
//  Audio is written to a temporary file for Speech framework recognition
//  and removed as soon as recognition finishes or is cancelled.
//

import AVFAudio
import Foundation
import Observation
import Speech

@MainActor
@Observable
final class KyraSpeechInputController {
    enum State: Equatable, Sendable {
        case idle
        case requestingPermission
        case recording
        case transcribing
    }

    private(set) var state: State = .idle
    private(set) var transcript: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var recordingLimitTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var authorizationRequestID = UUID()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    @ObservationIgnored private var previousAudioCategory: AVAudioSession.Category?
    @ObservationIgnored private var previousAudioMode: AVAudioSession.Mode?
    @ObservationIgnored private var previousAudioOptions: AVAudioSession.CategoryOptions?

    func toggle() async {
        switch state {
        case .recording:
            stopAndTranscribe()
            return
        case .requestingPermission, .transcribing:
            return
        case .idle:
            break
        }

        transcript = nil
        errorMessage = nil

        await beginRecording()
    }

    func cancel() {
        authorizationRequestID = UUID()
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        transcriptionTimeoutTask?.cancel()
        transcriptionTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recorder?.stop()
        recorder = nil
        removeTemporaryAudio()
        deactivateAudioSession()
        state = .idle
    }

    func clearError() {
        errorMessage = nil
    }

    private func beginRecording() async {
        guard let recognizer, recognizer.isAvailable else {
            fail(String(localized: "Voice input isn't available right now. You can still type to Kyra."))
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            fail(String(localized: "On-device speech recognition isn't available for this language on this device. You can still type to Kyra."))
            return
        }

        guard await requestPermissions() else { return }

        do {
            try startRecording()
            state = .recording
            recordingLimitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled else { return }
                self?.stopAndTranscribe()
            }
        } catch {
            fail(String(localized: "The microphone couldn't start. You can still type to Kyra."))
        }
    }

    private func requestPermissions() async -> Bool {
        let requestID = UUID()
        authorizationRequestID = requestID
        state = .requestingPermission
        guard await hasMicrophonePermission() else {
            guard authorizationRequestID == requestID else { return false }
            fail(String(localized: "Allow microphone access in Settings to dictate a question to Kyra."))
            return false
        }
        guard authorizationRequestID == requestID else { return false }
        guard await hasSpeechPermission() else {
            guard authorizationRequestID == requestID else { return false }
            fail(String(localized: "Allow Speech Recognition in Settings to turn your voice into text for Kyra."))
            return false
        }
        return authorizationRequestID == requestID
    }

    private func hasMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            true
        case .denied:
            false
        case .undetermined:
            await AVAudioApplication.requestRecordPermission()
        @unknown default:
            false
        }
    }

    private func hasSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            true
        case .denied, .restricted:
            false
        case .notDetermined:
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            false
        }
    }

    private func startRecording() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("astra-kyra-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let audioSession = AVAudioSession.sharedInstance()
        previousAudioCategory = audioSession.category
        previousAudioMode = audioSession.mode
        previousAudioOptions = audioSession.categoryOptions
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)

        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard audioRecorder.record() else {
            throw SpeechInputError.recordingFailed
        }
        recordingURL = url
        recorder = audioRecorder
    }

    private func stopAndTranscribe() {
        guard state == .recording, let recognizer, let recordingURL else { return }
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        recorder?.stop()
        recorder = nil
        deactivateAudioSession()

        let request = SFSpeechURLRecognitionRequest(url: recordingURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        state = .transcribing

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let recognizedText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failureMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.receiveRecognition(text: recognizedText, isFinal: isFinal, failureMessage: failureMessage)
            }
        }

        transcriptionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            guard self?.state == .transcribing else { return }
            self?.fail(String(localized: "That took too long to transcribe. Try again or type your question."))
        }
    }

    private func receiveRecognition(text: String?, isFinal: Bool, failureMessage: String?) {
        guard state == .transcribing else { return }
        if failureMessage != nil {
            let cleanedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if cleanedText.isEmpty {
                fail(String(localized: "Your voice couldn't be transcribed. Try again or type your question."))
            } else {
                finishTranscription(text: cleanedText)
            }
            return
        }
        guard isFinal else { return }
        let cleanedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cleanedText.isEmpty else {
            fail(String(localized: "No speech was picked up. Try again or type your question."))
            return
        }
        finishTranscription(text: cleanedText)
    }

    private func finishTranscription(text: String) {
        transcript = text
        transcriptionTimeoutTask?.cancel()
        transcriptionTimeoutTask = nil
        recognitionTask = nil
        removeTemporaryAudio()
        state = .idle
    }

    private func fail(_ message: String) {
        recordingLimitTask?.cancel()
        recordingLimitTask = nil
        transcriptionTimeoutTask?.cancel()
        transcriptionTimeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recorder?.stop()
        recorder = nil
        removeTemporaryAudio()
        deactivateAudioSession()
        errorMessage = message
        state = .idle
    }

    private func removeTemporaryAudio() {
        guard let recordingURL else { return }
        try? FileManager.default.removeItem(at: recordingURL)
        self.recordingURL = nil
    }

    private func deactivateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        if let previousAudioCategory {
            try? audioSession.setCategory(
                previousAudioCategory,
                mode: previousAudioMode ?? .default,
                options: previousAudioOptions ?? []
            )
        }
        previousAudioCategory = nil
        previousAudioMode = nil
        previousAudioOptions = nil
    }
}

private enum SpeechInputError: Error {
    case recordingFailed
}
