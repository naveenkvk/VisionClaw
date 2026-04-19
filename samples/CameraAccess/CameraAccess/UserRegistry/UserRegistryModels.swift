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
        let recent_conversations: [Conversation]

        struct User: Codable {
            let id: String
            let name: String?
            let notes: String?
            let last_seen_at: String
        }

        struct Conversation: Codable {
            let topics: [String]
            let action_items: [String]
            let occurred_at: String
        }
    }
}

/// Response from POST /faces/register
struct FaceRegistrationResponse: Codable {
    let data: FaceRegistrationData?
    let error: APIError?

    struct FaceRegistrationData: Codable {
        let user_id: String
        let face_embedding_id: String
        let is_new_user: Bool
    }
}

/// Response from POST /conversations
struct ConversationSaveResponse: Codable {
    let data: ConversationData?
    let error: APIError?

    struct ConversationData: Codable {
        let conversation_id: String
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
