import Foundation
import SwiftUI
import Speech

enum SessionMode {
    case passive   // Face detection only, Gemini disconnected
    case active    // Full conversation + tool calling
}

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var sessionMode: SessionMode = .passive
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var openClawConnectionState: OpenClawConnectionState = .notConfigured
  private let geminiService = GeminiLiveService()
  let openClawBridge = OpenClawBridge()  // Made internal for UserRegistryCoordinator
  private var toolCallRouter: ToolCallRouter?
  var userRegistryCoordinator: UserRegistryCoordinator?
  private var fullTranscript: String = ""
  let audioManager = AudioManager()  // Made internal for wake word integration
  // WebSocket removed - using HTTP-only architecture
  private var lastVideoFrameTime: Date = .distantPast
  private var stateObservation: Task<Void, Never>?

  // Auto-sleep tracking
  private var lastSpeechTime: Date?
  private var silenceCheckTimer: Timer?
  private let autoSleepTimeout: TimeInterval = 30.0

  // Context buffering for passive mode
  private var bufferedContext: [String] = []

  var streamingMode: StreamingMode = .glasses

  // MARK: - Session Mode Management

  /// Start in PASSIVE mode - face detection + wake word only
  func startPassiveMode() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured. Open GeminiConfig.swift and replace YOUR_GEMINI_API_KEY with your key from https://aistudio.google.com/apikey"
      return
    }

    sessionMode = .passive
    isGeminiActive = true  // Active in the sense of "app session running", not "Gemini connected"

    NSLog("[Gemini] Started PASSIVE mode - listening for wake word")

    // Setup audio for wake word detection only
    do {
      try audioManager.setupAudioSession(useIPhoneMode: streamingMode == .iPhone)
      try audioManager.startWakeWordListening()
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      sessionMode = .passive
    }

    // Check OpenClaw connectivity (for face detection tool calls)
    await openClawBridge.checkConnection()
    openClawBridge.resetSession()
  }

  /// Activate Gemini session (called when wake word detected)
  func activateGeminiSession() async {
    guard sessionMode == .passive else {
      NSLog("[Gemini] Already in ACTIVE mode")
      return
    }

    NSLog("[Gemini] Activating Gemini session...")
    sessionMode = .active

    // Transition audio from wake word to Gemini streaming
    audioManager.transitionToActiveMode()

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        guard self.sessionMode == .active else { return }
        // Mute mic while model speaks when speaker is on the phone
        // (loudspeaker + co-located mic overwhelms iOS echo cancellation)
        let speakerOnPhone = self.streamingMode == .iPhone || SettingsManager.shared.speakerOutputEnabled
        if speakerOnPhone && self.geminiService.isModelSpeaking { return }
        self.geminiService.sendAudio(data: data)
        self.resetSilenceTimer()
      }
    }

    geminiService.onAudioReceived = { [weak self] data in
      guard let self else { return }
      self.audioManager.playAudio(data: data)
      Task { @MainActor in
        self.resetSilenceTimer()
      }
    }

    geminiService.onInterrupted = { [weak self] in
      self?.audioManager.stopPlayback()
    }

    geminiService.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        // Clear user transcript when AI finishes responding
        self.userTranscript = ""
      }
    }

    geminiService.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        guard self.sessionMode == .active else { return }
        self.userTranscript += text
        self.aiTranscript = ""
        self.fullTranscript += "User: " + text + "\n"
        self.resetSilenceTimer()
      }
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        guard self.sessionMode == .active else { return }
        self.aiTranscript += text
        self.fullTranscript += "AI: " + text + "\n"
        self.resetSilenceTimer()
      }
    }

    // Handle unexpected disconnection
    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        self.stopSession()
        self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
      }
    }

    // Check OpenClaw connectivity and start fresh session
    await openClawBridge.checkConnection()
    openClawBridge.resetSession()

    // Wire tool call handling
    toolCallRouter = ToolCallRouter(bridge: openClawBridge)

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        guard self.sessionMode == .active else {
          NSLog("[Gemini] Tool call ignored - session in passive mode")
          return
        }
        for call in toolCall.functionCalls {
          self.toolCallRouter?.handleToolCall(call) { [weak self] response in
            self?.geminiService.sendToolResponse(response)
          }
        }
      }
    }

    geminiService.onToolCallCancellation = { [weak self] cancellation in
      guard let self else { return }
      Task { @MainActor in
        guard self.sessionMode == .active else { return }
        self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
      }
    }

    // Observe service state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        self.toolCallStatus = self.openClawBridge.lastToolCallStatus
        self.openClawConnectionState = self.openClawBridge.connectionState
      }
    }

    // Connect to Gemini and wait for setupComplete
    let setupOk = await geminiService.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini"
      }
      errorMessage = msg
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      sessionMode = .passive
      connectionState = .disconnected
      return
    }

    // Start full audio capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      sessionMode = .passive
      connectionState = .disconnected
      return
    }

    // Apply buffered context from passive mode
    flushBufferedContext()

    // Start silence monitoring for auto-sleep
    startSilenceMonitoring()

    NSLog("[Gemini] Session ACTIVE - Gemini connected and responding")
  }

  /// Deactivate back to PASSIVE mode (auto-sleep or manual)
  func deactivateGeminiSession() {
    guard sessionMode == .active else { return }

    NSLog("[Gemini] Deactivating Gemini session - returning to PASSIVE mode")

    // Save conversation if transcript exists
    if !fullTranscript.isEmpty {
      userRegistryCoordinator?.endSession(transcript: fullTranscript)
    }

    // Stop silence monitoring
    silenceCheckTimer?.invalidate()
    silenceCheckTimer = nil
    lastSpeechTime = nil

    // Disconnect from Gemini
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    geminiService.disconnect()
    stateObservation?.cancel()
    stateObservation = nil

    // Transition audio back to wake word mode
    audioManager.transitionToPassiveMode()

    // Clear state
    sessionMode = .passive
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
    fullTranscript = ""

    NSLog("[Gemini] Returned to PASSIVE mode - listening for wake word")
  }

  // MARK: - Legacy startSession (kept for compatibility)
  func startSession() async {
    // For backwards compatibility, start in passive then immediately activate
    await startPassiveMode()
    await activateGeminiSession()
  }

  func stopSession() {
    // If in ACTIVE mode, deactivate first
    if sessionMode == .active {
      deactivateGeminiSession()
    }

    // Stop wake word listening
    audioManager.stopWakeWordListening()
    audioManager.stopCapture()

    // Fully stop session
    isGeminiActive = false
    sessionMode = .passive
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
    fullTranscript = ""
    bufferedContext.removeAll()

    NSLog("[Gemini] Session fully stopped")
  }

  // MARK: - Silence Detection & Auto-Sleep

  private func startSilenceMonitoring() {
    lastSpeechTime = Date()
    silenceCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.checkForSilence()
      }
    }
  }

  private func checkForSilence() {
    guard let lastSpeech = lastSpeechTime else { return }

    let silenceDuration = Date().timeIntervalSince(lastSpeech)
    if silenceDuration >= autoSleepTimeout {
      NSLog("[Gemini] Auto-sleep triggered after %.0fs of silence", silenceDuration)
      deactivateGeminiSession()
    }
  }

  private func resetSilenceTimer() {
    lastSpeechTime = Date()
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard SettingsManager.shared.videoStreamingEnabled else { return }
    guard isGeminiActive, connectionState == .ready else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
    lastVideoFrameTime = now
    geminiService.sendVideoFrame(image: image)
  }

  // MARK: - Context Injection & Buffering

  func injectSystemContext(_ text: String) {
    if sessionMode == .active && connectionState == .ready {
      // Send immediately to Gemini
      NSLog("[Gemini] Injecting system context: \(text.prefix(50))...")

      let content: [String: Any] = [
        "turns": [
          [
            "role": "user",
            "parts": [
              ["text": "[System Context: \(text)]"]
            ]
          ]
        ]
      ]

      geminiService.sendClientContent(content)
    } else {
      // Buffer for later when session activates
      bufferedContext.append(text)
      NSLog("[Gemini] Context buffered (passive mode): \(text.prefix(50))...")
    }
  }

  private func flushBufferedContext() {
    guard sessionMode == .active, connectionState == .ready else { return }
    guard !bufferedContext.isEmpty else { return }

    for context in bufferedContext {
      let content: [String: Any] = [
        "turns": [
          [
            "role": "user",
            "parts": [
              ["text": "[System Context: \(context)]"]
            ]
          ]
        ]
      ]

      geminiService.sendClientContent(content)
    }

    NSLog("[Gemini] Flushed \(bufferedContext.count) buffered context messages")
    bufferedContext.removeAll()
  }
}

// MARK: - WakeWordDelegate

extension GeminiSessionViewModel: WakeWordDelegate {
    func wakeWordDetected() {
        NSLog("[Gemini] Wake word detected! Activating session...")

        Task { @MainActor in
            await activateGeminiSession()
        }
    }
}
