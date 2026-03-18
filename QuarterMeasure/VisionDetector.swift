import Foundation
import Combine
import Vision
import CoreVideo
import UIKit

class VisionDetector: ObservableObject {
    @Published var quarterDetected: Bool = false
    @Published var quarterBoundingBox: CGRect = .zero

    let quarterDiameterInches: CGFloat = 0.955

    /// Analyze a still UIImage for a quarter (called after photo capture)
    func detectQuarter(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        performDetection(with: handler)
    }

    /// Analyze a live CVPixelBuffer from the camera feed
    func detectQuarter(in pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        performDetection(with: handler)
    }

    private func performDetection(with handler: VNImageRequestHandler) {
        // Use rectangle detection, not contour — matches the quarter's foreshortened shape
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNRectangleObservation] else {
                DispatchQueue.main.async { self?.quarterDetected = false }
                return
            }

            // Filter candidates: a quarter viewed from above is nearly square (circle -> bounding box ~1:1)
            // Width must be > 5% of image width to avoid tiny false circles
            let quarterCandidates = results.filter { obs in
                let w = obs.boundingBox.width
                let h = obs.boundingBox.height
                guard w > 0, h > 0 else { return false }
                let aspectRatio = w / h
                // Must be near-square (0.8–1.25), reasonably large (>8% screen dimension) 
                // and small enough not to be the entire frame (< 60%)
                return aspectRatio > 0.80 && aspectRatio < 1.25
                    && w > 0.08 && w < 0.60
                    && h > 0.08 && h < 0.60
            }

            let found = !quarterCandidates.isEmpty
            let box = quarterCandidates.first?.boundingBox ?? .zero

            DispatchQueue.main.async {
                self.quarterDetected = found
                self.quarterBoundingBox = box
            }
        }

        request.minimumAspectRatio = 0.80
        request.maximumAspectRatio = 1.25
        request.minimumSize = 0.08
        request.maximumObservations = 5

        do {
            try handler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
        }
    }
}
