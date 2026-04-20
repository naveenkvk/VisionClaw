# VisionClaw User Registry - Deployment Checklist

**Quick Status**: ✅ Code Complete | 🔲 Xcode Setup | 🔲 Backend Setup | 🔲 Testing

---

## Phase 1: Code Implementation ✅ COMPLETE

- [x] Created `FaceDetection/FaceDetectionResult.swift`
- [x] Created `FaceDetection/FaceDetectionManager.swift`
- [x] Created `UserRegistry/UserRegistryModels.swift`
- [x] Created `UserRegistry/UserRegistryBridge.swift`
- [x] Created `UserRegistry/UserRegistryCoordinator.swift`
- [x] Modified `Secrets.swift` (added registry config)
- [x] Modified `Secrets.swift.example` (added registry config)
- [x] Modified `GeminiSessionViewModel.swift` (context injection)
- [x] Modified `IPhoneCameraManager.swift` (detector wiring)
- [x] Modified `StreamSessionViewModel.swift` (component initialization)
- [x] Created `~/.openclaw/skills/user-registry/SKILL.md`

**Lines Added**: ~820 lines across 11 files

---

## Phase 2: Xcode Project Setup 🔲 TODO (5 minutes)

### 2.1: Add Files to Project
- [ ] Open `CameraAccess.xcodeproj` in Xcode
- [ ] Add `FaceDetection/` folder to project (drag & drop)
- [ ] Add `UserRegistry/` folder to project (drag & drop)
- [ ] Verify target membership: CameraAccess
- [ ] Verify "Copy items if needed" was checked

### 2.2: Build Verification
- [ ] Clean Build Folder (Cmd+Shift+K)
- [ ] Build Project (Cmd+B)
- [ ] ✅ Build succeeds with no errors

**See**: `XCODE_SETUP_GUIDE.md` for detailed instructions

---

## Phase 3: Backend Services 🔲 TODO (10 minutes)

### 3.1: PostgreSQL + User Registry
```bash
# Navigate to user registry repo
cd /path/to/user-registry-service

# Start services
docker-compose up -d

# Verify PostgreSQL
docker ps | grep postgres

# Verify User Registry
curl http://localhost:3100/health
# Expected: {"status":"ok"}

# Check database
docker exec -it user-registry_postgres_1 psql -U postgres -d user_registry
\dt  # Should show: users, face_embeddings, conversations
\dx  # Should show: vector extension
\q
```

- [ ] PostgreSQL running on port 5432
- [ ] User Registry running on port 3100
- [ ] Health check returns OK
- [ ] Database tables exist
- [ ] pgvector extension enabled

### 3.2: OpenClaw Gateway
```bash
# Check if running
curl http://localhost:18789/v1/chat/completions
# Expected: 400 or 401 (means gateway is up)

# Verify skill loaded
grep -r "user-registry" ~/.openclaw/skills/
# Expected: Shows SKILL.md

# Check config
cat ~/.openclaw/openclaw.json | grep -A 5 "env"
# Expected: Shows USER_REGISTRY_HOST and USER_REGISTRY_TOKEN

# Restart gateway to load skill
openclaw gateway restart

# Test skill detection
openclaw chat "what skills are loaded?"
# Expected: Should mention "user-registry"
```

- [ ] Gateway running on port 18789
- [ ] Skill directory configured in openclaw.json
- [ ] Environment variables set (USER_REGISTRY_HOST, USER_REGISTRY_TOKEN)
- [ ] Gateway restarted after skill added
- [ ] Skill appears in loaded skills list

### 3.3: VisionClaw Configuration
Edit `/Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess/CameraAccess/Secrets.swift`:

```swift
// Update this line with your Mac's IP or hostname
static let userRegistryHost = "http://192.168.1.XXX"  // or "http://Your-Mac.local"
```

- [ ] Updated `userRegistryHost` with Mac's IP address
- [ ] Verified Mac's Bonjour hostname: `scutil --get LocalHostName`
- [ ] iPhone can reach Mac: `ping Your-Mac.local` from iPhone terminal app

---

## Phase 4: End-to-End Testing 🔲 TODO (30 minutes)

### 4.1: Face Detection Pipeline Test
**Purpose**: Verify detection fires and logs work

