# User Registry Integration Fixes

## Issues Identified and Fixed

### 1. VisionClaw iOS App Issues

#### 1.1 Typo in UserRegistryBridge.swift
**Location**: `UserRegistryBridge.swift:36`
**Issue**: `pclientath` instead of `path`
**Fix**: Changed to correct parameter name `path`

#### 1.2 JSON Field Naming Mismatch
**Location**: `UserRegistryModels.swift`
**Issue**: Swift models used snake_case (e.g., `recent_conversations`) but backend returns camelCase (e.g., `recentConversations`)
**Fix**: Updated all model properties to use camelCase to match backend:
- `recent_conversations` → `recentConversations`
- `action_items` → `actionItems`
- `occurred_at` → `occurredAt`
- `last_seen_at` → `lastSeenAt`
- `user_id` → `userId`
- `face_embedding_id` → `faceEmbeddingId`
- `is_new_user` → `isNewUser`
- `conversation_id` → `conversationId`

#### 1.3 User Registry Host Configuration
**Location**: `Secrets.swift:22`
**Issue**: Using placeholder hostname `"http://Your-Mac.local"` instead of actual IP
**Fix**: Changed to `"http://192.168.1.173"` to match OpenClaw host

#### 1.4 WebSocket Client ID Issue
**Location**: `OpenClawEventClient.swift:14`
**Issue**: Using random UUID for client ID, but OpenClaw gateway expects a constant value
**Fix**: Changed from `UUID().uuidString` to constant `"visionclaw-glass"`

### 2. User Registry Backend Issues

#### 2.1 Missing pgvector Extension
**Issue**: Database didn't have the pgvector extension enabled, causing "type 'vector' does not exist" errors
**Fix**: Enabled the extension:
```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

#### 2.2 Incorrect Column Type for Embeddings
**Issue**: `face_embeddings.embedding` column was `varchar(5000)` instead of `vector(128)`
**Fix**: Altered the column type:
```sql
ALTER TABLE face_embeddings
ALTER COLUMN embedding TYPE vector(128)
USING embedding::vector(128);
```

#### 2.3 Missing Vector Index
**Issue**: No ivfflat index for optimized vector similarity searches
**Fix**: Created the index:
```sql
CREATE INDEX face_embeddings_embedding_idx
ON face_embeddings
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
```

### 3. Integration Setup

#### 3.1 Database Initialization Script
**Created**: `scripts/init-db.sh`
**Purpose**: Automates database setup with proper pgvector configuration
**Usage**: Run after `docker-compose up`
```bash
cd /Users/naveenkumarvk/Projects/USER-REGISTRY
./scripts/init-db.sh
```

#### 3.2 Migration Documentation
**Created**: `src/database/migrations/001_initial_schema.sql`
**Purpose**: Documents the required database schema changes for future deployments

## Verification Steps

### Test User Registry Backend
```bash
# Health check
curl http://localhost:3100/health

# Test face search (should return matched: false if no faces registered)
curl -X POST http://localhost:3100/faces/search \
  -H "Content-Type: application/json" \
  -d '{"embedding":[0.1,0.1,0.1,...128 values...],"threshold":0.4}'

# Test face registration
curl -X POST http://localhost:3100/faces/register \
  -H "Content-Type: application/json" \
  -d '{"embedding":[...],"confidenceScore":0.92,"source":"mediapipe"}'
```

### Test from VisionClaw iOS App
1. Build and run the app in Xcode
2. Point camera at a face
3. Check logs for face detection and registry lookup
4. Verify context injection into Gemini session

## Current Status

✅ User Registry backend running and healthy on port 3100
✅ PostgreSQL with pgvector extension enabled
✅ Database schema corrected (embedding column is vector(128))
✅ Vector index created for similarity search
✅ API endpoints tested and working:
  - POST /faces/search
  - POST /faces/register
  - POST /conversations (not tested, should work)
  - PATCH /users/:id (not tested, should work)
  - GET /users/:id/summary (not tested, should work)

⚠️ OpenClaw gateway connection: WebSocket connection issue partially fixed
  - Changed client ID to constant value
  - Gateway might not be running or might have additional validation requirements

## Next Steps

1. **Start OpenClaw Gateway** (if not running):
   - Verify it's accessible at `http://192.168.1.173:18789`
   - Ensure the gateway token matches: `21c9e6fa03ca7784e68a2e096253c7490dd192467fbce904`

2. **Test End-to-End Flow**:
   - VisionClaw detects face → calls OpenClaw
   - OpenClaw skill calls User Registry
   - Context injected into Gemini session

3. **Environment Variables for OpenClaw**:
   Create `~/.openclaw/openclaw.json` with:
   ```json
   {
     "skills": {
       "dirs": ["~/.openclaw/skills"]
     },
     "env": {
       "USER_REGISTRY_HOST": "http://localhost",
       "USER_REGISTRY_TOKEN": ""
     }
   }
   ```

