import Foundation
import Speech
import AVFoundation

protocol WakeWordDelegate: AnyObject {
    func wakeWordDetected()
}

class WakeWordDetector {
    weak var delegate: WakeWordDelegate?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let detectionQueue = DispatchQueue(label: "com.visionclaw.wakeword", qos: .userInitiated)

    // Configurable wake phrases (case-insensitive)
    private let wakePhrases = ["hey openclaw", "hey open claw", "openclaw"]

    // Debouncing: don't trigger multiple times within 5 seconds
    private var lastTriggerTime: Date?
    private let triggerCooldown: TimeInterval = 5.0

    // Track authorization status
    private(set) var isAuthorized = false

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.defaultTaskHint = .dictation  // Optimize for continuous speech

        // Check current authorization status
        isAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = status == .authorized
                completion(status == .authorized)
            }
        }
    }

    func startListening() {
        guard isAuthorized else {
            NSLog("[WakeWord] Cannot start - speech recognition not authorized")
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            NSLog("[WakeWord] Speech recognizer not available")
            return
        }

        // Cancel any existing task
        stopListening()

        detectionQueue.async { [weak self] in
            guard let self else { return }

            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = self.recognitionRequest else {
                NSLog("[WakeWord] Failed to create recognition request")
                return
            }

            // Configure for continuous recognition
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false  // Allow cloud for better accuracy

            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                if let result = result {
                    let transcription = result.bestTranscription.formattedString.lowercased()
                    self.checkForWakeWord(in: transcription)
                }

                if let error = error {
                    NSLog("[WakeWord] Recognition error: %@", error.localizedDescription)
                }

                // If task finished, restart it for continuous listening
                if result?.isFinal == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startListening()
                    }
                }
            }

            NSLog("[WakeWord] Started listening for wake word")
        }
    }

    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        NSLog("[WakeWord] Stopped listening")
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard recognitionRequest != nil else { return }

        detectionQueue.async { [weak self] in
            self?.recognitionRequest?.append(buffer)
        }
    }

    private func checkForWakeWord(in transcription: String) {
        // Check if any wake phrase is present
        let matched = wakePhrases.contains { phrase in
            transcription.contains(phrase)
        }

        guard matched else { return }

        // Apply debounce
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < triggerCooldown {
            NSLog("[WakeWord] Wake word detected but ignored (cooldown active)")
            return
        }

        lastTriggerTime = Date()
        NSLog("[WakeWord] Wake word detected: \(transcription)")

        // Notify delegate on main thread
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.wakeWordDetected()
        }
    }
}
