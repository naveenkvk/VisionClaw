# User Registry System — Master Implementation Guide

**Project**: Ray-Ban Meta Glasses → Face Recognition → Persistent Memory
**Components**: VisionClaw iOS App + OpenClaw Skill + NestJS Microservice
**Status**: Implementation-ready specification
**Version**: 1.0

This document is the single source of truth for the entire User Registry system. It is intended to be placed at the root of all three project repositories (the VisionClaw iOS app, the OpenClaw skill folder, and the NestJS backend service) so Claude Code has complete cross-component context when working on any single piece.

When working on a specific component, focus on the section relevant to that component, but always read Sections 1 through 4 first to understand the system as a whole. Every component must implement its contracts exactly as specified so the pieces integrate without surprises.

---

## Table of Contents

1. System overview
2. End-to-end data flow
3. Component responsibilities
4. Wire contracts (the API surface)
5. iOS app (VisionClaw) specification
6. OpenClaw skill specification
7. NestJS microservice specification
8. Threading and concurrency rules
9. Error handling strategy
10. Deployment checklist
11. Future-proofing notes
12. Glossary

---

## 1. System Overview

The User Registry system gives Ray-Ban Meta glasses persistent memory of people. When you meet someone:

- A face embedding is extracted on the iPhone from the glasses video stream
- The embedding is sent to a backing service which looks up whether this person has been seen before
- If known, their name, past topics, and open action items are injected into the live Gemini conversation so the AI can greet them contextually
- If unknown, a new entry is created silently so that on the next encounter they are recognized
- When the conversation ends, the transcript is summarized into topics and action items and saved against that person

The system is strictly local-first. All components run on the user's own Mac at home over the local WiFi network. No data leaves the house unless the user explicitly wires in an external sync.

### 1.1 Hardware and hosts

| Component | Host | Port |
|---|---|---|
| Ray-Ban Meta glasses | N/A | N/A |
| VisionClaw app | User's iPhone | N/A |
| OpenClaw Gateway | User's Mac | 18789 |
| NestJS User Registry | User's Mac (Docker) | 3100 |
| PostgreSQL + pgvector | User's Mac (Docker) | 5432 |

The iPhone reaches the Mac over home WiFi using the Mac's Bonjour hostname (for example `Your-Mac.local`).

### 1.2 Non-goals (explicit scope boundaries)

The initial implementation does NOT include any of the following. They may be added later, but implementations MUST NOT pretend they exist:

- Social network (Facebook, Instagram) profile sync
- Cloud deployment, multi-tenancy, or user accounts
- Authentication or rate limiting on the NestJS service (single-user local trust)
- Live streaming of faces (detection is debounced to one pass every 3 seconds)
- On-device face recognition (all matching happens server-side via pgvector)

---

## 2. End-to-End Data Flow

```
┌────────────────────────────────────────────────────────────────┐
│  Ray-Ban Meta glasses                                          │
│  Video stream over Meta DAT SDK (~24 fps)                      │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│  VisionClaw iOS app (iPhone)                                   │
│                                                                │
│  • IPhoneCameraManager / DAT SDK throttles frames to ~1 fps    │
│  • FaceDetectionManager runs MediaPipe on each frame           │
│  • On detection → UserRegistryCoordinator orchestrates lookup  │
│  • Simultaneously → frames still stream to Gemini Live         │
│  • On session end → transcript passed to Coordinator           │
└────────────────────────┬───────────────────────────────────────┘
                         │ HTTPS POST /v1/chat/completions
                         │ (OpenClaw gateway tool call envelope)
                         ▼
┌────────────────────────────────────────────────────────────────┐
│  OpenClaw Gateway (Mac, port 18789)                            │
│                                                                │
│  • Receives "execute" tool call from VisionClaw                │
│  • Agent sees user-registry skill in its system prompt         │
│  • Agent uses web_fetch / exec curl to call NestJS service     │
│  • Returns structured tool response back to VisionClaw         │
└────────────────────────┬───────────────────────────────────────┘
                         │ HTTP POST /faces/search etc.
                         ▼
┌────────────────────────────────────────────────────────────────┐
│  NestJS User Registry microservice (Mac Docker, port 3100)     │
│                                                                │
│  • FaceEmbeddingsService runs pgvector cosine similarity       │
│  • UsersService manages identity                               │
│  • ConversationsService persists history                       │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│  PostgreSQL 16 + pgvector (Mac Docker, port 5432)              │
│                                                                │
│  • users, face_embeddings, conversations, social_profiles      │
│  • ivfflat indexes on embedding columns                        │
└────────────────────────────────────────────────────────────────┘
```

