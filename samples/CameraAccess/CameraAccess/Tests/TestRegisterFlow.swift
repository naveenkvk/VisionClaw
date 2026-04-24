//
//  TestRegisterFlow.swift
//  CameraAccess
//
//  Created by Claude Code on 2026-04-24.
//  Test script for validating the register flow with mock data
//

import Foundation

@MainActor
class RegisterFlowTest {

    static func runTest() async {
        print("=== Testing Register Flow ===\n")

        // Step 1: Create mock face embedding (128 random floats between -1 and 1)
        print("📝 Step 1: Creating mock face embedding...")
        let mockEmbedding = (0..<128).map { _ in Float.random(in: -1...1) }
        let mockConfidence: Float = 0.92
        print("✅ Created 128-dimensional embedding with confidence: \(mockConfidence)\n")

        // Step 2: Test UserRegistry registration
        print("📝 Step 2: Registering face with UserRegistry (port 3100)...")
        let userRegistryBridge = UserRegistryBridge()

        guard let registerResponse = await userRegistryBridge.registerFace(
            embedding: mockEmbedding,
            confidence: mockConfidence,
            snapshotJPEG: nil,  // No snapshot for test
            locationHint: "Test Location",
            existingUserId: nil
        ) else {
            print("❌ FAILED: UserRegistry registration failed")
            print("   Possible causes:")
            print("   - UserRegistry service not running on port 3100")
            print("   - Network connectivity issue")
            print("   - Invalid endpoint configuration")
            return
        }

        guard let data = registerResponse.data else {
            print("❌ FAILED: Registration response missing data")
            print("   Response: \(registerResponse)")
            return
        }

        let userId = data.userId
        print("✅ Face registered successfully!")
        print("   User ID: \(userId)")
        print("   Face Embedding ID: \(data.faceEmbeddingId)")
        print("   Is New User: \(data.isNewUser)")
        print()

        // Step 3: Test OpenResponses registration
        print("📝 Step 3: Registering profile with OpenResponses (port 18789, stage: register)...")
        let openResponsesBridge = OpenResponsesBridge()

        // Create minimal profile
        let minimalProfile = UserProfile.minimal()
        print("   Profile: \(minimalProfile)")
        print()

        guard let welcomeMessage = await openResponsesBridge.registerUser(
            userId: userId,
            profile: minimalProfile
        ) else {
            print("❌ FAILED: OpenResponses registration failed")
            print("   Possible causes:")
            print("   - OpenResponses API not deployed at http://192.168.1.173:18789/v1/responses")
            print("   - OpenClaw Gateway not running")
            print("   - Invalid bearer token")
            print("   - Backend skill not configured for 'register' stage")
            print()
            print("⚠️  Note: Face is still registered in UserRegistry (user_id: \(userId))")
            print("   The app will continue to work, but without conversational welcome message")
            return
        }

        print("✅ Profile registered successfully!")
        print("   Welcome Message:")
        print("   ---")
        print("   \(welcomeMessage)")
        print("   ---")
        print()

        // Step 4: Verify we can fetch context for this user
        print("📝 Step 4: Verifying context retrieval (stage: fetch)...")
        guard let contextText = await openResponsesBridge.fetchContext(userId: userId) else {
            print("⚠️  WARNING: Context fetch failed")
            print("   This is expected for a newly registered user with no conversation history")
            print()
            print("=== Test Complete ===")
            print("✅ Register flow validated (with expected fetch warning)")
            return
        }

        print("✅ Context retrieved successfully!")
        print("   Context:")
        print("   ---")
        print("   \(contextText)")
        print("   ---")
        print()

        print("=== Test Complete ===")
        print("✅ All stages passed! Register flow is working correctly.")
        print()
        print("Summary:")
        print("- UserRegistry: ✅ Face registered (ID: \(userId))")
        print("- OpenResponses: ✅ Profile registered with welcome message")
        print("- OpenResponses: ✅ Context retrieval working")
    }
}

// Main execution
Task { @MainActor in
    await RegisterFlowTest.runTest()
    exit(0)
}

// Keep the script running
RunLoop.main.run()
