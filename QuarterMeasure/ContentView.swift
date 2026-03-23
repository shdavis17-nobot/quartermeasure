import SwiftUI
import Vision

// MARK: - Modern Window Access
extension UIWindow {
    static var current: UIWindow? {
        UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .map { $0 as? UIWindowScene }
            .compactMap { $0 }
            .first?.windows
            .filter { $0.isKeyWindow }
            .first
    }
}

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var visionDetector = VisionDetector()
    @StateObject private var motionManager = MotionManager()
    @StateObject private var storeManager = StoreManager()

    // UI State
    @State private var hasFrozenImage = false
    @State private var capturedImage: UIImage? = nil
    
    // Measurement State
    @State private var startPoint: CGPoint = .zero
    @State private var endPoint: CGPoint = .zero
    @State private var isDragging = false
    @State private var hasMeasurement = false
    @State private var selectedRef: ReferenceObject = .quarter
    @State private var selectedUnit: MeasurementUnit = .imperial
    @State private var showSettings = false
    @State private var cachedAnnotatedImage: UIImage? = nil
    @State private var zoomLevel: CGFloat = 1.0
    @GestureState private var magnifyBy = 1.0

    private let pinHapticTrigger = UISelectionFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            ZStack(alignment: .top) {
                // 1. The Visual Core
                ZStack {
                    if hasFrozenImage, let img = cameraManager.capturedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        CameraPreviewView(cameraManager: cameraManager)
                            .onAppear {
                                // 35B ARCHITECT: Setup reactive reference sync
                                visionDetector.currentReference = selectedRef
                                cameraManager.cvPixelBufferHandler = { [weak visionDetector] buf in
                                    visionDetector?.detectQuarter(in: buf)
                                }
                            }
                            .onChange(of: selectedRef) { oldValue, newValue in
                                visionDetector.currentReference = newValue
                            }
                    }
                }
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    MagnificationGesture()
                        .updating($magnifyBy) { value, state, _ in
                            state = value
                        }
                        .onChanged { value in
                            let nextZoom = zoomLevel * value
                            cameraManager.setZoom(factor: nextZoom)
                        }
                        .onEnded { value in
                            zoomLevel *= value
                        }
                )
                .onTapGesture { location in
                    guard !hasFrozenImage else { return }
                    visionDetector.assistDetection(at: location, in: size, image: nil, reference: selectedRef, pitch: motionManager.pitch, roll: motionManager.roll)
                }
                
                // 2. The Interaction Layer (ONLY if frozen)
                if hasFrozenImage {
                    Color.white.opacity(0.001) 
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if !isDragging {
                                        startPoint = value.startLocation
                                        isDragging = true
                                        hasMeasurement = false
                                    }
                                    endPoint = value.location
                                }
                                .onEnded { value in
                                    let dragDist = hypot(value.translation.width, value.translation.height)
                                    if dragDist < 15 {
                                        if let img = cameraManager.capturedImage {
                                            visionDetector.assistDetection(at: value.location, in: size, image: img, reference: selectedRef, pitch: motionManager.pitch, roll: motionManager.roll)
                                        }
                                    } else {
                                        finalizeMeasurement(at: value.location, in: size)
                                    }
                                }
                        )
                        .onTapGesture { location in
                            if let img = cameraManager.capturedImage {
                                visionDetector.assistDetection(at: location, in: size, image: img, reference: selectedRef, pitch: motionManager.pitch, roll: motionManager.roll)
                            }
                        }
                }

                // 3. Overlays
                Group {
                    if visionDetector.quarterDetected {
                        VisionOverlay(box: visionDetector.quarterBoundingBox, viewSize: size, reference: selectedRef)
                    }

                    if isDragging || hasMeasurement {
                        if sqrt(pow(motionManager.pitch, 2) + pow(motionManager.roll, 2)) > 82.0 {
                            Text("⚠️ Angle too shallow for precision")
                                .font(.caption2)
                                .foregroundColor(.black)
                                .padding(4)
                                .background(Color.yellow)
                                .cornerRadius(4)
                                .padding(.top, 40)
                                .zIndex(5)
                        }
                        MeasurementOverlay(start: startPoint, end: endPoint, label: measurementLabel)
                    }
                    
                    if visionDetector.isAssistantScanning, let tapPt = visionDetector.assistantPoint {
                        FocusReticle(point: tapPt)
                    }
                    
                    VStack {
                        topBar
                        Spacer()
                        if !hasFrozenImage {
                            VStack {
                                zoneBadge
                                if cameraManager.currentZoom < 1.0 {
                                    Text("Center objects for best 0.5x accuracy")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(4)
                                        .background(.black.opacity(0.4), in: Capsule())
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        bottomBar
                    }
                }
                .allowsHitTesting(!isDragging)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func finalizeMeasurement(at point: CGPoint, in size: CGSize) {
        let processPoint: (EdgeDetector.SnapResult) -> Void = { result in
            DispatchQueue.main.async {
                endPoint = result.point
                isDragging = false
                hasMeasurement = true
            }
            
            // Haptic Feedback based on confidence
            if result.confidence > 0.8 {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
            } else {
                pinHapticTrigger.selectionChanged()
            }
            
            if let img = cameraManager.capturedImage {
                cachedAnnotatedImage = ExportRenderer.render(
                    source: img,
                    startPoint: startPoint,
                    endPoint: endPoint,
                    viewSize: size,
                    label: measurementLabel
                )
            }
        }
        
        if let img = cameraManager.capturedImage {
            EdgeDetector.snap(point: point, in: size, image: img, completion: processPoint)
        } else {
            // No image, simple snap
            processPoint(EdgeDetector.SnapResult(point: point, confidence: 0))
        }
    }

    // MARK: - Subviews
    private var topBar: some View {
        HStack {
            Button(action: { /* Share Logic */ }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3).padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text("QuarterMeasure").font(.headline.bold())
            Spacer()
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title3).padding()
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal).padding(.top, 44)
    }

    private var bottomBar: some View {
        VStack(spacing: 20) {
            // Reference Switcher
            Picker("Reference", selection: $selectedRef) {
                ForEach(ReferenceObject.allCases) { ref in
                    Label(ref.rawValue, systemImage: ref.symbolName).tag(ref)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            HStack(spacing: 20) {
                // Freeze Button
                Button(action: {
                    if hasFrozenImage {
                        hasFrozenImage = false
                        hasMeasurement = false
                        visionDetector.quarterDetected = false
                    } else {
                        cameraManager.capturePhoto { _ in }
                        hasFrozenImage = true
                    }
                }) {
                    Circle()
                        .fill(hasFrozenImage ? Color.red : Color.white)
                        .frame(width: 60, height: 60)
                        .overlay(Image(systemName: hasFrozenImage ? "arrow.counterclockwise" : "camera.fill")
                            .foregroundColor(hasFrozenImage ? .white : .black))
                        .shadow(radius: 10)
                }
                
                if hasFrozenImage {
                    // Unit Switcher
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(MeasurementUnit.allCases) { u in
                            Text(u.rawValue).tag(u)
                        }
                    }
                    .pickerStyle(.menu)
                    .background(.ultraThinMaterial, in: Capsule())
                } else {
                    // Zoom Presets
                    HStack(spacing: 12) {
                        ZoomButton(label: "0.5x", zoom: 0.5, current: cameraManager.currentZoom) {
                            cameraManager.setZoom(factor: 0.5)
                        }
                        ZoomButton(label: "1x", zoom: 1.0, current: cameraManager.currentZoom) {
                            cameraManager.setZoom(factor: 1.0)
                        }
                        ZoomButton(label: "2x", zoom: 2.0, current: cameraManager.currentZoom) {
                            cameraManager.setZoom(factor: 2.0)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.bottom, 34)
        }
        .padding(.top, 20)
        .background(.ultraThinMaterial)
    }

    private var zoneBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: motionManager.levelZone == .green ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(motionManager.levelZone == .green ? "Level" : "Level Phone")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundColor(motionManager.levelZone == .green ? .green : .yellow)
    }

    private var measurementLabel: String {
        let pixels = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        let isAIDetected = visionDetector.quarterDetected && visionDetector.quarterBoundingBox.width > 0
        
        // CALIBRATION MASTER FIX: Correctly map Vision 0-1 to logical screen points
        let screen = UIWindow.current?.windowScene?.screen.bounds.size ?? CGSize(width: 393, height: 852) // fallback to standard iPhone 15 size
        
        // How much wider is the image compared to the screen?
        let scale = screen.height / 1920.0
        let scaledImageWidth = 1080.0 * scale
        
        let refPixels: CGFloat
        if isAIDetected {
            let box = visionDetector.quarterBoundingBox
            // Use the physical width in points (before crop) as the reference
            refPixels = max(box.width * scaledImageWidth, box.height * screen.height)
        } else {
            refPixels = 210.0 // Adjusted for typical 10" iPhone handheld height
        }
            
        let rawVal = MeasurementEngine.measure(
            pixelDistance: pixels,
            refPixelSize: refPixels,
            reference: selectedRef,
            unit: selectedUnit,
            pitch: motionManager.pitch,
            roll: motionManager.roll
        )
        
        return (isAIDetected ? "±" : "~") + " " + rawVal
    }
}

// MARK: - Overlay Subviews
struct VisionOverlay: View {
    let box: CGRect
    let viewSize: CGSize
    let reference: ReferenceObject
    
    @State private var pulse = 1.0
    
    var body: some View {
        let screen = UIWindow.current?.windowScene?.screen.bounds.size ?? CGSize(width: 393, height: 852)
        let scale = screen.height / 1920.0
        let scaledWidth = 1080.0 * scale
        let offsetX = (scaledWidth - screen.width) / 2.0
        
        // PORTRAIT ALIGNMENT: 35B Calibration
        let rect = CGRect(
            x: (box.origin.x * scaledWidth) - offsetX,
            y: (1.0 - box.origin.y - box.size.height) * screen.height,
            width: box.size.width * scaledWidth,
            height: box.size.height * screen.height
        )
        
        ZStack(alignment: .topLeading) {
            // Glassmorphic Pulse Layer
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.green.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green, lineWidth: 3)
                        .shadow(color: .green.opacity(0.4), radius: 6 * pulse)
                )
                .scaleEffect(0.98 + (0.04 * pulse))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = 1.2 }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            
            Text(reference.rawValue)
                .font(.caption2.bold())
                .padding(4)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 4))
                .offset(x: rect.minX, y: rect.minY - 20)
        }
    }
}

struct FocusReticle: View {
    let point: CGPoint
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: animate ? 40 : 80, height: animate ? 40 : 80)
            
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 10, height: 10)
        }
        .position(point)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: animate)
        .onAppear { animate = true }
    }
}

struct MeasurementOverlay: View {
    let start: CGPoint
    let end: CGPoint
    let label: String
    
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [5]))
            
            Circle().fill(Color.yellow).frame(width: 8, height: 8).position(start)
            Circle().fill(Color.yellow).frame(width: 8, height: 8).position(end)
            
            Text(label)
                .font(.caption.bold())
                .padding(4)
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
                .foregroundColor(.black)
                .position(x: (start.x + end.x)/2, y: (start.y + end.y)/2 - 15)
        }
    }
}

// MARK: - Reusable Components
struct ZoomButton: View {
    let label: String
    let zoom: CGFloat
    let current: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .padding(10)
                .background(abs(current - zoom) < 0.05 ? Color.blue : Color.black.opacity(0.4))
                .foregroundColor(.white)
                .clipShape(Circle())
        }
    }
}