### 2.1 Temporal ordering of a single encounter

| # | Actor | Action |
|---|---|---|
| 1 | Glasses | Stream video to phone |
| 2 | VisionClaw | Throttle to 1 fps, pass each frame to MediaPipe |
| 3 | VisionClaw | MediaPipe emits embedding + confidence + bbox |
| 4 | VisionClaw | Debounce: if last detection was <3s ago, drop |
| 5 | VisionClaw | Coordinator calls OpenClaw with `lookup_face` intent |
| 6 | OpenClaw | Agent reads skill, calls `POST /faces/search` |
| 7 | NestJS | pgvector similarity query against `face_embeddings` |
| 8 | NestJS | Returns matched user + 3 most recent conversations, OR null |
| 9 | OpenClaw | If no match, agent calls `POST /faces/register` to create user |
| 10 | OpenClaw | Returns structured result to VisionClaw as tool response |
| 11 | VisionClaw | Injects context into live Gemini session (system turn) |
| 12 | Gemini | Speaks contextual greeting through glasses |
| 13 | User | Has conversation |
| 14 | VisionClaw | On session end, passes full transcript to Coordinator |
| 15 | Coordinator | Calls OpenClaw with `save_conversation` intent + transcript |
| 16 | OpenClaw | Agent extracts topics + action items using Claude |
| 17 | OpenClaw | Agent calls `POST /conversations` with extracted data |
| 18 | NestJS | Persists conversation linked to user_id |
| 19 | NestJS | Updates `users.last_seen_at` |

---

## 3. Component Responsibilities

Each component owns exactly one job. Do not leak concerns across boundaries.

### 3.1 VisionClaw (iOS)

- Capture video frames
- Run on-device face detection via MediaPipe
- Extract 128-dimensional embedding + confidence + snapshot
- Throttle and debounce detection events
- Call OpenClaw Gateway for lookup/register/save
- Inject returned context into the live Gemini session
- Capture transcripts and pass them on session end
- Never: store embeddings locally, run similarity search, talk to NestJS directly

### 3.2 OpenClaw Skill

- Receive natural-language tool calls from VisionClaw
- Translate them into structured HTTP calls to the NestJS service
- Use Claude (or whatever is the active agent model) to extract topics + action items from transcripts
- Format the NestJS response into a tool response VisionClaw can consume
- Never: persist state, run its own database, bypass the NestJS service

### 3.3 NestJS microservice

- Own the PostgreSQL schema
- Run pgvector similarity searches
- Expose a clean REST API
- Enforce data integrity (unique constraints, FK cascades)
- Never: talk to Gemini, run face detection, make outbound calls to OpenClaw

---

## 4. Wire Contracts

Every cross-component interaction goes through one of these five endpoints on the NestJS service. Treat these as frozen contracts — any change must be coordinated across all three components.

All responses use a consistent envelope:

```json
{ "data": { ... } | null, "error": { "code": "...", "message": "..." } | null }
```

All request and response bodies are JSON. All timestamps are ISO-8601 UTC strings. All IDs are UUID v4.

### 4.1 `POST /faces/search`

Find the closest matching person to a given face embedding.

**Request**:
```json
{
  "embedding": [0.123, -0.456, ...],
  "threshold": 0.4
}
```

- `embedding` — array of exactly 128 float32 values from MediaPipe
- `threshold` — maximum cosine distance to count as a match (default 0.4)

**Response (match found)**:
```json
{
  "data": {
    "matched": true,
    "user": {
      "id": "uuid",
      "name": "Naveen",
      "notes": "Photographer, met at PyCon",
      "last_seen_at": "2026-04-15T18:30:00Z"
    },
    "confidence": 0.87,
    "recent_conversations": [
      {
        "topics": ["photography", "Puerto Rico trip"],
        "action_items": ["Share Lightroom preset"],
        "occurred_at": "2026-03-14T14:12:00Z"
      }
    ]
  },
  "error": null
}
```

