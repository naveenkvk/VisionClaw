import Foundation

// MARK: - Conversational Lookup

struct ConversationalLookupRequest: Codable {
    let registryResponse: String  // JSON-encoded registry response
    let embedding: [Float]
    let locationHint: String?
    // API expects camelCase - Swift property names match
}

struct ConversationalLookupResponse: Codable {
    let conversational: String
    let user: UserSummary?
    let shouldInject: Bool
    // API returns camelCase - Swift property names match
}

struct UserSummary: Codable {
    let userId: String
    let name: String?
    let lastSeenAt: String?
    let recentTopics: [String]
    let actionItems: [String]
    // API returns camelCase - Swift property names match
}

// MARK: - Conversational Register

struct ConversationalRegisterRequest: Codable {
    let registryResponse: String
    let embedding: [Float]
    let locationHint: String?
    // API expects camelCase - Swift property names match
}

struct ConversationalRegisterResponse: Codable {
    let conversational: String
    let userId: String
    let shouldInject: Bool
    // API returns camelCase - Swift property names match
}

// MARK: - Conversational Save

struct ConversationalSaveRequest: Codable {
    let userId: String
    let transcript: String
    let durationSeconds: Int
    let locationHint: String?
    // API expects camelCase - Swift property names match
}

struct ConversationalSaveResponse: Codable {
    let conversational: String
    let conversationId: String
    // API returns camelCase - Swift property names match
}

// MARK: - Helper Extensions

extension FaceLookupResponse {
    func toJSON() -> String {
        let encoder = JSONEncoder()
        // Keep camelCase consistent with API expectations
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
        // Keep camelCase consistent with API expectations
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
