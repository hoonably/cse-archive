import Foundation
import Combine
import CoreMotion

final class DetectViewModel: ObservableObject {
    @Published private(set) var liveAccel: (x: Double, y: Double, z: Double) = (0,0,0)
    @Published private(set) var liveGyro: (x: Double, y: Double, z: Double) = (0,0,0)
    @Published var currentActivity: String = "NOT READY"
    
    @Published private(set) var accelMag: Double = 0
    @Published private(set) var gyroMag: Double = 0
    @Published private(set) var meanAccelMag: Double = 0
    @Published private(set) var stdAccelMag: Double = 0

    @Published private(set) var accelHistory: [ChartDataPoint] = []
    @Published private(set) var gyroHistory: [ChartDataPoint] = []
    private let maxHistoryCount = 150
    
    // MARK: - [CONFIGURATION] 🏠 Easy-to-modify settings area
    //! [MODIFY ME] Sliding window size
    private let detectionWindowSeconds: Double = 1.8
    private let samplingRateHz: Double = 50.0
    private var fixedWindowSize: Int { Int(detectionWindowSeconds * samplingRateHz) }
    
    private var sampleBuffer: [SensorSample] = []
    private var predictionHistory: [String] = [] 
    private var sampleCounter: Int = 0 

    private let motion: MotionManager = .shared
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable? // Accurate 50Hz timer

    init() {
        startTracking()
    }

    private func startTracking() {
        motion.start()
        
        // [FIX] Uses a precise 50Hz timer to read data instead of combineLatest.
        timer = Timer.publish(every: 1.0/50.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onHeartbeat()
            }
    }

    private func onHeartbeat() {
        let accel = motion.accel
        let gyro = motion.gyro
        let ts = motion.timestamp
        
        self.liveAccel = (accel.x, accel.y, accel.z)
        self.liveGyro = (gyro.x, gyro.y, gyro.z)
        
        // 1. Buffer update
        let s = SensorSample(timestamp: ts, accelX: accel.x, accelY: accel.y, accelZ: accel.z,
                             gyroX: gyro.x, gyroY: gyro.y, gyroZ: gyro.z, label: nil)
        self.sampleBuffer.append(s)
        if self.sampleBuffer.count > self.fixedWindowSize { self.sampleBuffer.removeFirst() }
        
        // 2. Value update
        self.accelMag = sqrt(accel.x*accel.x + accel.y*accel.y + accel.z*accel.z)
        self.gyroMag = sqrt(gyro.x*gyro.x + gyro.y*gyro.y + gyro.z*gyro.z)
        
        // 3. Graph history update (Downsampled to 25Hz to reduce load)
        self.sampleCounter += 1
        if self.sampleCounter % 2 == 0 {
            self.updateHistory(accel, gyro)
        }
        
        // 4. Statistics and Classification (Periodic)
        if self.sampleCounter % 5 == 0 { self.updateStats() }
        if self.sampleCounter % 10 == 0 && self.sampleBuffer.count >= self.fixedWindowSize {
            let res = ActivityClassifier.classify(samples: self.sampleBuffer)
            self.predictionHistory.append(res.activity)
            if self.predictionHistory.count > 5 { self.predictionHistory.removeFirst() }
            self.currentActivity = self.getMajorityLabel(self.predictionHistory)
        }
    }

    private func updateHistory(_ a: CMAcceleration, _ g: CMRotationRate) {
        accelHistory.append(contentsOf: [
            ChartDataPoint(index: sampleCounter, axis: "X", value: a.x),
            ChartDataPoint(index: sampleCounter, axis: "Y", value: a.y),
            ChartDataPoint(index: sampleCounter, axis: "Z", value: a.z)
        ])
        gyroHistory.append(contentsOf: [
            ChartDataPoint(index: sampleCounter, axis: "X", value: g.x),
            ChartDataPoint(index: sampleCounter, axis: "Y", value: g.y),
            ChartDataPoint(index: sampleCounter, axis: "Z", value: g.z)
        ])
        let threshold = maxHistoryCount * 3
        if accelHistory.count > threshold {
            accelHistory.removeFirst(accelHistory.count - threshold)
            gyroHistory.removeFirst(gyroHistory.count - threshold)
        }
    }

    private func updateStats() {
        guard !sampleBuffer.isEmpty else { return }
        let mags = sampleBuffer.map { sqrt($0.accelX*$0.accelX + $0.accelY*$0.accelY + $0.accelZ*$0.accelZ) }
        let meanVal = mags.reduce(0, +) / Double(mags.count)
        self.meanAccelMag = meanVal
        let variance = mags.reduce(0) { $0 + ($1 - meanVal) * ($1 - meanVal) } / Double(mags.count)
        self.stdAccelMag = sqrt(variance)
    }

    private func getMajorityLabel(_ h: [String]) -> String {
        let counts = h.reduce(into: [:]) { counts, label in counts[label, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? "Detecting..."
    }
}