**Response (no match)**:
```json
{ "data": { "matched": false, "user": null, "confidence": null, "recent_conversations": [] }, "error": null }
```

### 4.2 `POST /faces/register`

Register a new face, creating a new user unless `existing_user_id` is supplied.

**Request**:
```json
{
  "embedding": [0.123, -0.456, ...],
  "confidence_score": 0.92,
  "source": "mediapipe",
  "snapshot_url": "https://... or null",
  "location_hint": "Home office",
  "existing_user_id": null
}
```

**Response**:
```json
{
  "data": {
    "user_id": "uuid",
    "face_embedding_id": "uuid",
    "is_new_user": true
  },
  "error": null
}
```

### 4.3 `POST /conversations`

Persist a conversation with extracted topics and action items.

**Request**:
```json
{
  "user_id": "uuid",
  "transcript": "full verbatim text ...",
  "topics": ["photography", "Puerto Rico trip"],
  "action_items": ["Share Lightroom preset"],
  "duration_seconds": 840,
  "location_hint": "Coffee shop downtown",
  "occurred_at": "2026-04-18T15:00:00Z"
}
```

**Response**:
```json
{ "data": { "conversation_id": "uuid" }, "error": null }
```

The service must also update `users.last_seen_at = occurred_at` inside the same transaction.

### 4.4 `PATCH /users/:id`

Update a user's name or notes — typically after identification.

**Request**:
```json
{ "name": "Naveen", "notes": "Met through Ray-Ban demo" }
```

**Response**:
```json
{ "data": { "user": { "id": "uuid", "name": "Naveen", ... } }, "error": null }
```

Either field may be omitted; whatever is provided is updated.

### 4.5 `GET /users/:id/summary`

Return the full profile for a user — useful for retrospective queries.

**Response**:
```json
{
  "data": {
    "user": { "id": "uuid", "name": "Naveen", "first_seen_at": "...", "last_seen_at": "..." },
    "conversations": [ { "id": "uuid", "topics": [...], "action_items": [...], "occurred_at": "..." } ],
    "face_count": 3
  },
  "error": null
}
```

### 4.6 Error codes

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `INVALID_EMBEDDING_DIMENSION` | Embedding is not exactly 128 floats |
| 400 | `VALIDATION_FAILED` | Any other DTO validation failure |
| 404 | `USER_NOT_FOUND` | `/users/:id` targets a missing user |
| 409 | `DUPLICATE_FACE` | Attempted to register an embedding that already exists verbatim |
| 500 | `DATABASE_ERROR` | Unhandled SQL error |
| 503 | `SERVICE_UNAVAILABLE` | pgvector not ready or connection pool exhausted |

---

## 5. iOS App Specification (VisionClaw)

The VisionClaw repo already contains the Meta DAT SDK integration, Gemini Live client, and OpenClaw bridge. This section adds face detection and user registry integration as a set of new files, with minimal edits to existing code.

### 5.1 New files

Create the following under `samples/CameraAccess/CameraAccess/`:

```
FaceDetection/
  FaceDetectionManager.swift
  FaceDetectionResult.swift
UserRegistry/
  UserRegistryBridge.swift
  UserRegistryCoordinator.swift
  UserRegistryModels.swift
```

### 5.2 FaceDetectionManager.swift

Wraps MediaPipe Face Detection. Responsibilities:

- Initialize `FaceDetector` from `MediaPipeTasksVision` using the short-range model (`face_detection_short_range.tflite`)
- Accept `CMSampleBuffer` as input on a background dispatch queue
- Extract embedding + confidence + bounding box
- Debounce: only fire `didDetectFace` once per 3 seconds
- Crop bounding box and return a JPEG snapshot (50 percent quality)
- Emit `didLoseFace()` when no face has been detected for 5 seconds
- Return `nil` if confidence is below 0.7
- Expose a `FaceDetectionDelegate` protocol

Key implementation notes:

- Never block the main thread. All work happens on `DispatchQueue.global(qos: .userInitiated)`.
- Gracefully skip frames when the previous detection is still in-flight (drop, do not queue).
- The MediaPipe model file must be bundled as a resource in the Xcode project.

### 5.3 FaceDetectionResult.swift

Plain data struct, no logic:

```swift
struct FaceDetectionResult {
    let embedding: [Float]         // 128 values
    let confidence: Float          // 0.0 to 1.0
    let boundingBox: CGRect        // normalized 0.0 to 1.0
    let capturedAt: Date
    let snapshotJPEG: Data?
}
```