## Files Modified

### VisionClaw Project
- `samples/CameraAccess/CameraAccess/UserRegistry/UserRegistryBridge.swift`
- `samples/CameraAccess/CameraAccess/UserRegistry/UserRegistryModels.swift`
- `samples/CameraAccess/CameraAccess/Secrets.swift`
- `samples/CameraAccess/CameraAccess/OpenClaw/OpenClawEventClient.swift`

### User Registry Project
- Database schema (manual ALTER commands)
- `scripts/init-db.sh` (new file)
- `src/database/migrations/001_initial_schema.sql` (new file)

### OpenClaw Skill
- No changes needed (skill already correctly defined)

## Known Issues

1. OpenClaw gateway connection still needs verification
2. Full end-to-end test pending OpenClaw gateway availability
3. Need to verify environment variables in OpenClaw configuration

## Testing Checklist

- [x] User Registry health endpoint responds
- [x] Face search endpoint works (returns matched: false for unknown faces)
- [x] Face registration endpoint works (creates new user + embedding)
- [x] Face search finds registered faces (returns matched: true with confidence)
- [x] Database has pgvector extension enabled
- [x] Embedding column is vector(128) type
- [x] Vector similarity search index created
- [ ] OpenClaw gateway reachable
- [ ] VisionClaw → OpenClaw → User Registry integration works
- [ ] Context injection into Gemini session works
- [ ] Conversation saving works
- [ ] Full end-to-end flow with actual face detection

---

# Intent-Based API Integration Update (2026-04-20)

## Overview

Updated VisionClaw's User Registry integration to use OpenClaw Gateway's new `/api/v1/message` endpoint with intent-based syntax for structured communication. This replaces the previous natural language approach while preserving the existing chat completions format for all other features.

## Changes Made

### 1. OpenClawBridge.swift - New Intent Methods

**Added three new methods** (after line 239):

#### `callUserRegistryLookup(embedding:threshold:)`
- **Endpoint**: `POST /api/v1/message`
- **Format**: `[INTENT:lookup_face] {"embedding":[...], "threshold":0.4}`
- **Returns**: Structured JSON with match status, user info, and recent conversations

#### `callUserRegistryRegister(embedding:confidence:snapshotJPEG:locationHint:)`
- **Endpoint**: `POST /api/v1/message`
- **Format**: `[INTENT:register_face] {"embedding":[...], "confidence_score":0.92, ...}`
- **Returns**: User ID and face embedding ID

#### `callUserRegistrySaveConversation(userId:transcript:durationSeconds:locationHint:)`
- **Endpoint**: `POST /api/v1/message`
- **Format**: `[INTENT:save_conversation] {"user_id":"...", "transcript":"...", ...}`
- **Returns**: Conversation ID

**Existing `delegateTask()` method**: Unchanged - LinkedIn finder and location tracking continue using `/v1/chat/completions`

### 2. UserRegistryCoordinator.swift - Updated Flow

#### `handleFaceDetection()` - Line 43
- **Before**: Built natural language task string, called `delegateTask()`
- **After**: Directly calls `callUserRegistryLookup()` with structured parameters
- **Benefit**: No more fragile string formatting or JSON embedding in text

#### `processLookupResponse()` - Line 64
- **Updated**: Added explicit `registerNewFace()` call when `matched: false`
- **Before**: Relied on skill to auto-register (unreliable)
- **After**: Explicit registration flow with proper error handling

#### `registerNewFace()` - New Method
- **Purpose**: Handle new face registration via `callUserRegistryRegister()`
- **Flow**: Parse response → extract user_id → set session state
- **Location**: After `processLookupResponse()`

#### `endSession()` - Line 140
- **Before**: Built natural language task with embedded transcript, called `delegateTask()`
- **After**: Calls `callUserRegistrySaveConversation()` with structured parameters
- **Benefit**: Clean separation of data from instructions

### 3. UserRegistryModels.swift - Added CodingKeys

Added snake_case to camelCase mappings for all models:

#### `FaceLookupData.User`
```swift
enum CodingKeys: String, CodingKey {
    case id, name, notes
    case lastSeenAt = "last_seen_at"
}
```

#### `FaceLookupData.Conversation`
```swift
enum CodingKeys: String, CodingKey {
    case topics
    case actionItems = "action_items"
    case occurredAt = "occurred_at"
}
```

#### `FaceRegistrationData`
```swift
enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case faceEmbeddingId = "face_embedding_id"
    case isNewUser = "is_new_user"
}
```

#### `ConversationData`
```swift
enum CodingKeys: String, CodingKey {
    case conversationId = "conversation_id"
}
```

## Build Status

✅ **BUILD SUCCEEDED**

```bash
cd samples/CameraAccess
xcodebuild -scheme CameraAccess -sdk iphoneos -configuration Debug clean build
```

