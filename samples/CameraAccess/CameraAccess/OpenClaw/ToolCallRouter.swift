import Foundation

@MainActor
class ToolCallRouter {
  private let bridge: OpenClawBridge
  private weak var geminiViewModel: GeminiSessionViewModel?
  private var inFlightTasks: [String: Task<Void, Never>] = [:]
  private var consecutiveFailures = 0
  private let maxConsecutiveFailures = 3

  init(bridge: OpenClawBridge, geminiViewModel: GeminiSessionViewModel? = nil) {
    self.bridge = bridge
    self.geminiViewModel = geminiViewModel
  }

  /// Route a tool call from Gemini to OpenClaw. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    NSLog("[ToolCall] Received: %@ (id: %@) args: %@",
          callName, callId, String(describing: call.args))

    // Circuit breaker: stop sending tool calls after repeated failures
    if consecutiveFailures >= maxConsecutiveFailures {
      NSLog("[ToolCall] Circuit breaker open (%d consecutive failures), rejecting %@",
            consecutiveFailures, callId)
      let errorResult: ToolResult = .failure(
        "Tool execution is temporarily unavailable after \(consecutiveFailures) consecutive failures. " +
        "Please tell the user you cannot complete this action right now and suggest they check their OpenClaw gateway connection."
      )
      let response = buildToolResponse(callId: callId, name: callName, result: errorResult)
      sendResponse(response)
      return
    }

    let task = Task { @MainActor in
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)
      let result = await bridge.delegateTask(task: taskDesc, toolName: callName)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      switch result {
      case .success:
        self.consecutiveFailures = 0
      case .failure:
        self.consecutiveFailures += 1
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      // Inject text for immediate speech
      if let speakableText = self.extractSpeakableText(from: result) {
        NSLog("[ToolCall] Injecting speakable text: \(String(speakableText.prefix(100)))")
        self.geminiViewModel?.injectAgentResponse(speakableText)
      }

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        NSLog("[ToolCall] Cancelling in-flight call: %@", id)
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (id, task) in inFlightTasks {
      NSLog("[ToolCall] Cancelling in-flight call: %@", id)
      task.cancel()
    }
    inFlightTasks.removeAll()
    consecutiveFailures = 0
  }

  // MARK: - Private

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue
          ]
        ]
      ]
    ]
  }

  // MARK: - Speech Injection

  /// Extract speakable text from tool result for immediate speech
  /// Returns nil for errors, pure JSON, or empty responses
  private func extractSpeakableText(from result: ToolResult) -> String? {
    guard case .success(let content) = result else {
      // Don't speak errors - they're shown in UI only
      return nil
    }

    var text = content.trimmingCharacters(in: .whitespacesAndNewlines)

    // Skip empty responses
    guard !text.isEmpty else { return nil }

    // Try to extract message from JSON responses
    if text.hasPrefix("{") || text.hasPrefix("[") {
      if let data = text.data(using: .utf8),
         let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        // Try common message fields
        if let message = json["message"] as? String {
          text = message
        } else if let result = json["result"] as? String {
          text = result
        } else if let content = json["content"] as? String {
          text = content
        } else {
          // Pure JSON with no human-readable field - skip
          return nil
        }
      }
    }

    // Clean markdown formatting
    text = text.replacingOccurrences(of: "**", with: "")
    text = text.replacingOccurrences(of: "__", with: "")
    text = text.replacingOccurrences(of: "`", with: "")

    // Truncate to prevent speech flooding
    let maxLength = 500
    if text.count > maxLength {
      let index = text.index(text.startIndex, offsetBy: maxLength)
      text = String(text[..<index]) + "..."
    }

    return text
  }
}