### 5.4 UserRegistryBridge.swift

HTTP client for the NestJS service. Mirrors the style of `OpenClawBridge.swift`:

- Uses `URLSession` with async/await
- Reads host/port/token from `Secrets.swift`
- All methods return optionals and log errors via `os_log` under subsystem `com.visionclaw.registry`
- Never throws to caller — failures return `nil` or `false`

Required methods:

```swift
func searchFace(embedding: [Float], threshold: Float = 0.4) async -> FaceLookupResponse?
func registerFace(embedding: [Float], confidence: Float, snapshotJPEG: Data?, locationHint: String?, existingUserId: String?) async -> FaceRegistrationResponse?
func saveConversation(userId: String, transcript: String, topics: [String], actionItems: [String], durationSeconds: Int, locationHint: String?) async -> Bool
func updateUser(userId: String, name: String?, notes: String?) async -> Bool
func getUserSummary(userId: String) async -> UserSummaryResponse?
```

Note: In the current architecture, VisionClaw routes all calls through OpenClaw — it does not talk to NestJS directly. `UserRegistryBridge` exists as a fallback and testing convenience for direct calls during development. In production flow, `UserRegistryCoordinator` sends tool calls through the existing `OpenClawBridge` and OpenClaw's agent calls NestJS on its behalf. Keep both paths because they are useful at different stages (direct for unit testing, routed for end-to-end).

### 5.5 UserRegistryCoordinator.swift

The main orchestrator. Responsibilities:

1. Conform to `FaceDetectionDelegate`.
2. On `didDetectFace(result:)`:
   - Construct a Gemini tool call payload describing a `lookup_face` intent, passing the embedding
   - Send via `OpenClawBridge`
   - Parse the response to either: set `currentUserId` and inject context, or trigger `register_face` then set `currentUserId`
3. `func injectContextIntoGemini(user:conversations:)`:
   - Build a compact context string (under 500 characters)
   - Example: `"You are speaking with Naveen. Last seen 3 days ago. Recent topics: photography, Puerto Rico. Open items: share Lightroom preset."`
   - Pass to `GeminiSessionViewModel.injectSystemContext(_:)`
4. `func endSession(transcript:)`:
   - If `currentUserId` is set, send a `save_conversation` tool call through OpenClaw with the full transcript
   - OpenClaw's agent is responsible for extracting topics and action items
   - Reset `currentUserId` and `sessionStartTime`

Session duration is tracked from `didDetectFace` (first detection of the session) to `endSession`.

### 5.6 Modifications to existing files

Do not rewrite these files. Append only.

**`GeminiSessionViewModel.swift`**:
- Add `var userRegistryCoordinator: UserRegistryCoordinator?`
- Add `func injectSystemContext(_ text: String)` which appends a system-role turn to the live Gemini session
- In the existing session-end handler, call `userRegistryCoordinator?.endSession(transcript: fullTranscript)`

**`IPhoneCameraManager.swift`**:
- Add `var faceDetectionManager: FaceDetectionManager?`
- In the existing per-frame handler, after handing the JPEG to Gemini, also pass the `CMSampleBuffer` to `faceDetectionManager?.detect(sampleBuffer:)` on a background queue

**`Secrets.swift`**:
- Append:
```swift
static let userRegistryHost = "http://Your-Mac.local"
static let userRegistryPort = 3100
static let userRegistryToken = "" // empty until auth is added
```

### 5.7 Dependencies

Add via Swift Package Manager:

- `MediaPipeTasksVision` from https://github.com/google/mediapipe

Bundle the model file `face_detection_short_range.tflite` as a project resource.

### 5.8 Wiring in the app entry point

In whatever SwiftUI view or `AppDelegate` initializes the Gemini session:

```swift
let detector = FaceDetectionManager()
let bridge = UserRegistryBridge()
let coordinator = UserRegistryCoordinator(bridge: bridge, openClaw: openClawBridge, gemini: geminiViewModel)
detector.delegate = coordinator
iPhoneCameraManager.faceDetectionManager = detector
geminiViewModel.userRegistryCoordinator = coordinator
```

---

## 6. OpenClaw Skill Specification

