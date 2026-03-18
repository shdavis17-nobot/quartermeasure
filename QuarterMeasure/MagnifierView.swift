import SwiftUI

/// Real 2.5× magnifying loupe.
/// In frozen-image mode supplies an actual cropped + scaled view of the source image.
/// Falls back to a glassmorphism bubble with crosshair when no image is available.
struct MagnifierView: View {
    /// Touch location in parent coordinate space
    var touchLocation: CGPoint
    var isVisible: Bool
    /// If provided, crops and zooms this image for true pixel-accurate magnification
    var sourceImage: UIImage? = nil
    /// The size of the view that is displaying the source image (for coordinate mapping)
    var viewSize: CGSize = .zero

    // Spec constants
    private let loupeSize:   CGFloat = 120
    private let loupeLift:   CGFloat = 60   // pt above fingertip
    private let magnification: CGFloat = 2.5

    var body: some View {
        Group {
            if isVisible {
                ZStack {
                    // ── Glass backing
                    Circle()
                        .fill(.ultraThinMaterial)

                    // ── Magnified content
                    if let img = sourceImage, viewSize != .zero {
                        magnifiedContent(img)
                    } else {
                        // live-camera fallback: tinted glass
                        Circle()
                            .fill(Color.black.opacity(0.25))
                    }

                    // ── 1px precision crosshair
                    ZStack {
                        Rectangle()
                            .frame(width: 1, height: loupeSize * 0.45)
                        Rectangle()
                            .frame(width: loupeSize * 0.45, height: 1)
                    }
                    .foregroundColor(.white.opacity(0.9))

                    // ── Outer ring stroke
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                }
                .frame(width: loupeSize, height: loupeSize)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                // Render 60pt above the fingertip
                .position(x: touchLocation.x,
                          y: touchLocation.y - loupeLift - loupeSize / 2)
                .transition(.opacity.animation(.easeOut(duration: 0.2)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: isVisible)
    }

    // MARK: - Pixel-accurate magnified crop
    private func magnifiedContent(_ image: UIImage) -> some View {
        // UIImage.size is in POINTS; CGImage.cropping(to:) works in PIXELS.
        // Always derive dimensions from CGImage to avoid scale-factor mismatch on Retina.
        guard let cgSrc = image.cgImage else { return AnyView(Color.clear) }
        let imgW = CGFloat(cgSrc.width)
        let imgH = CGFloat(cgSrc.height)

        // Scale view coords → image pixel coords (points × (pixels/points) = pixels)
        let scaleX = imgW / viewSize.width
        let scaleY = imgH / viewSize.height

        // The region of the source image that maps to (loupeSize / magnification) view-points
        let captureSize = loupeSize / magnification
        let imgCaptureW = captureSize * scaleX
        let imgCaptureH = captureSize * scaleY

        let imgX = (touchLocation.x * scaleX) - imgCaptureW / 2
        let imgY = (touchLocation.y * scaleY) - imgCaptureH / 2

        let cropRect = CGRect(
            x: max(0, imgX),
            y: max(0, imgY),
            width:  min(imgCaptureW, imgW - max(0, imgX)),
            height: min(imgCaptureH, imgH - max(0, imgY))
        )

        // Crop the image (CGImage pixel space — matches cropRect correctly now)
        if let cgCrop = cgSrc.cropping(to: cropRect) {
            let cropped = UIImage(cgImage: cgCrop,
                                  scale: image.scale,
                                  orientation: image.imageOrientation)
            return AnyView(
                Image(uiImage: cropped)
                    .resizable()
                    .scaledToFill()
            )
        }

        return AnyView(Color.clear)
    }
}