1. [ ] Build and run app on **physical iPhone** (not simulator)
2. [ ] Tap "Start on iPhone" button
3. [ ] Point camera at face (yours or someone else's)
4. [ ] Check Xcode console logs:
   ```
   [FaceDetection] Face detected (placeholder), confidence: 0.XX
   [UserRegistry] Face detected, confidence: 0.XX
   ```
5. [ ] Wait 3 seconds, should see another detection
6. [ ] Verify debouncing: max 1 detection per 3 seconds

**Success**: Detection logs appear every 3 seconds when face in frame

### 4.2: OpenClaw Integration Test
**Purpose**: Verify lookup request reaches OpenClaw

1. [ ] Monitor OpenClaw logs:
   ```bash
   tail -f ~/.openclaw/logs/gateway.log
   ```
2. [ ] Point camera at face in VisionClaw
3. [ ] Check logs for:
   ```
   [OpenClaw] Sending 1 messages in conversation
   [OpenClaw] Agent result: ...
   ```
4. [ ] Verify skill handles `lookup_face` intent

**Success**: OpenClaw receives and processes face lookup request

### 4.3: User Registry Integration Test
**Purpose**: Verify database operations work

**First Encounter (New User)**:
1. [ ] Point camera at face
2. [ ] Check User Registry logs:
   ```bash
   docker logs user-registry-app-1 -f --tail 50
   ```
3. [ ] Should see: `POST /faces/search` → `matched: false`
4. [ ] Should see: `POST /faces/register` → new user created
5. [ ] Verify database:
   ```bash
   psql -U postgres -d user_registry -c "SELECT id, name, last_seen_at FROM users;"
   ```
6. [ ] Should see 1 new user with NULL name

**Second Encounter (Known User)**:
1. [ ] Wait 5+ minutes (or change threshold in code)
2. [ ] Restart VisionClaw app
3. [ ] Point camera at same face
4. [ ] Should see: `POST /faces/search` → `matched: true`
5. [ ] Check Xcode logs:
   ```
   [UserRegistry] Injecting context: Speaking with a known person...
   [Gemini] Injecting system context: Speaking with...
   ```

**Success**: User recognized on second encounter, context injected

### 4.4: Gemini Context Injection Test
**Purpose**: Verify AI receives context

1. [ ] Start Gemini session (tap microphone button)
2. [ ] Point camera at face
3. [ ] Wait for context injection logs
4. [ ] Say "Hi" to Gemini
5. [ ] **Expected**: Gemini's greeting should acknowledge meeting before (if second encounter)
6. [ ] Say "Who am I talking to?"
7. [ ] **Expected**: Gemini mentions "a known person" or specific context

**Success**: Gemini's responses reflect injected context

### 4.5: Conversation Save Test
**Purpose**: Verify transcript saved with topics

1. [ ] Have a conversation with Gemini (talk about specific topics)
   - Example: "I'm planning a trip to Japan next month"
   - Example: "Remind me to buy camera gear"
2. [ ] End Gemini session (hang up)
3. [ ] Check logs:
   ```
   [UserRegistry] Saving conversation for user <uuid>, duration: XXs
   [OpenClaw] Sending 1 messages...
   [UserRegistry] Conversation saved successfully
   ```
4. [ ] Verify database:
   ```bash
   psql -U postgres -d user_registry -c "SELECT user_id, topics, action_items, occurred_at FROM conversations ORDER BY occurred_at DESC LIMIT 1;"
   ```
5. [ ] Should see topics extracted (e.g., ["Japan trip", "camera gear"])
6. [ ] Should see action items (e.g., ["Buy camera gear"])

**Success**: Conversation saved with extracted topics and action items

---

## Phase 5: Edge Cases & Error Handling 🔲 TODO (15 minutes)

### 5.1: Backend Down Test (Graceful Degradation)
1. [ ] Stop User Registry: `docker stop user-registry-app-1`
2. [ ] Start VisionClaw session
3. [ ] Point camera at face
4. [ ] **Expected**: Logs show error but Gemini session continues
5. [ ] Verify no crashes, no modal dialogs
6. [ ] Restart backend: `docker start user-registry-app-1`

### 5.2: No Face in Frame Test
1. [ ] Point camera at wall (no faces)
2. [ ] Wait 10 seconds
3. [ ] **Expected**: No detection logs (or "No face detected")
4. [ ] Verify no errors or crashes

### 5.3: Face Loss Detection Test
1. [ ] Point camera at face → detection fires
2. [ ] Point camera away for 5+ seconds
3. [ ] Check logs:
   ```
   [UserRegistry] Face lost
   ```

### 5.4: Multiple Faces Test
1. [ ] Point camera at multiple faces
2. [ ] **Expected**: Only first face triggers lookup
3. [ ] Subsequent faces ignored (single user per session)

---

## Phase 6: Optional Enhancements 🔲 FUTURE

### 6.1: Real Embeddings (MediaPipe)
- [ ] Add MediaPipe SPM dependency
- [ ] Bundle `face_detection_short_range.tflite` model
- [ ] Uncomment MediaPipe code in FaceDetectionManager
- [ ] Test real face matching (same person → same embedding)

### 6.2: Glasses Camera Mode
- [ ] Wire face detector in glasses video frame handler
- [ ] Test with Ray-Ban Meta streaming
- [ ] Verify debouncing works at 24fps input

### 6.3: User Naming Flow
- [ ] Say "This is Naveen" during session
- [ ] Verify `PATCH /users/:id` called
- [ ] Next encounter: Gemini says "Hi Naveen"

---

## Troubleshooting Guide

### "Build failed: Cannot find type 'FaceDetectionManager'"
- **Cause**: Files not added to Xcode project
- **Fix**: Drag FaceDetection/ and UserRegistry/ folders into Xcode

### "Build failed: Unresolved identifier 'Secrets.userRegistryHost'"
- **Cause**: Secrets.swift not updated or not rebuilt
- **Fix**: Clean Build Folder (Cmd+Shift+K), rebuild

### "[UserRegistry] ERROR: Gemini view model not available"
- **Cause**: Coordinator not wired in StreamSessionViewModel
- **Fix**: Verify `startIPhoneSession()` creates and wires coordinator

### "[OpenClaw] Gateway unreachable"
- **Cause**: OpenClaw not running or wrong host/port
- **Fix**: `curl http://localhost:18789/v1/chat/completions` to test

### "[UserRegistry] HTTP 500"
- **Cause**: User Registry crashed or database down
- **Fix**: `docker logs user-registry-app-1` to see error

### "No detection logs at all"
- **Cause**: Camera permissions denied or face detector not wired
- **Fix**: Check Settings → CameraAccess → Camera permission

---

## Success Criteria

### Minimum Viable (Placeholder Mode)
- [x] All files created and modified
- [ ] Xcode project builds
- [ ] Detection logs appear when pointing at face
- [ ] OpenClaw receives lookup requests
- [ ] Graceful degradation when backend down

### Full Integration
- [ ] User Registry backend running
- [ ] First encounter creates new user in database
- [ ] Second encounter matches user and injects context
- [ ] Gemini acknowledges context in responses
- [ ] Conversation saved with topics and action items

### Production Ready
- [ ] Real embeddings implemented (MediaPipe or FaceNet)
- [ ] Glasses camera mode supported
- [ ] User naming flow works
- [ ] Tested with 5+ different people

---

## Quick Commands Reference

```bash
# Backend
docker-compose up -d
docker logs user-registry-app-1 -f
psql -U postgres -d user_registry -c "SELECT * FROM users;"

# OpenClaw
openclaw gateway restart
tail -f ~/.openclaw/logs/gateway.log

# VisionClaw
# (Run in Xcode, monitor console)

# Database queries
psql -U postgres -d user_registry -c "SELECT COUNT(*) FROM face_embeddings;"
psql -U postgres -d user_registry -c "SELECT COUNT(*) FROM conversations;"
```

---

**Current Status**: Phase 1 ✅ Complete | Phase 2-5 🔲 Ready to Test

**Next Action**: Open Xcode and add new files to project (5 minutes)

**Documentation**:
- Detailed implementation: `IMPLEMENTATION_SUMMARY.md`
- Xcode setup: `XCODE_SETUP_GUIDE.md`
- This checklist: `DEPLOYMENT_CHECKLIST.md`
