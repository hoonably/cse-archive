import Foundation

struct PoliteLLMHardwareProfile {
    let workload: WorkloadType
    let sampleCount: Int
    let averageCPUUsagePercent: Double?
    let averageGPUUsagePercent: Double?
    let averageProcessGPUmsPerSecond: Double?
    let averageDRAMBandwidthGBs: Double?
    let pressureScore: Double
    let suggestedQoSMode: LLMQoSMode

    var summaryText: String {
        guard sampleCount > 0 else { return "No profile" }

        let gpuText = Self.formatPercent(averageGPUUsagePercent)
        let dramText = Self.formatBandwidth(averageDRAMBandwidthGBs)
        return "\(sampleCount) samples, GPU \(gpuText), DRAM \(dramText), \(suggestedQoSMode.displayName)"
    }

    private static func formatPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private static func formatBandwidth(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f GB/s", value)
    }
}

struct PoliteLLMAction {
    enum Kind {
        case setDelay(Int)
        case setQoS(LLMQoSMode)
    }

    let commands: [Kind]
    let reason: String

    init(kind: Kind, reason: String) {
        self.commands = [kind]
        self.reason = reason
    }

    init(commands: [Kind], reason: String) {
        self.commands = commands
        self.reason = reason
    }
}

final class PoliteLLMController {
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

        var favorsQoS: Bool {
            cpu >= 0.20 && cpu >= max(gpu, dram) * 0.90
        }

        var favorsDelay: Bool {
            max(gpu, dram) >= 0.18
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

    private let maxDelayMs = 160
    private let qosEscalationDelayMs = 80
    private let qosEscalationDeficit = 0.05
    private let qosEscalationPressure = 0.75
    private let minDecisionIntervalSeconds = 0.45
    private let minThrottleIntervalSeconds = 0.6
    private let minRecoveryIntervalSeconds = 1.8
    private let deficitDeadband = 0.03
    private let recoveryHeadroom = 0.06

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

    func resetForRun() {
        foregroundAccumulator = HardwareAccumulator()
        activeProfile = nil
        latestHardwarePressure = nil
        throttleHistory = []
        lastFrameDecisionElapsed = nil
        lastAdjustmentElapsed = nil
        deficitStreak = 0
        healthyStreak = 0
        statusText = "Waiting for foreground profile"
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
        guard isLLMActive,
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
                format: "SLO deficit %.1f%% %@",
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
            statusText = String(format: "Healthy %.1f FPS over SLO", evaluationFPS - sloFPS)
            return recoveryActionIfNeeded(
                elapsed: observation.elapsed,
                currentDelayMs: currentDelayMs,
                currentQoSMode: currentQoSMode
            )
        }

        deficitStreak = 0
        healthyStreak = 0
        statusText = "Near SLO"
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

        let pressure = latestHardwarePressure
        let reason = String(
            format: "fps_deficit=%.1f%%_pressure=%@",
            deficitRatio * 100,
            pressure?.summary ?? "unknown"
        )

        if deficitRatio >= 0.20 {
            return severeThrottleAction(
                elapsed: elapsed,
                currentDelayMs: currentDelayMs,
                currentQoSMode: currentQoSMode,
                reason: reason
            )
        }

        if shouldEscalateQoSAfterDelay(
            deficitRatio: deficitRatio,
            currentDelayMs: currentDelayMs,
            pressure: pressure
        ),
           let qosAction = qosThrottleAction(
            elapsed: elapsed,
            currentQoSMode: currentQoSMode,
            reason: "sustained_high_pressure_\(reason)"
           ) {
            return qosAction
        }

        if pressure?.favorsQoS == true,
           let qosAction = qosThrottleAction(
            elapsed: elapsed,
            currentQoSMode: currentQoSMode,
            reason: reason
           ) {
            return qosAction
        }

        if pressure?.favorsDelay == true,
           let delayAction = delayThrottleAction(
            deficitRatio: deficitRatio,
            elapsed: elapsed,
            currentDelayMs: currentDelayMs,
            reason: reason
           ) {
            return delayAction
        }

        if let delayAction = delayThrottleAction(
            deficitRatio: deficitRatio,
            elapsed: elapsed,
            currentDelayMs: currentDelayMs,
            reason: reason
        ) {
            return delayAction
        }

        return qosThrottleAction(
            elapsed: elapsed,
            currentQoSMode: currentQoSMode,
            reason: "delay_cap_\(reason)"
        )
    }

