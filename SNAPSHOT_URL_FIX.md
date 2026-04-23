# Snapshot URL Database Column Size Fix

## Problem

**HTTP 500 Error during face registration:**
```
[UserRegistry] HTTP 500: {"statusCode":500,"message":"Internal server error"}
```

**Root Cause (from Docker logs):**
```
PostgreSQL Error 22001: string data right truncation
File: varchar.c, line: 638
```

The `snapshotUrl` field with base64-encoded JPEG was exceeding the `VARCHAR(500)` database column limit.

## Details

### Base64 Image Size
A typical face snapshot:
- JPEG quality: 50%
- Bounding box crop: ~200x200 pixels
- Base64 encoded: **~20,000+ characters**
- Database column: `VARCHAR(500)` (only 500 chars!)

### Database Schema (from CLAUDE.md)
```sql
CREATE TABLE face_embeddings (
  ...
  snapshot_url VARCHAR(500),  -- ❌ Too small for base64 images
  ...
);
```

## Temporary Fix ✅

**Disabled snapshot upload in `UserRegistryBridge.swift`:**
```swift
// TODO: Snapshot disabled - base64 encoding exceeds VARCHAR(500) limit
// if let snapshot = snapshotJPEG {
//     body["snapshotUrl"] = "data:image/jpeg;base64," + snapshot.base64EncodedString()
// }
```

**Impact:**
- ✅ Face registration works
- ✅ Embedding stored correctly
- ❌ No visual snapshot saved (acceptable for MVP)

## Permanent Solutions

### Option 1: Increase Database Column Size (Quick Fix)
```sql
ALTER TABLE face_embeddings
ALTER COLUMN snapshot_url TYPE TEXT;
```

**Pros:**
- Simple, one-line change
- Supports base64 data URIs

**Cons:**
- Storing large binary data in database is inefficient
- Increases database size significantly
- Slower queries/backups

### Option 2: Store in Blob Storage (Recommended)
Use S3, MinIO, or local filesystem:

```swift
// 1. Save snapshot to storage
let filename = "\(UUID().uuidString).jpg"
let url = await storageService.upload(snapshotJPEG, filename: filename)

// 2. Send URL (not base64)
body["snapshotUrl"] = url  // e.g., "file:///snapshots/abc-123.jpg"
```

**Pros:**
- Efficient database usage
- Fast queries
- Easy to serve images to web UI
- Can add CDN later

**Cons:**
- Requires storage service setup
- More moving parts

### Option 3: Remove Snapshots Entirely (Simplest)
```sql
ALTER TABLE face_embeddings
DROP COLUMN snapshot_url;
```

Update NestJS DTO to make field optional.

**Pros:**
- Simplest solution
- Snapshots not critical for face recognition

**Cons:**
- Lose visual confirmation of registrations
- Harder to debug false matches

## Recommendation

For MVP: **Option 3** (Remove snapshots)
- Snapshots are not required for face recognition
- Embeddings contain all necessary information
- Can add back later with Option 2 if needed

For Production: **Option 2** (Blob storage)
- Proper separation of concerns
- Scalable architecture
- Better performance

## Migration Steps (Option 2)

### 1. Add Local Storage Service

**NestJS Backend:**
```typescript
// src/storage/storage.service.ts
@Injectable()
export class StorageService {
  private readonly uploadDir = './uploads/snapshots';

  async save(base64Data: string, filename: string): Promise<string> {
    const buffer = Buffer.from(base64Data.replace(/^data:image\/\w+;base64,/, ''), 'base64');
    const path = `${this.uploadDir}/${filename}`;
    await fs.promises.writeFile(path, buffer);
    return `file://${path}`;
  }
}
```

### 2. Update Database Schema
```sql
ALTER TABLE face_embeddings
ALTER COLUMN snapshot_url TYPE VARCHAR(1000);  -- Longer for file paths or URLs
```

### 3. Update NestJS Controller
```typescript
// src/face-embeddings/face-embeddings.service.ts
async register(dto: RegisterFaceDto) {
  let snapshotUrl = null;

  if (dto.snapshotUrl && dto.snapshotUrl.startsWith('data:image')) {
    const filename = `${uuidv4()}.jpg`;
    snapshotUrl = await this.storageService.save(dto.snapshotUrl, filename);
  }

  // Save to database with file:// URL
  await this.faceEmbeddingsRepo.create({ ...dto, snapshotUrl });
}
```

### 4. Re-enable in Swift
```swift
if let snapshot = snapshotJPEG {
    body["snapshotUrl"] = "data:image/jpeg;base64," + snapshot.base64EncodedString()
}
```

## Testing

### Verify Fix Works
```bash
# Test registration without snapshot
curl -X POST http://MacBook-Pro.local:3100/faces/register \
  -H "Content-Type: application/json" \
  -d '{"embedding":[0.1, ...128 values], "confidenceScore":0.71, "source":"mediapipe"}'

# Expected: HTTP 200 with userId
```

### Run VisionClaw
```
[UserRegistry] Face detected, confidence: 0.71
[UserRegistry] Processing face detection (dual-API flow)...
[UserRegistry] Registered new user: abc-123-uuid
```

✅ Should now succeed without HTTP 500 error

## Files Changed

1. **UserRegistryBridge.swift** - Commented out snapshot upload
2. **SNAPSHOT_URL_FIX.md** (this file) - Documentation

## Next Steps

1. ✅ Test face registration (should work now)
2. ⏳ Decide on permanent solution (recommend Option 3 for MVP)
3. ⏳ Update User Registry database schema if keeping snapshots
4. ⏳ Implement storage service if using Option 2

---

**Status**: ✅ Temporary fix applied (snapshots disabled)
**Impact**: Face registration now works, no visual snapshots stored
**Build**: ✅ Success
