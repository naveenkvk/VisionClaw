# Quick Start: Dual-API Architecture

## ✅ What's Done

The VisionClaw iOS app now uses a dual-API architecture:
1. **User Registry** (port 3100) - Direct calls for data retrieval
2. **OpenClaw Conversational** (port 3114) - Human-friendly processing

**Build Status**: ✅ `BUILD SUCCEEDED`

---

## 🔧 What You Need to Do

### Step 1: Update Configuration

Edit `samples/CameraAccess/CameraAccess/Secrets.swift`:

```swift
// Find this line:
static let openClawConversationalHost = "http://192.168.1.XXX"

// Replace with your OpenClaw Mac IP:
static let openClawConversationalHost = "http://192.168.1.173" // Example
```

**How to find OpenClaw Mac IP:**
```bash
# On the Mac running OpenClaw:
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### Step 2: Verify User Registry

```bash
# From your dev Mac:
curl http://MacBook-Pro.local:3100/health

# Expected: {"status":"ok"}
```

If this fails, start User Registry:
```bash
cd /Users/naveenkumarvk/Projects/USER-REGISTRY
docker-compose up
```

### Step 3: Build and Run

```bash
cd /Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build
```

Expected: `** BUILD SUCCEEDED **`

---

## 📝 What Logs to Look For

### Success Indicators

**Face Detection:**
```
[UserRegistry] Processing face detection (dual-API flow)...
[UserRegistry] Recognized user: Sarah Chen
[OpenClawConversational] Lookup successful
```

**Face Registration:**
```
[UserRegistry] No match, registering new face...
[UserRegistry] Registered new user: abc-123-uuid
```

**Conversation Save:**
```
[UserRegistry] Saving conversation for user abc-123, duration: 840s
[UserRegistry] Conversation saved and notified to OpenClaw: def-456-uuid
```

### Error Indicators (Non-Critical)

**OpenClaw Conversational Unavailable (Fallback Mode):**
```
[UserRegistry] Conversational processing failed, falling back to raw data
[UserRegistry] Known user recognized (fallback): abc-123-uuid
```
👉 This is OK! VisionClaw will use raw User Registry data until OpenClaw implements the conversational endpoints.

**User Registry Unavailable:**
```
[UserRegistry] Direct lookup failed, skipping
```
👉 Check that User Registry Docker container is running on port 3100.

---

## 🧪 Testing Without OpenClaw Conversational API

The OpenClaw conversational endpoints (port 3114) **are not implemented yet**. The VisionClaw code is ready and will:

1. ✅ Call User Registry directly (port 3100) - **Works now**
2. ⏳ Try to call OpenClaw conversational (port 3114) - **Not implemented, will fail gracefully**
3. ✅ Fall back to processing raw User Registry data - **Works now**

**Current Behavior:**
- Face detection works
- User registration works
- Conversation saving works
- Context injection works (but uses raw data, not conversational text)

**Once OpenClaw Implements Endpoints:**
- Context injection will use conversational text (e.g., "Hey! I recognize Sarah Chen...")
- UserRegistry.md will be automatically updated

---

## 🚨 Troubleshooting

### Build Fails

```bash
# Clean build
rm -rf ~/Library/Developer/Xcode/DerivedData/CameraAccess-*
xcodebuild clean
xcodebuild build
```

### "Invalid URL for lookup_face"

Check `Secrets.swift`:
- `openClawConversationalHost` must start with `http://`
- Example: `"http://192.168.1.173"` (not `"192.168.1.173"`)

### "Direct lookup failed"

Check User Registry:
```bash
# Is it running?
docker ps | grep user-registry

# Can you reach it?
curl http://MacBook-Pro.local:3100/health

# Start it:
cd /Users/naveenkumarvk/Projects/USER-REGISTRY
docker-compose up
```

### "Conversational processing failed"

This is **expected** until OpenClaw implements the conversational endpoints. VisionClaw will fall back to raw data processing.

---

## 📋 Checklist Before PR

- [ ] Updated `Secrets.swift` with OpenClaw Mac IP
- [ ] User Registry running and reachable (`curl http://MacBook-Pro.local:3100/health`)
- [ ] Build succeeds (`xcodebuild build`)
- [ ] Tested face detection on physical iPhone
- [ ] Logs show dual-API calls (port 3100 + fallback for port 3114)
- [ ] Verified graceful degradation when OpenClaw unreachable

---

## 📞 Questions?

See full implementation details in: `DUAL_API_IMPLEMENTATION.md`

**Key Files Changed:**
- `Secrets.swift` - Added conversational host/port
- `GeminiConfig.swift` - Exposed config values
- `UserRegistryCoordinator.swift` - Rewritten detection flow
- `StreamSessionViewModel.swift` - Updated wiring

**New Files:**
- `OpenClaw/ConversationalModels.swift` - Request/response models
- `OpenClaw/OpenClawConversationalBridge.swift` - HTTP client

---

**Status**: Ready for testing (with fallback mode until OpenClaw implements conversational endpoints)
