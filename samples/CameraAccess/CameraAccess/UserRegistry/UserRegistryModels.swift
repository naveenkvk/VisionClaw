import Foundation

// MARK: - Wire Protocol Models (match NestJS contracts exactly)

/// Response from POST /faces/search
struct FaceLookupResponse: Codable {
    let data: FaceLookupData?
    let error: APIError?

    struct FaceLookupData: Codable {
        let matched: Bool
        let user: User?
        let confidence: Float?
        let recentConversations: [Conversation]

        struct User: Codable {
            let id: String
            let name: String?
            let notes: String?
            let lastSeenAt: String

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case notes
                case lastSeenAt = "last_seen_at"
            }
        }

        struct Conversation: Codable {
            let topics: [String]
            let actionItems: [String]
            let occurredAt: String

            enum CodingKeys: String, CodingKey {
                case topics
                case actionItems = "action_items"
                case occurredAt = "occurred_at"
            }
        }
    }
}

/// Response from POST /faces/register
struct FaceRegistrationResponse: Codable {
    let data: FaceRegistrationData?
    let error: APIError?

    struct FaceRegistrationData: Codable {
        let userId: String
        let faceEmbeddingId: String
        let isNewUser: Bool

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case faceEmbeddingId = "face_embedding_id"
            case isNewUser = "is_new_user"
        }
    }
}

/// Response from POST /conversations
struct ConversationSaveResponse: Codable {
    let data: ConversationData?
    let error: APIError?

    struct ConversationData: Codable {
        let conversationId: String

        enum CodingKeys: String, CodingKey {
            case conversationId = "conversation_id"
        }
    }
}

/// Generic API error structure
struct APIError: Codable {
    let code: String
    let message: String
}

// MARK: - Internal Models

/// Compact context for injection into Gemini
struct UserContext {
    let userId: String
    let name: String?
    let lastSeenDays: Int?
    let recentTopics: [String]
    let actionItems: [String]

    /// Generate a compact string (<500 chars) for Gemini system context
    func toSystemMessage() -> String {
        var parts: [String] = []

        if let name = name {
            parts.append("Speaking with \(name)")
        } else {
            parts.append("Speaking with a known person")
        }

        if let days = lastSeenDays, days > 0 {
            parts.append("last seen \(days) day\(days == 1 ? "" : "s") ago")
        }

        if !recentTopics.isEmpty {
            let topics = recentTopics.prefix(3).joined(separator: ", ")
            parts.append("Recent topics: \(topics)")
        }

        if !actionItems.isEmpty {
            let items = actionItems.prefix(3).joined(separator: "; ")
            parts.append("Action items: \(items)")
        }

        return parts.joined(separator: ". ") + "."
    }
}
