import Foundation
import CoreML
import Vision
import UIKit

/// Wrapper for FaceNet-128 CoreML model
/// Produces 128-dimensional face embeddings for recognition
class FaceNetModel {
    private var model: VNCoreMLModel?
    private let modelInputSize = CGSize(width: 112, height: 112)

    init() {
        setupModel()
    }

    private func setupModel() {
        // Try to load face recognition model (AdaFace or FaceNet)
        // Try AdaFace first (512-dim), then fall back to FaceNet (128-dim)
        var modelURL: URL?
        var modelName: String = "Unknown"

        if let adaFaceURL = Bundle.main.url(forResource: "AdaFace_IR18", withExtension: "mlmodelc") {
            modelURL = adaFaceURL
            modelName = "AdaFace_IR18 (512-dim)"
        } else if let faceNetURL = Bundle.main.url(forResource: "FaceNet", withExtension: "mlmodelc") {
            modelURL = faceNetURL
            modelName = "FaceNet (128-dim)"
        }

        guard let url = modelURL else {
            NSLog("[FaceNet] ERROR: No face recognition model found in bundle")
            NSLog("[FaceNet] Please add AdaFace.mlmodel or FaceNet.mlmodel to the project")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: url)
            self.model = try VNCoreMLModel(for: mlModel)
            NSLog("[FaceNet] Model loaded successfully: %@", modelName)
        } catch {
            NSLog("[FaceNet] Failed to load model: %@", error.localizedDescription)
        }
    }

    /// Extract face embedding from a face image (512-dim for AdaFace, 128-dim for FaceNet)
    /// - Parameter faceImage: Cropped face image (will be resized to 112x112)
    /// - Returns: Float array of embeddings, or nil if inference fails
    func extractEmbedding(from faceImage: UIImage) -> [Float]? {
        guard let model = model else {
            NSLog("[FaceNet] Model not loaded")
            return nil
        }

        // Resize image to 112x112
        guard let resizedImage = resize(image: faceImage, to: modelInputSize) else {
            NSLog("[FaceNet] Failed to resize image")
            return nil
        }

        // Convert to CVPixelBuffer
        guard let pixelBuffer = resizedImage.pixelBuffer() else {
            NSLog("[FaceNet] Failed to create pixel buffer")
            return nil
        }

        // Run inference
        let request = VNCoreMLRequest(model: model)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let firstResult = results.first,
                  let embedding = extractEmbeddingFromMLFeatureValue(firstResult.featureValue) else {
                NSLog("[FaceNet] Failed to extract embedding from results")
                return nil
            }

            return embedding
        } catch {
            NSLog("[FaceNet] Inference failed: %@", error.localizedDescription)
            return nil
        }
    }

    /// Extract embedding from MLFeatureValue (handles different output types)
    private func extractEmbeddingFromMLFeatureValue(_ featureValue: MLFeatureValue) -> [Float]? {
        // Try multiArray first (most common for embeddings)
        if let multiArray = featureValue.multiArrayValue {
            return extractFromMultiArray(multiArray)
        }

        // Try sequence of values
        if let sequence = featureValue.sequenceValue {
            // Handle sequence type
            NSLog("[FaceNet] Sequence output not yet implemented")
            return nil
        }

        NSLog("[FaceNet] Unsupported feature value type: %@", String(describing: featureValue.type))
        return nil
    }

    /// Extract float array from MLMultiArray
    private func extractFromMultiArray(_ multiArray: MLMultiArray) -> [Float]? {
        let count = multiArray.count

        // AdaFace outputs 512 dimensions (can also handle 128-dim models)
        guard count == 512 || count == 128 else {
            NSLog("[FaceNet] Unexpected embedding size: %d (expected 512 or 128)", count)
            return nil
        }

        var embedding: [Float] = []
        embedding.reserveCapacity(count)

        for i in 0..<count {
            let value = multiArray[i].floatValue
            embedding.append(value)
        }

        // L2 normalize the embedding
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        NSLog("[FaceNet] Extracted %d-dimensional embedding", count)
        return embedding
    }

    /// Resize image to target size
    private func resize(image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - UIImage Extension for CoreML

extension UIImage {
    /// Convert UIImage to CVPixelBuffer for CoreML input
    func pixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self.size.height)

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        guard let cgImage = self.cgImage, let ctx = context else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}
