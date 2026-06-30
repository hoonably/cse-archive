import Foundation

/// Ablation selector for the Polite LLM study.
///
/// The full `PoliteLLMController` drives two levers at once (decode delay and
/// QoS mode). To isolate the contribution of each lever, the ablation controller
/// exercises exactly one of them while keeping the rest of the decision pipeline
/// (SLO-deficit detection, streaks, throttle/recovery intervals, hardware-pressure
/// gating) identical for a fair comparison.
///
/// This is additive: it does not touch `PoliteLLMController`.
enum PoliteLLMAblationKind: String, CaseIterable, Identifiable {
    case none
    case delayOnly = "delay_only"
    case qosOnly = "qos_only"

    var id: String { rawValue }

    var isActive: Bool { self != .none }

    /// Long form shown in the UI option list.
    var displayName: String {
        switch self {
        case .none:
            return "Off"
        case .delayOnly:
            return "Delay Only Polite LLM"
        case .qosOnly:
            return "QoS Mode Only Polite LLM"
        }
    }

    /// Compact form for segmented controls / status badges.
    var shortName: String {
        switch self {
        case .none:
            return "Off"
        case .delayOnly:
            return "Delay Only"
        case .qosOnly:
            return "QoS Only"
        }
    }

    /// CSV source tag so action logs can be attributed to the specific ablation.
    var logSource: String {
        switch self {
        case .none:
            return "polite"
        case .delayOnly:
            return "polite_delay_only"
        case .qosOnly:
            return "polite_qos_only"
        }
    }
}

/// Single-lever variant of the Polite LLM controller used for ablation studies.
///
/// Shares the same tuning constants and decision skeleton as `PoliteLLMController`
/// so that the only behavioral difference is which lever (delay vs. QoS) is allowed.
final class PoliteLLMAblationController {
    private enum ThrottleRecord {
        case delay(from: Int, to: Int)
        case qos(from: LLMQoSMode, to: LLMQoSMode)
    }

    private struct HardwarePressure {
        enum DominantResource: String {
            case cpu = "CPU"
            case gpu = "GPU"
            case dram = "DRAM"
            case none = "none"
        }

        let cpu: Double
        let gpu: Double
        let dram: Double

        var dominantResource: DominantResource {
            let maxPressure = max(cpu, max(gpu, dram))
            guard maxPressure >= 0.12 else { return .none }
            if cpu >= gpu && cpu >= dram { return .cpu }
            if gpu >= cpu && gpu >= dram { return .gpu }
            return .dram
        }

        var maxPressure: Double {
            max(cpu, max(gpu, dram))
        }

        var blocksRecovery: Bool {
            maxPressure >= 0.45
        }

        var summary: String {
            String(
                format: "%@_cpu=%.2f_gpu=%.2f_dram=%.2f",
                dominantResource.rawValue.lowercased(),
                cpu,
                gpu,
                dram
            )
        }

        init(snapshot: MactopTelemetrySnapshot, baseline: PoliteLLMHardwareProfile) {
            cpu = Self.pressure(
                current: snapshot.cpuUsagePercent,
                baseline: baseline.averageCPUUsagePercent,
                deltaSaturation: 160,
                absoluteSaturation: 800
            )
            gpu = max(
                Self.pressure(
                    current: snapshot.gpuUsagePercent,
                    baseline: baseline.averageGPUUsagePercent,
                    deltaSaturation: 30,
                    absoluteSaturation: 80
                ),
                Self.pressure(
                    current: snapshot.ubiClawProcessGPUmsPerSecond,
                    baseline: baseline.averageProcessGPUmsPerSecond,
                    deltaSaturation: 180,
                    absoluteSaturation: 500
                )
            )
            dram = Self.pressure(
                current: snapshot.dramCombinedBandwidthGBs,
                baseline: baseline.averageDRAMBandwidthGBs,
                deltaSaturation: 35,
                absoluteSaturation: 120
            )
        }

        private static func pressure(
            current: Double?,
            baseline: Double?,
            deltaSaturation: Double,
            absoluteSaturation: Double
        ) -> Double {
            guard let current = finite(current) else { return 0 }

            let absolutePressure = normalized(current, saturation: absoluteSaturation) * 0.35
            guard let baseline = finite(baseline) else { return absolutePressure }

            let deltaPressure = normalized(current - baseline, saturation: deltaSaturation)
            return max(deltaPressure, absolutePressure)
        }