No compilation errors. Only 2 pre-existing duplicate file warnings (unrelated to this change).

## Success Criteria

### Compile-Time ✅
- ✅ Build succeeds with no compilation errors
- ✅ Face lookup uses `/api/v1/message` with `[INTENT:lookup_face]`
- ✅ Face registration uses `/api/v1/message` with `[INTENT:register_face]`
- ✅ Conversation save uses `/api/v1/message` with `[INTENT:save_conversation]`
- ✅ LinkedIn finder code unchanged (still uses old endpoint)
- ✅ Location tracking code unchanged (still uses old endpoint)
- ✅ Gemini conversation code unchanged

### Runtime ⏳ (Pending Testing)
- ⏳ Logs show structured intent payloads being sent
- ⏳ Responses are parsed correctly
- ⏳ Context is injected into Gemini
- ⏳ LinkedIn finder still works
- ⏳ Location tracking still works
- ⏳ No regression in Gemini conversation

## Testing Plan

### Test 1: Face Lookup Flow
1. Start app, pair Ray-Ban Meta glasses
2. Enable face detection
3. Point camera at known face
4. **Expected Logs**:
   ```
   [UserRegistry] Calling lookup_face intent with 128-dim embedding
   [OpenClaw] lookup_face result: {"matched":true,"user_id":"..."}
   [UserRegistry] Known user recognized: <uuid>
   ```

### Test 2: New Face Registration
1. Point camera at new person
2. **Expected Logs**:
   ```
   [UserRegistry] No match found, registering new face
   [OpenClaw] register_face result: {"user_id":"...","is_new_user":true}
   [UserRegistry] New user registered: <uuid>
   ```

### Test 3: Conversation Save
1. Have conversation while face detected
2. End session (stop streaming)
3. **Expected Logs**:
   ```
   [UserRegistry] Saving conversation for user <uuid>, duration: Xs
   [OpenClaw] save_conversation result: {"conversation_id":"..."}
   [UserRegistry] Conversation saved: ...
   ```

### Test 4: LinkedIn Finder (Old Endpoint - No Change)
1. Say: "Find LinkedIn for John Smith"
2. **Expected**: Uses `delegateTask()` → `/skill/linkedin-finder`
3. Should work exactly as before

### Test 5: Location Updates (Old Endpoint - No Change)
1. Trigger location update
2. **Expected**: Uses `delegateTask()` → `/v1/chat/completions`
3. Should work exactly as before

## Key Benefits

1. **Type Safety**: Structured data instead of string interpolation
2. **Reliability**: No dependency on agent's natural language understanding
3. **Debuggability**: Clear intent markers in logs
4. **Maintainability**: Explicit methods vs. generic task delegation
5. **Backward Compatibility**: Existing features unchanged

## Intent Payload Examples

### lookup_face
```json
{
  "channel": "webchat",
  "message": "[INTENT:lookup_face] {\"embedding\":[0.123,-0.456,...128 floats],\"threshold\":0.4}"
}
```

### register_face
```json
{
  "channel": "webchat",
  "message": "[INTENT:register_face] {\"embedding\":[...],\"confidence_score\":0.92,\"source\":\"mediapipe\",\"snapshot_url\":\"data:image/jpeg;base64,...\"}"
}
```

### save_conversation
```json
{
  "channel": "webchat",
  "message": "[INTENT:save_conversation] {\"user_id\":\"abc123\",\"transcript\":\"Full conversation text...\",\"duration_seconds\":840,\"occurred_at\":\"2026-04-20T22:30:00Z\"}"
}
```

## Architecture

```
VisionClaw (iPhone)
    │
    ├─→ User Registry Features
    │   └─→ callUserRegistryLookup/Register/SaveConversation()
    │       └─→ POST /api/v1/message [INTENT:...] {json}
    │
    └─→ Other Features (LinkedIn, Location, Chat)
        └─→ delegateTask()
            └─→ POST /v1/chat/completions (OpenAI format)

OpenClaw Gateway
    │
    ├─→ /api/v1/message (intent-based)
    │   └─→ Parse [INTENT:...] → Route to skill
    │
    └─→ /v1/chat/completions (chat format)
        └─→ Agent processes conversationally
```

## Rollback Plan

If issues arise:
1. `git stash` or commit current changes
2. Revert to commit `ad5a01a` (before intent-based changes)
3. Natural language format will continue working

## Next Steps

1. Deploy to iPhone device
2. Run Tests 1-5 above
3. Verify OpenClaw Gateway skill processes intents
4. Verify NestJS service receives correct payloads
5. Monitor logs during real face detection sessions
6. Update this document with runtime test results

## Notes

- All changes are iOS client-side only
- No OpenClaw Gateway changes required (endpoint already exists)
- No NestJS service changes required (expects same JSON format)
- User Registry skill SKILL.md already documents intent format
- Failures log errors but don't crash session (graceful degradation)
