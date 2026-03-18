import SwiftUI
import PhotosUI
import CoreGraphics

struct ContentView: View {
    @EnvironmentObject var storeManager: StoreManager
    @EnvironmentObject var appearanceManager: AppearanceManager

    @StateObject private var cameraManager  = CameraManager()
    @StateObject private var visionDetector = VisionDetector()
    @StateObject private var motionManager  = MotionManager()

    // Measurement
    @State private var startPoint: CGPoint   = .zero
    @State private var endPoint: CGPoint     = .zero
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging   = false
    @State private var hasMeasurement = false

    // User prefs
    @State private var selectedRef: ReferenceObject  = .quarter
    @State private var selectedUnit: MeasurementUnit = .imperial

    // UI
    @State private var showSettings = false
    @State private var viewSize: CGSize = .zero

    // PhotosPicker
    @State private var pickerItem: PhotosPickerItem? = nil

    // Haptics
    @State private var detectionHapticTrigger = false
    @State private var pinHapticTrigger       = false

    // MARK: Computed
    private var distancePts: CGFloat {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        return sqrt(dx * dx + dy * dy)
    }

    private var refPixelSize: CGFloat {
        guard visionDetector.quarterDetected else { return 0 }
        return visionDetector.quarterBoundingBox.width * viewSize.width
    }

    private var measurementLabel: String {
        guard hasMeasurement else { return "—" }
        if refPixelSize > 0 {
            return MeasurementEngine.measure(
                pixelDistance: distancePts,
                refPixelSize: refPixelSize,
                reference: selectedRef,
                unit: selectedUnit
            )
        }
        return MeasurementEngine.formatPoints(distancePts)
    }

    private var canCapture: Bool { !motionManager.isLocked }
    private var canPin:     Bool { !motionManager.isLocked }

    // MARK: Body
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Background (live or frozen)
                    backgroundLayer.edgesIgnoringSafeArea(.all)

