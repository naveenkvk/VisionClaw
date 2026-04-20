import Foundation
import UIKit

/// Result from a single face detection pass
struct FaceDetectionResult {
    /// 128-dimensional embedding vector from MediaPipe
    let embedding: [Float]

    /// Confidence score (0.0 to 1.0)
    let confidence: Float

    /// Bounding box in normalized coordinates (0.0 to 1.0)
    let boundingBox: CGRect

    /// Timestamp when this face was detected
    let capturedAt: Date

    /// JPEG snapshot of the detected face (50% quality), optional
    let snapshotJPEG: Data?
}

/// Delegate protocol for face detection events
protocol FaceDetectionDelegate: AnyObject {
    /// Called when a face is detected (debounced to max once per 3 seconds)
    func didDetectFace(_ result: FaceDetectionResult)

    /// Called when no face has been detected for 5 seconds
    func didLoseFace()
}
