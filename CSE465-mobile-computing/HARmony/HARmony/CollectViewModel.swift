import Foundation
import Combine
import CoreMotion
import AVFoundation

// MARK: - Recording State
enum RecordingState: Equatable {
    case idle
    case countdown(remainingSeconds: Int)
    case recording(remainingSeconds: Int)
    case finished(sampleCount: Int)
}

final class CollectViewModel: ObservableObject {

    // MARK: Published state
    @Published var selectedLabel: ActivityLabel = .still
    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var liveAccel: (x: Double, y: Double, z: Double) = (0, 0, 0)
    @Published private(set) var liveGyro:  (x: Double, y: Double, z: Double) = (0, 0, 0)
    @Published private(set) var savedSamples: [SensorSample] = []
    @Published private(set) var pendingTrial: [SensorSample]? = nil

    /// [ADD] History for live graphs
    @Published private(set) var accelHistory: [ChartDataPoint] = []
    @Published private(set) var gyroHistory: [ChartDataPoint] = []
    // MARK: - [CONFIGURATION] 🏠 Easy-to-modify settings area
    private let samplingRateHz: Double = 50.0
    private let maxHistoryCount = 150 // 3s duration (50Hz * 3s)
    private var sampleCounter = 0

    @Published var recordingDuration: Int = 5

    // MARK: Private state
    private let motion: MotionManager = .shared
    private var cancellables = Set<AnyCancellable>()
    private var currentTrialSamples: [SensorSample] = []
    private var trialTimer: AnyCancellable?
    private var samplingTimer: AnyCancellable?
    private var trialStartTime: TimeInterval = 0
    private var beepPlayer: AVAudioPlayer?
    private var timer: AnyCancellable?

    init() {
        startHeartbeat()
        prepareBeep()
    }

    func startTrial() {
        guard case .idle = recordingState else { return }
        currentTrialSamples.removeAll(keepingCapacity: true)
        enterCountdown()
    }
    func cancelTrial() {
        stopTimer(); stopSampling(); currentTrialSamples.removeAll()
        recordingState = .idle
    }
    func saveTrial() {
        if let t = pendingTrial { savedSamples.append(contentsOf: t) }
        pendingTrial = nil; recordingState = .idle
    }
    func discardTrial() { pendingTrial = nil; recordingState = .idle }

    func saveCSVToDocuments() throws -> URL {
        let csv = savedSamples.toCSV()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HAR_\(Int(Date().timeIntervalSince1970)).csv")
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func enterCountdown() {
        recordingState = .countdown(remainingSeconds: 1)
        trialTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect().prefix(1)
            .sink { [weak self] _ in self?.enterRecording() }
    }
    private func enterRecording() {
        stopTimer(); playBeep()
        recordingState = .recording(remainingSeconds: recordingDuration)
        startSampling()
        var remaining = recordingDuration
        trialTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                remaining -= 1
                if remaining > 0 { self.recordingState = .recording(remainingSeconds: remaining) }
                else { self.finishRecording() }
            }
    }
    private func finishRecording() {
        stopTimer(); stopSampling()
        pendingTrial = currentTrialSamples; currentTrialSamples.removeAll()
        recordingState = .finished(sampleCount: pendingTrial?.count ?? 0)
    }
    private func stopTimer() { trialTimer?.cancel(); trialTimer = nil }
    private func startSampling() {
        stopSampling(); trialStartTime = ProcessInfo.processInfo.systemUptime
        samplingTimer = Timer.publish(every: motion.updateInterval, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.captureSample() }
    }
    private func stopSampling() { samplingTimer?.cancel(); samplingTimer = nil }
    private func captureSample() {
        let ts = ProcessInfo.processInfo.systemUptime - trialStartTime
        let s = SensorSample(timestamp: ts, accelX: liveAccel.x, accelY: liveAccel.y, accelZ: liveAccel.z,
                             gyroX: liveGyro.x, gyroY: liveGyro.y, gyroZ: liveGyro.z, label: selectedLabel.title)
        currentTrialSamples.append(s)
    }

    private func startHeartbeat() {
        motion.start()
        // [FIX] Uses a precise 50Hz timer to synchronize speed instead of combineLatest.
        timer = Timer.publish(every: 1.0/samplingRateHz, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.onHeartbeat()
            }
    }

    private func onHeartbeat() {
        let accel = motion.accel
        let gyro = motion.gyro
        
        // 1. Real-time value update
        self.liveAccel = (accel.x, accel.y, accel.z)
        self.liveGyro = (gyro.x, gyro.y, gyro.z)
        
        // 2. Graph history update (Downsampled to 25Hz to reduce visual load)
        self.sampleCounter += 1
        if self.sampleCounter % 2 == 0 {
            self.updateHistory(accel, gyro)
        }
    }

    private func updateHistory(_ a: CMAcceleration, _ g: CMRotationRate) {
        // [FIX] sampleCounter is already incremented in onHeartbeat
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

    private func prepareBeep() {
        let sampleRate: Double = 44_100; let duration: Double = 0.15; let freq = 880.0
        let frameCount = Int(sampleRate * duration); var data = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let phase = 2.0 * Double.pi * freq * Double(i) / sampleRate
            data[i] = Int16(sin(phase) * (1.0 - Double(i)/Double(frameCount)) * Double(Int16.max) * 0.6)
        }
        let dataSize = data.count * 2; let chunkSize = 36 + dataSize; var wav = Data()
        func ap(_ s: String) { wav.append(contentsOf: s.utf8) }
        func ap32(_ v: Int32) { var val = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &val, Array.init)) }
        func ap16(_ v: Int16) { var val = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &val, Array.init)) }
        ap("RIFF"); ap32(Int32(chunkSize)); ap("WAVE"); ap("fmt "); ap32(16); ap16(1); ap16(1); ap32(Int32(sampleRate)); ap32(Int32(sampleRate * 2)); ap16(2); ap16(16); ap("data"); ap32(Int32(dataSize))
        for s in data { ap16(s) }
        beepPlayer = try? AVAudioPlayer(data: wav); beepPlayer?.prepareToPlay()
    }
    private func playBeep() { beepPlayer?.currentTime = 0; beepPlayer?.play() }
}
