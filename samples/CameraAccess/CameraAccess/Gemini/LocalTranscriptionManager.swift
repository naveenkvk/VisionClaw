import Foundation
import Speech
import AVFoundation

/// Independent speech recognition for passive mode transcript capture
/// Runs locally using iOS Speech framework, independent of Gemini Live API
/// Thread-safe: can be called from any queue
class LocalTranscriptionManager: NSObject {

    // MARK: - Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var isTranscribing = false
    private var accumulatedTranscript: String = ""
    private var lastPartialTranscript: String = ""  // Fallback if no final results
    private let queue = DispatchQueue(label: "com.visionclaw.transcription", qos: .userInitiated)

    // Callbacks
    var onTranscriptionUpdate: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?

    // MARK: - Lifecycle

    override init() {
        super.init()

        // Request authorization on init
        SFSpeechRecognizer.requestAuthorization { authStatus in
            switch authStatus {
            case .authorized:
                NSLog("[LocalTranscription] Speech recognition authorized")
            case .denied:
                NSLog("[LocalTranscription] Speech recognition denied by user")
            case .restricted:
                NSLog("[LocalTranscription] Speech recognition restricted")
            case .notDetermined:
                NSLog("[LocalTranscription] Speech recognition not determined")
            @unknown default:
                NSLog("[LocalTranscription] Unknown authorization status")
            }
        }
    }

    // MARK: - Public API

    /// Start transcribing audio buffers
    func startTranscribing() throws {
        try queue.sync {
            guard !isTranscribing else {
                NSLog("[LocalTranscription] Already transcribing")
                return
            }

            // Check authorization
            guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
                throw NSError(
                    domain: "LocalTranscription",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"]
                )
            }

            // Check availability
            guard let recognizer = speechRecognizer, recognizer.isAvailable else {
                throw NSError(
                    domain: "LocalTranscription",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"]
                )
            }

            // Cancel any ongoing task
            recognitionTask?.cancel()
            recognitionTask = nil

            // Create new request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let request = recognitionRequest else {
                throw NSError(
                    domain: "LocalTranscription",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create recognition request"]
                )
            }

            // Configure request
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false  // Use server-based for better accuracy

            // Start recognition task
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                self.queue.async {
                    if let result = result {
                        let transcription = result.bestTranscription.formattedString

                        // Store last partial result (fallback for when stopped before final)
                        self.lastPartialTranscript = transcription

                        // Update partial result (dispatch to main for callback)
                        DispatchQueue.main.async {
                            self.onPartialResult?(transcription)
                        }

                        // If final result, accumulate
                        if result.isFinal {
                            self.accumulatedTranscript += transcription + " "
                            self.lastPartialTranscript = ""  // Clear since we have final
                            let currentTranscript = self.accumulatedTranscript

                            // Dispatch callback to main actor
                            DispatchQueue.main.async {
                                self.onTranscriptionUpdate?(currentTranscript)
                            }
                            NSLog("[LocalTranscription] Final segment: %@", transcription)
                        }
                    }

                    if let error = error {
                        NSLog("[LocalTranscription] Recognition error: %@", error.localizedDescription)
                        let _ = self.stopTranscribing()
                    }
                }
            }

            isTranscribing = true
            accumulatedTranscript = ""
            lastPartialTranscript = ""

            NSLog("[LocalTranscription] Started transcription")
        }
    }

    /// Stop transcribing and return final transcript
    func stopTranscribing() -> String {
        return queue.sync {
            guard isTranscribing else { return "" }

            recognitionTask?.cancel()
            recognitionTask = nil

            recognitionRequest?.endAudio()
            recognitionRequest = nil

            isTranscribing = false

            // Use accumulated transcript if available, otherwise use last partial result
            let usedPartial = accumulatedTranscript.isEmpty
            let finalTranscript = usedPartial ? lastPartialTranscript : accumulatedTranscript

            // Clear both
            accumulatedTranscript = ""
            lastPartialTranscript = ""

            NSLog("[LocalTranscription] Stopped. Final transcript length: %d chars (from %@)",
                  finalTranscript.count,
                  usedPartial ? "partial" : "final")

            return finalTranscript
        }
    }

    /// Feed audio buffer for transcription (called from AudioManager)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        queue.async { [weak self] in
            guard let self, self.isTranscribing, let request = self.recognitionRequest else { return }
            request.append(buffer)
        }
    }

    /// Reset accumulated transcript without stopping
    func resetTranscript() {
        queue.async { [weak self] in
            self?.accumulatedTranscript = ""
            NSLog("[LocalTranscription] Transcript reset")
        }
    }

    /// Get current accumulated transcript
    func getCurrentTranscript() -> String {
        return queue.sync {
            return accumulatedTranscript
        }
    }

    // MARK: - Cleanup

    deinit {
        recognitionTask?.cancel()
    }
}
