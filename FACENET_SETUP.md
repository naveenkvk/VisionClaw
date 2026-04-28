# FaceNet-128 Face Recognition Setup Guide

## Status: ✅ Code Implementation Complete

The FaceNet integration code is ready. You just need to:
1. Add `FaceNetModel.swift` to Xcode
2. Download the FaceNet CoreML model
3. Test with real face recognition

---

## Step 1: Add FaceNetModel.swift to Xcode Project (2 minutes)

1. Open `CameraAccess.xcodeproj` in Xcode
2. In the Project Navigator, locate the `FaceDetection` folder
3. Right-click on `FaceDetection` → **Add Files to "CameraAccess"...**
4. Navigate to: `/Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess/CameraAccess/FaceDetection/`
5. Select `FaceNetModel.swift`
6. ✅ Ensure "Add to targets: CameraAccess" is checked
7. Click **Add**

---

## Step 2: Download FaceNet CoreML Model (5 minutes)

### Option A: Download Pre-converted Model (Recommended)

Download a ready-made FaceNet CoreML model:

1. **Option 1: FaceNet-PyTorch CoreML**
   ```bash
   cd /tmp
   # Download from a CoreML model repository
   # Example: https://github.com/niw/FaceNet_CoreML
   git clone https://github.com/niw/FaceNet_CoreML.git
   cp FaceNet_CoreML/FaceNet.mlmodel ~/Downloads/
   ```

2. **Option 2: MobileFaceNet (Lightweight Alternative)**
   - Search for "MobileFaceNet CoreML" on GitHub
   - Download the `.mlmodel` file
   - Rename it to `FaceNet.mlmodel`

### Option B: Convert TensorFlow/PyTorch Model to CoreML

If no pre-converted model is available:

```bash
# Install coremltools
pip install coremltools tensorflow

# Convert FaceNet model
python3 << 'EOF'
import coremltools as ct
import tensorflow as tf

# Load FaceNet model (download from GitHub)
# Example: https://github.com/davidsandberg/facenet
model = tf.keras.models.load_model('path/to/facenet_keras.h5')

# Convert to CoreML
coreml_model = ct.convert(model, inputs=[ct.ImageType(shape=(1, 160, 160, 3))])
coreml_model.save('FaceNet.mlmodel')
print("✅ Conversion complete: FaceNet.mlmodel")
EOF
```

---

## Step 3: Add Model to Xcode Project

1. In Xcode, right-click on the `FaceDetection` folder
2. Select **Add Files to "CameraAccess"...**
3. Navigate to your downloaded `FaceNet.mlmodel` file
4. ✅ Ensure "Add to targets: CameraAccess" is checked
5. Click **Add**

The model will be automatically compiled to `FaceNet.mlmodelc` during build.

---

## Step 4: Verify Installation

Build the project:

```bash
cd /Users/naveenkumarvk/Projects/VisionClaw/samples/CameraAccess
xcodebuild -project CameraAccess.xcodeproj -scheme CameraAccess -sdk iphonesimulator build
```

✅ Expected output: `** BUILD SUCCEEDED **`

---

## Step 5: Test Face Recognition

1. **Clear the database:**
   ```bash
   docker exec user-registry-postgres-1 psql -U postgres -d user_registry -c "TRUNCATE users CASCADE;"
   ```

2. **Run the app** on a physical iPhone or simulator

3. **Test with User 1:**
   - Point camera at first person
   - Wait for detection
   - Check logs: `[FaceNet] Model loaded successfully`
   - Check logs: `[FaceNet] embedding extracted: 128 dimensions`

4. **Test with User 2 (different person):**
   - Point camera at second person
   - Should create a NEW user (not match User 1)

5. **Test with User 1 again:**
   - Point camera at first person again
   - Should MATCH the existing User 1

---

## Troubleshooting

### Error: "FaceNet.mlmodelc not found in bundle"

**Cause:** Model file not added to Xcode project or not in build target

**Fix:**
1. Select `FaceNet.mlmodel` in Project Navigator
2. Check **File Inspector** (right sidebar)
3. Ensure "Target Membership: CameraAccess" is ✅ checked

### Error: "Failed to load model"

**Cause:** Model architecture incompatible

**Fix:**
- Ensure the model:
  - Input: 160×160 RGB image
  - Output: 128-dimensional float array
  - Check model details in Xcode (click on .mlmodel file)

### Error: "Unsupported feature value type"

**Cause:** Model output format doesn't match expected type

**Fix:**
- Open `FaceNetModel.swift`
- Check `extractEmbeddingFromMLFeatureValue()` method
- Add logging to see what type the model returns
- Update extraction logic accordingly

### False Positives Still Occurring

**Cause:** Model not loaded, falling back to landmark-based detection

**Check:**
```bash
# Search logs for FaceNet messages
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.visionclaw"' | grep FaceNet
```

**Expected logs:**
```
[FaceNet] Model loaded successfully
[FaceNet] embedding extracted: 128 dimensions
```

---

## Alternative: Quick Testing with Placeholder

If you can't obtain a FaceNet model immediately but want to test the system flow:

1. Modify `FaceNetModel.swift` to generate random but consistent embeddings:

```swift
func extractEmbedding(from faceImage: UIImage) -> [Float]? {
    // TEMPORARY: Generate deterministic random embedding based on image hash
    let imageHash = faceImage.hashValue
    var embedding: [Float] = []
    for i in 0..<128 {
        let seed = (imageHash + i) % 10000
        embedding.append(Float(seed) / 10000.0)
    }
    // L2 normalize
    let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
    return embedding.map { $0 / magnitude }
}
```

This will give you unique embeddings per image for testing the flow, but **NOT real face recognition**.

---

## What You Get with FaceNet

✅ **Real face recognition** - Neural network trained on millions of faces
✅ **128-dimensional embeddings** - Deep features capturing facial characteristics
✅ **High accuracy** - Can distinguish between similar-looking people
✅ **Robust to pose/lighting** - Works across different angles and conditions
✅ **Production-ready** - Used in real face recognition systems worldwide

---

## Current Threshold Settings

After implementing FaceNet, you may need to adjust thresholds:

- **Current:** 0.15 (very strict)
- **With FaceNet:** Can use 0.4-0.6 (FaceNet embeddings are more distinctive)

Update in these files:
- `UserRegistryCoordinator.swift:64` → `threshold: 0.4`
- `UserRegistryBridge.swift:18` → `threshold: Float = 0.4`
- `OpenClawBridge.swift:261` → `threshold: Float = 0.4`

---

## Next Steps

1. ✅ Add `FaceNetModel.swift` to Xcode
2. ✅ Download and add `FaceNet.mlmodel`
3. ✅ Build project
4. ✅ Test with 2 different people
5. ✅ Verify embeddings are different and accurate
6. ✅ Adjust threshold if needed (start with 0.4)

**Estimated total time:** 15-30 minutes

Good luck! 🚀