        private static func finite(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }

        private static func normalized(_ value: Double, saturation: Double) -> Double {
            guard value.isFinite, saturation > 0 else { return 0 }
            return min(1, max(0, value / saturation))
        }
    }

    private struct HardwareAccumulator {
        var sampleCount = 0
        var cpuUsageSum = 0.0
        var cpuUsageCount = 0
        var gpuUsageSum = 0.0
        var gpuUsageCount = 0
        var processGPUmsPerSecondSum = 0.0
        var processGPUmsPerSecondCount = 0
        var dramBandwidthSum = 0.0
        var dramBandwidthCount = 0

        mutating func add(_ snapshot: MactopTelemetrySnapshot) {
            guard snapshot.isAvailable else { return }

            var accepted = false
            if let value = finite(snapshot.cpuUsagePercent) {
                cpuUsageSum += value
                cpuUsageCount += 1
                accepted = true
            }
            if let value = finite(snapshot.gpuUsagePercent) {
                gpuUsageSum += value
                gpuUsageCount += 1
                accepted = true
            }
            if let value = finite(snapshot.ubiClawProcessGPUmsPerSecond) {
                processGPUmsPerSecondSum += value
                processGPUmsPerSecondCount += 1
                accepted = true
            }
            if let value = finite(snapshot.dramCombinedBandwidthGBs) {
                dramBandwidthSum += value
                dramBandwidthCount += 1
                accepted = true
            }

            if accepted {
                sampleCount += 1
            }
        }

        func profile(for workload: WorkloadType) -> PoliteLLMHardwareProfile? {
            guard sampleCount > 0 else { return nil }

            let cpu = average(cpuUsageSum, cpuUsageCount)
            let gpu = average(gpuUsageSum, gpuUsageCount)
            let processGPU = average(processGPUmsPerSecondSum, processGPUmsPerSecondCount)
            let dram = average(dramBandwidthSum, dramBandwidthCount)
            let score = Self.pressureScore(
                cpuUsagePercent: cpu,
                gpuUsagePercent: gpu,
                processGPUmsPerSecond: processGPU,
                dramBandwidthGBs: dram
            )
            return PoliteLLMHardwareProfile(
                workload: workload,
                sampleCount: sampleCount,
                averageCPUUsagePercent: cpu,
                averageGPUUsagePercent: gpu,
                averageProcessGPUmsPerSecond: processGPU,
                averageDRAMBandwidthGBs: dram,
                pressureScore: score,
                suggestedQoSMode: Self.suggestedQoSMode(
                    score: score,
                    cpuUsagePercent: cpu,
                    gpuUsagePercent: gpu,
                    processGPUmsPerSecond: processGPU,
                    dramBandwidthGBs: dram
                )
            )
        }

        private func average(_ sum: Double, _ count: Int) -> Double? {
            guard count > 0 else { return nil }
            return sum / Double(count)
        }

        private func finite(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }

        private static func pressureScore(
            cpuUsagePercent: Double?,
            gpuUsagePercent: Double?,
            processGPUmsPerSecond: Double?,
            dramBandwidthGBs: Double?
        ) -> Double {
            let gpuPressure = normalized(gpuUsagePercent, saturation: 80)
            let processGPUPressure = normalized(processGPUmsPerSecond, saturation: 500)
            let dramPressure = normalized(dramBandwidthGBs, saturation: 120)
            let cpuPressure = normalized(cpuUsagePercent, saturation: 800)

            return min(
                1,
                gpuPressure * 0.35
                    + processGPUPressure * 0.25
                    + dramPressure * 0.30
                    + cpuPressure * 0.10
            )
        }

        private static func suggestedQoSMode(
            score: Double,
            cpuUsagePercent: Double?,
            gpuUsagePercent: Double?,
            processGPUmsPerSecond: Double?,
            dramBandwidthGBs: Double?
        ) -> LLMQoSMode {
            if value(dramBandwidthGBs) >= 80
                || value(gpuUsagePercent) >= 75
                || value(processGPUmsPerSecond) >= 650
                || score >= 0.65 {
                return .background
            }

            if value(dramBandwidthGBs) >= 30
                || value(gpuUsagePercent) >= 35
                || value(processGPUmsPerSecond) >= 200
                || value(cpuUsagePercent) >= 500
                || score >= 0.30 {
                return .utility
            }

            return .userInitiated
        }

