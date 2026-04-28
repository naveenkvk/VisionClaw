import Foundation

enum OpenClawConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: OpenClawConnectionState = .notConfigured

  // Callback for OpenClaw responses (for TTS and transcription display)
  var onResponseReceived: ((String) -> Void)?

  private let session: URLSession
  private let pingSession: URLSession
  private var sessionKey: String
  private var conversationHistory: [[String: String]] = []
  private let maxHistoryTurns = 10

  private static let stableSessionKey = "agent:main:glass"

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)

    self.sessionKey = OpenClawBridge.stableSessionKey
  }

  // MARK: - Authentication Helper

  /// Get authorization header value using static token (HTTP-only architecture)
  private func getAuthorizationHeader() -> String {
    return "Bearer \(GeminiConfig.openClawGatewayToken)"
  }

  func checkConnection() async {
    guard GeminiConfig.isOpenClawConfigured else {
      connectionState = .notConfigured
      return
    }
    connectionState = .checking

    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let urlString = "http://\(host):\(GeminiConfig.openClawPort)/v1/chat/completions"
    guard let url = URL(string: urlString) else {
      connectionState = .unreachable("Invalid URL: \(urlString)")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("glass", forHTTPHeaderField: "x-openclaw-message-channel")
    do {
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        connectionState = .connected
        NSLog("[OpenClaw] Gateway reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[OpenClaw] Gateway unreachable: %@", error.localizedDescription)
    }
  }

  func resetSession() {
    conversationHistory = []
    NSLog("[OpenClaw] Session reset (key retained: %@)", sessionKey)
  }

  // MARK: - LinkedIn Profile Finder
  
  /// Check if task is a LinkedIn search request and handle it
    private func handleLinkedInRequest(_ task: String) async -> ToolResult? {
    let lowerTask = task.lowercased()
    
    // Check for LinkedIn-related keywords
    let linkedInPatterns = [
      "find linkedin",
      "get linkedin",
      "search linkedin",
      "linkedin profile",
      "linkedin for",
      "find.*linkedin",
      "linkedin.*profile"
    ]
    
    let isLinkedInRequest = linkedInPatterns.contains { pattern in
      lowerTask.range(of: pattern, options: .regularExpression) != nil
    }
    
    guard isLinkedInRequest else { return nil }
    
    let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    // Extract name - remove common keywords
    var name = task
      .replacingOccurrences(of: "find linkedin for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "find linkedin profile for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "get linkedin of", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "get linkedin for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "search linkedin for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "linkedin profile for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "linkedin for", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "linkedin", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "profile", with: "", options: .caseInsensitive)
      .trimmingCharacters(in: trimSet)
    
    guard !name.isEmpty else { return nil }
    
    NSLog("[OpenClaw] LinkedIn request detected for: %@", name)
    
    // Call the LinkedIn finder skill via direct endpoint
    return await callLinkedInFinder(name: name)
  }
  
  /// Call the LinkedIn finder skill directly
  private func callLinkedInFinder(name: String) async -> ToolResult {
    guard let url = URL(string: "\(GeminiConfig.openClawHost):5002/skill/linkedin-finder") else {
      return .failure("Invalid skill URL")
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
      "name": name,
      "send_to_telegram": true
    ]
    
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return .failure("Skill returned HTTP \(code)")
      }
      
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let url = json["url"] as? String {
        let response = "Found LinkedIn profile for \(name): \(url)\n\nSent to Telegram ✓"
        onResponseReceived?(response)
        return .success(response)
      }

      let raw = String(data: data, encoding: .utf8) ?? "No result"
      onResponseReceived?(raw)
      return .success(raw)
    } catch {
      return .failure("LinkedIn finder error: \(error.localizedDescription)")
    }
  }

  // MARK: - Agent Chat (session continuity via x-openclaw-session-key header)

  func delegateTask(
    task: String,
    toolName: String = "execute"
  ) async -> ToolResult {
    lastToolCallStatus = .executing(toolName)

    // Check for LinkedIn requests first
    if let linkedInResult = await handleLinkedInRequest(task) {
      lastToolCallStatus = .completed("linkedin-finder")
      conversationHistory.append(["role": "user", "content": task])
      conversationHistory.append(["role": "assistant", "content": linkedInResult.responseValue as? String ?? "LinkedIn search completed"])
      return linkedInResult
    }

    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let urlString = "http://\(host):\(GeminiConfig.openClawPort)/v1/chat/completions"
    guard let url = URL(string: urlString) else {
      lastToolCallStatus = .failed(toolName, "Invalid URL: \(urlString)")
      return .failure("Invalid gateway URL")
    }

    // Append the new user message to conversation history
    conversationHistory.append(["role": "user", "content": task])

    // Trim history to keep only the most recent turns (user+assistant pairs)
    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
    request.setValue("glass", forHTTPHeaderField: "x-openclaw-message-channel")

    let body: [String: Any] = [
      "model": "openclaw",
      "messages": conversationHistory,
      "stream": false
    ]

    NSLog("[OpenClaw] Sending %d messages in conversation", conversationHistory.count)

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        // Append assistant response to history for continuity
        conversationHistory.append(["role": "assistant", "content": content])
        NSLog("[OpenClaw] Agent result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        onResponseReceived?(content)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      conversationHistory.append(["role": "assistant", "content": raw])
      NSLog("[OpenClaw] Agent raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      onResponseReceived?(raw)
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] Agent error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("Agent error: \(error.localizedDescription)")
    }
  }

  // MARK: - User Registry Intents (structured API)

  /// Call lookup_face intent via /api/v1/message endpoint
  func callUserRegistryLookup(
    embedding: [Float],
    threshold: Float = 0.15
  ) async -> ToolResult {
    lastToolCallStatus = .executing("lookup_face")

    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let urlString = "http://\(host):\(GeminiConfig.openClawPort)/api/v1/message"

    guard let url = URL(string: urlString) else {
      lastToolCallStatus = .failed("lookup_face", "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    // Build intent payload
    let embeddingData: [String: Any] = [
      "embedding": embedding,
      "threshold": threshold
    ]

    guard let embeddingJson = try? JSONSerialization.data(withJSONObject: embeddingData),
          let embeddingStr = String(data: embeddingJson, encoding: .utf8) else {
      lastToolCallStatus = .failed("lookup_face", "Failed to serialize embedding")
      return .failure("Failed to serialize embedding")
    }

    let intentMessage = "[INTENT:lookup_face] \(embeddingStr)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "channel": "webchat",
      "message": intentMessage
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        NSLog("[OpenClaw] lookup_face failed: HTTP %d", code)
        lastToolCallStatus = .failed("lookup_face", "HTTP \(code)")
        return .failure("lookup_face returned HTTP \(code)")
      }

      // Parse response - expecting OpenClaw message response wrapper
      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let message = json["message"] as? String {
        NSLog("[OpenClaw] lookup_face result: %@", String(message.prefix(200)))
        lastToolCallStatus = .completed("lookup_face")
        return .success(message)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      NSLog("[OpenClaw] lookup_face raw: %@", String(raw.prefix(200)))
      lastToolCallStatus = .completed("lookup_face")
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] lookup_face error: %@", error.localizedDescription)
      lastToolCallStatus = .failed("lookup_face", error.localizedDescription)
      return .failure("lookup_face error: \(error.localizedDescription)")
    }
  }

  /// Call register_face intent via /api/v1/message endpoint
  func callUserRegistryRegister(
    embedding: [Float],
    confidence: Float,
    snapshotJPEG: Data?,
    locationHint: String?
  ) async -> ToolResult {
    lastToolCallStatus = .executing("register_face")

    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let urlString = "http://\(host):\(GeminiConfig.openClawPort)/api/v1/message"

    guard let url = URL(string: urlString) else {
      lastToolCallStatus = .failed("register_face", "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var registerData: [String: Any] = [
      "embedding": embedding,
      "confidence_score": confidence,
      "source": "mediapipe"
    ]

    if let snapshot = snapshotJPEG {
      registerData["snapshot_url"] = "data:image/jpeg;base64," + snapshot.base64EncodedString()
    }

    if let location = locationHint {
      registerData["location_hint"] = location
    }

    guard let registerJson = try? JSONSerialization.data(withJSONObject: registerData),
          let registerStr = String(data: registerJson, encoding: .utf8) else {
      lastToolCallStatus = .failed("register_face", "Failed to serialize")
      return .failure("Failed to serialize register data")
    }

    let intentMessage = "[INTENT:register_face] \(registerStr)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "channel": "webchat",
      "message": intentMessage
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        NSLog("[OpenClaw] register_face failed: HTTP %d", code)
        lastToolCallStatus = .failed("register_face", "HTTP \(code)")
        return .failure("register_face returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let message = json["message"] as? String {
        NSLog("[OpenClaw] register_face result: %@", String(message.prefix(200)))
        lastToolCallStatus = .completed("register_face")
        return .success(message)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      lastToolCallStatus = .completed("register_face")
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] register_face error: %@", error.localizedDescription)
      lastToolCallStatus = .failed("register_face", error.localizedDescription)
      return .failure("register_face error: \(error.localizedDescription)")
    }
  }

  /// Call save_conversation intent via /api/v1/message endpoint
  func callUserRegistrySaveConversation(
    userId: String,
    transcript: String,
    durationSeconds: Int,
    locationHint: String?
  ) async -> ToolResult {
    lastToolCallStatus = .executing("save_conversation")

    let host = GeminiConfig.openClawHost
      .replacingOccurrences(of: "http://", with: "")
      .replacingOccurrences(of: "https://", with: "")
    let urlString = "http://\(host):\(GeminiConfig.openClawPort)/api/v1/message"

    guard let url = URL(string: urlString) else {
      lastToolCallStatus = .failed("save_conversation", "Invalid URL")
      return .failure("Invalid gateway URL")
    }

    var saveData: [String: Any] = [
      "user_id": userId,
      "transcript": transcript,
      "duration_seconds": durationSeconds,
      "occurred_at": ISO8601DateFormatter().string(from: Date())
    ]

    if let location = locationHint {
      saveData["location_hint"] = location
    }

    guard let saveJson = try? JSONSerialization.data(withJSONObject: saveData),
          let saveStr = String(data: saveJson, encoding: .utf8) else {
      lastToolCallStatus = .failed("save_conversation", "Failed to serialize")
      return .failure("Failed to serialize conversation data")
    }

    let intentMessage = "[INTENT:save_conversation] \(saveStr)"

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "channel": "webchat",
      "message": intentMessage
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        NSLog("[OpenClaw] save_conversation failed: HTTP %d", code)
        lastToolCallStatus = .failed("save_conversation", "HTTP \(code)")
        return .failure("save_conversation returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let message = json["message"] as? String {
        NSLog("[OpenClaw] save_conversation result: %@", String(message.prefix(200)))
        lastToolCallStatus = .completed("save_conversation")
        return .success(message)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      lastToolCallStatus = .completed("save_conversation")
      return .success(raw)
    } catch {
      NSLog("[OpenClaw] save_conversation error: %@", error.localizedDescription)
      lastToolCallStatus = .failed("save_conversation", error.localizedDescription)
      return .failure("save_conversation error: \(error.localizedDescription)")
    }
  }
}
