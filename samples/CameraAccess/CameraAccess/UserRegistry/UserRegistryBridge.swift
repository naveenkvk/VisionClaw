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

    func searchFace(embedding: [Float], threshold: Float = 0.7) async -> FaceLookupResponse? {
        guard let url = buildURL(path: "/faces/search") else { return nil }

        let body: [String: Any] = [
            "embedding": embedding,
            "threshold": threshold
        ]

        NSLog("[UserRegistry] Searching with %d-dim embedding, threshold: %.2f", embedding.count, threshold)
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
            "confidenceScore": confidence,  // camelCase for NestJS
            "source": "mediapipe"
        ]

        // TODO: Snapshot disabled - base64 encoding exceeds VARCHAR(500) limit in database
        // Need to either: increase DB column size, store in blob storage, or use file URLs
        // if let snapshot = snapshotJPEG {
        //     body["snapshotUrl"] = "data:image/jpeg;base64," + snapshot.base64EncodedString()
        // }

        if let location = locationHint {
            body["locationHint"] = location  // camelCase
        }

        if let userId = existingUserId {
            body["existingUserId"] = userId  // camelCase
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
            "userId": userId,                    // camelCase for NestJS
            "transcript": transcript,
            "topics": topics,
            "actionItems": actionItems,          // camelCase for NestJS
            "durationSeconds": durationSeconds,  // camelCase for NestJS
            "occurredAt": ISO8601DateFormatter().string(from: Date())  // camelCase for NestJS
        ]

        if let location = locationHint {
            body["locationHint"] = location  // camelCase
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

            // Log request details (excluding embedding to reduce noise)
            var logBody = body
            if let embedding = logBody["embedding"] as? [Float] {
                logBody["embedding"] = "[<\(embedding.count) values>]"
            }
            if let bodyData = try? JSONSerialization.data(withJSONObject: logBody),
               let bodyStr = String(data: bodyData, encoding: .utf8) {
                NSLog("[UserRegistry] POST %@: %@", url.path, String(bodyStr.prefix(200)))
            }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("[UserRegistry] Invalid response type")
                return nil
            }

            // Log response status and body
            let responseStr = String(data: data, encoding: .utf8) ?? "no body"
            NSLog("[UserRegistry] Response HTTP %d: %@", httpResponse.statusCode, String(responseStr.prefix(300)))

            guard (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Try to decode, log response data on failure
            let decoder = JSONDecoder()
            // User Registry returns camelCase, so no key conversion needed
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                let responseStr = String(data: data, encoding: .utf8) ?? "no response"
                NSLog("[UserRegistry] Decoding error: \(error.localizedDescription)")
                NSLog("[UserRegistry] Response was: %@", String(responseStr.prefix(500)))
                return nil
            }
        } catch {
            NSLog("[UserRegistry] Request error: \(error.localizedDescription)")
            return nil
        }
    }
}