The OpenClaw side is a pure skill — a `SKILL.md` file that goes in `~/.openclaw/skills/user-registry/`. No code, no TypeScript, no JavaScript. The OpenClaw agent reads the skill and uses its built-in `web_fetch` (or `exec curl`) tool to call the NestJS service.

### 6.1 File layout

```
~/.openclaw/skills/user-registry/
  SKILL.md
```

### 6.2 SKILL.md contents

```markdown
---
name: user-registry
description: >
  Look up, register, and save conversation context for people seen through
  Ray-Ban Meta glasses via VisionClaw. Stores face embeddings and conversation
  history in a local User Registry microservice on port 3100.
metadata:
  openclaw:
    requires:
      env:
        - USER_REGISTRY_HOST
        - USER_REGISTRY_TOKEN
---

# User Registry Skill

You have access to a local User Registry microservice at
`{USER_REGISTRY_HOST}:3100`. Use `web_fetch` (preferred) or `exec curl` to
call it. All calls require the header `Authorization: Bearer {USER_REGISTRY_TOKEN}`
once auth is enabled; for now the token may be empty.

## Face lookup

When VisionClaw sends a `lookup_face` intent with a `face_embedding` argument:

1. POST `{USER_REGISTRY_HOST}:3100/faces/search`
   with body `{ "embedding": [...floats], "threshold": 0.4 }`.
2. If `data.matched` is `true`, return a structured response containing the
   person's name, last seen date, and their three most recent topics +
   action items.
3. If `data.matched` is `false`, do NOT immediately register — return `matched: false`
   and let VisionClaw decide whether to register. VisionClaw will typically
   follow up with a `register_face` intent.

## Face registration

When VisionClaw sends a `register_face` intent:

1. POST `{USER_REGISTRY_HOST}:3100/faces/register` with the embedding,
   confidence, source, snapshot_url, and location_hint.
2. Return the returned `user_id` and `is_new_user` flag.

## Conversation saving

When VisionClaw sends a `save_conversation` intent with `user_id` and `transcript`:

1. Extract topics (max 5, each under 5 words) and action items
   (max 5, each under 10 words) from the transcript. Use this prompt verbatim:

   "Extract from the following conversation transcript:
    - Topics discussed (max 5, each under 5 words)
    - Action items or follow-ups (max 5, each under 10 words)
    Return JSON only, no preamble: { \"topics\": [...], \"action_items\": [...] }"

2. POST `{USER_REGISTRY_HOST}:3100/conversations` with body:
   `{ user_id, transcript, topics, action_items, duration_seconds, location_hint, occurred_at }`
3. Return `conversation_id` on success.

## Identification (naming)

When asked to name a person (e.g. "this is Naveen"):

1. PATCH `{USER_REGISTRY_HOST}:3100/users/{user_id}` with
   `{ "name": "Naveen", "notes": "..." }`.
2. Return the updated user.

## Retrospective queries

When asked "who did I meet last week" or similar:

1. GET `{USER_REGISTRY_HOST}:3100/users/{user_id}/summary`
2. Return the full summary.

## Endpoint reference (frozen contract)

| Method | Path | Purpose |
|---|---|---|
| POST | /faces/search | Find nearest match |
| POST | /faces/register | Register new face |
| POST | /conversations | Save conversation + topics + actions |
| PATCH | /users/{id} | Update name / notes |
| GET | /users/{id}/summary | Full user history |

## Error handling

If the registry is unreachable (timeout, connection refused), return
`{ matched: false, error: "registry_unreachable" }` and let VisionClaw
proceed without context. Never retry more than once per call.
If the response contains `error.code`, surface that code in the tool response
so VisionClaw can log it.
```

### 6.3 openclaw.json snippet

Ensure `skills.dirs` includes `~/.openclaw/skills` and env vars are set:

```json
{
  "skills": { "dirs": ["~/.openclaw/skills"] },
  "env": {
    "USER_REGISTRY_HOST": "http://localhost",
    "USER_REGISTRY_TOKEN": ""
  }
}
```

### 6.4 Why a skill and not custom code

OpenClaw's design philosophy is that skills are textbooks and tools are organs. The agent already has HTTP tools; the skill just teaches it how and when to use them for this domain. Writing a custom OpenClaw tool in TypeScript is only justified if the skill approach proves unreliable in practice. Start with the skill. Escalate to a tool only if the agent makes consistent formatting mistakes.

