import Foundation
import Combine
import CoreMotion

// MARK: - Level Zone
enum LevelZone: Equatable {
    case green    // ±2.0° — safe to capture
    case warning  // 2.0°–5.0° — caution
    case locked   // >5.0° — capture / pin disabled
}

// MARK: - Motion Manager
class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published var pitch: Double = 0.0
    @Published var roll:  Double = 0.0
    @Published var levelZone: LevelZone = .locked

    // Haptic trigger — fires exactly once when transitioning into the green zone
    @Published var levelAchievedTick: Bool = false

    // Convenient computed booleans
    var isLevel:  Bool { levelZone == .green }
    var isLocked: Bool { levelZone == .locked }

    // Thresholds (degrees)
    private let greenThreshold:   Double = 2.0
    private let warningThreshold: Double = 5.0

    init() { startDeviceMotion() }

    func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0  // 30 Hz for smoother reticle
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let p = motion.attitude.pitch * 180 / .pi
            let r = motion.attitude.roll  * 180 / .pi

            self.pitch = p
            self.roll  = r

            let maxTilt = max(abs(p), abs(r))
            let previousZone = self.levelZone

            let newZone: LevelZone
            if maxTilt <= self.greenThreshold {
                newZone = .green
            } else if maxTilt <= self.warningThreshold {
                newZone = .warning
            } else {
                newZone = .locked
            }

            self.levelZone = newZone

            // Haptic tick exactly when reaching green for first time
            if newZone == .green && previousZone != .green {
                self.levelAchievedTick.toggle()
            }
        }
    }

    func stopDeviceMotion() {
        motionManager.stopDeviceMotionUpdates()
    }
}
