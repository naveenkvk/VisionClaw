import Foundation

/// Orchestrates face detection → lookup → context injection → conversation save flow
/// Uses unified OpenResponses API for context/profile management
@MainActor
class UserRegistryCoordinator: FaceDetectionDelegate {
    // MARK: - Dependencies
    private weak var geminiViewModel: GeminiSessionViewModel?
    private let userRegistryBridge: UserRegistryBridge
    private let openClawBridge: OpenClawBridge
    private let openResponsesBridge: OpenResponsesBridge

    // MARK: - Session State
    private var currentUserId: String?
    private var sessionStartTime: Date?
    private var currentUserName: String?

    // MARK: - Initialization
    init(
        userRegistryBridge: UserRegistryBridge,
        openClawBridge: OpenClawBridge,
        openResponsesBridge: OpenResponsesBridge,
        gemini: GeminiSessionViewModel
    ) {
        self.userRegistryBridge = userRegistryBridge
        self.openClawBridge = openClawBridge
        self.openResponsesBridge = openResponsesBridge
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

    // MARK: - Face Detection Flow (Unified OpenResponses API)

    private func handleFaceDetection(_ result: FaceDetectionResult) async {
        NSLog("[UserRegistry] Processing face detection...")

        // Step 1: Face lookup via User Registry (direct, unchanged)
        guard let lookupResponse = await userRegistryBridge.searchFace(
            embedding: result.embedding,
            threshold: 0.4
        ) else {
            NSLog("[UserRegistry] Direct lookup failed")
            return
        }

        // Step 2: Handle based on match result
        if let data = lookupResponse.data, data.matched, let user = data.user {
            // Known user - fetch conversational context via OpenResponses
            NSLog("[UserRegistry] Known user detected: %@", user.id)

            currentUserId = user.id
            currentUserName = user.name
            sessionStartTime = Date()

            // Call OpenResponses fetch stage
            if let contextText = await openResponsesBridge.fetchContext(userId: user.id) {
                injectContextIntoGemini(contextText)
                NSLog("[UserRegistry] Context injected for user: %@", user.name ?? user.id)
            } else {
                // Fallback: build context from raw data
                NSLog("[UserRegistry] Context fetch failed, using fallback")
                await processRawLookupResponse(lookupResponse, originalResult: result)
            }
        } else {
            // Unknown user - register
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
        // Step 1: Register face directly with User Registry
        guard let registerResponse = await userRegistryBridge.registerFace(
            embedding: result.embedding,
            confidence: result.confidence,
            snapshotJPEG: result.snapshotJPEG,
            locationHint: nil,  // TODO: Add location tracking
            existingUserId: nil
        ) else {
            NSLog("[UserRegistry] Registration failed")
            return
        }

        guard let data = registerResponse.data else {
            NSLog("[UserRegistry] Registration response missing data")
            return
        }

        // Update local state immediately
        currentUserId = data.userId
        currentUserName = nil  // Will be set when user identifies themselves
        sessionStartTime = Date()

        // Step 2: Register profile via OpenResponses (minimal profile initially)
        if let welcomeMessage = await openResponsesBridge.registerUser(
            userId: data.userId,
            profile: UserProfile.minimal()
        ) {
            injectContextIntoGemini(welcomeMessage)
            NSLog("[UserRegistry] New user registered with welcome: %@", data.userId)
        } else {
            NSLog("[UserRegistry] Profile registration failed (non-fatal, face is registered)")
            // Continue anyway - face is registered in User Registry
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

        // Inject for immediate speech output
        gemini.injectAgentResponse(context)

        // Also inject as system context for conversation history
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
        NSLog("[UserRegistry] Ending session for user %@ (duration: %ds)", userId, duration)

        Task {
            // Call OpenResponses update stage
            if let updateResponse = await openResponsesBridge.updateFromTranscript(
                userId: userId,
                chatTranscript: transcript
            ) {
                NSLog("[UserRegistry] Conversation updated: %@", updateResponse.status)

                // Log extracted insights
                if let notes = updateResponse.changes.notesAdded, notes > 0 {
                    NSLog("[UserRegistry] Added %d notes", notes)
                }
                if let skills = updateResponse.changes.skillsMerged, skills > 0 {
                    NSLog("[UserRegistry] Merged %d skills", skills)
                }
                if let interests = updateResponse.changes.interestsMerged, interests > 0 {
                    NSLog("[UserRegistry] Merged %d interests", interests)
                }
                if updateResponse.changes.summaryUpdated == true {
                    NSLog("[UserRegistry] User summary updated")
                }
            } else {
                NSLog("[UserRegistry] Update from transcript failed (non-blocking)")
                // Don't retry automatically - user can continue using the app
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
