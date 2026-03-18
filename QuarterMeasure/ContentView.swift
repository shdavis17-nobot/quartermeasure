import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storeManager: StoreManager
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionDetector = VisionDetector()
    @StateObject private var motionManager = MotionManager()
    
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var distanceMeasure: CGFloat = 0.0
    @State private var startPoint: CGPoint = .zero
    
    var body: some View {
        ZStack {
            CameraPreviewView(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    cameraManager.cvPixelBufferHandler = { pixelBuffer in
                        visionDetector.detectQuarter(in: pixelBuffer)
                    }
                }
            
            VStack {
                HStack {
                    if !storeManager.isProUnlocked {
                        Button(action: {
                            Task {
                                if let product = storeManager.products.first {
                                    try? await storeManager.purchase(product)
                                }
                            }
                        }) {
                            Text("Unlock Pro - $0.99")
                                .font(.headline)
                                .padding()
                                .background(Color.blue.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .padding()
                    }
                    Spacer()
                }
                .padding(.top, 40)
                .padding(.horizontal)
                
                Spacer()
                
                // Quarter Detection UI
                if visionDetector.quarterDetected {
                    Text("Quarter Detected")
                        .font(.subheadline)
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                } else {
                    Text("Align Quarter")
                        .font(.subheadline)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                // Leveling UI
                HStack {
                    Circle()
                        .fill(motionManager.isLevel ? Color.green : Color.red)
                        .frame(width: 20, height: 20)
                    Text(motionManager.isLevel ? "Level" : "Not Level")
                        .foregroundColor(.white)
                        .font(.body)
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
                .padding(.bottom, 30)
            }
            
            // Interaction overlay for measuring
            Color.white.opacity(0.001) // Nearly invisible layer for hit testing
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                startPoint = value.startLocation
                                isDragging = true
                            }
                            dragLocation = value.location
                            // Calculate distance in points
                            let dx = dragLocation.x - startPoint.x
                            let dy = dragLocation.y - startPoint.y
                            distanceMeasure = sqrt(dx*dx + dy*dy)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            
            if isDragging {
                Path { path in
                    path.move(to: startPoint)
                    path.addLine(to: dragLocation)
                }
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5]))
                
                MagnifierView(touchLocation: dragLocation, isVisible: isDragging)
                
                Text(String(format: "%.1f pts", distanceMeasure))
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                    .position(x: dragLocation.x + 40, y: dragLocation.y)
            }
        }
        .preferredColorScheme(.dark)
    }
}