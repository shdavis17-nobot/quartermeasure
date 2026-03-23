import Foundation
import Combine
import Vision
import CoreVideo
import UIKit
import CoreImage

class VisionDetector: ObservableObject {
    @Published var quarterDetected: Bool = false
    @Published var quarterBoundingBox: CGRect = .zero
    @Published var isAssistantScanning: Bool = false
    @Published var assistantPoint: CGPoint? = nil
    @Published var currentReference: ReferenceObject = .quarter
    
    // Core state for 35B Architect Precision
    var currentPitch: Double = 0.0
    var currentRoll: Double = 0.0
    private let ciContext = CIContext()
    
    let quarterDiameterInches: CGFloat = 0.955
    let creditCardWidthInches: CGFloat = 3.375
    
    private var liveROI: CGRect? = nil

    /// 1. ASSISTED DETECTION (Manual Tap)
    func assistDetection(at viewPoint: CGPoint, in viewSize: CGSize, image: UIImage?, reference: ReferenceObject, pitch: Double, roll: Double) {
        self.currentPitch = pitch
        self.currentRoll = roll
        
        DispatchQueue.main.async {
            self.assistantPoint = viewPoint
            self.isAssistantScanning = true
        }
        
        // Auto-reset reticle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isAssistantScanning = false 
        }
        
        // 35B ARCHITECT: Handle Live Tap vs Still Tap
        if let stillImage = image?.normalized() {
            let imgSize = stillImage.size
            let scale = max(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
            let scaledW = imgSize.width * scale
            let scaledH = imgSize.height * scale
            let offsetX = (scaledW - viewSize.width) / 2.0
            let offsetY = (scaledH - viewSize.height) / 2.0
            
            let normX = (viewPoint.x + offsetX) / scaledW
            let normY = 1.0 - ((viewPoint.y + offsetY) / scaledH)
            
            let roiSize: CGFloat = 0.55
            let roi = CGRect(x: normX - roiSize/2, y: normY - roiSize/2, width: roiSize, height: roiSize)
            
            if let cgImg = preprocess(stillImage, forCard: reference == .creditCard) {
                let handler = VNImageRequestHandler(cgImage: cgImg, orientation: .up, options: [:])
                performVisionScan(handler: handler, bufferSize: imgSize, roi: roi, reference: reference)
            }
        } else {
            // LIVE TAP: Set ROI for the next camera frame
            let normX = viewPoint.x / viewSize.width
            let normY = 1.0 - (viewPoint.y / viewSize.height)
            let roiSize: CGFloat = 0.45
            self.liveROI = CGRect(x: normX - roiSize/2, y: normY - roiSize/2, width: roiSize, height: roiSize)
        }
    }

    /// 2. LIVE DETECTION (Camera Loop)
    func detectQuarter(in buffer: CVPixelBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        let bufferSize = CGSize(width: width, height: height)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right, options: [:])
        performVisionScan(handler: handler, bufferSize: bufferSize, roi: self.liveROI, reference: self.currentReference)
        
        // Clear ROI if detected
        if quarterDetected { self.liveROI = nil }
    }

    private func performVisionScan(handler: VNImageRequestHandler, bufferSize: CGSize, roi: CGRect?, reference: ReferenceObject) {
        let request = VNDetectRectanglesRequest { [weak self] req, err in
            guard let self = self,
                  let results = req.results as? [VNRectangleObservation],
                  let top = results.filter({ self.isGeometryValid($0, bufferSize: bufferSize, reference: reference) }).first else {
                if roi == nil { DispatchQueue.main.async { self?.quarterDetected = false } }
                return
            }
            
            DispatchQueue.main.async {
                self.quarterBoundingBox = top.boundingBox
                self.quarterDetected = true
                self.isAssistantScanning = false
            }
        }
        
        request.minimumAspectRatio = 0.4
        request.maximumAspectRatio = 3.5
        request.maximumObservations = 5
        request.minimumConfidence = 0.65 // Block false positive background rectangles
        if let roi = roi { request.regionOfInterest = roi }
        
        try? handler.perform([request])
    }

    private func isGeometryValid(_ obs: VNRectangleObservation, bufferSize: CGSize, reference: ReferenceObject) -> Bool {
        // Because we pass .right, the VNObservation is based on width/height flipped.
        // We use the raw buffer size but orientation gives us height x width aspect map.
        let physicalWidth = obs.boundingBox.width * bufferSize.height
        let physicalHeight = obs.boundingBox.height * bufferSize.width
        let physicalAR = physicalWidth / max(1.0, physicalHeight)
        
        switch reference {
        case .quarter, .penny, .nickel:
            return abs(physicalAR - 1.0) < 0.25
        case .creditCard:
            let isHorizontal = abs(physicalAR - 1.58) < 0.40
            let isVertical = abs(physicalAR - 0.63) < 0.30
            return isHorizontal || isVertical
        }
    }

    private func preprocess(_ image: UIImage, forCard: Bool = false) -> CGImage? {
        guard let ciImg = CIImage(image: image) else { return image.cgImage }
        let contrast = forCard ? 1.75 : 1.15
        let exposure = forCard ? 0.45 : 0.2
        let filtered = ciImg
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
            .applyingFilter("CIContrastAdjust", parameters: ["inputContrast": contrast])
        return ciContext.createCGImage(filtered, from: filtered.extent)
    }

    func getCorrectionFactor() -> Double {
        let totalTiltDeg = sqrt(pow(currentPitch, 2) + pow(currentRoll, 2))
        let tiltRad = totalTiltDeg * .pi / 180.0
        if totalTiltDeg > 82.0 { return 7.18 }
        return 1.0 / max(0.14, cos(tiltRad))
    }
}

extension UIImage {
    func normalized() -> UIImage? {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}
