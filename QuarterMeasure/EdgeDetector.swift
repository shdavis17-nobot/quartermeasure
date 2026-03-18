import Foundation
import Vision
import UIKit
import CoreGraphics

/// Finds the nearest high-contrast edge within a radius of a touch point.
/// Vision work runs on a background queue to never block the main thread.
struct EdgeDetector {

    /// Async snap — calls completion on the main queue with the snapped point.
    static func snap(
        point: CGPoint,
        in viewSize: CGSize,
        image: UIImage,
        radius: CGFloat = 40,
        completion: @escaping (CGPoint) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let snapped = snapSync(point: point, in: viewSize, image: image, radius: radius)
            DispatchQueue.main.async { completion(snapped) }
        }
    }

    // Synchronous implementation — MUST be called on a background queue only
    private static func snapSync(
        point: CGPoint,
        in viewSize: CGSize,
        image: UIImage,
        radius: CGFloat
    ) -> CGPoint {
        guard let cgImage = image.cgImage else { return point }

        // Use CGImage pixel dimensions (not UIImage.size which is in points)
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        let scaleX = imgW / viewSize.width
        let scaleY = imgH / viewSize.height

        let imgPoint  = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        let imgRadius = radius * max(scaleX, scaleY)

        let cropRect = CGRect(
            x: max(0, imgPoint.x - imgRadius),
            y: max(0, imgPoint.y - imgRadius),
            width:  min(imgRadius * 2, imgW - max(0, imgPoint.x - imgRadius)),
            height: min(imgRadius * 2, imgH - max(0, imgPoint.y - imgRadius))
        )

        guard let cropped = cgImage.cropping(to: cropRect) else { return point }

        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight    = true
        request.maximumImageDimension = 256

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try? handler.perform([request])

        var bestEdge: CGPoint? = nil
        if let result = request.results?.first {
            var minDist = CGFloat.infinity
            for i in 0..<min(result.contourCount, 10) {
                guard let contour = try? result.contour(at: i) else { continue }
                let bb = contour.normalizedPath.boundingBox

                let centerX = (bb.midX * CGFloat(cropped.width))  + cropRect.minX
                let centerY = ((1 - bb.midY) * CGFloat(cropped.height)) + cropRect.minY

                let vx = centerX / scaleX
                let vy = centerY / scaleY
                let dx = vx - point.x
                let dy = vy - point.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < minDist && dist < radius {
                    minDist  = dist
                    bestEdge = CGPoint(x: vx, y: vy)
                }
            }
        }

        return bestEdge ?? point
    }
}
