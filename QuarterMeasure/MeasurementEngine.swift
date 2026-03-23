import Foundation
import CoreGraphics

// MARK: - Reference Objects

enum ReferenceObject: String, CaseIterable, Identifiable {
    case quarter     = "Quarter"
    case penny       = "Penny"
    case nickel      = "Nickel"
    case creditCard  = "Credit Card"

    var id: String { rawValue }

    /// Real-world diameter or longest dimension in inches
    var realWorldInches: Double {
        switch self {
        case .quarter:    return 0.955
        case .penny:      return 0.750
        case .nickel:     return 0.835
        case .creditCard: return 3.370   // width of a standard ISO credit card
        }
    }

    var symbolName: String {
        switch self {
        case .quarter:    return "dollarsign.circle"
        case .penny:      return "centsign.circle"
        case .nickel:     return "n.circle"
        case .creditCard: return "creditcard"
        }
    }
}

// MARK: - Measurement Units

enum MeasurementUnit: String, CaseIterable, Identifiable {
    case imperial = "in"
    case metric   = "cm"
    var id: String { rawValue }
}

// MARK: - Engine

struct MeasurementEngine {
    /// Converts a pixel distance into real-world inches, then to the selected unit.
    /// - Parameters:
    ///   - pixelDistance: Distance in screen points between the two measurement pins.
    ///   - refPixelSize: The bounding box width (in screen points) of the detected reference object.
    ///   - reference: The reference object the user placed in frame.
    ///   - unit: Desired output unit.
    /// - Returns: Formatted measurement string, e.g. "3.50 in" or "8.89 cm"
    static func measure(
        pixelDistance: CGFloat,
        refPixelSize: CGFloat,
        reference: ReferenceObject,
        unit: MeasurementUnit,
        pitch: Double = 0.0,
        roll: Double = 0.0
    ) -> String {
        guard refPixelSize > 0 else { return "—" }
        
        // 35B ARCHITECT: Simplified to Pure Ratio.
        // Reason: Coplanar objects (sitting on the same table) scale equally with tilt.
        // The ratio of (measured_pixels / reference_pixels) is inherently tilt-invariant.
        let inches = (pixelDistance / refPixelSize) * CGFloat(reference.realWorldInches)
        
        switch unit {
        case .imperial:
            return String(format: "%.2f in", inches)
        case .metric:
            let cm = inches * 2.54
            return cm >= 10
                ? String(format: "%.1f cm", cm)
                : String(format: "%.2f cm", cm)
        }
    }

    // Pixel-only fallback (no reference calibration yet)
    static func formatPoints(_ pts: CGFloat) -> String {
        String(format: "%.0f pt", pts)
    }
}
