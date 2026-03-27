import Foundation
import Combine
import CoreMotion

// MARK: - Level Zone
enum LevelZone: Equatable {
    case green    // ±12.0° — Handheld friendly
    case warning  // 12.0°–24.0° — Caution
    case locked   // >24.0° — Critical tilt
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

    // Very aggressive low-pass filter alpha for 'Zen' steadiness
    private let filterAlpha: Double = 0.08

    private let greenThreshold:   Double = 12.0
    private let warningThreshold: Double = 24.0
    private let hysteresis:       Double = 4.0

    init() { }

    func start() {
        startDeviceMotion()
    }

    private func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else { 
            print("[MotionManager] Device motion unavailable")
            return 
        }

        print("[MotionManager] Starting filtered gravity updates...")
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }

            // Math Fix: Calculate tilt relative to the Z-axis (screen normal).
            // When flat on a table, grav.z is -1.0. We want that to be 0 degrees of tilt.
            let grav = motion.gravity
            
            // atan2(component, abs(z)) gives the angle in degrees from 'vertical'
            // We use -grav.y because +Y is toward the top of the phone
            let rawPitch = atan2(-grav.y, abs(grav.z)) * 180 / .pi
            let rawRoll  = atan2(grav.x,  abs(grav.z)) * 180 / .pi

            // Simple Low-Pass Filter to eliminate jitter
            self.pitch = (self.filterAlpha * rawPitch) + ((1.0 - self.filterAlpha) * self.pitch)
            self.roll  = (self.filterAlpha * rawRoll)  + ((1.0 - self.filterAlpha) * self.roll)

            // Total tilt magnitude from absolute level
            let totalTilt = acos(max(-1.0, min(1.0, -grav.z))) * 180 / .pi
            let maxTilt = totalTilt // More accurate for a bullseye reticle than max(p, r)

            let previousZone = self.levelZone
            var newZone = previousZone

            switch previousZone {
            case .green:
                if maxTilt > (self.greenThreshold + self.hysteresis) {
                    newZone = (maxTilt > self.warningThreshold) ? .locked : .warning
                }
            case .warning:
                if maxTilt <= self.greenThreshold {
                    newZone = .green
                } else if maxTilt > (self.warningThreshold + self.hysteresis) {
                    newZone = .locked
                }
            case .locked:
                if maxTilt <= self.greenThreshold {
                    newZone = .green
                } else if maxTilt <= self.warningThreshold {
                    newZone = .warning
                }
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
