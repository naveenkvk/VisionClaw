//
//  OpenResponsesBridge.swift
//  CameraAccess
//
//  Created by Claude Code on 2026-04-24.
//  HTTP client for unified OpenResponses API
//

import Foundation
import os.log

class OpenResponsesBridge {
    private let session: URLSession
    private let log = OSLog(subsystem: "com.visionclaw.openresponses", category: "bridge")

    // Callback for spoken responses (for TTS and transcription display)
    var onResponseReceived: ((String) -> Void)?

    // OpenClaw Gateway envelope constants
    private let openClawModel = "openclaw:main"
    private let openClawInstructions = "You are handling a Vision Claw registry operation. Apply the visionclawbridge skill for the input provided."
    private let openClawUser = "visionclaw-registry"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 90  // 30s timeout for AI processing
        self.session = URLSession(configuration: config)
    }

    // MARK: - Stage: fetch (context retrieval for known users)

    /// Fetch conversational context for a known user
    /// - Parameter userId: UUID from User Registry
    /// - Returns: Plain text summary (e.g., "Speaking with Naveen. Last seen 3 days ago...")
    func fetchContext(
        userId: String,
        source: String = "visionclaw"
    ) async -> String? {
        let payload: [String: Any] = [
            "source": source,
            "stage": OpenResponsesStage.fetch.rawValue,
            "userId": userId
        ]

        guard let result: String = await postStage(stage: .fetch, body: payload) else {
            os_log("Fetch context failed for user: %@", log: log, type: .error, userId)
            return nil
        }

        os_log("Fetched context for user %@ (%d chars)", log: log, type: .info, userId, result.count)
        return result
    }

    // MARK: - Stage: register (user onboarding)

    /// Register a new user with profile
    /// - Parameters:
    ///   - userId: UUID from User Registry (face already registered)
    ///   - profile: User profile (can be minimal initially)
    /// - Returns: Plain text welcome message (e.g., "Welcome! I've added you to my memory...")
    func registerUser(
        userId: String,
        profile: UserProfile,
        source: String = "visionclaw"
    ) async -> String? {
        guard let profileDict = try? profile.toDictionary() else {
            os_log("Failed to serialize profile", log: log, type: .error)
            return nil
        }

        let payload: [String: Any] = [
            "source": source,
            "stage": OpenResponsesStage.register.rawValue,
            "userId": userId,
            "profile": profileDict
        ]

        guard let result: String = await postStage(stage: .register, body: payload) else {
            os_log("Register user failed: %@", log: log, type: .error, userId)
            return nil
        }

        os_log("Registered user %@", log: log, type: .info, userId)
        return result
    }

    // MARK: - Stage: update (session complete, process transcript)

    /// Update user profile from conversation transcript
    /// - Parameters:
    ///   - userId: UUID from User Registry
    ///   - chatTranscript: Full verbatim transcript of session
    /// - Returns: JSON response with change tracking
    func updateFromTranscript(
        userId: String,
        chatTranscript: String,
        source: String = "visionclaw"
    ) async -> UpdateResponse? {
        let payload: [String: Any] = [
            "source": source,
            "stage": OpenResponsesStage.update.rawValue,
            "userId": userId,
            "chatTranscript": chatTranscript
        ]

        guard let result: UpdateResponse = await postStage(stage: .update, body: payload) else {
            os_log("Update from transcript failed: %@", log: log, type: .error, userId)
            return nil
        }

        os_log("Updated user %@ (status: %@, notes: %d, skills: %d)",
               log: log, type: .info,
               userId, result.status,
               result.changes.notesAdded ?? 0,
               result.changes.skillsMerged ?? 0)
        return result
    }

    // MARK: - Private Helpers

    /// Build endpoint URL from configuration
    private func buildURL() -> URL? {
        let host = GeminiConfig.openResponsesHost
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        let urlString = "http://\(host):\(GeminiConfig.openResponsesPort)\(GeminiConfig.openResponsesEndpoint)"

        guard let url = URL(string: urlString) else {
            os_log("Invalid OpenResponses URL: %@", log: log, type: .error, urlString)
            return nil
        }

        return url
    }

    /// Get authorization header (reuses OpenClaw Gateway token)
    private func getAuthorizationHeader() -> String {
        return "Bearer \(GeminiConfig.openClawGatewayToken)"
    }

    /// Generic POST method supporting different response types
    private func postStage<T: Decodable>(
        stage: OpenResponsesStage,
        body: [String: Any]
    ) async -> T? {
        guard let url = buildURL() else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            // Step 1: Stringify the inner payload (stage-specific data)
            let innerPayloadData = try JSONSerialization.data(withJSONObject: body)
            guard let innerPayloadString = String(data: innerPayloadData, encoding: .utf8) else {
                os_log("Failed to stringify inner payload", log: log, type: .error)
                return nil
            }

            // Step 2: Wrap in OpenClaw Gateway envelope
            let wrappedPayload: [String: Any] = [
                "model": openClawModel,
                "instructions": openClawInstructions,
                "input": innerPayloadString,
                "user": openClawUser
            ]

            // Step 3: Serialize the wrapped payload
            request.httpBody = try JSONSerialization.data(withJSONObject: wrappedPayload)

            // Log the wrapped request payload
            if let requestJson = try? JSONSerialization.data(withJSONObject: wrappedPayload, options: .prettyPrinted),
               let requestString = String(data: requestJson, encoding: .utf8) {
                os_log("[OpenResponses] REQUEST to %@ (stage: %@):\n%@",
                       log: log, type: .debug,
                       url.absoluteString, stage.rawValue, requestString)
            }

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                os_log("Non-HTTP response received", log: log, type: .error)
                return nil
            }

            guard (200...299).contains(http.statusCode) else {
                os_log("HTTP %d: %@", log: log, type: .error, http.statusCode, String(data: data, encoding: .utf8) ?? "")
                return nil
            }

            // Log the response
            let responseString = String(data: data, encoding: .utf8) ?? "<binary data>"
            os_log("[OpenResponses] RESPONSE from %@ (stage: %@, HTTP %d):\n%@",
                   log: log, type: .debug,
                   url.absoluteString, stage.rawValue, http.statusCode, responseString)

            // Special handling for String responses (fetch, register)
            if T.self == String.self {
                // Try to parse as OpenResponses JSON structure first
                if let extractedText = extractTextFromResponse(data) {
                    // Notify callback for TTS + transcription
                    Task { @MainActor in
                        self.onResponseReceived?(extractedText)
                    }
                    return extractedText as? T
                }

                // Fallback: return raw string
                return String(data: data, encoding: .utf8) as? T
            }

            // JSON decoding for UpdateResponse
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)

        } catch {
            os_log("Request failed: %@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    /// Extract text from OpenResponses JSON structure
    /// Expected format: {"output": [{"content": [{"type": "output_text", "text": "..."}]}]}
    private func extractTextFromResponse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [[String: Any]],
              let firstOutput = output.first,
              let content = firstOutput["content"] as? [[String: Any]] else {
            return nil
        }

        // Find first output_text content
        for item in content {
            if let type = item["type"] as? String,
               type == "output_text",
               let text = item["text"] as? String {
                os_log("[OpenResponses] Extracted text: %@", log: log, type: .info, String(text.prefix(100)))
                return text
            }
        }

        return nil
    }
}
