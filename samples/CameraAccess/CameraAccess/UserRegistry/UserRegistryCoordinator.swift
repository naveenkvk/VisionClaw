import Foundation

/// Orchestrates face detection → lookup → context injection → conversation save flow
@MainActor
class UserRegistryCoordinator: FaceDetectionDelegate {
    // MARK: - Dependencies
    private weak var geminiViewModel: GeminiSessionViewModel?
    private var openClawBridge: OpenClawBridge { geminiViewModel!.openClawBridge }

    // MARK: - Session State
    private var currentUserId: String?
    private var sessionStartTime: Date?
    private var currentUserName: String?

    // MARK: - Initialization
    init(gemini: GeminiSessionViewModel) {
        self.geminiViewModel = gemini
    }

    // MARK: - FaceDetectionDelegate

    func didDetectFace(_ result: FaceDetectionResult) {
        NSLog("[UserRegistry] Face detected, confidence: %.2f", result.confidence)

        // Skip if already processing a user in this session
        if currentUserId != nil {
            NSLog("[UserRegistry] Already have active user, skipping detection")
            return
        }

        Task {
            await handleFaceDetection(result)
        }
    }

    func didLoseFace() {
        NSLog("[UserRegistry] Face lost")
        // Could trigger session end here, but spec says wait for explicit endSession call
    }

    // MARK: - Face Detection Flow

    private func handleFaceDetection(_ result: FaceDetectionResult) async {
        NSLog("[UserRegistry] Calling lookup_face intent with %d-dim embedding", result.embedding.count)

        // Call new structured lookup method
        let toolResult = await openClawBridge.callUserRegistryLookup(
            embedding: result.embedding,
            threshold: 0.4
        )

        switch toolResult {
        case .success(let response):
            await processLookupResponse(response, originalResult: result)
        case .failure(let error):
            NSLog("[UserRegistry] Lookup failed: \(error)")
            // Graceful degradation: continue session without context
        }
    }

    private func processLookupResponse(_ response: String, originalResult: FaceDetectionResult) async {
        // Parse OpenClaw's response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[UserRegistry] Failed to parse lookup response")
            return
        }

        if let matched = json["matched"] as? Bool, matched,
           let userId = json["user_id"] as? String {
            // Known person
            currentUserId = userId
            sessionStartTime = Date()

            let name = json["name"] as? String
            currentUserName = name

            let topics = json["recent_topics"] as? [String] ?? []
            let actionItems = json["action_items"] as? [String] ?? []
            let lastSeen = json["last_seen_at"] as? String

            let context = buildUserContext(name: name, lastSeen: lastSeen, topics: topics, actionItems: actionItems)
            injectContextIntoGemini(context)

            NSLog("[UserRegistry] Known user recognized: %@", userId)
        } else {
            // No match - explicitly register new face
            NSLog("[UserRegistry] No match found, registering new face")
            await registerNewFace(originalResult)
        }
    }

    /// Explicitly register a new face when lookup returns no match
    private func registerNewFace(_ result: FaceDetectionResult) async {
        let toolResult = await openClawBridge.callUserRegistryRegister(
            embedding: result.embedding,
            confidence: result.confidence,
            snapshotJPEG: result.snapshotJPEG,
            locationHint: nil
        )

        switch toolResult {
        case .success(let response):
            // Parse registration response
            if let data = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userId = json["user_id"] as? String {
                currentUserId = userId
                sessionStartTime = Date()
                NSLog("[UserRegistry] New user registered: %@", userId)
            }
        case .failure(let error):
            NSLog("[UserRegistry] Registration failed: %@", error)
        }
    }

    private func buildUserContext(name: String?, lastSeen: String?, topics: [String], actionItems: [String]) -> String {
        var parts: [String] = []

        if let name = name {
            parts.append("Speaking with \(name)")
        } else {
            parts.append("Speaking with a known person")
        }

        if let lastSeenStr = lastSeen,
           let lastSeenDate = ISO8601DateFormatter().date(from: lastSeenStr) {
            let days = Calendar.current.dateComponents([.day], from: lastSeenDate, to: Date()).day ?? 0
            if days > 0 {
                parts.append("last seen \(days) day\(days == 1 ? "" : "s") ago")
            }
        }

        if !topics.isEmpty {
            let topicStr = topics.prefix(3).joined(separator: ", ")
            parts.append("Recent topics: \(topicStr)")
        }

        if !actionItems.isEmpty {
            let itemStr = actionItems.prefix(3).joined(separator: "; ")
            parts.append("Action items: \(itemStr)")
        }

        return parts.joined(separator: ". ") + "."
    }

    private func injectContextIntoGemini(_ context: String) {
        guard let gemini = geminiViewModel else {
            NSLog("[UserRegistry] ERROR: Gemini view model not available")
            return
        }

        NSLog("[UserRegistry] Injecting context: \(context)")
        gemini.injectSystemContext(context)
    }

    // MARK: - Session End

    func endSession(transcript: String) {
        guard let userId = currentUserId else {
            NSLog("[UserRegistry] No active user, skipping conversation save")
            return
        }

        guard !transcript.isEmpty else {
            NSLog("[UserRegistry] Empty transcript, skipping save")
            resetSession()
            return
        }

        let duration = sessionStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0

        NSLog("[UserRegistry] Saving conversation for user %@, duration: %ds", userId, duration)

        Task {
            let result = await openClawBridge.callUserRegistrySaveConversation(
                userId: userId,
                transcript: transcript,
                durationSeconds: duration,
                locationHint: nil
            )

            switch result {
            case .success(let response):
                NSLog("[UserRegistry] Conversation saved: %@", String(response.prefix(100)))
            case .failure(let error):
                NSLog("[UserRegistry] Failed to save conversation: %@", error)
            }

            resetSession()
        }
    }

    private func resetSession() {
        currentUserId = nil
        sessionStartTime = nil
        currentUserName = nil
    }
}
