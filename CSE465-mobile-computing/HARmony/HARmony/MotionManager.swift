import Foundation
import Combine
import CoreMotion

/// Lightweight motion service reading accelerometer and gyro.
/// Designed to be extended later with windows/features.
final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    @Published private(set) var accel: CMAcceleration = .init(x: 0, y: 0, z: 0)
    @Published private(set) var gyro: CMRotationRate = .init(x: 0, y: 0, z: 0)
    @Published private(set) var timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate

    // Configure desired update interval (Hz)
    var updateInterval: TimeInterval = 1.0 / 50.0 { // 50 Hz default
        didSet {
            motionManager.accelerometerUpdateInterval = updateInterval
            motionManager.gyroUpdateInterval = updateInterval
        }
    }

    private init() {
        queue.qualityOfService = .userInitiated
        motionManager.accelerometerUpdateInterval = updateInterval
        motionManager.gyroUpdateInterval = updateInterval
    }

    func start() {
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let self = self, let data = data else { return }
                DispatchQueue.main.async {
                    self.accel = data.acceleration
                    self.timestamp = data.timestamp
                }
            }
        }
        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let self = self, let data = data else { return }
                DispatchQueue.main.async {
                    self.gyro = data.rotationRate
                    // prefer the latest timestamp among sensors
                    self.timestamp = max(self.timestamp, data.timestamp)
                }
            }
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
}

