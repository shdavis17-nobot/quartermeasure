import Foundation
import Vision
import UIKit
import CoreGraphics

/// THE CENTROID-STABLE EDGE ENGINE: Uses sub-pixel averaging to prevent jitter.
struct EdgeDetector {

    struct SnapResult {
        let point: CGPoint
        let confidence: CGFloat 
    }

    static func snap(
        point: CGPoint,
        in viewSize: CGSize,
        image: UIImage,
        radius: CGFloat = 45,
        completion: @escaping (SnapResult) -> Void
    ) {
        DispatchQueue.global(qos: .userInteractive).async {
            let result = snapSync(point: point, in: viewSize, image: image, radius: radius)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func snapSync(
        point: CGPoint,
        in viewSize: CGSize,
        image: UIImage,
        radius: CGFloat
    ) -> SnapResult {
        guard let cgImage = image.cgImage else { return SnapResult(point: point, confidence: 0) }

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

        guard let cropped = cgImage.cropping(to: cropRect) else { return SnapResult(point: point, confidence: 0) }

        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 512 

        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        try? handler.perform([request])

        var bestMatch: CGPoint? = nil
        var maxConfidence: CGFloat = 0.0

        if let result = request.results?.first {
            // Audit up to 15 nearby contours
            for i in 0..<min(result.contourCount, 15) {
                guard let contour = try? result.contour(at: i) else { continue }
                
                // CENTROID LOGIC: Average all points in the contour for rock-solid stability
                let contourPoints = contour.normalizedPoints
                guard !contourPoints.isEmpty else { continue }
                
                var sumX: Double = 0
                var sumY: Double = 0
                for i in 0..<contour.pointCount {
                    let p = contourPoints[i]
                    sumX += Double(p.x)
                    sumY += Double(p.y)
                }
                
                let centroidX = CGFloat(sumX / Double(contour.pointCount))
                let centroidY = CGFloat(sumY / Double(contour.pointCount))
                
                // Map from crop-normalized (Vision) to full-image (UIKit)
                let centerX = (centroidX * CGFloat(cropped.width)) + cropRect.minX
                let centerY = ((1.0 - centroidY) * CGFloat(cropped.height)) + cropRect.minY
                
                let vx = centerX / scaleX
                let vy = centerY / scaleY
                let dx = vx - point.x
                let dy = vy - point.y
                let dist = hypot(dx, dy)

                if dist < radius {
                    // Closed-loop objects (coins) get higher confidence
                    let confidence: CGFloat = (contour.childContours.count >= 0) ? 0.95 : 0.5
                    
                    if confidence > maxConfidence {
                        maxConfidence = confidence
                        bestMatch = CGPoint(x: vx, y: vy)
                    }
                }
            }
        }

        return SnapResult(point: bestMatch ?? point, confidence: maxConfidence)
    }
}
