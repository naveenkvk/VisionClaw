# Xcode Setup Guide - VisionClaw User Registry

**Time Required**: 5-10 minutes

## Quick Start

All code has been written. You just need to add the new files to your Xcode project.

## Step-by-Step Instructions

### 1. Open Xcode Project
```bash
cd /Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Add New Files to Project

#### Option A: Drag and Drop (Easiest)
1. In Finder, navigate to:
   - `CameraAccess/CameraAccess/FaceDetection/`
   - `CameraAccess/CameraAccess/UserRegistry/`
2. Drag both folders into Xcode's Project Navigator
3. In the dialog:
   - ✅ Check "Copy items if needed"
   - ✅ Check "Create groups"
   - ✅ Ensure "CameraAccess" target is selected
4. Click "Finish"

#### Option B: File Menu
1. Right-click `CameraAccess` group in Project Navigator
2. Select "Add Files to CameraAccess..."
3. Navigate to and select:
   - `FaceDetection/FaceDetectionResult.swift`
   - `FaceDetection/FaceDetectionManager.swift`
   - `UserRegistry/UserRegistryModels.swift`
   - `UserRegistry/UserRegistryBridge.swift`
   - `UserRegistry/UserRegistryCoordinator.swift`
4. Options:
   - ✅ "Copy items if needed"
   - ✅ "CameraAccess" target
5. Click "Add"

### 3. Verify Files Added
In Project Navigator, you should see:
```
CameraAccess/
├── FaceDetection/
│   ├── FaceDetectionResult.swift
│   └── FaceDetectionManager.swift
└── UserRegistry/
    ├── UserRegistryModels.swift
    ├── UserRegistryBridge.swift
    └── UserRegistryCoordinator.swift
```

### 4. Build Project
```
Press Cmd+B or Product → Build
```

**Expected**: Build succeeds with no errors

**If you see errors**:
- "Cannot find type X": File not added to target
  - Select file → File Inspector → Target Membership → Check "CameraAccess"

### 5. Update Configuration (Already Done)
The following files have already been updated:
- ✅ `Secrets.swift` - User Registry config added
- ✅ `GeminiSessionViewModel.swift` - Context injection added
- ✅ `IPhoneCameraManager.swift` - Face detector wired
- ✅ `StreamSessionViewModel.swift` - Components initialized

## Optional: Add MediaPipe (Real Face Detection)

Skip this if you want to test with placeholder embeddings first.

### A. Add Swift Package
1. File → Add Package Dependencies
2. Enter: `https://github.com/google/mediapipe`
3. Click "Add Package"
4. Select `MediaPipeTasksVision`
5. Click "Add Package"

### B. Bundle Model File
1. Download `face_detection_short_range.tflite` from:
   https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite
2. Rename to `face_detection_short_range.tflite`
3. Drag into Xcode project root
4. Check:
   - ✅ "Copy items if needed"
   - ✅ "CameraAccess" target
5. Verify in Build Phases → Copy Bundle Resources

### C. Enable MediaPipe Code
Open `FaceDetection/FaceDetectionManager.swift`:
1. Uncomment the `import MediaPipeTasksVision` at top
2. Uncomment the extension at bottom (marked with `/* ... */`)
3. Replace `setupDetector()` call with `setupDetectorWithMediaPipe()`

## Testing

### Without Backend (Placeholder Mode)
```bash
# 1. Build and run on iPhone
# 2. Tap "Start on iPhone"
# 3. Start Gemini session
# 4. Point at face
# 5. Check Xcode console logs:
[FaceDetection] Face detected (placeholder), confidence: 0.XX
```

### With Backend
See `IMPLEMENTATION_SUMMARY.md` Phase 3 & 4 for full setup.

## Troubleshooting

### Build Fails: "No such module"
- Clean Build Folder (Cmd+Shift+K)
- Close Xcode
- Delete `~/Library/Developer/Xcode/DerivedData/CameraAccess-*`
- Reopen and build

### Files Appear Gray in Xcode
- File not added to target
- Select file → Inspector → Target Membership → Check "CameraAccess"

### Runtime: "Model file not found"
- Model not in Copy Bundle Resources
- Verify: Build Phases → Copy Bundle Resources → See `face_detection_short_range.tflite`

### No Detection Logs
1. Check camera permissions granted
2. Verify `startIPhoneSession()` wires detector
3. Add breakpoint in `FaceDetectionManager.detect()`

## Quick Verification

Run this in Xcode console after app launches:
```swift
// Should see the new classes
(lldb) expr FaceDetectionManager()
(lldb) expr UserRegistryCoordinator(gemini: geminiViewModel)
```

## Next Steps

After successful build:
1. ✅ Xcode setup complete
2. → Test face detection pipeline (see IMPLEMENTATION_SUMMARY.md)
3. → Set up backend services
4. → Test end-to-end flow

---

**Need Help?** Check console logs for `[FaceDetection]` and `[UserRegistry]` tags.
