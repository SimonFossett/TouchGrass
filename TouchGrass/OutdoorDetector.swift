//
//  OutdoorDetector.swift
//  TouchGrass
//
//  Uses MobileNetV2 via Vision to decide whether a photo was taken outdoors.
//  If none of the top predictions clear the confidence threshold AND match an
//  outdoor label fragment, the image is considered indoors.
//

import UIKit
import Vision
import CoreML

enum OutdoorDetector {

    // ImageNet label fragments that indicate an outdoor scene.
    private static let outdoorKeywords: [String] = [
        "outdoor", "outside",
        "nature", "natural",
        "mountain", "hill", "cliff", "valley", "alp", "volcano",
        "sky", "cloud", "horizon", "sunlight", "sunrise", "sunset",
        "beach", "shore", "coast", "sand", "seashore", "lakeshore",
        "forest", "tree", "grass", "lawn", "meadow", "jungle", "woodland",
        "park", "garden", "field", "farm", "barn", "paddock",
        "lake", "river", "ocean", "sea", "waterfall", "rapids",
        "street", "road", "sidewalk", "path", "trail", "alley",
        "snow", "glacier", "ice rink",
        "patio", "terrace", "balcony",
        "athletic field", "baseball", "football field", "golf"
    ]

    /// Asynchronously classifies `image` using MobileNetV2 and calls `completion`
    /// on an arbitrary thread with `true` if the scene appears to be outdoors.
    ///
    /// - If the model cannot be loaded the call defaults to `true` so the user
    ///   is never unfairly blocked by a technical failure.
    static func isOutdoor(image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            completion(false)
            return
        }

        guard let model = try? VNCoreMLModel(for: MobileNetV2().model) else {
            // Allow posting if the model fails to initialise.
            completion(true)
            return
        }

        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let results = request.results as? [VNClassificationObservation] else {
                completion(false)
                return
            }

            // Primary check: any top-5 result with confidence > 0.6 that matches
            // an outdoor keyword.
            let highConfidenceOutdoor = results.prefix(5).contains { result in
                result.confidence > 0.6 &&
                outdoorKeywords.contains { result.identifier.lowercased().contains($0) }
            }

            // Secondary check: spread-confidence outdoor scenes (e.g. a wide
            // landscape) may not hit 0.6 on any single label, so we also accept
            // a match in the top-10 at a lower threshold.
            let broadOutdoor = !highConfidenceOutdoor && results.prefix(10).contains { result in
                result.confidence > 0.3 &&
                outdoorKeywords.contains { result.identifier.lowercased().contains($0) }
            }

            completion(highConfidenceOutdoor || broadOutdoor)
        }

        // Center-crop gives the best results for scene classification.
        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
