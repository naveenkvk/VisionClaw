# OpenClaw Device Identity - Testing Guide

## Quick Start

This guide will help you verify that the device identity authentication is working correctly.

---

## Prerequisites

1. ✅ Code is implemented and builds successfully
2. OpenClaw Gateway running on Mac at `192.168.1.173:18789`
3. iPhone on same WiFi network as Mac
4. Ray-Ban Meta glasses paired (optional, for full flow)

---

## Test 1: First Launch - New Device Authentication

### Steps

1. **Clean Install** (if testing for first time):
   ```bash
   # Delete app from iPhone to clear Keychain
   # Or use Xcode: Product → Clean Build Folder
   ```

2. **Launch App in Xcode**:
   - Open `samples/CameraAccess/CameraAccess.xcodeproj`
   - Select your iPhone as target device
   - Run (⌘R)

3. **Monitor Console Output**:
   - Open Xcode Console (⌘⇧C)
   - Filter for: `DeviceIdentity`, `OpenClawWS`

### Expected Console Output

```
✅ [DeviceIdentity] Generating new Ed25519 keypair
✅ [DeviceIdentity] Generated new device ID: a1b2c3d4e5f6...
✅ [DeviceIdentity] Saved to keychain: com.visionclaw.device.privateKey
✅ [DeviceIdentity] Saved to keychain: com.visionclaw.device.publicKey
✅ [OpenClawWS] Connecting to ws://192.168.1.173:18789
✅ [OpenClawWS] Received challenge nonce
✅ [DeviceIdentity] Signed challenge: 64 bytes
✅ [OpenClawWS] Signed challenge with device key
✅ [OpenClawWS] Connected and authenticated
✅ [OpenClawWS] Device token stored for future reconnections
```

### Success Criteria

- [x] Keypair generated and saved to Keychain
- [x] Device ID derived from public key
- [x] Challenge received and signed
- [x] WebSocket connection authenticated
- [x] Device token stored

### Failure Indicators

❌ `[OpenClawWS] Connect failed: device identity required` → Device identity not sent correctly
❌ `[DeviceIdentity] Keychain save failed: -34018` → Keychain access issue (check entitlements)
❌ `[DeviceIdentity] Failed to sign challenge: ...` → Crypto operation failed
❌ Timeout or no response → Gateway not reachable

---

## Test 2: HTTP Endpoints Authentication

### Steps

1. **Wait for WebSocket to connect** (from Test 1)

2. **Trigger Face Detection** (or any user registry operation):
   - Point camera at a face (if MediaPipe enabled)
   - Or manually trigger from code/debug menu

3. **Monitor Console for HTTP Requests**:
   - Filter for: `OpenClaw`, `lookup_face`

### Expected Console Output

```
✅ [OpenClaw] Sending lookup_face request
✅ [OpenClaw] Using device token for authorization
✅ [OpenClaw] lookup_face result: {"matched":false,...}
```

### Success Criteria

- [x] HTTP request sent with device token (not legacy token)
- [x] Response is 200 OK (not 404)
- [x] Response contains valid JSON data

### Failure Indicators

❌ `[OpenClaw] lookup_face failed: HTTP 404` → Device token not recognized by gateway
❌ `[OpenClaw] No device token available - using legacy token` → WebSocket auth didn't complete
❌ `[OpenClaw] ... error: The request timed out` → Gateway not responding

---

## Test 3: Reconnection with Stored Token

### Steps

1. **Close App** (swipe up from app switcher)
   - This keeps Keychain data intact

2. **Wait 5 seconds**

3. **Relaunch App**

4. **Monitor Console**:
   - Filter for: `DeviceIdentity`, `OpenClawWS`

### Expected Console Output

```
✅ [DeviceIdentity] Loaded existing identity: a1b2c3d4e5f6...
✅ [OpenClawWS] Connecting to ws://192.168.1.173:18789
✅ [OpenClawWS] Received challenge nonce
✅ [OpenClawWS] Using stored device token for reconnection
✅ [OpenClawWS] Signed challenge with device key
✅ [OpenClawWS] Connected and authenticated
```

### Success Criteria

- [x] Existing keypair loaded (not regenerated)
- [x] Stored device token used for reconnection
- [x] Connection succeeds without manual approval
- [x] Reconnection is fast (<2 seconds)

### Failure Indicators

❌ `[DeviceIdentity] Generating new Ed25519 keypair` → Keychain was cleared (unexpected)
❌ `[OpenClawWS] Connect failed: invalid token` → Token was invalidated or expired
❌ Connection takes >5 seconds → Token not being used (falling back to full auth)

---

## Test 4: Network Interruption Recovery

### Steps

1. **Connect Successfully** (verify WebSocket is connected)

2. **Disconnect WiFi**:
   - Turn off WiFi on iPhone
   - Wait 5 seconds

3. **Monitor Console**:
   - Should see reconnection attempts

4. **Reconnect WiFi**:
   - Turn WiFi back on
   - Wait for reconnection

5. **Verify Recovery**:
   - Check console for successful reconnection

### Expected Console Output

