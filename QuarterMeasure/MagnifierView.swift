import SwiftUI

struct MagnifierView: View {
    var touchLocation: CGPoint
    var isVisible: Bool
    
    var body: some View {
        Group {
            if isVisible {
                Circle()
                    .stroke(Color.primary, lineWidth: 2)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
                    .frame(width: 90, height: 90)
                    .overlay(
                        Group {
                            Rectangle().frame(width: 1, height: 12)
                            Rectangle().frame(width: 12, height: 1)
                        }
                        .foregroundColor(.red)
                    )
                    // Offset above finger to make it visible
                    .position(x: touchLocation.x, y: touchLocation.y - 70)
                    .shadow(radius: 5)
            }
        }
        .allowsHitTesting(false)
    }
}