                    // Live viewfinder overlays
                    if !cameraManager.isFrozen {
                        // Bullseye reticle
                        LevelReticleView(zone: motionManager.levelZone)

                        // Zone badge
                        zoneBadge
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 16)
                    }

                    // Bounding box
                    if visionDetector.quarterDetected && !visionDetector.quarterBoundingBox.isEmpty {
                        boundingBoxOverlay(in: geo.size)
                    }

                    // Measurement overlay (frozen only)
                    if cameraManager.isFrozen {
                        measurementOverlay(in: geo.size)
                    }

                    // Bottom HUD
                    VStack {
                        Spacer()
                        if cameraManager.isFrozen { frozenBottomBar } else { liveBottomBar }
                    }
                }
                .onAppear { viewSize = geo.size }
                .onChange(of: geo.size) { _, s in viewSize = s }
            }
            .navigationTitle("QuarterMeasure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(storeManager)
                    .environmentObject(appearanceManager)
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    guard let item,
                          let data  = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    await MainActor.run {
                        cameraManager.capturedImage = image
                        cameraManager.isFrozen = true
                        resetMeasurement()
                    }
                    visionDetector.detectQuarter(in: image)
                }
            }
        }
        // Haptics
        .sensoryFeedback(.success, trigger: detectionHapticTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: pinHapticTrigger)
        // Level-achieved tick haptic (from MotionManager)
        .sensoryFeedback(.selection, trigger: motionManager.levelAchievedTick)
        .onChange(of: visionDetector.quarterDetected) { _, detected in
            if detected { detectionHapticTrigger.toggle() }
        }
    }

    // MARK: - Background
    @ViewBuilder
    private var backgroundLayer: some View {
        if let frozen = cameraManager.capturedImage {
            Image(uiImage: frozen)
                .resizable()
                .scaledToFill()
                .onAppear { cameraManager.cvPixelBufferHandler = nil }
        } else {
            CameraPreviewView(cameraManager: cameraManager)
                .onAppear {
                    cameraManager.cvPixelBufferHandler = { buf in
                        visionDetector.detectQuarter(in: buf)
                    }
                }
        }
    }

    // MARK: - Zone Badge (live mode)
    @ViewBuilder
    private var zoneBadge: some View {
        switch motionManager.levelZone {
        case .green:
            EmptyView()
        case .warning:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                Text("Tilt Detected").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        case .locked:
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").foregroundColor(.red)
                Text("Too Tilted — Level Phone").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Bounding Box
    private func boundingBoxOverlay(in size: CGSize) -> some View {
        let box = visionDetector.quarterBoundingBox
        let rect = CGRect(
            x:      box.minX * size.width,
            y:      (1 - box.maxY) * size.height,
            width:  box.width  * size.width,
            height: box.height * size.height
        )
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.green, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            Text(selectedRef.rawValue)
                .font(.caption2.bold())
                .foregroundColor(.black)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green, in: Capsule())
                .offset(x: rect.minX, y: rect.minY - 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Measurement Overlay
    private func measurementOverlay(in size: CGSize) -> some View {
        Color.white.opacity(0.001)
            .edgesIgnoringSafeArea(.all)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canPin else { return }
                        if !isDragging {
                            startPoint = value.startLocation
                            isDragging = true
                            hasMeasurement = false
                        }
                        dragLocation = value.location
                    }
                    .onEnded { value in
                        guard canPin else { return }
                        if let img = cameraManager.capturedImage {
                            endPoint = EdgeDetector.snap(point: value.location, in: size, image: img)
                        } else {
                            endPoint = value.location
                        }
                        isDragging = false
                        hasMeasurement = true
                        pinHapticTrigger.toggle()
                    }
            )
            .overlay {
                if isDragging || hasMeasurement {
                    let lineEnd = isDragging ? dragLocation : endPoint
                    ZStack {
                        Path { path in
                            path.move(to: startPoint)
                            path.addLine(to: lineEnd)
                        }
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6]))

                        Circle().fill(Color.yellow).frame(width: 10, height: 10).position(startPoint)

                        if isDragging {
                            // Real pixel-accurate loupe
                            MagnifierView(
                                touchLocation: dragLocation,
                                isVisible: true,
                                sourceImage: cameraManager.capturedImage,
                                viewSize: size
                            )
                        } else {
                            Circle().fill(Color.yellow).frame(width: 10, height: 10).position(endPoint)
                        }
                    }
                }
            }
    }

    // MARK: - Live Bottom Bar
    private var liveBottomBar: some View {
        VStack(spacing: 12) {
            // Reference picker
            Picker("Reference", selection: $selectedRef) {
                ForEach(ReferenceObject.allCases) { ref in
                    Label(ref.rawValue, systemImage: ref.symbolName).tag(ref)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            // Detection status
            HStack(spacing: 6) {
                Circle().fill(visionDetector.quarterDetected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(visionDetector.quarterDetected
                     ? "\(selectedRef.rawValue) Detected"
                     : "Align \(selectedRef.rawValue) in Frame")
                .font(.subheadline)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            // Shutter — disabled when locked
            Button {
                cameraManager.capturePhoto { img in
                    if let img { visionDetector.detectQuarter(in: img) }
                }
            } label: {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.5), lineWidth: 3).frame(width: 72, height: 72)
                    Circle().fill(shutterFill).frame(width: 60, height: 60)
                }
            }
            .disabled(motionManager.isLocked)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Frozen Bottom Bar
    private var frozenBottomBar: some View {
        VStack(spacing: 10) {
            if hasMeasurement {
                if storeManager.isProUnlocked {
                    HStack(spacing: 14) {
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(MeasurementUnit.allCases) { u in Text(u.rawValue).tag(u) }
                        }
                        .pickerStyle(.segmented).frame(width: 100)

                        Text(measurementLabel)
                            .font(.title2.monospacedDigit().bold())

                        if let img = cameraManager.capturedImage {
                            let annotated = ExportRenderer.render(
                                source: img,
                                startPoint: startPoint,
                                endPoint: endPoint,
                                viewSize: viewSize,
                                label: measurementLabel
                            )
                            ShareLink(
                                item: Image(uiImage: annotated),
                                preview: SharePreview("QuarterMeasure", image: Image(uiImage: annotated))
                            ) {
                                Image(systemName: "square.and.arrow.up").font(.title2)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    Button { showSettings = true } label: {
                        Label("Unlock Pro to see measurement", systemImage: "lock.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            } else {
                Text("Drag to measure")
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if cameraManager.isFrozen {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    cameraManager.retake()
                    resetMeasurement()
                } label: { Label("Retake", systemImage: "arrow.counterclockwise") }
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
    }

    // MARK: - Helpers
    private var shutterFill: Color {
        switch motionManager.levelZone {
        case .locked:  return .gray
        case .warning: return .yellow
        case .green:   return visionDetector.quarterDetected ? .green : .white
        }
    }

    private func resetMeasurement() {
        isDragging = false; hasMeasurement = false
        startPoint = .zero; endPoint = .zero; dragLocation = .zero
    }
}
