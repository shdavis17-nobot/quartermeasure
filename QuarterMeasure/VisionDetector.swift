import Foundation
import Combine
import Vision
import CoreVideo

class VisionDetector: ObservableObject {
    @Published var quarterDetected: Bool = false
    @Published var distanceToQuarter: CGFloat = 0.0
    
    let quarterDiameterInches: CGFloat = 0.955
    
    func detectQuarter(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectContoursRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNContoursObservation],
                  let contourObserv = results.first else {
                DispatchQueue.main.async {
                    self?.quarterDetected = false
                }
                return
            }
            
            var foundQuarter = false
            
            for i in 0..<contourObserv.contourCount {
                do {
                    let contour = try contourObserv.contour(at: i)
                    let boundingBox = contour.normalizedPath.boundingBox
                    
                    let aspectRatio = boundingBox.width / boundingBox.height
                    // A quarter should be a perfect circle depending on camera angle
                    if aspectRatio > 0.85 && aspectRatio < 1.15 {
                        foundQuarter = true
                        break
                    }
                } catch {
                    continue
                }
            }
            
            DispatchQueue.main.async {
                self.quarterDetected = foundQuarter
            }
        }
        
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 512
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform vision request: \(error)")
        }
    }
}