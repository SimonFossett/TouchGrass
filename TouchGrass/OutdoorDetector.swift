//
//  OutdoorDetector.swift
//  TouchGrass
//
//  Determines whether a captured photo was taken outdoors.
//
//  Root-cause note: MobileNetV2 is an ImageNet-1000 *object* classifier.
//  Its labels are things like "running shoe", "jean", "tabby cat" — NOT
//  scene descriptors. Generic words like "outdoor", "sky", "grass", or
//  "nature" do not exist anywhere in ImageNet's vocabulary, so matching
//  against them always fails. A photo of feet in grass is classified as
//  "running shoe", which matched nothing and permanently returned false.
//
//  The corrected strategy has three layers:
//  1. Hard-block only when a confident *indoor* object is detected using
//     real ImageNet label fragments (sofa, toilet, washing machine, etc.)
//  2. Hard-allow when a recognised *outdoor* ImageNet label appears.
//  3. For neutral predictions (shoes, clothing, people) — the common case
//     for TouchGrass-style "feet on grass" photos — fall back to a fast
//     pixel-level green / sky-blue channel check.
//

import UIKit
import Vision
import CoreML

enum OutdoorDetector {

    // MARK: - Indoor keywords (actual ImageNet-1000 vocabulary)
    // A match here means the photo is definitely indoors.
    private static let indoorKeywords: [String] = [
        // Seating
        "sofa", "couch", "loveseat", "recliner", "ottoman",
        "rocking chair", "folding chair",
        // Bedroom
        "four-poster", "bunk bed", "pillow", "quilt", "comforter",
        // Lighting (ceiling-mounted fixtures never appear outdoors)
        "table lamp", "chandelier", "ceiling fan",
        // Storage / furniture
        "bookcase", "wardrobe", "filing cabinet",
        // Screens & electronics
        "monitor", "television", "laptop",
        // Kitchen appliances
        "refrigerator", "icebox", "dishwasher", "washing machine",
        "microwave", "oven", "toaster", "blender",
        // Bathroom
        "bathtub", "toilet", "shower curtain", "shower cap", "bidet",
        // Misc indoor
        "fireplace", "radiator",
        "wall clock", "grandfather clock",
        "medicine chest",
    ]

    // MARK: - Outdoor keywords (actual ImageNet-1000 vocabulary)
    // A match here means the photo is definitely outdoors.
    private static let outdoorKeywords: [String] = [
        // Landscapes that exist in ImageNet
        "lakeside", "lakeshore",
        "seashore", "seacoast",
        "cliff", "alp", "valley", "vale", "volcano",
        "promontory", "sandbar", "coral reef", "geyser",
        // Outdoor objects whose ImageNet labels confirm an outdoor setting
        "lawn mower", "mower",   // grass context — highly relevant
        "park bench",
        "picket fence", "chainlink fence", "split rail",
        "stone wall",
        "barn", "silo", "hay",
        "harvester", "thresher", "plow",
        // Always-outdoor activities / gear
        "parachute", "canoe", "kayak",
    ]

    // MARK: - Public API

    /// Asynchronously decides whether `image` appears to have been taken
    /// outdoors, then calls `completion` on an arbitrary thread.
    /// Defaults to `true` on any failure so a model error never hard-blocks
    /// a legitimate post.
    static func isOutdoor(image: UIImage, completion: @escaping (Bool) -> Void) {
        guard let ciImage = CIImage(image: image) else {
            completion(true)
            return
        }

        guard let model = try? VNCoreMLModel(for: MobileNetV2().model) else {
            completion(true)
            return
        }

        let request = VNCoreMLRequest(model: model) { request, _ in
            guard let results = request.results as? [VNClassificationObservation] else {
                completion(Self.pixelBasedOutdoorCheck(ciImage))
                return
            }

            let top10 = Array(results.prefix(10))

            // ── Layer 1: strong indoor signal ──────────────────────────────
            // Even low confidence is enough — we just need to be sure
            // something definitively indoor is present.
            let definitelyIndoor = top10.prefix(5).contains { result in
                result.confidence > 0.25 &&
                indoorKeywords.contains { result.identifier.lowercased().contains($0) }
            }
            if definitelyIndoor {
                completion(false)
                return
            }

            // ── Layer 2: recognised outdoor label ──────────────────────────
            let definitelyOutdoor = top10.contains { result in
                result.confidence > 0.10 &&
                outdoorKeywords.contains { result.identifier.lowercased().contains($0) }
            }
            if definitelyOutdoor {
                completion(true)
                return
            }

            // ── Layer 3: neutral predictions (shoes, clothing, people) ──────
            // This is the typical result for a "feet on grass" photo.
            // Resolve via pixel-level colour analysis.
            completion(Self.pixelBasedOutdoorCheck(ciImage))
        }

        // scaleFit preserves aspect ratio so the whole scene is visible to the model.
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    // MARK: - Pixel-based heuristic

    /// Renders the image into a tiny 64×64 RGBA bitmap and checks whether a
    /// meaningful proportion of pixels are natural-green (grass, trees) or
    /// sky-blue — the two dominant colours in outdoor photos that
    /// MobileNetV2's object labels miss entirely.
    private static func pixelBasedOutdoorCheck(_ ciImage: CIImage) -> Bool {
        let side = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        // Draw the full CI image scaled to 64×64.
        let ciCtx = CIContext()
        guard let cgImg = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return true }
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: side, height: side))

        guard let pixelData = ctx.data else { return true }
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var greenCount = 0
        var blueCount  = 0
        let total = side * side

        for i in 0..<total {
            let r = Int(pixels[i * 4])
            let g = Int(pixels[i * 4 + 1])
            let b = Int(pixels[i * 4 + 2])

            // Natural green: green channel leads, not overly bright (avoids
            // neon-green UI elements or yellow-greens).
            if g > r + 20 && g > b + 10 && g > 40 && g < 220 {
                greenCount += 1
            }
            // Sky blue: blue channel dominant with reasonable brightness.
            if b > r + 20 && b > g + 10 && b > 80 {
                blueCount += 1
            }
        }

        // More than 15 % natural green OR sky blue → outdoor.
        let greenRatio = Double(greenCount) / Double(total)
        let blueRatio  = Double(blueCount)  / Double(total)
        return greenRatio > 0.15 || blueRatio > 0.15
    }
}