    private func shouldEscalateQoSAfterDelay(
        deficitRatio: Double,
        currentDelayMs: Int,
        pressure: HardwarePressure?
    ) -> Bool {
        guard let pressure else { return false }
        return currentDelayMs >= qosEscalationDelayMs
            && deficitRatio >= qosEscalationDeficit
            && pressure.maxPressure >= qosEscalationPressure
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
            statusText = "Healthy but hardware pressure high"
            return nil
        }

        while let record = throttleHistory.popLast() {
            switch record {
            case .delay(let fromDelay, let toDelay):
                guard currentDelayMs == toDelay else { continue }
                lastAdjustmentElapsed = elapsed
                return PoliteLLMAction(
                    kind: .setDelay(fromDelay),
                    reason: "fps_headroom_restore_delay"
                )

            case .qos(let fromQoSMode, let toQoSMode):
                guard currentQoSMode == toQoSMode else { continue }
                lastAdjustmentElapsed = elapsed
                return PoliteLLMAction(
                    kind: .setQoS(fromQoSMode),
                    reason: "fps_headroom_restore_qos"
                )
            }
        }

        return nil
    }

    private func severeThrottleAction(
        elapsed: Double,
        currentDelayMs: Int,
        currentQoSMode: LLMQoSMode,
        reason: String
    ) -> PoliteLLMAction? {
        var commands: [PoliteLLMAction.Kind] = []
        var records: [ThrottleRecord] = []

        if let delayCommand = makeDelayThrottleCommand(
            deficitRatio: 0.20,
            currentDelayMs: currentDelayMs
        ) {
            commands.append(delayCommand.kind)
            records.append(delayCommand.record)
        }

        if let qosCommand = makeQoSThrottleCommand(currentQoSMode: currentQoSMode) {
            commands.append(qosCommand.kind)
            records.append(qosCommand.record)
        }

        guard !commands.isEmpty else { return nil }
        lastAdjustmentElapsed = elapsed
        throttleHistory.append(contentsOf: records)
        return PoliteLLMAction(commands: commands, reason: "severe_\(reason)")
    }

    private func delayThrottleAction(
        deficitRatio: Double,
        elapsed: Double,
        currentDelayMs: Int,
        reason: String
    ) -> PoliteLLMAction? {
        guard let command = makeDelayThrottleCommand(
            deficitRatio: deficitRatio,
            currentDelayMs: currentDelayMs
        ) else {
            return nil
        }

        lastAdjustmentElapsed = elapsed
        throttleHistory.append(command.record)
        return PoliteLLMAction(kind: command.kind, reason: reason)
    }

    private func qosThrottleAction(
        elapsed: Double,
        currentQoSMode: LLMQoSMode,
        reason: String
    ) -> PoliteLLMAction? {
        guard let command = makeQoSThrottleCommand(currentQoSMode: currentQoSMode) else {
            return nil
        }

        lastAdjustmentElapsed = elapsed
        throttleHistory.append(command.record)
        return PoliteLLMAction(kind: command.kind, reason: reason)
    }

    private func makeDelayThrottleCommand(
        deficitRatio: Double,
        currentDelayMs: Int
    ) -> (kind: PoliteLLMAction.Kind, record: ThrottleRecord)? {
        guard currentDelayMs < maxDelayMs else { return nil }

        let nextDelay = min(maxDelayMs, currentDelayMs + delayStep(for: deficitRatio))
        guard nextDelay != currentDelayMs else { return nil }
        return (.setDelay(nextDelay), .delay(from: currentDelayMs, to: nextDelay))
    }

    private func makeQoSThrottleCommand(
        currentQoSMode: LLMQoSMode
    ) -> (kind: PoliteLLMAction.Kind, record: ThrottleRecord)? {
        guard let lowerQoSMode = currentQoSMode.morePoliteMode else { return nil }
        return (.setQoS(lowerQoSMode), .qos(from: currentQoSMode, to: lowerQoSMode))
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
    var morePoliteMode: LLMQoSMode? {
        switch self {
        case .userInitiated:
            return .utility
        case .utility:
            return .background
        case .background:
            return nil
        }
    }

    var lessPoliteMode: LLMQoSMode? {
        switch self {
        case .background:
            return .utility
        case .utility:
            return .userInitiated
        case .userInitiated:
            return nil
        }
    }
}