        private static func normalized(_ value: Double?, saturation: Double) -> Double {
            guard let value, value.isFinite, saturation > 0 else { return 0 }
            return min(1, max(0, value / saturation))
        }

        private static func value(_ value: Double?) -> Double {
            guard let value, value.isFinite else { return 0 }
            return value
        }
    }

    // Tuning constants mirror PoliteLLMController so only the active lever differs.
    private let maxDelayMs = 160
    private let minDecisionIntervalSeconds = 0.45
    private let minThrottleIntervalSeconds = 0.6
    private let minRecoveryIntervalSeconds = 1.8
    private let deficitDeadband = 0.03
    private let recoveryHeadroom = 0.06

    private(set) var mode: PoliteLLMAblationKind = .none
    private var foregroundAccumulator = HardwareAccumulator()
    private var cachedProfiles: [WorkloadType: PoliteLLMHardwareProfile] = [:]
    private var activeProfile: PoliteLLMHardwareProfile?
    private var latestHardwarePressure: HardwarePressure?
    private var throttleHistory: [ThrottleRecord] = []
    private var lastFrameDecisionElapsed: Double?
    private var lastAdjustmentElapsed: Double?
    private var deficitStreak = 0
    private var healthyStreak = 0
    private(set) var statusText = "Idle"

    func configure(mode: PoliteLLMAblationKind) {
        self.mode = mode
    }

    func resetForRun() {
        foregroundAccumulator = HardwareAccumulator()
        activeProfile = nil
        latestHardwarePressure = nil
        throttleHistory = []
        lastFrameDecisionElapsed = nil
        lastAdjustmentElapsed = nil
        deficitStreak = 0
        healthyStreak = 0
        statusText = mode.isActive ? "Waiting for foreground profile" : "Off"
    }

    func observeHardwareSnapshot(
        _ snapshot: MactopTelemetrySnapshot,
        phase: ScenarioPhase
    ) {
        if phase == .foreground {
            foregroundAccumulator.add(snapshot)
        }

        guard snapshot.isAvailable, let profile = activeProfile else { return }
        latestHardwarePressure = HardwarePressure(snapshot: snapshot, baseline: profile)
    }

    @discardableResult
    func finalizeForegroundProfile(for workload: WorkloadType) -> PoliteLLMHardwareProfile? {
        guard let profile = foregroundAccumulator.profile(for: workload) else {
            statusText = "No hardware profile"
            return cachedProfiles[workload]
        }

        cachedProfiles[workload] = profile
        activeProfile = profile
        statusText = "Profiled \(profile.summaryText)"
        return profile
    }

    func bestProfile(for workload: WorkloadType) -> PoliteLLMHardwareProfile? {
        activeProfile ?? cachedProfiles[workload]
    }

    func actionForFrame(
        _ observation: ForegroundFrameRateObservation,
        isLLMActive: Bool,
        currentDelayMs: Int,
        currentQoSMode: LLMQoSMode
    ) -> PoliteLLMAction? {
        guard mode.isActive,
              isLLMActive,
              let sloFPS = observation.sloFPS,
              sloFPS.isFinite,
              sloFPS > 0,
              observation.recentFPS.isFinite,
              observation.recentFPS > 0 else {
            return nil
        }

        if let lastFrameDecisionElapsed,
           observation.elapsed - lastFrameDecisionElapsed < minDecisionIntervalSeconds {
            return nil
        }
        lastFrameDecisionElapsed = observation.elapsed

        let evaluationFPS = observation.recentFPS
        let deficitRatio = (sloFPS - evaluationFPS) / sloFPS
        if deficitRatio > deficitDeadband {
            deficitStreak += 1
            healthyStreak = 0
            statusText = String(
                format: "[%@] SLO deficit %.1f%% %@",
                mode.shortName,
                deficitRatio * 100,
                latestHardwarePressure?.dominantResource.rawValue ?? "unknown"
            )
            return throttleActionIfNeeded(
                deficitRatio: deficitRatio,
                elapsed: observation.elapsed,
                currentDelayMs: currentDelayMs,
                currentQoSMode: currentQoSMode
            )
        }

        if deficitRatio < -recoveryHeadroom {
            healthyStreak += 1
            deficitStreak = 0
            statusText = String(
                format: "[%@] Healthy %.1f FPS over SLO",
                mode.shortName,
                evaluationFPS - sloFPS
            )
            return recoveryActionIfNeeded(
                elapsed: observation.elapsed,
                currentDelayMs: currentDelayMs,
                currentQoSMode: currentQoSMode
            )
        }

        deficitStreak = 0
        healthyStreak = 0
        statusText = "[\(mode.shortName)] Near SLO"
        return nil
    }

