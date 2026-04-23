import Foundation

/// Orchestrates face detection → lookup → context injection → conversation save flow
/// Uses dual-API architecture: User Registry (direct) + OpenClaw Conversational (processing)
@MainActor
class UserRegistryCoordinator: FaceDetectionDelegate {
    // MARK: - Dependencies
    private weak var geminiViewModel: GeminiSessionViewModel?
    private let userRegistryBridge: UserRegistryBridge
    private let openClawBridge: OpenClawBridge
    private let conversationalBridge: OpenClawConversationalBridge

    // MARK: - Session State
    private var currentUserId: String?
    private var sessionStartTime: Date?
    private var currentUserName: String?

    // MARK: - Initialization
    init(
        userRegistryBridge: UserRegistryBridge,
        openClawBridge: OpenClawBridge,
        conversationalBridge: OpenClawConversationalBridge,
        gemini: GeminiSessionViewModel
    ) {
        self.userRegistryBridge = userRegistryBridge
        self.openClawBridge = openClawBridge
        self.conversationalBridge = conversationalBridge
        self.geminiViewModel = gemini
    }

    // MARK: - FaceDetectionDelegate

    nonisolated func didDetectFace(_ result: FaceDetectionResult) {
        NSLog("[UserRegistry] Face detected, confidence: %.2f", result.confidence)

        Task { @MainActor in
            // Skip if already processing a user in this session
            if currentUserId != nil {
                NSLog("[UserRegistry] Already have active user, skipping detection")
                return
            }

            await handleFaceDetection(result)
        }
    }

    nonisolated func didLoseFace() {
        NSLog("[UserRegistry] Face lost")
        // Could trigger session end here, but spec says wait for explicit endSession call
    }

    // MARK: - Face Detection Flow (Dual-API Architecture)

    private func handleFaceDetection(_ result: FaceDetectionResult) async {
        NSLog("[UserRegistry] Processing face detection (dual-API flow)...")

        // Step 1: Call User Registry directly for raw data
        guard let lookupResponse = await userRegistryBridge.searchFace(
            embedding: result.embedding,
            threshold: 0.4
        ) else {
            NSLog("[UserRegistry] Direct lookup failed, skipping")
            return
        }

        // Step 2: Send raw response to OpenClaw for conversational processing
        guard let conversationalResponse = await conversationalBridge.lookupFaceConversational(
            registryResponse: lookupResponse.toJSON(),
            embedding: result.embedding,
            locationHint: nil  // TODO: Add location tracking
        ) else {
            NSLog("[UserRegistry] Conversational processing failed, falling back to raw data")
            // Fallback: process raw response without conversational enhancement
            await processRawLookupResponse(lookupResponse, originalResult: result)
            return
        }

        // Step 3: Handle based on match result
        if let data = lookupResponse.data, data.matched, let user = conversationalResponse.user {
            // Known user - inject conversational context
            currentUserId = user.userId
            currentUserName = user.name
            sessionStartTime = Date()

            if conversationalResponse.shouldInject {
                injectContextIntoGemini(conversationalResponse.conversational)
            }

            NSLog("[UserRegistry] Recognized user: %@", user.name ?? user.userId)
        } else {
            // Unknown user - register directly, get conversational feedback
            NSLog("[UserRegistry] No match, registering new face...")
            await registerNewFace(result)
        }
    }

    /// Fallback: process raw User Registry response without conversational enhancement
    private func processRawLookupResponse(_ response: FaceLookupResponse, originalResult: FaceDetectionResult) async {
        guard let data = response.data, data.matched, let user = data.user else {
            NSLog("[UserRegistry] No match in raw response, registering...")
            await registerNewFace(originalResult)
            return
        }

        // Extract topics and action items from recent conversations
        let topics = data.recentConversations.flatMap { $0.topics }.prefix(3).map { $0 }
        let actionItems = data.recentConversations.flatMap { $0.actionItems }.prefix(3).map { $0 }

        currentUserId = user.id
        currentUserName = user.name
        sessionStartTime = Date()

        let context = buildUserContext(
            name: user.name,
            lastSeen: user.lastSeenAt,
            topics: Array(topics),
            actionItems: Array(actionItems)
        )
        injectContextIntoGemini(context)

        NSLog("[UserRegistry] Known user recognized (fallback): %@", user.id)
    }

    /// Explicitly register a new face when lookup returns no match
    private func registerNewFace(_ result: FaceDetectionResult) async {
        // Step 1: Register directly with User Registry
        guard let registerResponse = await userRegistryBridge.registerFace(
            embedding: result.embedding,
            confidence: result.confidence,
            snapshotJPEG: result.snapshotJPEG,
            locationHint: nil,
            existingUserId: nil
        ) else {
            NSLog("[UserRegistry] Registration failed")
            return
        }

        guard let data = registerResponse.data else {
            NSLog("[UserRegistry] Registration response missing data")
            return
        }

        // Step 2: Get conversational feedback from OpenClaw
        let conversationalResponse = await conversationalBridge.registerFaceConversational(
            registryResponse: registerResponse.toJSON(),
            embedding: result.embedding,
            locationHint: nil
        )

        // Step 3: Update local state
        currentUserId = data.userId
        currentUserName = nil
        sessionStartTime = Date()

        // Optionally inject conversational registration message
        if let response = conversationalResponse, response.shouldInject {
            injectContextIntoGemini(response.conversational)
        }

        NSLog("[UserRegistry] Registered new user: %@", data.userId)
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
            // Step 1: Save directly to User Registry
            // NOTE: Topics and action items extracted by OpenClaw, so pass empty arrays here
            let success = await userRegistryBridge.saveConversation(
                userId: userId,
                transcript: transcript,
                topics: [],  // Will be extracted by OpenClaw
                actionItems: [],  // Will be extracted by OpenClaw
                durationSeconds: duration,
                locationHint: nil
            )

            // Step 2: Notify OpenClaw for conversational processing + UserRegistry.md update
            if success {
                let conversationalResponse = await conversationalBridge.saveConversationConversational(
                    userId: userId,
                    transcript: transcript,
                    durationSeconds: duration,
                    locationHint: nil
                )

                if let response = conversationalResponse {
                    NSLog("[UserRegistry] Conversation saved and notified to OpenClaw: %@", response.conversationId)
                } else {
                    NSLog("[UserRegistry] Conversation saved but OpenClaw notification failed")
                }
            } else {
                NSLog("[UserRegistry] Failed to save conversation")
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