---

## 7. NestJS Microservice Specification

### 7.1 Project layout

```
user-registry/
├── src/
│   ├── app.module.ts
│   ├── main.ts
│   ├── database/
│   │   └── migrations/001_initial_schema.ts
│   ├── users/
│   │   ├── users.module.ts
│   │   ├── users.controller.ts
│   │   ├── users.service.ts
│   │   └── entities/user.entity.ts
│   ├── face-embeddings/
│   │   ├── face-embeddings.module.ts
│   │   ├── face-embeddings.controller.ts
│   │   ├── face-embeddings.service.ts
│   │   └── entities/face-embedding.entity.ts
│   └── conversations/
│       ├── conversations.module.ts
│       ├── conversations.controller.ts
│       ├── conversations.service.ts
│       └── entities/conversation.entity.ts
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── package.json
└── tsconfig.json
```

### 7.2 Database schema

Enable the pgvector extension in the first migration:

```sql
CREATE EXTENSION IF NOT EXISTS vector;
```

**users**
| Column | Type | Notes |
|---|---|---|
| id | uuid | PK, default gen_random_uuid() |
| name | varchar(200) | nullable |
| notes | text | nullable |
| first_seen_at | timestamptz | not null, default now() |
| last_seen_at | timestamptz | not null, default now() |
| location_hint | varchar(200) | nullable |
| created_at | timestamptz | not null, default now() |

**face_embeddings**
| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK users.id ON DELETE CASCADE |
| embedding | vector(128) | not null |
| confidence_score | real | not null |
| source | varchar(32) | 'mediapipe' \| 'facebook' \| 'instagram' |
| snapshot_url | varchar(500) | nullable |
| captured_at | timestamptz | not null, default now() |

Index: `CREATE INDEX ON face_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);`
Index: `CREATE INDEX ON face_embeddings (user_id);`

**conversations**
| Column | Type | Notes |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK users.id ON DELETE CASCADE |
| transcript | text | not null |
| topics | jsonb | not null, default '[]' |
| action_items | jsonb | not null, default '[]' |
| duration_seconds | int | not null |
| location_hint | varchar(200) | nullable |
| occurred_at | timestamptz | not null |

Index: `CREATE INDEX ON conversations (user_id, occurred_at DESC);`

### 7.3 Similarity search

The hot-path query in `FaceEmbeddingsService.findClosestMatch`:

```sql
SELECT u.id, u.name, u.notes, u.last_seen_at,
       (fe.embedding <=> $1::vector) AS distance
FROM face_embeddings fe
JOIN users u ON u.id = fe.user_id
ORDER BY fe.embedding <=> $1::vector
LIMIT 1;
```

Return null if `distance > threshold`. Otherwise fetch the three most recent conversations for that user in a second query.

Do not use TypeORM's query builder for the vector distance expression — use raw SQL via `this.dataSource.query(...)`. TypeORM does not model the `<=>` operator.

### 7.4 Controllers and services

Every controller method:

- Validates the DTO using `class-validator`
- Returns the `{ data, error }` envelope
- Never throws to the client — uses exception filters to convert to envelope

Every service method:

- Returns domain objects, never HTTP objects
- Uses TypeORM transactions when touching multiple tables (e.g. register creates user + face_embedding atomically)

### 7.5 DTOs

Use `class-validator` decorators. Example for `FaceSearchDto`:

```typescript
export class FaceSearchDto {
  @IsArray()
  @ArrayMinSize(128)
  @ArrayMaxSize(128)
  @IsNumber({}, { each: true })
  embedding: number[];

  @IsNumber()
  @IsOptional()
  @Min(0)
  @Max(1)
  threshold?: number = 0.4;
}
```

### 7.6 Configuration

Environment variables (`.env.example`):

```
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_NAME=user_registry
DATABASE_USER=postgres
DATABASE_PASSWORD=dev_password
PORT=3100
LOG_LEVEL=info
```

### 7.7 Docker Compose

```yaml
version: '3.9'
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: user_registry
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: dev_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s

  app:
    build: .
    env_file: .env
    ports:
      - "3100:3100"
    depends_on:
      postgres:
        condition: service_healthy
    command: npm run start:prod

volumes:
  postgres_data:
```

