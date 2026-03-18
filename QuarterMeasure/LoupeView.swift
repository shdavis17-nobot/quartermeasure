import SwiftUI

struct LoupeView: View {
    var touchLocation: CGPoint
    
    var body: some View {
        GeometryReader { geometry in
            Circle()
                .stroke(Color.primary, lineWidth: 2)
                .background(
                    Circle()
                        .fill(Color.clear)
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Group {
                        Rectangle().frame(width: 1, height: 10)
                        Rectangle().frame(width: 10, height: 1)
                    }
                    .foregroundColor(.red)
                )
                // Offset above finger to make it visible
                .position(x: touchLocation.x, y: touchLocation.y - 60)
        }
        .allowsHitTesting(false)
    }
}