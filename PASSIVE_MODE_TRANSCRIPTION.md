# Passive Mode Transcription Implementation

## Overview

The VisionClaw app now supports **independent transcript capture** in passive mode, enabling conversation history to be saved even when Gemini is not actively connected. This allows for:

1. **Continuous conversation logging** - User speech is transcribed using iOS Speech framework in passive mode
2. **Seamless transition** - Passive transcripts are preserved when transitioning to active mode
3. **OpenClaw integration** - All transcripts (passive or active) are sent to OpenClaw for user registry storage

## Architecture

### Transcription Sources

| Mode | Transcription Source | Technology |
|------|---------------------|------------|
| **Passive** | iOS Speech Framework | Local (on-device or cloud-based) |
| **Active** | Gemini Live API | Cloud (WebSocket stream) |

### Component Responsibilities

#### 1. LocalTranscriptionManager.swift (New)
- **Location**: `samples/CameraAccess/CameraAccess/Audio/LocalTranscriptionManager.swift`
- **Purpose**: Independent speech recognition using iOS Speech framework
- **Features**:
  - Runs locally using `SFSpeechRecognizer`
  - Accumulates transcript continuously
  - Supports partial and final results
  - Authorization handling for speech recognition

#### 2. AudioManager.swift (Enhanced)
- **Location**: `samples/CameraAccess/CameraAccess/Gemini/AudioManager.swift`
- **Changes**:
  - Added `localTranscription` property
  - Added `isTranscribingLocally` flag
  - Enhanced audio routing to feed buffers to local transcription in passive mode
  - New methods: `startLocalTranscription()`, `stopLocalTranscription()`, `getLocalTranscript()`

#### 3. GeminiSessionViewModel.swift (Enhanced)
- **Location**: `samples/CameraAccess/CameraAccess/Gemini/GeminiSessionViewModel.swift`
- **Changes**:
  - Added `localTranscription` manager
  - Wires local transcription to audio manager in `startPassiveMode()`
  - Captures passive transcript before transitioning to active mode
  - Saves passive transcript when session stops in passive mode
  - Restarts local transcription when deactivating back to passive mode

## Data Flow

### Passive Mode Flow

```
┌─────────────────────────────────────────────────────────────┐
│  User speaks (in passive mode)                              │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  AudioManager captures audio buffers                        │
│  - Feeds to WakeWordDetector (wake word detection)          │
│  - Feeds to LocalTranscriptionManager (transcription)       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  LocalTranscriptionManager (iOS Speech)                     │
│  - Transcribes audio → text                                 │
│  - Accumulates in fullTranscript                            │
│  - Callback updates GeminiSessionViewModel.fullTranscript   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Wake word detected OR session manually stopped             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Transcript saved via UserRegistryCoordinator.endSession()  │
│  → OpenClawBridge → OpenClaw Gateway → NestJS backend       │
└─────────────────────────────────────────────────────────────┘
```

### Active Mode Flow (Unchanged)

```
User speaks → Gemini Live API → onInputTranscription callback
           → accumulates in fullTranscript
           → saved via UserRegistryCoordinator.endSession() on deactivation
```

### Transition Flow (Passive → Active)

```
1. User in PASSIVE mode, speaking
   → LocalTranscriptionManager accumulates: "User (passive): Hello..."

2. Wake word detected
   → stopLocalTranscription() captures final transcript
   → fullTranscript = "User (passive): Hello, Claude..."

3. Gemini activates (ACTIVE mode)
   → User continues speaking
   → Gemini transcription appends: "User: How are you?"
   → fullTranscript now: "User (passive): Hello, Claude...\nUser: How are you?\n"

4. Session ends (auto-sleep or manual)
   → Full transcript (passive + active) sent to OpenClaw
```

## Implementation Details

### LocalTranscriptionManager API