Use the official `pgvector/pgvector:pg16` image so the extension is preinstalled — do not attempt to install it at runtime.

---

## 8. Threading and Concurrency Rules

### 8.1 iOS

| Work | Queue / actor |
|---|---|
| Video capture callback | `AVCaptureSession` private queue |
| MediaPipe inference | `DispatchQueue.global(qos: .userInitiated)` |
| `UserRegistryBridge` calls | Swift concurrency (`async` funcs), any actor |
| UI updates | `@MainActor` |
| Gemini context injection | `@MainActor` (session is UI-bound) |
| `FaceDetectionDelegate` callbacks | Called on background queue; Coordinator hops to `@MainActor` before touching Gemini |

Rules:
- The main thread is never blocked.
- If a MediaPipe inference is in-flight when a new frame arrives, drop the new frame. Never queue.
- All `URLSession` work is async/await; no callback-based code.

### 8.2 NestJS

- Every request handler is `async`. No blocking code in controllers.
- `TypeOrmModule` manages the connection pool. Do not open manual connections.
- Use `@Transaction()` or `queryRunner.startTransaction()` for multi-table writes.
- The pgvector similarity query is read-only; no transaction needed.

### 8.3 OpenClaw skill

- The OpenClaw agent already serializes tool calls. No concurrency concerns at the skill level.
- If the agent calls multiple endpoints in a single turn (e.g. search → register → save), each call waits for the previous response. Do not ask the skill to parallelize.

---

## 9. Error Handling Strategy

### 9.1 Principle: graceful degradation

A failure in the registry must never break the live Gemini conversation. The user should still be able to talk through their glasses even if Postgres is down. Context injection is best-effort.

### 9.2 iOS

| Failure | Behavior |
|---|---|
| MediaPipe model fails to load | Log, continue without face detection for the session |
| No face in frame | Silent, expected |
| OpenClaw unreachable | Log, skip context injection, do not retry |
| Registry returns 500 | Log `error.code`, skip context injection |
| Transcript save fails | Log, show a non-blocking toast, do not retry automatically |

All errors log to `os_log` under subsystem `com.visionclaw.registry` with category matching the source file. Never show a modal dialog.

### 9.3 OpenClaw skill

If `web_fetch` returns a non-2xx response, the agent should include the status code in its tool response. If the request times out (default 10s), return `{ error: "registry_unreachable" }`.

### 9.4 NestJS

- All controllers are wrapped in a global `HttpExceptionFilter` that converts any thrown exception into the `{ data: null, error: { code, message } }` envelope.
- `class-validator` failures produce `VALIDATION_FAILED`.
- Unknown exceptions log with stack trace and return `DATABASE_ERROR` (or `INTERNAL_ERROR` if not DB-related).
- Never return stack traces or ORM internals to the client.

---

## 10. Deployment Checklist

Run through this list in order when bringing the system up for the first time on a new Mac.

### 10.1 Mac host prep

- [ ] Docker Desktop installed and running
- [ ] Node 20+ installed (for OpenClaw Gateway)
- [ ] OpenClaw Gateway installed and reachable on port 18789
- [ ] Confirm Bonjour hostname at System Settings → General → Sharing (e.g. `Your-Mac.local`)

### 10.2 NestJS microservice

- [ ] Clone the `user-registry` repo
- [ ] Copy `.env.example` to `.env` and set `DATABASE_PASSWORD`
- [ ] `docker-compose up --build`
- [ ] Verify `curl http://localhost:3100/health` returns 200
- [ ] Verify pgvector extension: `docker exec -it user-registry_postgres_1 psql -U postgres -d user_registry -c "\dx"` should list `vector`
- [ ] Run a smoke-test search: `curl -X POST http://localhost:3100/faces/search -H "Content-Type: application/json" -d '{"embedding":[0.1, ... 128 zeros ...], "threshold":0.4}'` returns `matched: false`

### 10.3 OpenClaw skill

- [ ] Create `~/.openclaw/skills/user-registry/` directory
- [ ] Place `SKILL.md` as specified in Section 6.2
- [ ] Add env vars to `~/.openclaw/openclaw.json` (Section 6.3)
- [ ] `openclaw gateway restart`
- [ ] Verify the skill appears in the agent's skills snapshot: ask the OpenClaw chat "what skills are loaded" — `user-registry` should be listed