```
⚠️  [OpenClawWS] Receive error: The network connection was lost
⚠️  [OpenClawWS] Reconnecting in 2s
✅ [OpenClawWS] Connecting to ws://192.168.1.173:18789
✅ [OpenClawWS] Using stored device token for reconnection
✅ [OpenClawWS] Connected and authenticated
```

### Success Criteria

- [x] Disconnection detected
- [x] Automatic reconnection attempted
- [x] Reconnection succeeds with stored token
- [x] No manual intervention required

---

## Test 5: End-to-End Face Recognition Flow

### Steps

1. **Ensure WebSocket Connected** (green status)

2. **Point Camera at Face**:
   - Use Ray-Ban Meta glasses camera
   - Or iPhone camera in testing mode

3. **Speak to Trigger Detection**:
   - Say: "Hey, do you recognize me?"

4. **Monitor Console**:
   - Filter for: `FaceDetection`, `UserRegistry`, `OpenClaw`

### Expected Console Output

```
✅ [FaceDetection] Face detected, confidence: 0.92
✅ [UserRegistry] Calling lookup_face
✅ [OpenClaw] lookup_face result: {"matched":false}
✅ [UserRegistry] No match, registering new face
✅ [OpenClaw] register_face result: {"user_id":"...","is_new_user":true}
✅ [Gemini] Context injected: "New person detected, no prior history"
```

### Success Criteria

- [x] Face detection triggers lookup
- [x] HTTP requests succeed (200 OK)
- [x] If no match, new user registered
- [x] Context injected into Gemini session

---

## Debugging Tips

### Check Gateway Logs

If WebSocket fails to connect, check OpenClaw Gateway logs on Mac:

```bash
# Find OpenClaw Gateway process
ps aux | grep openclaw

# View logs (location varies)
tail -f ~/.openclaw/logs/gateway.log
```

Look for:
- Device identity validation errors
- Challenge-response signature verification
- Token issuance

### Check Keychain Data

To verify keypair was stored:

1. On iPhone: Settings → Passwords → (authenticate)
2. Search for: `com.visionclaw.device`
3. Should NOT appear (Keychain items for keys aren't visible in UI)

Alternative: Check via code (add debug log):
```swift
if identityManager.loadPrivateKey() != nil {
    print("✅ Private key exists in Keychain")
}
```

### Force Re-Authentication

To test challenge-response without stored token:

```swift
// Temporarily add to DeviceIdentityManager:
func clearAllIdentity() {
    clearDeviceToken()
    // Delete keypair from Keychain
    SecItemDelete([
        kSecClass: kSecClassKey,
        kSecAttrApplicationTag: privateKeyTag
    ] as CFDictionary)
    // ... same for public key
}
```

Call this before testing to simulate first-time setup.

---

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "device identity required" | WebSocket not sending device proof | Check `sendConnectHandshake()` includes `device` field |
| HTTP 404 on lookup_face | Device token not used | Verify `getAuthorizationHeader()` returns device token |
| "Keychain save failed: -34018" | Keychain entitlement missing | Add Keychain Sharing capability in Xcode |
| No challenge received | Gateway not sending nonce | Check gateway configuration, protocol version |
| Connection timeout | Wrong host/port | Verify `Secrets.openClawHost` and `openClawPort` |

---

## Success Checklist

Before marking implementation as complete, verify ALL of these:

- [ ] Test 1: First launch generates keypair and authenticates
- [ ] Test 2: HTTP endpoints return 200 OK (not 404)
- [ ] Test 3: Reconnection uses stored token
- [ ] Test 4: Network interruption recovers automatically
- [ ] Test 5: End-to-end face recognition flow works
- [ ] Console shows NO errors related to device identity
- [ ] Gateway logs show successful device authentication
- [ ] Multiple reconnections work without issues
- [ ] Token persists across app restarts

---

## Rollback Instructions

If major issues occur, you can temporarily revert:

1. **Restore Old WebSocket Handshake**:
   ```swift
   // In OpenClawEventClient.swift
   "auth": [
     "token": GeminiConfig.openClawGatewayToken
   ]
   // Remove "device" field
   ```

2. **Restore Old HTTP Auth**:
   ```swift
   // In OpenClawBridge.swift
   request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", ...)
   ```

3. **Uncomment Client ID**:
   ```swift
   // In Secrets.swift
   static let openClawClientId = "cli"
   ```

**Note**: This rollback will NOT fix the "device identity required" error - it just restores the previous state. The proper fix is the device identity implementation.

---

## Next Steps After Successful Testing

1. **Document Results** → Update MEMORY.md with test outcomes
2. **Update User Registry Flow** → Ensure face detection coordinator uses authenticated connection
3. **Deploy to Production** → If testing successful, consider this implementation stable
4. **Monitor in Production** → Watch for any edge cases or token expiration issues

---

## Contact

If you encounter issues not covered here, check:
- `/DEVICE_IDENTITY_IMPLEMENTATION.md` for implementation details
- CLAUDE.md for system architecture
- OpenClaw Gateway documentation for protocol specification