```swift
// Start transcribing
func startTranscribing() throws

// Stop and return final transcript
func stopTranscribing() -> String

// Feed audio buffer (called from AudioManager tap)
func processAudioBuffer(_ buffer: AVAudioPCMBuffer)

// Get current accumulated transcript
func getCurrentTranscript() -> String

// Reset without stopping
func resetTranscript()

// Callbacks
var onTranscriptionUpdate: ((String) -> Void)?
var onPartialResult: ((String) -> Void)?
```

### AudioManager Enhancements

```swift
// Properties
var localTranscription: LocalTranscriptionManager?
private var isTranscribingLocally = false

// Methods
func startLocalTranscription()
func stopLocalTranscription() -> String
func getLocalTranscript() -> String
```

### GeminiSessionViewModel Changes

```swift
// Initialization
private let localTranscription = LocalTranscriptionManager()

// In startPassiveMode():
audioManager.localTranscription = localTranscription
localTranscription.onTranscriptionUpdate = { [weak self] transcript in
  self?.fullTranscript = "User (passive): " + transcript
}
audioManager.startLocalTranscription()

// In activateGeminiSession():
let passiveTranscript = audioManager.stopLocalTranscription()
if !passiveTranscript.isEmpty {
  fullTranscript = "User (passive): " + passiveTranscript + "\n"
}

// In deactivateGeminiSession():
if !fullTranscript.isEmpty {
  userRegistryCoordinator?.endSession(transcript: fullTranscript)
}
audioManager.transitionToPassiveMode()  // Restarts local transcription

// In stopSession():
if sessionMode == .passive {
  let passiveTranscript = audioManager.stopLocalTranscription()
  if !passiveTranscript.isEmpty {
    userRegistryCoordinator?.endSession(transcript: passiveTranscript)
  }
}
```

## Privacy & Permissions

### Required Info.plist Entries

Ensure these are present in `Info.plist`:

```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>VisionClaw uses speech recognition to capture conversation transcripts for your personal memory system.</string>

<key>NSMicrophoneUsageDescription</key>
<string>VisionClaw needs microphone access to listen for voice commands and capture conversations.</string>
```

### Authorization Flow

1. **First launch**: `LocalTranscriptionManager` requests speech recognition authorization
2. **User grants**: Speech recognition enabled for all future sessions
3. **User denies**: Passive mode transcription disabled, app logs warning

### Data Privacy

- **Local-first**: All transcription happens on-device or via Apple's cloud (user's choice via `requiresOnDeviceRecognition` flag)
- **No external services**: Transcripts only sent to user's own OpenClaw Gateway (localhost or home network)
- **User control**: Transcripts only saved if user has face detected (user registry session active)

## Debugging

### Key Log Markers

**Passive Mode Transcription**:
```
[LocalTranscription] Speech recognition authorized
[Audio] Started local transcription in passive mode
[LocalTranscript] Captured: Hello, how are you doing today?
```

**Transition to Active**:
```
[Gemini] Captured passive transcript before activation: 87 chars
[Audio] Stopped local transcription (captured 87 chars)
[Gemini] Session ACTIVE - Gemini connected and responding
```

**Saving Transcripts**:
```
[Gemini] Deactivating Gemini session - returning to PASSIVE mode
[UserRegistry] Ending session for user <uuid> (duration: 180s)
[OpenClaw] save_conversation result: {"conversation_id":"..."}
```