### 10.4 VisionClaw iOS app

- [ ] Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode 15+
- [ ] Add MediaPipe SPM dependency
- [ ] Drop `face_detection_short_range.tflite` into the project as a resource
- [ ] Add the six new files (Section 5.1)
- [ ] Append the three new values to `Secrets.swift`
- [ ] Apply the three append-only edits to existing files (Section 5.6)
- [ ] Build and run on a physical iPhone
- [ ] In "Start on iPhone" mode, point the camera at a face and verify logs show detection
- [ ] Pair the Ray-Ban Meta glasses via the Meta AI app with Developer Mode enabled
- [ ] Tap "Start Streaming" then the AI button and verify end-to-end

### 10.5 End-to-end verification

- [ ] Meet a new person (or yourself in a mirror): verify a new `users` row is created
- [ ] Meet the same person again after 5+ minutes: verify `matched: true` and context injected
- [ ] End the session: verify a `conversations` row is created with topics and action items
- [ ] Name the person via voice: "Claude, this is Naveen" → verify `users.name` updated
- [ ] Re-encounter: verify the name is spoken in the greeting

---

## 11. Future-Proofing Notes

Things the current system deliberately defers. When you get to them, the contracts in Section 4 should be stable enough that extensions are purely additive.

### 11.1 Social network sync

Add a `social_profiles` table and a `POST /social-profiles/sync` endpoint. The `face_embeddings` table's `source` column is already typed for `'facebook'` and `'instagram'`, so embeddings from synced profile photos can live alongside organic ones. The similarity search is unchanged — it runs across all sources.

### 11.2 Authentication

The NestJS service currently trusts any caller on localhost. To add auth:

- Introduce a `USER_REGISTRY_TOKEN` env var
- Add a `AuthGuard` that checks `Authorization: Bearer` matches the token
- Wire the same token into OpenClaw's `env` and VisionClaw's `Secrets.swift`

No schema changes needed.

### 11.3 Multi-model agent routing

OpenClaw already supports multiple agents. If the user wants topic extraction to use a cheaper model than the conversational one, configure a separate agent with Haiku and route `save_conversation` intents there via `agents.routing` in `openclaw.json`. The skill does not change.

### 11.4 Scaling beyond local

If the registry ever needs to run outside the home network:

- The `pgvector/pgvector:pg16` image deploys unchanged to any Docker host
- The NestJS service is stateless; scale horizontally behind a load balancer
- The only sticky state is the Postgres volume
- Replace the Bonjour hostname in `Secrets.swift` with the remote host's DNS name
- Add TLS termination in front of the NestJS service

### 11.5 Batch conversation backfill

To import historical conversations, write a one-off script that POSTs to `/conversations` with synthetic `occurred_at` timestamps. The schema makes no assumption that conversations arrive in real time.

### 11.6 Privacy and deletion

`ON DELETE CASCADE` on `face_embeddings.user_id` and `conversations.user_id` means deleting a `users` row removes all trace of that person. Surface this as a `DELETE /users/:id` endpoint when privacy controls are needed.

### 11.7 Multiple embeddings per person

The schema already supports this: one `users` row can have many `face_embeddings` rows. When the same person is recognized under different lighting, angles, or through Facebook sync, stacking embeddings improves match accuracy over time. The `register_face` endpoint should accept an `existing_user_id` to append a new embedding to an existing person rather than creating a duplicate.

---

## 12. Glossary

| Term | Definition |
|---|---|
| Embedding | 128-dim float vector produced by MediaPipe; represents a face |
| Cosine distance | Similarity metric used by pgvector; 0 = identical, 2 = opposite |
| Threshold | Max cosine distance to count as a match (default 0.4) |
| DAT SDK | Meta Wearables Device Access Toolkit; the glasses-to-phone protocol |
| Skill | A markdown file that teaches OpenClaw how to perform a task |
| Tool | A built-in OpenClaw capability (web_fetch, exec, read, write, etc.) |
| Gateway | The OpenClaw daemon on port 18789; the brain of the system |
| Intent | A named operation VisionClaw asks OpenClaw to perform |
| Context injection | Feeding prior-knowledge text into a live Gemini Live session |
| Debounce | Suppressing repeat events within a time window |

---

**End of document.** When in doubt, the wire contracts in Section 4 win. All three components must honor them exactly.
