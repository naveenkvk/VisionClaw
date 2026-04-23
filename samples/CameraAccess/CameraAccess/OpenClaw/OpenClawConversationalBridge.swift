import Foundation
import os.log

/// HTTP client for OpenClaw Conversational API (port 3114)
/// Provides human-friendly conversational wrappers around raw User Registry data
class OpenClawConversationalBridge {
    private let session: URLSession
    private let log = OSLog(subsystem: "com.visionclaw.openclaw", category: "conversational")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Base URL Construction

    private func buildURL(path: String) -> URL? {
        let host = GeminiConfig.openClawConversationalHost
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        let port = GeminiConfig.openClawConversationalPort
        let urlString = "http://\(host):\(port)\(path)"
        return URL(string: urlString)
    }

    private func getAuthorizationHeader() -> String {
        return "Bearer \(GeminiConfig.openClawGatewayToken)"
    }

    // MARK: - Face Lookup Conversational

    func lookupFaceConversational(
        registryResponse: String,
        embedding: [Float],
        locationHint: String?
    ) async -> ConversationalLookupResponse? {
        guard let url = buildURL(path: "/conversational/lookup_face") else {
            os_log("Invalid URL for lookup_face", log: log, type: .error)
            return nil
        }

        let requestBody = ConversationalLookupRequest(
            registryResponse: registryResponse,
            embedding: embedding,
            locationHint: locationHint
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("agent:main:glass", forHTTPHeaderField: "x-openclaw-session-key")

        do {
            let encoder = JSONEncoder()
            // API expects camelCase - no key conversion needed
            request.httpBody = try encoder.encode(requestBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("Invalid response type", log: log, type: .error)
                return nil
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                os_log("HTTP %d from lookup_face", log: log, type: .error, httpResponse.statusCode)
                return nil
            }

            let decoder = JSONDecoder()
            // API returns camelCase - no key conversion needed
            let conversationalResponse = try decoder.decode(ConversationalLookupResponse.self, from: data)

            os_log("Conversational lookup successful", log: log, type: .info)
            return conversationalResponse

        } catch {
            os_log("Lookup failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Face Register Conversational

    func registerFaceConversational(
        registryResponse: String,
        embedding: [Float],
        locationHint: String?
    ) async -> ConversationalRegisterResponse? {
        guard let url = buildURL(path: "/conversational/register_face") else {
            os_log("Invalid URL for register_face", log: log, type: .error)
            return nil
        }

        let requestBody = ConversationalRegisterRequest(
            registryResponse: registryResponse,
            embedding: embedding,
            locationHint: locationHint
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("agent:main:glass", forHTTPHeaderField: "x-openclaw-session-key")

        do {
            let encoder = JSONEncoder()
            // API expects camelCase - no key conversion needed
            request.httpBody = try encoder.encode(requestBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                os_log("HTTP error from register_face", log: log, type: .error)
                return nil
            }

            let decoder = JSONDecoder()
            // API returns camelCase - no key conversion needed
            let conversationalResponse = try decoder.decode(ConversationalRegisterResponse.self, from: data)

            os_log("Conversational register successful", log: log, type: .info)
            return conversationalResponse

        } catch {
            os_log("Register failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Save Conversation Conversational

    func saveConversationConversational(
        userId: String,
        transcript: String,
        durationSeconds: Int,
        locationHint: String?
    ) async -> ConversationalSaveResponse? {
        guard let url = buildURL(path: "/conversational/save_conversation") else {
            os_log("Invalid URL for save_conversation", log: log, type: .error)
            return nil
        }

        let requestBody = ConversationalSaveRequest(
            userId: userId,
            transcript: transcript,
            durationSeconds: durationSeconds,
            locationHint: locationHint
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("agent:main:glass", forHTTPHeaderField: "x-openclaw-session-key")

        do {
            let encoder = JSONEncoder()
            // API expects camelCase - no key conversion needed
            request.httpBody = try encoder.encode(requestBody)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                os_log("HTTP error from save_conversation", log: log, type: .error)
                return nil
            }

            let decoder = JSONDecoder()
            // API returns camelCase - no key conversion needed
            let conversationalResponse = try decoder.decode(ConversationalSaveResponse.self, from: data)

            os_log("Conversational save successful", log: log, type: .info)
            return conversationalResponse

        } catch {
            os_log("Save failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Get User Summary Conversational

    func getUserSummaryConversational(userId: String) async -> ConversationalLookupResponse? {
        guard let url = buildURL(path: "/conversational/get_user_summary/\(userId)") else {
            os_log("Invalid URL for get_user_summary", log: log, type: .error)
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(getAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("agent:main:glass", forHTTPHeaderField: "x-openclaw-session-key")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                os_log("HTTP error from get_user_summary", log: log, type: .error)
                return nil
            }

            let decoder = JSONDecoder()
            // API returns camelCase - no key conversion needed
            let conversationalResponse = try decoder.decode(ConversationalLookupResponse.self, from: data)

            os_log("User summary retrieved", log: log, type: .info)
            return conversationalResponse

        } catch {
            os_log("Summary failed: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }
}
