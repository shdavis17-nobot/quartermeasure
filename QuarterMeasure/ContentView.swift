import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storeManager: StoreManager
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionDetector = VisionDetector()
    @StateObject private var motionManager = MotionManager()

    // Measurement state
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var startPoint: CGPoint = .zero
    @State private var endPoint: CGPoint = .zero
    @State private var hasMeasurement: Bool = false

    // Computed distance in display points
    private var distancePts: CGFloat {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        return sqrt(dx*dx + dy*dy)
    }

    var body: some View {
        ZStack {
            // MARK: Background — live feed or frozen photo
            if let frozen = cameraManager.capturedImage {
                Image(uiImage: frozen)
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)
            } else {
                CameraPreviewView(cameraManager: cameraManager)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        cameraManager.cvPixelBufferHandler = { pixelBuffer in
                            visionDetector.detectQuarter(in: pixelBuffer)
                        }
                    }
            }

            // MARK: Top Bar
            VStack {
                HStack {
                    // Pro unlock button
                    if !storeManager.isProUnlocked {
                        Button {
                            Task {
                                if let product = storeManager.products.first {
                                    try? await storeManager.purchase(product)
                                }
                            }
                        } label: {
                            Label("Unlock Pro – $0.99", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.85), in: Capsule())
                                .foregroundColor(.white)
                        }
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.yellow)
                            .font(.title2)
                    }
                    Spacer()

                    // Retake button (only in frozen mode)
                    if cameraManager.isFrozen {
                        Button {
                            cameraManager.retake()
                            resetMeasurement()
                        } label: {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.top, 54)
                .padding(.horizontal, 16)

                Spacer()

                // MARK: Bottom controls
                if cameraManager.isFrozen {
                    // Frozen photo — show measurement hint
                    VStack(spacing: 6) {
                        if hasMeasurement {
                            Text(String(format: "%.0f pts (drag to adjust)", distancePts))
                                .font(.headline)
                                .foregroundColor(.yellow)
                        } else {
                            Text("Drag to measure")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 30)

                } else {
                    // Live view — detection status + level + shutter
                    VStack(spacing: 12) {
                        // Quarter detection pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(visionDetector.quarterDetected ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            Text(visionDetector.quarterDetected ? "Quarter Detected" : "Align Quarter in Frame")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())

                        // Level indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(motionManager.isLevel ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(motionManager.isLevel ? "Level ✓" : "Tilt phone until level")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())

                        // Shutter button — only enabled when level and quarter detected
                        Button {
                            cameraManager.capturePhoto { image in
                                if let img = image {
                                    visionDetector.detectQuarter(in: img)
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 70, height: 70)
                                Circle()
                                    .fill(shutterColor)
                                    .frame(width: 58, height: 58)
                            }
                        }
                        .disabled(!motionManager.isLevel)
                        .padding(.bottom, 30)
                    }
                }
            }

            // MARK: Measurement overlay (frozen mode only)
            if cameraManager.isFrozen {
                // Invisible drag layer
                Color.white.opacity(0.001)
                    .edgesIgnoringSafeArea(.all)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    startPoint = value.startLocation
                                    isDragging = true
                                    hasMeasurement = false
                                }
                                dragLocation = value.location
                            }
                            .onEnded { value in
                                endPoint = value.location
                                isDragging = false
                                hasMeasurement = true
                            }
                    )

                // Measurement line
                if isDragging || hasMeasurement {
                    let lineEnd = isDragging ? dragLocation : endPoint
                    Path { path in
                        path.move(to: startPoint)
                        path.addLine(to: lineEnd)
                    }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6]))

                    // Start pin
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 10, height: 10)
                        .position(startPoint)

                    // End pin / magnifier while dragging
                    if isDragging {
                        MagnifierView(touchLocation: dragLocation, isVisible: true)
                    } else {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 10, height: 10)
                            .position(endPoint)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Helpers
    private var shutterColor: Color {
        if !motionManager.isLevel { return .gray }
        return visionDetector.quarterDetected ? .green : .white
    }

    private func resetMeasurement() {
        isDragging = false
        hasMeasurement = false
        startPoint = .zero
        endPoint = .zero
        dragLocation = .zero
    }
}
