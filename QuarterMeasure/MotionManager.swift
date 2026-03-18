import Foundation
import Combine
import CoreMotion

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var isLevel: Bool = false
    
    init() {
        startDeviceMotion()
    }
    
    func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }
            
            self.pitch = motion.attitude.pitch * 180 / .pi
            self.roll = motion.attitude.roll * 180 / .pi
            
            let isPitchLevel = abs(self.pitch) < 3.0
            let isRollLevel = abs(self.roll) < 3.0
            
            self.isLevel = isPitchLevel && isRollLevel
        }
    }
    
    func stopDeviceMotion() {
        motionManager.stopDeviceMotionUpdates()
    }
}