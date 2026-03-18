import SwiftUI

/// Bullseye/Crosshair level reticle overlay shown in the live camera viewfinder.
/// Color reflects the 3-zone accuracy guard state.
struct LevelReticleView: View {
    let zone: LevelZone

    private var zoneColor: Color {
        switch zone {
        case .green:   return Color(red: 0.2, green: 1.0, blue: 0.4)   // Neon green
        case .warning: return .yellow
        case .locked:  return .red
        }
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(zoneColor.opacity(0.55), lineWidth: 1)
                .frame(width: 72, height: 72)

            // Mid ring
            Circle()
                .stroke(zoneColor.opacity(0.75), lineWidth: 1)
                .frame(width: 36, height: 36)

            // Center dot
            Circle()
                .fill(zoneColor)
                .frame(width: 5, height: 5)

            // Hairlines — top / bottom / left / right gaps (crosses, not solid lines)
            Group {
                // Vertical
                Rectangle()
                    .frame(width: 1, height: 20)
                    .offset(y: -48)
                Rectangle()
                    .frame(width: 1, height: 20)
                    .offset(y: 48)
                // Horizontal
                Rectangle()
                    .frame(width: 20, height: 1)
                    .offset(x: -48)
                Rectangle()
                    .frame(width: 20, height: 1)
                    .offset(x: 48)
            }
            .foregroundColor(zoneColor.opacity(0.85))
        }
        .animation(.easeInOut(duration: 0.2), value: zone)
        .allowsHitTesting(false)
    }
}
