# Wake Word Activation Implementation

## Status: Implementation Complete (Manual Step Required)

The wake word activation system has been fully implemented with the following components:

## ✅ Implemented Components

### 1. Wake Word Detector (`WakeWordDetector.swift`)
- **Location**: `samples/CameraAccess/CameraAccess/WakeWord/WakeWordDetector.swift`
- **Features**:
  - Uses Apple Speech Recognition framework
  - Detects "hey openclaw", "hey open claw", or "openclaw"
  - 5-second debounce to prevent multiple triggers
  - Continuous listening with auto-restart
  - Authorization request handling
  - Real-time audio buffer processing

### 2. Session Mode Management (`GeminiSessionViewModel.swift`)
- **Added**:
  - `SessionMode` enum: `.passive` and `.active`
  - `startPassiveMode()` - starts wake word listening only
  - `activateGeminiSession()` - connects to Gemini after wake word
  - `deactivateGeminiSession()` - returns to passive mode
  - Auto-sleep after 30 seconds of silence
  - Context buffering for passive mode
  - `WakeWordDelegate` conformance

### 3. Audio Manager Updates (`AudioManager.swift`)
- **Added**:
  - Wake word detector integration
  - Dual audio tap routing (passive vs active mode)
  - `startWakeWordListening()` - lightweight tap for wake word only
  - `transitionToActiveMode()` - switch to full Gemini streaming
  - `transitionToPassiveMode()` - switch back to wake word
  - Mode-aware audio buffer routing

### 4. UI Updates (`StreamView.swift`)
- **Added**:
  - `SessionModeIndicator` - shows "LISTENING" (gray) or "ACTIVE" (green)
  - Manual activation button (appears in passive mode)
  - Updated AI button to start in passive mode
  - Visual feedback for session state

### 5. Info.plist Update
- **Added**: `NSSpeechRecognitionUsageDescription` permission description

### 6. Wake Word Wiring (`StreamSessionViewModel.swift`)
- **Added**:
  - Wake word detector initialization in `startIPhoneSession()`
  - Authorization request on app launch
  - Detector wired to Gemini session as delegate

## ⚠️ Manual Step Required

### Add WakeWordDetector.swift to Xcode Project

The file `WakeWordDetector.swift` has been created but needs to be manually added to the Xcode project:

**Steps**:
1. Open `CameraAccess.xcodeproj` in Xcode
2. Right-click the `CameraAccess` group in the file navigator
3. Select "Add Files to CameraAccess..."
4. Navigate to `samples/CameraAccess/CameraAccess/WakeWord/`
5. Select `WakeWordDetector.swift`
6. ✅ Ensure "Copy items if needed" is **unchecked** (file is already in the right location)
7. ✅ Ensure "Add to targets: CameraAccess" is **checked**
8. Click "Add"

