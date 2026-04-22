import Foundation

/// Direct HTTP client for User Registry microservice
/// NOTE: In production, all calls route through OpenClaw.
/// This bridge exists for development/testing only.
@MainActor
class UserRegistryBridge {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API (matches wire contracts from CLAUDE.md Section 4)

    func searchFace(embedding: [Float], threshold: Float = 0.4) async -> FaceLookupResponse? {
        guard let url = buildURL(path: "/faces/search") else { return nil }

        let body: [String: Any] = [
            "embedding": embedding,
            "threshold": threshold
        ]

        return await post(url: url, body: body)
    }

    func registerFace(
        embedding: [Float],
        confidence: Float,
        snapshotJPEG: Data?,
        locationHint: String?,
        existingUserId: String?
    ) async -> FaceRegistrationResponse? {
        guard let url = buildURL(path: "/faces/register") else { return nil }

        var body: [String: Any] = [
            "embedding": embedding,
            "confidence_score": confidence,
            "source": "mediapipe"
        ]

        if let snapshot = snapshotJPEG {
            // Base64 encode snapshot
            body["snapshot_url"] = "data:image/jpeg;base64," + snapshot.base64EncodedString()
        }

        if let location = locationHint {
            body["location_hint"] = location
        }

        if let userId = existingUserId {
            body["existing_user_id"] = userId
        }

        return await post(url: url, body: body)
    }

    func saveConversation(
        userId: String,
        transcript: String,
        topics: [String],
        actionItems: [String],
        durationSeconds: Int,
        locationHint: String?
    ) async -> Bool {
        guard let url = buildURL(path: "/conversations") else { return false }

        var body: [String: Any] = [
            "user_id": userId,
            "transcript": transcript,
            "topics": topics,
            "action_items": actionItems,
            "duration_seconds": durationSeconds,
            "occurred_at": ISO8601DateFormatter().string(from: Date())
        ]

        if let location = locationHint {
            body["location_hint"] = location
        }

        let response: ConversationSaveResponse? = await post(url: url, body: body)
        return response?.data?.conversationId != nil
    }

    // MARK: - Private Helpers

    private func buildURL(path: String) -> URL? {
        guard Secrets.userRegistryHost.hasPrefix("http") else {
            NSLog("[UserRegistry] Invalid host in Secrets: \(Secrets.userRegistryHost)")
            return nil
        }

        let urlString = "\(Secrets.userRegistryHost):\(Secrets.userRegistryPort)\(path)"
        return URL(string: urlString)
    }

    private func post<T: Codable>(url: URL, body: [String: Any]) async -> T? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !Secrets.userRegistryToken.isEmpty {
            request.setValue("Bearer \(Secrets.userRegistryToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("[UserRegistry] Invalid response type")
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
                NSLog("[UserRegistry] HTTP %d: %@", httpResponse.statusCode, String(bodyStr.prefix(200)))
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("[UserRegistry] Error: \(error.localizedDescription)")
            return nil
        }
    }
}
