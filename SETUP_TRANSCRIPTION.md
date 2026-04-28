# Setup Instructions: Passive Mode Transcription

## Files Created/Modified

### ✅ Created Files
- **`CameraAccess/Gemini/LocalTranscriptionManager.swift`** - New independent speech recognition manager

### ✅ Modified Files
- **`CameraAccess/Gemini/AudioManager.swift`** - Added local transcription integration
- **`CameraAccess/Gemini/GeminiSessionViewModel.swift`** - Wired up passive mode transcript capture

## Required Setup Steps

### Step 1: Add LocalTranscriptionManager.swift to Xcode Project

The new file needs to be added to your Xcode project:

1. Open `CameraAccess.xcodeproj` in Xcode
2. In the Project Navigator (left sidebar), locate the **Gemini** folder
3. Right-click the **Gemini** folder → **Add Files to "CameraAccess"...**
4. Navigate to: `samples/CameraAccess/CameraAccess/Gemini/`
5. Select `LocalTranscriptionManager.swift`
6. Ensure these options are checked:
   - ☑ **Copy items if needed** (should be unchecked - file is already there)
   - ☑ **Create groups** (not folder references)
   - ☑ **Add to targets: CameraAccess**
7. Click **Add**

**Alternative (Drag & Drop)**:
- Drag `LocalTranscriptionManager.swift` from Finder into the Gemini folder in Xcode
- Ensure it's added to the CameraAccess target when prompted

### Step 2: Update Info.plist Permissions

Add speech recognition permission description:

1. Open `Info.plist` in Xcode
2. Add a new row (click the + button):
   - **Key**: `NSSpeechRecognitionUsageDescription`
   - **Type**: String
   - **Value**: `VisionClaw uses speech recognition to capture conversation transcripts for your personal memory system.`

This permission should already exist, but verify it's present:
   - **Key**: `NSMicrophoneUsageDescription`
   - **Value**: `VisionClaw needs microphone access to listen for voice commands and capture conversations.`

### Step 3: Build and Test

```bash
cd /Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build
```

**Expected output**:
```
** BUILD SUCCEEDED **
```

## Testing the Implementation

### Test 1: Passive Mode Transcription

1. **Launch app** on iPhone simulator or physical device
2. **Tap "Start Streaming"** (passive mode starts automatically)
3. **Speak without saying wake word**: "This is a test of passive transcription"
4. **Wait 5 seconds**, then check logs

**Expected logs**:
```
[LocalTranscription] Speech recognition authorized
[Audio] Started local transcription in passive mode
[LocalTranscript] Captured: This is a test of passive transcription
```

### Test 2: Wake Word Activation with Transcript Carryover

1. **Start in passive mode**, speak: "Hello there"
2. **Say wake word**: "Hey Claude"
3. **Continue speaking**: "How are you?"
4. **End session** (wait for auto-sleep or tap stop)

**Expected logs**:
```
[LocalTranscript] Captured: Hello there
[Gemini] Captured passive transcript before activation: 11 chars
[Gemini] Session ACTIVE - Gemini connected
[Gemini] You: How are you?
[UserRegistry] Ending session for user <uuid>
```

**Expected transcript sent to OpenClaw**:
```
User (passive): Hello there
User: How are you?
AI: I'm doing well, thank you!
```

### Test 3: Passive Mode Session End

1. **Start passive mode**
2. **Speak for 30 seconds** without wake word
3. **Tap "Stop Streaming"**

**Expected logs**:
```
[Gemini] Saved passive transcript on session stop: 142 chars
[UserRegistry] Ending session for user <uuid>
```

## Troubleshooting

### Issue: Build fails with "cannot find type 'LocalTranscriptionManager' in scope"

**Solution**: File not added to Xcode project - follow Step 1 above

### Issue: "Speech recognition not authorized"

**Solution**:
1. iOS Simulator: Go to Settings → Privacy & Security → Speech Recognition → Enable for CameraAccess
2. Physical device: Same path on device settings

### Issue: No transcription appearing in logs

**Possible causes**:
1. Microphone permission denied
2. Speech recognition authorization denied
3. Audio session setup failed

**Debug steps**:
```swift
// Check authorization status
print(SFSpeechRecognizer.authorizationStatus())
// Should print: authorized

// Check if recognizer is available
print(SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable ?? false)
// Should print: true
```

### Issue: Transcripts saved but empty

**Possible cause**: Face detection didn't trigger (no active user)

**Solution**: Ensure face is visible to camera before speaking

## Verification Checklist

Before committing, verify:

- [ ] `LocalTranscriptionManager.swift` appears in Xcode Project Navigator under Gemini folder
- [ ] File has checkmark next to "CameraAccess" target
- [ ] Build succeeds without errors
- [ ] `NSSpeechRecognitionUsageDescription` in Info.plist
- [ ] Test passive mode transcription (logs show captured text)
- [ ] Test wake word transition (passive transcript carries over)
- [ ] Test session end in passive mode (transcript saved)

## Next Steps

Once testing is complete:

1. **Update MEMORY.md**: Document passive transcription architecture
2. **Integration testing**: Test with face detection + user registry
3. **Performance monitoring**: Check CPU/memory usage during long transcription sessions
4. **Privacy review**: Verify transcripts only saved when user registry active

## Reference Documentation

- Implementation details: `/PASSIVE_MODE_TRANSCRIPTION.md`
- User registry spec: `/CLAUDE.md`
- Architecture notes: `/MEMORY.md`
- iOS Speech Framework: https://developer.apple.com/documentation/speech

## Quick Commands

```bash
# Build
cd /Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build

# Clean build
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator clean build

# View logs (when running on device/simulator)
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.visionclaw"' --level debug
```

---

**Status**: ⏳ Pending manual Xcode file addition
**Next action**: Add `LocalTranscriptionManager.swift` to Xcode project (Step 1 above)