**Session Stop in Passive Mode**:
```
[Gemini] Saved passive transcript on session stop: 142 chars
[UserRegistry] Ending session for user <uuid> (duration: 45s)
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No passive transcription | Speech recognition not authorized | Check Settings → Privacy → Speech Recognition |
| "Speech recognizer not available" | Network issue (cloud-based mode) | Enable on-device recognition or check network |
| Transcript not saved | No face detected (no active user) | Ensure face detection triggered before speaking |
| Duplicate text in transcript | Transition logic error | Check logs for multiple `stopLocalTranscription()` calls |

## Testing Checklist

### Manual Testing Steps

1. **Passive Mode Only**:
   - [ ] Start app in passive mode
   - [ ] Speak for 30 seconds (no wake word)
   - [ ] Stop session manually
   - [ ] Verify transcript saved to OpenClaw (check logs)

2. **Passive → Active Transition**:
   - [ ] Start in passive mode, speak "Hello"
   - [ ] Say wake word to activate Gemini
   - [ ] Speak "How are you?"
   - [ ] End session (auto-sleep or manual)
   - [ ] Verify combined transcript includes both parts

3. **Active → Passive → Active**:
   - [ ] Activate Gemini, speak "Test one"
   - [ ] Wait for auto-sleep (30s silence)
   - [ ] Speak "Test two" in passive mode
   - [ ] Activate again, speak "Test three"
   - [ ] Verify all three segments captured

4. **Face Detection Integration**:
   - [ ] Start passive mode with no face visible
   - [ ] Speak (no transcript should save)
   - [ ] Show face to camera
   - [ ] Speak again
   - [ ] Stop session
   - [ ] Verify only second speech saved (after face detection)

### Expected Transcript Format

**Passive only**:
```
User (passive): Hello, I'm testing the passive mode transcription feature.
```

**Passive → Active**:
```
User (passive): Hello, Claude.
User: How are you today?
AI: I'm doing well, thank you for asking!
```

## Performance Considerations

### Memory
- Transcript accumulation is unbounded - very long sessions may consume significant memory
- Consider adding max transcript length limit (e.g., 50,000 chars)

### CPU
- iOS Speech framework uses moderate CPU in cloud mode, minimal in on-device mode
- Audio routing adds negligible overhead (same buffer fed to two destinations)

### Network (Cloud Mode)
- Cloud-based speech recognition sends audio to Apple servers
- On-device mode recommended for privacy and offline use
- Toggle via `requiresOnDeviceRecognition` flag in `LocalTranscriptionManager.swift`

## Future Enhancements

### Potential Improvements

1. **Speaker diarization**: Tag who is speaking (user vs. others) in passive mode
2. **Keyword spotting**: Highlight important terms in passive transcripts
3. **Transcript summarization**: Auto-generate summaries of long passive sessions
4. **Offline mode**: Force on-device recognition for complete privacy
5. **Transcript export**: Allow users to export raw transcripts as text/JSON

### Integration Opportunities

1. **Face detection correlation**: Tag transcript segments with detected faces
2. **Context injection**: Use passive transcript to prime Gemini when activating
3. **Multi-language**: Support multiple languages via `SFSpeechRecognizer(locale:)`
4. **Real-time display**: Show live transcription UI in passive mode

## Files Changed

| File | Type | Lines Changed |
|------|------|---------------|
| `Audio/LocalTranscriptionManager.swift` | New | +195 |
| `Gemini/AudioManager.swift` | Modified | +45 |
| `Gemini/GeminiSessionViewModel.swift` | Modified | +30 |
| **Total** | | **+270** |

## Backward Compatibility

### Existing Behavior Preserved

- **Active mode transcription**: Unchanged (still uses Gemini Live API)
- **Wake word detection**: Unchanged
- **Face detection**: Unchanged
- **OpenClaw integration**: Unchanged (receives transcripts from both sources)

### Graceful Degradation

- If speech recognition authorization denied: passive mode works without transcription, logs warning
- If `LocalTranscriptionManager` fails to initialize: passive mode falls back to wake-word-only behavior
- If user never shows face: transcripts are still captured but not saved (no active user)

## References

- iOS Speech Framework: https://developer.apple.com/documentation/speech
- AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- CLAUDE.md: Master implementation guide (User Registry system)
- MEMORY.md: VisionClaw project memory (HTTP-only architecture)

---

**Implementation Date**: 2026-04-27
**Status**: ✅ Implemented, ready for testing
**Branch**: `userregistry`
