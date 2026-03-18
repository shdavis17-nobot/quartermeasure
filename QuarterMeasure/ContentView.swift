import SwiftUI

struct ContentView: View {
    @EnvironmentObject var storeManager: StoreManager
    @EnvironmentObject var appearanceManager: AppearanceManager

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionDetector = VisionDetector()
    @StateObject private var motionManager = MotionManager()

    // Measurement state
    @State private var startPoint: CGPoint = .zero
    @State private var endPoint: CGPoint = .zero
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging = false
    @State private var hasMeasurement = false

    // UI state
    @State private var showSettings = false

    // Haptic triggers
    @State private var detectionHapticTrigger = false
    @State private var pinHapticTrigger = false

    private var distancePts: CGFloat {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        return sqrt(dx * dx + dy * dy)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // MARK: Background
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

                // MARK: UI Overlays
                VStack {
                    Spacer()

                    if cameraManager.isFrozen {
                        frozenBottomBar
                    } else {
                        liveBottomBar
                    }
                }

                // MARK: Measurement overlay (frozen mode)
                if cameraManager.isFrozen {
                    measurementOverlay
                }
            }
            .navigationTitle("QuarterMeasure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Retake (frozen mode)
                if cameraManager.isFrozen {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            cameraManager.retake()
                            resetMeasurement()
                        } label: {
                            Label("Retake", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                // Settings gear
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(storeManager)
                    .environmentObject(appearanceManager)
            }
        }
        // Haptics
        .sensoryFeedback(.success, trigger: detectionHapticTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: pinHapticTrigger)
        .onChange(of: visionDetector.quarterDetected) { _, detected in
            if detected { detectionHapticTrigger.toggle() }
        }
    }

    // MARK: - Live Bottom Bar
    private var liveBottomBar: some View {
        VStack(spacing: 12) {
            // Detection status
            HStack(spacing: 6) {
                Circle()
                    .fill(visionDetector.quarterDetected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(visionDetector.quarterDetected ? "Quarter Detected" : "Align Quarter in Frame")
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            // Level indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(motionManager.isLevel ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(motionManager.isLevel ? "Level ✓" : "Tilt phone until level")
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            // Shutter button
            Button {
                cameraManager.capturePhoto { image in
                    if let img = image {
                        visionDetector.detectQuarter(in: img)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.5), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(shutterFill)
                        .frame(width: 60, height: 60)
                }
            }
            .disabled(!motionManager.isLevel)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Frozen Bottom Bar
    private var frozenBottomBar: some View {
        VStack(spacing: 8) {
            if hasMeasurement {
                if storeManager.isProUnlocked {
                    // Pro: show real label + export
                    HStack(spacing: 12) {
                        Text(String(format: "%.0f pt", distancePts))
                            .font(.title2.monospacedDigit().bold())
                        if let image = cameraManager.capturedImage,
                           let data = image.jpegData(compressionQuality: 0.9) {
                            ShareLink(
                                item: data,
                                preview: SharePreview(
                                    "QuarterMeasure Photo",
                                    image: Image(uiImage: image)
                                )
                            ) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    // Free: blur / gate the label
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Unlock Pro to see measurement")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            } else {
                Text("Drag to measure")
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Measurement Overlay
    private var measurementOverlay: some View {
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
                        pinHapticTrigger.toggle()
                    }
            )
            .overlay(
                Group {
                    if isDragging || hasMeasurement {
                        let lineEnd = isDragging ? dragLocation : endPoint
                        ZStack {
                            // Measurement line
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

                            // End — magnifier while dragging, pin when dropped
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
            )
    }

    // MARK: - Helpers
    private var shutterFill: Color {
        guard motionManager.isLevel else { return .gray }
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
