import Foundation
import AVFoundation
import UIKit

// Note: MediaPipe integration will be added when SPM dependency is configured
// For now, this implementation uses placeholder logic that can be tested end-to-end

class FaceDetectionManager {
    // MARK: - Public API
    weak var delegate: FaceDetectionDelegate?

    // MARK: - Private State
    private let detectionQueue = DispatchQueue(label: "com.visionclaw.facedetection", qos: .userInitiated)
    private var isInferenceInProgress = false
    private var lastDetectionTime: Date = .distantPast
    private var lastFaceSeenTime: Date?
    private var lossCheckTimer: DispatchSourceTimer?

    // MARK: - Configuration
    private let debounceInterval: TimeInterval = 3.0  // 3 seconds
    private let lossInterval: TimeInterval = 5.0      // 5 seconds
    private let minimumConfidence: Float = 0.7
    private let snapshotQuality: CGFloat = 0.5        // 50% JPEG quality

    // MARK: - Initialization
    init() {
        setupDetector()
        startLossMonitoring()
    }

    private func setupDetector() {
        // TODO: Initialize MediaPipe FaceDetector when SPM dependency is added
        // For now, log that we're using placeholder mode
        NSLog("[FaceDetection] Initialized (placeholder mode - MediaPipe integration pending)")
    }

    // MARK: - Detection Entry Point

    /// Process a sample buffer for face detection
    /// - Called from IPhoneCameraManager on background queue
    /// - Debounced to max once per 3 seconds
    /// - Returns immediately if previous inference still running
    func detect(sampleBuffer: CMSampleBuffer) {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }

            // Drop frame if inference is in-flight
            guard !self.isInferenceInProgress else { return }

            // Debounce: skip if last detection was < 3s ago
            let now = Date()
            guard now.timeIntervalSince(self.lastDetectionTime) >= self.debounceInterval else { return }

            self.isInferenceInProgress = true
            defer { self.isInferenceInProgress = false }

            // Run placeholder detection
            self.performPlaceholderDetection(sampleBuffer: sampleBuffer, timestamp: now)
        }
    }

    // MARK: - Placeholder Detection (for testing without MediaPipe)

    private func performPlaceholderDetection(sampleBuffer: CMSampleBuffer, timestamp: Date) {
        // Simulate detection with random success (50% chance)
        let detected = Int.random(in: 0...1) == 1

        guard detected else {
            NSLog("[FaceDetection] No face detected (placeholder)")
            return
        }

        // Generate placeholder data
        let confidence: Float = Float.random(in: 0.7...0.95)
        let bbox = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4) // Center of frame
        let embedding = extractPlaceholderEmbedding()
        let snapshotJPEG = cropAndCompress(sampleBuffer: sampleBuffer, bbox: bbox)

        let detectionResult = FaceDetectionResult(
            embedding: embedding,
            confidence: confidence,
            boundingBox: bbox,
            capturedAt: timestamp,
            snapshotJPEG: snapshotJPEG
        )

        // Update timing
        lastDetectionTime = timestamp
        lastFaceSeenTime = timestamp

        NSLog("[FaceDetection] Face detected (placeholder), confidence: %.2f", confidence)

        // Notify delegate on main thread
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectFace(detectionResult)
        }
    }

    private func extractPlaceholderEmbedding() -> [Float] {
        // PLACEHOLDER: Return 128 random values for now
        // This allows the pipeline to work end-to-end for testing
        // TODO: Replace with real embedding extraction:
        // Options:
        // 1. Use MediaPipe Face Mesh (provides 468 landmarks, can derive embedding)
        // 2. Use Apple's Vision framework VNFaceObservation with feature print
        // 3. Bundle a separate face recognition model (FaceNet, ArcFace)
        NSLog("[FaceDetection] WARNING: Using placeholder embedding (needs real implementation)")
        return (0..<128).map { _ in Float.random(in: -1.0...1.0) }
    }

    private func cropAndCompress(sampleBuffer: CMSampleBuffer, bbox: CGRect) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        // Convert normalized bbox to pixel coordinates
        let imageSize = ciImage.extent.size
        let cropRect = CGRect(
            x: bbox.origin.x * imageSize.width,
            y: bbox.origin.y * imageSize.height,
            width: bbox.width * imageSize.width,
            height: bbox.height * imageSize.height
        )

        let croppedImage = ciImage.cropped(to: cropRect)

        guard let cgImage = context.createCGImage(croppedImage, from: croppedImage.extent) else { return nil }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: snapshotQuality)
    }

    // MARK: - Loss Monitoring

    private func startLossMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: detectionQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.checkForLoss()
        }
        timer.resume()
        lossCheckTimer = timer
    }

    private func checkForLoss() {
        guard let lastSeen = lastFaceSeenTime else { return }

        let elapsed = Date().timeIntervalSince(lastSeen)
        if elapsed >= lossInterval {
            lastFaceSeenTime = nil
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didLoseFace()
            }
        }
    }

    deinit {
        lossCheckTimer?.cancel()
    }
}

// MARK: - MediaPipe Integration (to be implemented when SPM dependency is added)
/*
import MediaPipeTasksVision

extension FaceDetectionManager {
    private func setupDetectorWithMediaPipe() {
        detectionQueue.async { [weak self] in
            guard let modelPath = Bundle.main.path(forResource: "face_detection_short_range", ofType: "tflite") else {
                NSLog("[FaceDetection] ERROR: Model file not found in bundle")
                return
            }

            let options = FaceDetectorOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.minDetectionConfidence = self?.minimumConfidence ?? 0.7

            do {
                self?.faceDetector = try FaceDetector(options: options)
                NSLog("[FaceDetection] MediaPipe FaceDetector initialized")
            } catch {
                NSLog("[FaceDetection] ERROR: Failed to initialize detector: \(error.localizedDescription)")
            }
        }
    }

    private func processDetectionResult(_ result: FaceDetectorResult, originalBuffer: CMSampleBuffer, timestamp: Date) {
        guard let detection = result.detections.first else {
            // No face detected
            return
        }

        // Extract confidence (MediaPipe returns categories with scores)
        guard let confidence = detection.categories.first?.score,
              confidence >= minimumConfidence else {
            return
        }

        // Extract bounding box (normalized coordinates)
        let bbox = detection.boundingBox

        // Extract embedding (needs custom implementation)
        let embedding = extractEmbedding(from: originalBuffer, bbox: bbox)

        // Crop and compress snapshot
        let snapshotJPEG = cropAndCompress(sampleBuffer: originalBuffer, bbox: bbox)

        let detectionResult = FaceDetectionResult(
            embedding: embedding,
            confidence: confidence,
            boundingBox: bbox,
            capturedAt: timestamp,
            snapshotJPEG: snapshotJPEG
        )

        // Update timing
        lastDetectionTime = timestamp
        lastFaceSeenTime = timestamp

        // Notify delegate on main thread
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didDetectFace(detectionResult)
        }
    }
}
*/
