import UIKit
import SwiftUI

/// Renders a measurement-annotated UIImage suitable for sharing.
struct ExportRenderer {

    /// Compose the annotation overlay on top of the source image.
    /// - Parameters:
    ///   - source: The captured photo.
    ///   - startPoint: First measurement pin in view coordinates.
    ///   - endPoint: Second measurement pin in view coordinates.
    ///   - viewSize: Size of the view in which the image is displayed.
    ///   - label: Measurement text (e.g. "3.50 in").
    /// - Returns: Annotated UIImage at the source image's native resolution.
    static func render(
        source: UIImage,
        startPoint: CGPoint,
        endPoint: CGPoint,
        viewSize: CGSize,
        label: String
    ) -> UIImage {
        let imgSize = source.size
        let scaleX = imgSize.width  / viewSize.width
        let scaleY = imgSize.height / viewSize.height

        // Scale view points → image pixels
        let imgStart = CGPoint(x: startPoint.x * scaleX, y: startPoint.y * scaleY)
        let imgEnd   = CGPoint(x: endPoint.x   * scaleX, y: endPoint.y   * scaleY)

        let renderer = UIGraphicsImageRenderer(size: imgSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 1. Draw source photo
            source.draw(in: CGRect(origin: .zero, size: imgSize))

            // 2. Measurement line
            cgCtx.setStrokeColor(UIColor.systemYellow.cgColor)
            cgCtx.setLineWidth(max(2, imgSize.width / 300))
            let dashLen = imgSize.width / 80
            cgCtx.setLineDash(phase: 0, lengths: [dashLen, dashLen * 0.6])
            cgCtx.move(to: imgStart)
            cgCtx.addLine(to: imgEnd)
            cgCtx.strokePath()

            // 3. Measurement pins
            let pinRadius = max(8, imgSize.width / 120)
            cgCtx.setLineDash(phase: 0, lengths: [])
            cgCtx.setFillColor(UIColor.systemYellow.cgColor)
            for pin in [imgStart, imgEnd] {
                cgCtx.fillEllipse(in: CGRect(
                    x: pin.x - pinRadius, y: pin.y - pinRadius,
                    width: pinRadius * 2, height: pinRadius * 2))
            }

            // 4. Measurement label badge
            let midX = (imgStart.x + imgEnd.x) / 2
            let midY = (imgStart.y + imgEnd.y) / 2 - pinRadius * 4

            let fontSize = max(24, imgSize.width / 30)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let labelStr = NSAttributedString(string: label, attributes: attrs)
            let labelSize = labelStr.size()
            let padding: CGFloat = fontSize * 0.5
            let badgeRect = CGRect(
                x: midX - labelSize.width / 2 - padding,
                y: midY - labelSize.height / 2 - padding * 0.5,
                width: labelSize.width + padding * 2,
                height: labelSize.height + padding
            )

            // Badge background
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: padding)
            UIColor.black.withAlphaComponent(0.65).setFill()
            badgePath.fill()

            // Label text
            labelStr.draw(at: CGPoint(
                x: badgeRect.minX + padding,
                y: badgeRect.minY + padding * 0.5
            ))

            // 5. "Privacy Verified" watermark (bottom-right)
            let wmFontSize = max(14, imgSize.width / 60)
            let wmAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: wmFontSize, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.65)
            ]
            let watermark = NSAttributedString(
                string: "🔒 Privacy Verified · QuarterMeasure",
                attributes: wmAttrs
            )
            let wmSize = watermark.size()
            let margin = wmFontSize * 1.2
            watermark.draw(at: CGPoint(
                x: imgSize.width  - wmSize.width  - margin,
                y: imgSize.height - wmSize.height - margin
            ))
        }
    }
}
