import Foundation

// MARK: - Conversational Lookup

struct ConversationalLookupRequest: Codable {
    let registryResponse: String  // JSON-encoded registry response
    let embedding: [Float]
    let locationHint: String?

    enum CodingKeys: String, CodingKey {
        case registryResponse = "registry_response"
        case embedding
        case locationHint = "location_hint"
    }
}

struct ConversationalLookupResponse: Codable {
    let conversational: String
    let user: UserSummary?
    let shouldInject: Bool

    enum CodingKeys: String, CodingKey {
        case conversational
        case user
        case shouldInject = "should_inject"
    }
}

struct UserSummary: Codable {
    let userId: String
    let name: String?
    let lastSeenAt: String?
    let recentTopics: [String]
    let actionItems: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case lastSeenAt = "last_seen_at"
        case recentTopics = "recent_topics"
        case actionItems = "action_items"
    }
}

// MARK: - Conversational Register

struct ConversationalRegisterRequest: Codable {
    let registryResponse: String
    let embedding: [Float]
    let locationHint: String?

    enum CodingKeys: String, CodingKey {
        case registryResponse = "registry_response"
        case embedding
        case locationHint = "location_hint"
    }
}

struct ConversationalRegisterResponse: Codable {
    let conversational: String
    let userId: String
    let shouldInject: Bool

    enum CodingKeys: String, CodingKey {
        case conversational
        case userId = "user_id"
        case shouldInject = "should_inject"
    }
}

// MARK: - Conversational Save

struct ConversationalSaveRequest: Codable {
    let userId: String
    let transcript: String
    let durationSeconds: Int
    let locationHint: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case transcript
        case durationSeconds = "duration_seconds"
        case locationHint = "location_hint"
    }
}

struct ConversationalSaveResponse: Codable {
    let conversational: String
    let conversationId: String

    enum CodingKeys: String, CodingKey {
        case conversational
        case conversationId = "conversation_id"
    }
}

// MARK: - Helper Extensions

extension FaceLookupResponse {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

extension FaceRegistrationResponse {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
