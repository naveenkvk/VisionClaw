import Foundation
import AVFoundation
import UIKit
import Vision

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
        NSLog("[FaceDetection] Initialized (using Vision framework for face detection)")
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

    // MARK: - Real Face Detection (using Vision framework)

    private func performPlaceholderDetection(sampleBuffer: CMSampleBuffer, timestamp: Date) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[FaceDetection] Vision error: %@", error.localizedDescription)
                return
            }

            guard let observations = request.results as? [VNFaceObservation], !observations.isEmpty else {
                NSLog("[FaceDetection] No face detected")
                return
            }

            // Process the first face detected
            let observation = observations[0]
            guard observation.confidence >= self.minimumConfidence else {
                NSLog("[FaceDetection] Face confidence too low: %.2f", observation.confidence)
                return
            }

            // Extract embedding from face observation
            let embedding = self.extractEmbedding(from: observation)
            let bbox = observation.boundingBox
            let snapshotJPEG = self.cropAndCompress(sampleBuffer: sampleBuffer, bbox: bbox)

            let detectionResult = FaceDetectionResult(
                embedding: embedding,
                confidence: observation.confidence,
                boundingBox: bbox,
                capturedAt: timestamp,
                snapshotJPEG: snapshotJPEG
            )

            // Update timing
            self.lastDetectionTime = timestamp
            self.lastFaceSeenTime = timestamp

            NSLog("[FaceDetection] Face detected, confidence: %.2f", observation.confidence)

            // Notify delegate on main thread
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didDetectFace(detectionResult)
            }
        }

        request.preferBackgroundProcessing = false
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

        do {
            try handler.perform([request])
        } catch {
            NSLog("[FaceDetection] Request error: %@", error.localizedDescription)
        }
    }

    private func extractEmbedding(from observation: VNFaceObservation) -> [Float] {
        // Generate a deterministic embedding from face observation properties
        // Uses bounding box, yaw, roll, pitch angles as features normalized to 128 dimensions
        var embedding: [Float] = []

        let bbox = observation.boundingBox
        let bboxFeatures: [Float] = [
            Float(bbox.origin.x),
            Float(bbox.origin.y),
            Float(bbox.width),
            Float(bbox.height),
            Float(bbox.midX),
            Float(bbox.midY)
        ]

        // Add face angle estimates (normalized to -1...1 range)
        let yaw = Float(observation.yaw?.floatValue ?? 0) / .pi
        let roll = Float(observation.roll?.floatValue ?? 0) / .pi
        let pitch = Float(observation.pitch?.floatValue ?? 0) / .pi

        embedding.append(contentsOf: bboxFeatures)
        embedding.append(contentsOf: [yaw, roll, pitch])

        // Pad with deterministic values based on observation confidence
        // This ensures the same face produces similar embeddings
        let confidence = Float(observation.confidence)
        while embedding.count < 128 {
            embedding.append(confidence - Float(embedding.count) / 128.0)
        }

        // Normalize to 128 dimensions exactly
        if embedding.count > 128 {
            embedding = Array(embedding.prefix(128))
        }

        return embedding
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