    private func throttleActionIfNeeded(
        deficitRatio: Double,
        elapsed: Double,
        currentDelayMs: Int,
        currentQoSMode: LLMQoSMode
    ) -> PoliteLLMAction? {
        guard deficitStreak >= 2,
              canAdjust(at: elapsed, interval: minThrottleIntervalSeconds) else {
            return nil
        }

        let reason = String(
            format: "%@_fps_deficit=%.1f%%_pressure=%@",
            mode.rawValue,
            deficitRatio * 100,
            latestHardwarePressure?.summary ?? "unknown"
        )

        switch mode {
        case .delayOnly:
            return delayThrottleAction(
                deficitRatio: deficitRatio,
                elapsed: elapsed,
                currentDelayMs: currentDelayMs,
                reason: reason
            )
        case .qosOnly:
            return qosThrottleAction(
                elapsed: elapsed,
                currentQoSMode: currentQoSMode,
                reason: reason
            )
        case .none:
            return nil
        }
    }

    private func recoveryActionIfNeeded(
        elapsed: Double,
        currentDelayMs: Int,
        currentQoSMode: LLMQoSMode
    ) -> PoliteLLMAction? {
        guard healthyStreak >= 4,
              canAdjust(at: elapsed, interval: minRecoveryIntervalSeconds) else {
            return nil
        }

        if latestHardwarePressure?.blocksRecovery == true {
            statusText = "[\(mode.shortName)] Healthy but hardware pressure high"
            return nil
        }

        while let record = throttleHistory.popLast() {
            switch record {
            case .delay(let fromDelay, let toDelay):
                guard currentDelayMs == toDelay else { continue }
                lastAdjustmentElapsed = elapsed
                return PoliteLLMAction(
                    kind: .setDelay(fromDelay),
                    reason: "\(mode.rawValue)_fps_headroom_restore_delay"
                )

            case .qos(let fromQoSMode, let toQoSMode):
                guard currentQoSMode == toQoSMode else { continue }
                lastAdjustmentElapsed = elapsed
                return PoliteLLMAction(
                    kind: .setQoS(fromQoSMode),
                    reason: "\(mode.rawValue)_fps_headroom_restore_qos"
                )
            }
        }

        return nil
    }

    private func delayThrottleAction(
        deficitRatio: Double,
        elapsed: Double,
        currentDelayMs: Int,
        reason: String
    ) -> PoliteLLMAction? {
        guard currentDelayMs < maxDelayMs else {
            statusText = "[\(mode.shortName)] Delay at cap"
            return nil
        }

        let nextDelay = min(maxDelayMs, currentDelayMs + delayStep(for: deficitRatio))
        guard nextDelay != currentDelayMs else { return nil }

        lastAdjustmentElapsed = elapsed
        throttleHistory.append(.delay(from: currentDelayMs, to: nextDelay))
        return PoliteLLMAction(kind: .setDelay(nextDelay), reason: reason)
    }

    private func qosThrottleAction(
        elapsed: Double,
        currentQoSMode: LLMQoSMode,
        reason: String
    ) -> PoliteLLMAction? {
        guard let lowerQoSMode = currentQoSMode.morePoliteModeForAblation else {
            statusText = "[\(mode.shortName)] QoS at floor"
            return nil
        }

        lastAdjustmentElapsed = elapsed
        throttleHistory.append(.qos(from: currentQoSMode, to: lowerQoSMode))
        return PoliteLLMAction(kind: .setQoS(lowerQoSMode), reason: reason)
    }

    private func canAdjust(at elapsed: Double, interval: Double) -> Bool {
        guard let lastAdjustmentElapsed else { return true }
        return elapsed - lastAdjustmentElapsed >= interval
    }

    private func delayStep(for deficitRatio: Double) -> Int {
        switch deficitRatio {
        case 0.18...:
            return 30
        case 0.09...:
            return 20
        default:
            return 10
        }
    }
}

private extension LLMQoSMode {
    var morePoliteModeForAblation: LLMQoSMode? {
        switch self {
        case .userInitiated:
            return .utility
        case .utility:
            return .background
        case .background:
            return nil
        }
    }
}