**Alternative** (if the WakeWord folder doesn't exist in Xcode):
1. Right-click `CameraAccess` group → "New Group" → name it "WakeWord"
2. Right-click the new "WakeWord" group → "Add Files..."
3. Select `WakeWordDetector.swift` from the file system

After adding the file, run:
```bash
cd samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build
```

## 🔄 How It Works

### Passive Mode (Default)
```
User taps "AI" button
  ↓
startPassiveMode()
  ↓
Audio engine starts with lightweight tap
  ↓
WakeWordDetector processes audio buffers
  ↓
Speech recognition listens for "hey openclaw"
  ↓
Face detection runs continuously in background
  ↓
Context is buffered (not sent to Gemini yet)
```

### Activation Flow
```
User says "Hey Openclaw"
  ↓
WakeWordDetector.checkForWakeWord() matches phrase
  ↓
Delegate calls wakeWordDetected()
  ↓
activateGeminiSession()
  ↓
Audio transitions to full streaming mode
  ↓
Gemini WebSocket connects (~2-3s)
  ↓
Buffered context flushed to Gemini
  ↓
Silence monitoring starts (30s timeout)
  ↓
User has conversation with Gemini
```

### Auto-Sleep
```
30 seconds of silence detected
  ↓
deactivateGeminiSession()
  ↓
Gemini disconnects
  ↓
Conversation saved to User Registry
  ↓
Audio transitions back to wake word mode
  ↓
Returns to PASSIVE mode
```

## 🎯 Expected Behavior

### In PASSIVE Mode:
- ✅ Microphone listens ONLY for wake word (on-device)
- ✅ Face detection continues working
- ✅ User registry lookups happen in background
- ✅ Context from face detection is buffered
- ✅ NO audio sent to Gemini
- ✅ NO Gemini responses
- ✅ Gray "LISTENING" indicator visible
- ✅ Manual "Activate" button available

### In ACTIVE Mode:
- ✅ Full audio streaming to Gemini
- ✅ Gemini responds with speech
- ✅ Tool calling enabled
- ✅ Face detection still running
- ✅ Buffered context applied
- ✅ Green "ACTIVE" indicator visible
- ✅ Auto-sleep after 30s silence

## 🧪 Testing Checklist

### Test 1: Basic Wake Word Flow
- [ ] Start app in passive mode
- [ ] Point camera at a face → verify face detection logs
- [ ] Say "Hey Openclaw" → verify:
  - [ ] Mode indicator changes to "ACTIVE" (green)
  - [ ] Gemini WebSocket connects within 3s
  - [ ] Buffered face context is injected
- [ ] Ask Gemini a question → verify audio response
- [ ] Wait 30 seconds of silence → verify auto-sleep to PASSIVE

### Test 2: Face Detection Without Activation
- [ ] Start in PASSIVE mode
- [ ] Point camera at known person → verify:
  - [ ] Face lookup happens (check logs)
  - [ ] Context is buffered (check logs: "Context buffered")
  - [ ] Gemini does NOT respond or interrupt
- [ ] Say wake word → verify buffered context sent to Gemini

### Test 3: Manual Activation
- [ ] Start in PASSIVE mode
- [ ] Tap "Activate" button → verify Gemini activates
- [ ] Manual activation works same as wake word

### Test 4: Authorization Handling
- [ ] First run: verify speech recognition permission prompt
- [ ] Grant permission → verify wake word works
- [ ] Deny permission → verify manual activation button still works

### Test 5: Mode Transitions
- [ ] PASSIVE → ACTIVE → PASSIVE cycle works smoothly
- [ ] No audio glitches during transitions
- [ ] Face detection unaffected by mode changes

## 📊 Log Markers

### Success Logs (Expected):
```
[WakeWord] Started listening for wake word
[WakeWord] Wake word detected: hey openclaw
[Gemini] Activating Gemini session...
[Audio] Transitioning to ACTIVE mode
[Gemini] Session ACTIVE - Gemini connected and responding
[Gemini] Flushed N buffered context messages
[Gemini] Auto-sleep triggered after 30s of silence
[Audio] Transitioning to PASSIVE mode
[Gemini] Returned to PASSIVE mode - listening for wake word
```

### Failure Logs (Troubleshoot):
```
[WakeWord] Cannot start - speech recognition not authorized
[WakeWord] Speech recognizer not available
[WakeWord] Recognition error: ...
[Gemini] Activation failed: ...
```

## 🔧 Known Issues

### Speech Recognition Availability
- iOS may throttle speech recognition in background
- Wake word detection only works when app is in foreground
- **Workaround**: Use manual activation button if authorization denied

### Audio Mode Conflicts
- WebRTC and Gemini cannot run simultaneously (audio conflicts)
- **Solution**: UI disables conflicting buttons

### Model Download
- First time using Speech Recognition, iOS downloads language model
- May take 10-20 seconds on first launch
- **Solution**: Show user a loading state if needed

## 🚀 Future Enhancements (Out of Scope)

1. **Custom Wake Words**: Let users configure their own phrase
2. **Background Wake Word**: Use background audio mode (complex permissions)
3. **Multiple Wake Words**: "Sleep Openclaw" to deactivate
4. **Adaptive Timeout**: Adjust 30s silence based on context
5. **Visual Wake Word**: Hand wave gesture to activate
6. **Porcupine SDK Migration**: If battery life becomes an issue

## 📝 Rollback Plan

If wake word causes issues, disable by:

1. Comment out wake word setup in `StreamSessionViewModel.startIPhoneSession()`
2. Change `startPassiveMode()` back to `startSession()` in AI button
3. Remove manual "Activate" button from UI
4. All existing functionality (always-on Gemini) is preserved

## ✅ Verification

After adding the file to Xcode, build should succeed:

```bash
cd samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build
```

Expected output:
```
** BUILD SUCCEEDED **
```

## 🎉 Success Criteria

- ✅ Face detection works continuously in both modes
- ✅ Gemini only connects after wake word detected
- ✅ Audio NOT streamed to Gemini in PASSIVE mode
- ✅ Context from face detection buffered and applied correctly
- ✅ Auto-sleep after 30s silence works reliably
- ✅ No crashes or memory leaks during mode transitions
- ✅ Wake word detection accuracy > 90% in quiet environments
