//
//  OpenResponsesModels.swift
//  CameraAccess
//
//  Created by Claude Code on 2026-04-24.
//  Data models for OpenResponses API three-stage interface
//

import Foundation

// MARK: - Stage Enumeration

enum OpenResponsesStage: String, Codable {
    case register
    case fetch
    case update
}

// MARK: - User Profile

struct UserProfile: Codable {
    let name: String?
    let role: String?
    let keySkills: [String]?
    let interests: [String]?
    let notes: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case name
        case role
        case keySkills = "key_skills"
        case interests
        case notes
        case metadata
    }

    /// Minimal initializer for faces detected without identification
    static func minimal() -> UserProfile {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return UserProfile(
            name: nil,
            role: nil,
            keySkills: nil,
            interests: nil,
            notes: "Registered via Ray-Ban Meta glasses",
            metadata: [
                "source": "mediapipe",
                "registered_at": timestamp
            ]
        )
    }
}

// MARK: - Request Models

struct RegisterRequest: Codable {
    let source: String
    let stage: OpenResponsesStage
    let userId: String
    let profile: UserProfile

    enum CodingKeys: String, CodingKey {
        case source
        case stage
        case userId = "userId"
        case profile
    }
}

struct FetchRequest: Codable {
    let source: String
    let stage: OpenResponsesStage
    let userId: String

    enum CodingKeys: String, CodingKey {
        case source
        case stage
        case userId = "userId"
    }
}

struct UpdateRequest: Codable {
    let source: String
    let stage: OpenResponsesStage
    let userId: String
    let chatTranscript: String

    enum CodingKeys: String, CodingKey {
        case source
        case stage
        case userId = "userId"
        case chatTranscript = "chatTranscript"
    }
}

// MARK: - Response Models

struct UpdateResponse: Codable {
    let status: String
    let userId: String
    let changes: ProfileChanges

    struct ProfileChanges: Codable {
        let notesAdded: Int?
        let skillsMerged: Int?
        let interestsMerged: Int?
        let summaryUpdated: Bool?

        enum CodingKeys: String, CodingKey {
            case notesAdded = "notes_added"
            case skillsMerged = "skills_merged"
            case interestsMerged = "interests_merged"
            case summaryUpdated = "summary_updated"
        }
    }

    enum CodingKeys: String, CodingKey {
        case status
        case userId = "user_id"
        case changes
    }
}

// MARK: - Codable Helpers

extension UserProfile {
    func toDictionary() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(self)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "com.visionclaw", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to convert UserProfile to dictionary"
            ])
        }
        return dict
    }
}
