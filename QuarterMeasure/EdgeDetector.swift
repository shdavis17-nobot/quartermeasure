import Foundation
import Vision
import UIKit
import CoreGraphics

/// Finds the nearest high-contrast edge within a radius of a touch point.
/// Uses VNDetectEdgesRequest on a cropped region of the frozen image.
struct EdgeDetector {

    /// Attempts to snap `point` to a nearby edge in `image`.
    /// - Parameters:
    ///   - point: Touch location in view coordinates.
    ///   - viewSize: Size of the view displaying the image.
    ///   - image: The frozen captured UIImage.
    ///   - radius: Search radius in view points (default 40).
    /// - Returns: Snapped point (or original if no edge found).
    static func snap(
        point: CGPoint,
        in viewSize: CGSize,
        image: UIImage,
        radius: CGFloat = 40
    ) -> CGPoint {
        guard let cgImage = image.cgImage else { return point }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Scale from view space to image space
        let scaleX = imgW / viewSize.width
        let scaleY = imgH / viewSize.height

        let imgPoint = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        let imgRadius = radius * max(scaleX, scaleY)

        // Crop region around touch
        let cropRect = CGRect(
            x: max(0, imgPoint.x - imgRadius),
            y: max(0, imgPoint.y - imgRadius),
            width: min(imgRadius * 2, imgW - max(0, imgPoint.x - imgRadius)),
            height: min(imgRadius * 2, imgH - max(0, imgPoint.y - imgRadius))
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return point }

        // Run edge detection on the crop
        var bestEdge: CGPoint? = nil
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 256

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try? handler.perform([request])

        if let result = request.results?.first {
            var minDist = CGFloat.infinity
            for i in 0..<min(result.contourCount, 10) {
                guard let contour = try? result.contour(at: i) else { continue }
                let bb = contour.normalizedPath.boundingBox

                // Convert normalized contour center back to crop image space
                let centerX = (bb.midX * CGFloat(cropped.width)) + cropRect.minX
                let centerY = ((1 - bb.midY) * CGFloat(cropped.height)) + cropRect.minY

                // Convert to view space
                let vx = centerX / scaleX
                let vy = centerY / scaleY

                let dx = vx - point.x
                let dy = vy - point.y
                let dist = sqrt(dx*dx + dy*dy)
                if dist < minDist && dist < radius {
                    minDist = dist
                    bestEdge = CGPoint(x: vx, y: vy)
                }
            }
        }

        return bestEdge ?? point
    }
}
