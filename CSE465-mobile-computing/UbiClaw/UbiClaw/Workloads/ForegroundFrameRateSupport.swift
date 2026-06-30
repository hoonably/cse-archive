import AppKit
import Charts
import Combine
import SwiftUI

struct WorkloadSummaryMetric: Identifiable {
    let title: String
    let value: String
    let valueColor: Color

    var id: String { title }

    init(_ title: String, value: String, valueColor: Color = .primary) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
    }

    static func llmTokensPerSecond(_ tokensPerSecond: Double) -> WorkloadSummaryMetric {
        WorkloadSummaryMetric(
            "LLM tok/s",
            value: tokensPerSecond > 0 ? String(format: "%.1f", tokensPerSecond) : "—"
        )
    }
}

struct WorkloadSettingsBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 14) {
            content
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.08))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkloadIntegerSettingField: View {
    let title: String
    @Binding var value: Int

    private var positiveValue: Binding<Int> {
        Binding(
            get: { value },
            set: { value = max(1, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            TextField("", value: positiveValue, format: .number)
                .frame(width: 76)
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct WorkloadDoubleSettingField: View {
    let title: String
    @Binding var value: Double

    private var nonnegativeValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = max(0, $0) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            TextField("", value: nonnegativeValue, format: .number)
                .frame(width: 76)
        }
        .textFieldStyle(.roundedBorder)
    }
}

enum WorkloadChartDisplayMode: String, CaseIterable, Identifiable {
    case recent
    case fullRun = "full_run"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recent:
            return "Recent"
        case .fullRun:
            return "Full Run"
        }
    }
}

enum WorkloadChartDefaults {
    static let warmupHiddenSeconds = 0.1
    static let recentWindowSeconds = 5.0
    static let recentMaxHistorySamples = 300
    static let fullRunMaxHistorySamples = 1200
    static let chartSampleIntervalSeconds = 0.1
    static let uiPublishIntervalSeconds = 0.25
    static let recentAverageWindowSeconds = 1.0

    static func dynamicYDomain(for values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter { $0.isFinite && $0 > 0 }

        guard !finiteValues.isEmpty else {
            return 0...1
        }

        let lower = max(0, (finiteValues.min() ?? 0) * 0.9)
        let upper = (finiteValues.max() ?? 1) * 1.1
        return lower...upper
    }
}

enum WorkloadChartAnnotations {
    static func isChartEventLabel(_ label: String) -> Bool {
        label.hasPrefix("Delay ") || label.hasPrefix("QoS ")
            || label == "Gen Pause" || label == "Gen Resume"
            || label == "Foreground Only Start"
            || label.hasSuffix("LLM Start") || label.hasSuffix("LLM End")
    }

    static func displayLabel(for label: String) -> String {
        label
            .replacingOccurrences(of: "Foreground Only", with: "Foreground")
            .replacingOccurrences(of: "Foreground + LLM", with: "LLM")
            .replacingOccurrences(of: "LLM Inference Only", with: "LLM")
    }

    static func eventColor(for label: String) -> Color {
        if label == "Foreground Only Start" { return .green }
        if label.hasSuffix("LLM Start") { return .red }
        if label.hasSuffix("LLM End") { return .indigo }
        if label == "Gen Pause" { return .purple }
        if label == "Gen Resume" { return .mint }
        if label == "QoS Background" { return .red }
        if label == "QoS Utility" { return .orange }
        if label == "QoS Normal" { return .green }
        if let delayMs = delayMilliseconds(from: label) {
            return delayColor(for: delayMs)
        }
        return .green
    }

    private static func delayMilliseconds(from label: String) -> Int? {
        guard label.hasPrefix("Delay ") else { return nil }
        let numberText = label
            .replacingOccurrences(of: "Delay ", with: "")
            .replacingOccurrences(of: "ms", with: "")
        return Int(numberText)
    }

    private static func delayColor(for delayMs: Int) -> Color {
        switch delayMs {
        case ..<90:
            return .green
        case ..<150:
            return .orange
        default:
            return .red
        }
    }
}

struct ForegroundFrameRateSample: Identifiable {
    var id: Double { elapsedSeconds }
    let elapsedSeconds: Double
    let fps: Double
    let smoothFPS: Double
}

struct ForegroundFrameRateObservation {
    let elapsed: TimeInterval
    let currentFPS: Double
    let recentFPS: Double
    let averageFPS: Double
    let sloFPS: Double?
}

final class ForegroundFrameRateMonitor: ObservableObject {
    @Published private(set) var currentFPS: Double = 0
    @Published private(set) var recentFPS: Double = 0
    @Published private(set) var averageFPS: Double = 0
    @Published private(set) var samples: [ForegroundFrameRateSample] = []
    @Published private(set) var foregroundBaselineMeanFPS: Double?
    @Published private(set) var foregroundBaselineP95FPS: Double?
    @Published private(set) var chartDisplayMode: WorkloadChartDisplayMode = .recent

    private let workloadID: String
    private let chartWindowSeconds = WorkloadChartDefaults.recentWindowSeconds
    private let chartWarmupHiddenSeconds = WorkloadChartDefaults.warmupHiddenSeconds
    private let maxMeaningfulFPS = ForegroundFrameRateMonitor.displayRefreshRateCapFPS()
    private let maxFPSHistorySamples = WorkloadChartDefaults.recentMaxHistorySamples
    private let chartSampleIntervalSeconds = WorkloadChartDefaults.chartSampleIntervalSeconds
    private let uiPublishIntervalSeconds = WorkloadChartDefaults.uiPublishIntervalSeconds
    private let recentAverageWindowSeconds = WorkloadChartDefaults.recentAverageWindowSeconds
    private let foregroundBaselineSampleStartSeconds = 3.0
    private let foregroundBaselineSampleEndSeconds = 8.0
    private var foregroundSLOBasis: ForegroundSLOBasis = .baselineMean
    private var foregroundSLOMultiplier = ForegroundSLODefaults.multiplier
    private var foregroundSLOPercentile = ForegroundSLODefaults.percentile

    private var measuredFrameCount = 0
    private var totalMeasuredFrameTimeSeconds = 0.0
    private var latestCurrentFPS = 0.0
    private var latestAverageFPS = 0.0
    private var latestRecentFPS = 0.0
    private var lastFPSLogDate: Date?
    private var lastFrameElapsed: TimeInterval?
    private var lastChartSampleElapsed: TimeInterval?
    private var lastUIPublishElapsed: TimeInterval?
    private var recentFrameTimes: [(elapsed: Double, frameTimeSeconds: Double)] = []
    private var foregroundBaselineFrameTimeMsValues: [Double] = []
    private var foregroundLLMDurationSeconds: Double = 0
    private var cumulativeSLODeficitSeconds: Double = 0
    private var sloViolationSeconds: Double = 0
    private var lastSLOSampleElapsed: Double?
    private var timelineMarkers: [TimelineMarker] = []
    private var sampleOriginAbsoluteTime: TimeInterval?
    private var sampleOriginScenarioElapsed: Double?

    init(workloadID: String) {
        self.workloadID = workloadID
    }

    func reset() {
        currentFPS = 0
        recentFPS = 0
        averageFPS = 0
        samples = []
        foregroundBaselineMeanFPS = nil
        foregroundBaselineP95FPS = nil
        measuredFrameCount = 0
        totalMeasuredFrameTimeSeconds = 0
        latestCurrentFPS = 0
        latestAverageFPS = 0
        latestRecentFPS = 0
        lastFPSLogDate = nil
        lastFrameElapsed = nil
        lastChartSampleElapsed = nil
        lastUIPublishElapsed = nil
        recentFrameTimes = []
        foregroundBaselineFrameTimeMsValues = []
        foregroundLLMDurationSeconds = 0
        cumulativeSLODeficitSeconds = 0
        sloViolationSeconds = 0
        lastSLOSampleElapsed = nil
        timelineMarkers = []
        sampleOriginAbsoluteTime = nil
        sampleOriginScenarioElapsed = nil
    }

    func updateTimelineMarkers(_ timelineMarkers: [TimelineMarker]) {
        self.timelineMarkers = timelineMarkers
        resolveSampleOriginScenarioElapsedIfNeeded()
        captureForegroundBaselineIfNeeded()
    }

    func beginSampling(at absoluteTime: TimeInterval = CFAbsoluteTimeGetCurrent()) {
        guard sampleOriginAbsoluteTime == nil else { return }
        sampleOriginAbsoluteTime = absoluteTime
        resolveSampleOriginScenarioElapsedIfNeeded()
    }

    func updateChartDisplayMode(_ mode: WorkloadChartDisplayMode) {
        guard mode != chartDisplayMode else { return }
        chartDisplayMode = mode
        trimFrameSamplesToDisplayMode()
    }

    func updateSLOConfig(
        basis: ForegroundSLOBasis,
        multiplier: Double,
        percentile: Double
    ) {
        foregroundSLOBasis = basis
        foregroundSLOMultiplier = ForegroundSLODefaults.clampMultiplier(multiplier)
        foregroundSLOPercentile = ForegroundSLODefaults.clampPercentile(percentile)
    }

    func stopLogging(logger: CSVLogger?) {
        logger?.log(
            event: "fg_task_end",
            workload: workloadID,
            params: "avg_fps=\(String(format: "%.2f", latestAverageFPS)),recent_fps=\(String(format: "%.2f", latestRecentFPS))"
        )
        lastFPSLogDate = nil
        lastFrameElapsed = nil
    }

    @discardableResult
    func recordFrame(
        elapsed: TimeInterval,
        isActive: Bool,
        logger: CSVLogger?
    ) -> ForegroundFrameRateObservation? {
        guard isActive else { return nil }
        beginSampling(at: CFAbsoluteTimeGetCurrent() - elapsed)

        let rawFPS: Double
        let frameTimeMs: Double?
        if let lastFrameElapsed {
            let delta = elapsed - lastFrameElapsed
            rawFPS = delta > 0 ? 1.0 / delta : currentFPS
            frameTimeMs = delta > 0 ? delta * 1000 : nil
        } else {
            rawFPS = 0
            frameTimeMs = nil
        }
        let cappedFPS = Self.capFPS(rawFPS, maxFPS: maxMeaningfulFPS)
        lastFrameElapsed = elapsed

        latestCurrentFPS = cappedFPS
        if let frameTimeMs {
            let frameTimeSeconds = frameTimeMs / 1000
            measuredFrameCount += 1
            totalMeasuredFrameTimeSeconds += frameTimeSeconds
            latestAverageFPS = totalMeasuredFrameTimeSeconds > 0
                ? Double(measuredFrameCount) / totalMeasuredFrameTimeSeconds
                : 0
            updateRecentFrameTimes(elapsed: elapsed, frameTimeSeconds: frameTimeSeconds)
            updateForegroundBaselineSamples(
                elapsed: elapsed,
                frameTimeMs: Self.capFrameTimeMs(frameTimeMs, maxFPS: maxMeaningfulFPS)
            )
        }
        let sloEvaluationFPS = currentSLOEvaluationFPS(fallbackFPS: cappedFPS)
        updateSLOMetrics(elapsed: elapsed, fps: sloEvaluationFPS, isActive: isActive)
        if shouldRecordChartSample(elapsed: elapsed) {
            samples.append(
                ForegroundFrameRateSample(
                    elapsedSeconds: elapsed,
                    fps: cappedFPS,
                    smoothFPS: latestRecentFPS > 0 ? latestRecentFPS : cappedFPS
                )
            )
            trimFrameSamplesToDisplayMode(currentElapsed: elapsed)
        }

        publishFrameRateStateIfNeeded(elapsed: elapsed)
        let observation = ForegroundFrameRateObservation(
            elapsed: elapsed,
            currentFPS: cappedFPS,
            recentFPS: sloEvaluationFPS,
            averageFPS: latestAverageFPS,
            sloFPS: foregroundSLOFPS()
        )

        let logDate = Date()
        let shouldLog = lastFPSLogDate.map { logDate.timeIntervalSince($0) >= 1.0 } ?? true
        if shouldLog {
            logger?.log(
                event: "fg_fps",
                workload: workloadID,
                params: "current_fps=\(String(format: "%.2f", cappedFPS)),raw_fps=\(String(format: "%.2f", rawFPS)),avg_fps=\(String(format: "%.2f", latestAverageFPS)),recent_fps=\(String(format: "%.2f", latestRecentFPS))"
            )
            lastFPSLogDate = logDate
        }

        return observation
    }

    private func captureForegroundBaselineIfNeeded() {
        guard foregroundBaselineP95FPS == nil,
              timelineMarkers.contains(where: { $0.label == "Foreground Only End" }) else {
            return
        }

        let baselineFrameTimes = foregroundBaselineFrameTimeMsValues
            .filter { $0.isFinite && $0 > 0 }

        let sortedFrameTimes = baselineFrameTimes
            .sorted()

        // Baseline percentiles are frame-time percentiles converted back to FPS for this chart.
        // P95 frame time maps to a lower FPS baseline available as an alternate SLO basis.
        if let meanFrameTimeMs = Self.mean(baselineFrameTimes),
           let p95FrameTimeMs = Self.percentile(sortedFrameTimes, percentile: 0.95) {
            foregroundBaselineMeanFPS = Self.fps(forFrameTimeMs: meanFrameTimeMs)
            foregroundBaselineP95FPS = Self.fps(forFrameTimeMs: p95FrameTimeMs)
        } else if latestAverageFPS > 0 {
            foregroundBaselineMeanFPS = latestAverageFPS
            foregroundBaselineP95FPS = latestAverageFPS
        }
    }

    func foregroundSLOFPS() -> Double? {
        let baselineFPS: Double?
        switch foregroundSLOBasis {
        case .baselineMean:
            guard let foregroundBaselineMeanFPS, foregroundBaselineMeanFPS > 0 else { return nil }
            return foregroundBaselineMeanFPS * foregroundSLOMultiplier
        case .baselinePercentile:
            baselineFPS = foregroundBaselineFPS(percentile: foregroundSLOPercentile)
        }

        guard let baselineFPS, baselineFPS > 0 else { return nil }
        return baselineFPS
    }

    func foregroundSLOLabel() -> String {
        if foregroundSLOBasis == .baselinePercentile {
            return String(
                format: "SLO (Baseline P%.0f Frame Time)",
                foregroundSLOPercentile * 100
            )
        }

        return String(
            format: "SLO (%.0f%% %@)",
            foregroundSLOMultiplier * 100,
            foregroundSLOBasis.baselineLabel
        )
    }

    var foregroundSLOTargetText: String {
        guard let sloFPS = foregroundSLOFPS() else { return "—" }
        return String(format: "%.1f FPS", sloFPS)
    }

    private func foregroundBaselineFPS(percentile: Double) -> Double? {
        let sortedFrameTimes = foregroundBaselineFrameTimeMsValues
            .filter { $0.isFinite && $0 > 0 }
            .sorted()

        if let percentileFrameTimeMs = Self.percentile(
            sortedFrameTimes,
            percentile: percentile
        ) {
            return Self.fps(forFrameTimeMs: percentileFrameTimeMs)
        }

        return foregroundBaselineP95FPS
    }

    func currentSLOViolationText(isActive: Bool) -> String {
        guard let currentSLODeficitPercent = currentSLODeficitPercent(
            isActive: isActive
        ) else {
            return "—"
        }
        return String(format: "%.1f%%", currentSLODeficitPercent)
    }

    func currentSLOViolationColor(isActive: Bool) -> Color {
        metricColor(
            forPercent: currentSLODeficitPercent(
                isActive: isActive
            )
        )
    }

    var cumulativeSLOViolationText: String {
        guard let cumulativeSLOViolationPercentSeconds else { return "—" }
        return String(format: "%.1f %%-s", cumulativeSLOViolationPercentSeconds)
    }

    var cumulativeSLOViolationColor: Color {
        guard foregroundLLMDurationSeconds > 0 else { return .secondary }
        return .primary
    }

    var sloViolationTimeText: String {
        guard foregroundLLMDurationSeconds > 0 else { return "—" }
        return String(format: "%.1fs", sloViolationSeconds)
    }

    var sloViolationTimeColor: Color {
        guard foregroundLLMDurationSeconds > 0 else { return .secondary }
        return .primary
    }

    func chartWindowStart() -> Double {
        switch chartDisplayMode {
        case .recent:
            return max(0, (samples.last?.elapsedSeconds ?? 0) - chartWindowSeconds)
        case .fullRun:
            return 0
        }
    }

    func chartXDomain() -> ClosedRange<Double> {
        switch chartDisplayMode {
        case .recent:
            return 0...chartWindowSeconds
        case .fullRun:
            return 0...max(1, samples.last?.elapsedSeconds ?? 1)
        }
    }

    func chartXAxisLabel() -> String {
        switch chartDisplayMode {
        case .recent:
            return "Last 5s"
        case .fullRun:
            return "Full run"
        }
    }

    func chartYDomain() -> ClosedRange<Double> {
        let halfRange: Double = 20
        if let mean = foregroundBaselineMeanFPS, mean.isFinite, mean > 0 {
            let lower = max(0, mean - halfRange)
            let upper = mean + halfRange
            return lower...upper
        }
        var values = samples.map(\.smoothFPS)
        values += [
            foregroundBaselineMeanFPS,
            foregroundBaselineP95FPS,
            foregroundSLOFPS()
        ].compactMap { $0 }
        return WorkloadChartDefaults.dynamicYDomain(for: values)
    }

    func chartEventMarkers() -> [TimelineMarker] {
        timelineMarkers.filter {
            let xPosition = chartEventXPosition(for: $0)
            let xUpperBound = chartXDomain().upperBound
            return xPosition > 0
                && xPosition < xUpperBound
                && isChartEventLabel($0.label)
        }
    }

    func chartEventXPosition(for marker: TimelineMarker) -> Double {
        marker.elapsedTime - chartOriginElapsed() - chartWindowStart()
    }

    private func updateSLOMetrics(
        elapsed: Double,
        fps: Double,
        isActive: Bool
    ) {
        guard isActive,
              isForegroundLLMActive(),
              let foregroundSLOFPS = foregroundSLOFPS(),
              foregroundSLOFPS > 0 else {
            lastSLOSampleElapsed = nil
            return
        }

        let previousElapsed = lastSLOSampleElapsed
            ?? foregroundLLMStartElapsed()
            ?? elapsed
        let delta = max(0, elapsed - previousElapsed)
        lastSLOSampleElapsed = elapsed
        guard delta > 0 else { return }

        let deficitRatio = sloDeficitPercent(for: fps, sloFPS: foregroundSLOFPS) / 100
        foregroundLLMDurationSeconds += delta
        cumulativeSLODeficitSeconds += deficitRatio * delta
        if deficitRatio > 0 {
            sloViolationSeconds += delta
        }
    }

    private func updateForegroundBaselineSamples(elapsed: Double, frameTimeMs: Double) {
        guard foregroundBaselineP95FPS == nil,
              !timelineMarkers.contains(where: { $0.label == "Foreground Only End" }),
              elapsed >= foregroundBaselineSampleStartSeconds,
              elapsed <= foregroundBaselineSampleEndSeconds,
              frameTimeMs.isFinite,
              frameTimeMs > 0 else {
            return
        }

        foregroundBaselineFrameTimeMsValues.append(frameTimeMs)
    }

    private func trimFrameSamplesToDisplayMode(currentElapsed: Double? = nil) {
        switch chartDisplayMode {
        case .recent:
            let latestElapsed = currentElapsed ?? samples.last?.elapsedSeconds ?? 0
            samples.removeAll { latestElapsed - $0.elapsedSeconds > chartWindowSeconds }
            if samples.count > maxFPSHistorySamples {
                samples.removeFirst(samples.count - maxFPSHistorySamples)
            }
        case .fullRun:
            decimateFullRunSamplesIfNeeded()
        }
    }

    private func currentSLODeficitPercent(isActive: Bool) -> Double? {
        guard isActive,
              isForegroundLLMActive(),
              let foregroundSLOFPS = foregroundSLOFPS(),
              foregroundSLOFPS > 0 else {
            return nil
        }

        return sloDeficitPercent(
            for: currentSLOEvaluationFPS(fallbackFPS: latestCurrentFPS),
            sloFPS: foregroundSLOFPS
        )
    }

    private func currentSLOEvaluationFPS(fallbackFPS: Double) -> Double {
        latestRecentFPS > 0 ? latestRecentFPS : fallbackFPS
    }

    private func shouldRecordChartSample(elapsed: Double) -> Bool {
        guard elapsed >= chartWarmupHiddenSeconds else { return false }
        guard let lastChartSampleElapsed else {
            self.lastChartSampleElapsed = elapsed
            return true
        }
        guard elapsed - lastChartSampleElapsed >= chartSampleIntervalSeconds else { return false }
        self.lastChartSampleElapsed = elapsed
        return true
    }

    private func publishFrameRateStateIfNeeded(elapsed: Double) {
        guard lastUIPublishElapsed == nil
                || elapsed - (lastUIPublishElapsed ?? 0) >= uiPublishIntervalSeconds else {
            return
        }

        currentFPS = latestCurrentFPS
        recentFPS = latestRecentFPS
        averageFPS = latestAverageFPS
        lastUIPublishElapsed = elapsed
    }

    private func updateRecentFrameTimes(elapsed: Double, frameTimeSeconds: Double) {
        recentFrameTimes.append((elapsed, frameTimeSeconds))
        let lowerBound = elapsed - recentAverageWindowSeconds
        recentFrameTimes.removeAll { $0.elapsed < lowerBound }

        let totalFrameTime = recentFrameTimes.reduce(0) { $0 + $1.frameTimeSeconds }
        latestRecentFPS = totalFrameTime > 0
            ? Double(recentFrameTimes.count) / totalFrameTime
            : latestCurrentFPS
    }

    private func decimateFullRunSamplesIfNeeded() {
        guard samples.count > WorkloadChartDefaults.fullRunMaxHistorySamples else { return }

        let stride = max(2, Int(ceil(Double(samples.count) / Double(WorkloadChartDefaults.fullRunMaxHistorySamples))))
        let lastIndex = samples.count - 1
        samples = samples.enumerated().compactMap { index, sample in
            if index == lastIndex || index % stride == 0 {
                return sample
            }
            return nil
        }
    }

    private var cumulativeSLOViolationPercentSeconds: Double? {
        guard foregroundLLMDurationSeconds > 0 else { return nil }
        return max(0, cumulativeSLODeficitSeconds * 100)
    }

    private func sloDeficitPercent(for fps: Double, sloFPS: Double) -> Double {
        let deficit = (sloFPS - fps) / sloFPS
        return min(100, max(0, deficit * 100))
    }

    private func metricColor(forPercent percent: Double?) -> Color {
        guard percent != nil else { return .secondary }
        return .primary
    }

    private func isForegroundLLMActive() -> Bool {
        guard let start = timelineMarkers.last(where: { $0.label == "Foreground + LLM Start" })?.elapsedTime else {
            return false
        }

        guard let end = timelineMarkers.last(where: { $0.label == "Foreground + LLM End" })?.elapsedTime else {
            return true
        }

        return end < start
    }

    private func foregroundLLMStartElapsed() -> Double? {
        guard let start = timelineMarkers.last(where: { $0.label == "Foreground + LLM Start" })?.elapsedTime else {
            return nil
        }

        return start - chartOriginElapsed()
    }

    private func chartOriginElapsed() -> Double {
        if let sampleOriginScenarioElapsed {
            return sampleOriginScenarioElapsed
        }

        if let sampleOriginAbsoluteTime,
           let estimatedElapsed = Self.estimatedScenarioElapsed(
            at: sampleOriginAbsoluteTime,
            using: timelineMarkers
           ) {
            return estimatedElapsed
        }

        return workloadStartElapsed()
    }

    private func resolveSampleOriginScenarioElapsedIfNeeded() {
        guard sampleOriginScenarioElapsed == nil,
              let sampleOriginAbsoluteTime,
              let estimatedElapsed = Self.estimatedScenarioElapsed(
                at: sampleOriginAbsoluteTime,
                using: timelineMarkers
              ) else {
            return
        }

        sampleOriginScenarioElapsed = estimatedElapsed
    }

    private func workloadStartElapsed() -> Double {
        timelineMarkers.first(where: { $0.label == "Foreground Only Start" })?.elapsedTime ?? 0
    }

    private func isChartEventLabel(_ label: String) -> Bool {
        WorkloadChartAnnotations.isChartEventLabel(label)
    }

    private static func percentile(_ sortedValues: [Double], percentile: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        guard sortedValues.count > 1 else { return sortedValues[0] }

        let clampedPercentile = min(1, max(0, percentile))
        let position = clampedPercentile * Double(sortedValues.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))

        if lowerIndex == upperIndex {
            return sortedValues[lowerIndex]
        }

        let fraction = position - Double(lowerIndex)
        return sortedValues[lowerIndex] + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func fps(forFrameTimeMs frameTimeMs: Double) -> Double {
        guard frameTimeMs > 0 else { return 0 }
        return 1000.0 / frameTimeMs
    }

    private static func capFPS(_ fps: Double, maxFPS: Double) -> Double {
        guard fps.isFinite, fps > 0 else { return 0 }
        return min(fps, maxFPS)
    }

    private static func capFrameTimeMs(_ frameTimeMs: Double, maxFPS: Double) -> Double {
        guard frameTimeMs.isFinite, frameTimeMs > 0, maxFPS > 0 else { return frameTimeMs }
        return max(frameTimeMs, 1000.0 / maxFPS)
    }

    private static func displayRefreshRateCapFPS() -> Double {
        let refreshRates = NSScreen.screens
            .map { Double($0.maximumFramesPerSecond) }
            .filter { $0.isFinite && $0 > 0 }
        return max(refreshRates.max() ?? 120, 120)
    }

    private static func estimatedScenarioElapsed(
        at absoluteTime: TimeInterval,
        using timelineMarkers: [TimelineMarker]
    ) -> Double? {
        guard let nearestMarker = timelineMarkers.min(by: {
            abs($0.createdAt - absoluteTime) < abs($1.createdAt - absoluteTime)
        }) else {
            return nil
        }

        return max(0, nearestMarker.elapsedTime + absoluteTime - nearestMarker.createdAt)
    }
}

struct WorkloadHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkloadSummaryPanel: View {
    let metrics: [WorkloadSummaryMetric]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(metric.value)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .foregroundStyle(metric.valueColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WorkloadMetricSeriesSample: Identifiable {
    var id: Int { iteration }
    let iteration: Int
    let elapsedSeconds: Double
    let value: Double
}

enum WorkloadMetricSLODirection {
    case lowerIsBetter
    case higherIsBetter
    case none
}

final class WorkloadMetricSeriesMonitor: ObservableObject {
    @Published private(set) var samples: [WorkloadMetricSeriesSample] = []
    @Published private(set) var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Published private(set) var baselineMeanValue: Double?
    @Published private(set) var baselineP95Value: Double?

    private let chartWindowSeconds = WorkloadChartDefaults.recentWindowSeconds
    private let baselineSampleStartSeconds = 3.0
    private let baselineSampleEndSeconds = 8.0
    private var baselineValues: [Double] = []
    private var timelineMarkers: [TimelineMarker] = []
    private var sampleOriginAbsoluteTime: TimeInterval?
    private var sampleOriginScenarioElapsed: Double?
    private var lastChartSampleElapsed: TimeInterval?

    func reset() {
        samples = []
        baselineMeanValue = nil
        baselineP95Value = nil
        baselineValues = []
        timelineMarkers = []
        sampleOriginAbsoluteTime = nil
        sampleOriginScenarioElapsed = nil
        lastChartSampleElapsed = nil
    }

    func updateChartDisplayMode(_ mode: WorkloadChartDisplayMode) {
        guard mode != chartDisplayMode else { return }
        chartDisplayMode = mode
        trimSamplesToDisplayMode()
    }

    func updateTimelineMarkers(_ timelineMarkers: [TimelineMarker]) {
        self.timelineMarkers = timelineMarkers
        resolveSampleOriginScenarioElapsedIfNeeded()
        captureBaselineIfNeeded()
    }

    func beginSampling(at absoluteTime: TimeInterval = CFAbsoluteTimeGetCurrent()) {
        guard sampleOriginAbsoluteTime == nil else { return }
        sampleOriginAbsoluteTime = absoluteTime
        resolveSampleOriginScenarioElapsedIfNeeded()
    }

    func record(iteration: Int, value: Double, elapsedSinceStart: TimeInterval) {
        record(
            iteration: iteration,
            value: value,
            sampleStartElapsed: elapsedSinceStart,
            sampleEndElapsed: elapsedSinceStart
        )
    }

    func record(
        iteration: Int,
        value: Double,
        sampleStartElapsed: TimeInterval,
        sampleEndElapsed: TimeInterval
    ) {
        guard sampleEndElapsed >= WorkloadChartDefaults.warmupHiddenSeconds,
              value.isFinite,
              value > 0 else {
            return
        }

        beginSampling(at: CFAbsoluteTimeGetCurrent() - sampleEndElapsed)
        let chartElapsed = max(sampleStartElapsed, WorkloadChartDefaults.warmupHiddenSeconds)

        updateBaselineSamples(elapsed: chartElapsed, value: value)
        guard shouldRecordChartSample(elapsed: chartElapsed) else { return }

        samples.append(
            WorkloadMetricSeriesSample(
                iteration: iteration,
                elapsedSeconds: chartElapsed,
                value: value
            )
        )
        trimSamplesToDisplayMode(currentElapsed: chartElapsed)
    }

    func chartYDomain() -> ClosedRange<Double> {
        var values = samples.map(\.value)
        values += [baselineMeanValue, baselineP95Value].compactMap { $0 }
        return WorkloadChartDefaults.dynamicYDomain(for: values)
    }

    func chartWindowStart() -> Double {
        switch chartDisplayMode {
        case .recent:
            return max(0, (samples.last?.elapsedSeconds ?? 0) - chartWindowSeconds)
        case .fullRun:
            return 0
        }
    }

    func chartXDomain() -> ClosedRange<Double> {
        switch chartDisplayMode {
        case .recent:
            return 0...chartWindowSeconds
        case .fullRun:
            return 0...max(1, samples.last?.elapsedSeconds ?? 1)
        }
    }

    func chartXAxisLabel() -> String {
        switch chartDisplayMode {
        case .recent:
            return "Last 5s"
        case .fullRun:
            return "Full run"
        }
    }

    func chartEventMarkers() -> [TimelineMarker] {
        timelineMarkers.filter {
            let xPosition = chartEventXPosition(for: $0)
            let xUpperBound = chartXDomain().upperBound
            return xPosition > 0
                && xPosition < xUpperBound
                && WorkloadChartAnnotations.isChartEventLabel($0.label)
        }
    }

    func chartEventXPosition(for marker: TimelineMarker) -> Double {
        marker.elapsedTime - chartOriginElapsed() - chartWindowStart()
    }

    private func trimSamplesToDisplayMode(currentElapsed: Double? = nil) {
        switch chartDisplayMode {
        case .recent:
            let latestElapsed = currentElapsed ?? samples.last?.elapsedSeconds ?? 0
            samples.removeAll { latestElapsed - $0.elapsedSeconds > chartWindowSeconds }
            if samples.count > WorkloadChartDefaults.recentMaxHistorySamples {
                samples.removeFirst(samples.count - WorkloadChartDefaults.recentMaxHistorySamples)
            }
        case .fullRun:
            decimateFullRunSamplesIfNeeded()
        }
    }

    private func shouldRecordChartSample(elapsed: Double) -> Bool {
        guard let lastChartSampleElapsed else {
            self.lastChartSampleElapsed = elapsed
            return true
        }
        guard elapsed - lastChartSampleElapsed >= WorkloadChartDefaults.chartSampleIntervalSeconds else {
            return false
        }
        self.lastChartSampleElapsed = elapsed
        return true
    }

    private func decimateFullRunSamplesIfNeeded() {
        guard samples.count > WorkloadChartDefaults.fullRunMaxHistorySamples else { return }

        let stride = max(2, Int(ceil(Double(samples.count) / Double(WorkloadChartDefaults.fullRunMaxHistorySamples))))
        let lastIndex = samples.count - 1
        samples = samples.enumerated().compactMap { index, sample in
            if index == lastIndex || index % stride == 0 {
                return sample
            }
            return nil
        }
    }

    private func updateBaselineSamples(elapsed: Double, value: Double) {
        guard baselineP95Value == nil,
              !timelineMarkers.contains(where: { $0.label == "Foreground Only End" }),
              elapsed >= baselineSampleStartSeconds,
              elapsed <= baselineSampleEndSeconds,
              value.isFinite,
              value > 0 else {
            return
        }

        baselineValues.append(value)
    }

    private func captureBaselineIfNeeded() {
        guard baselineP95Value == nil,
              timelineMarkers.contains(where: { $0.label == "Foreground Only End" }) else {
            return
        }

        let sortedValues = baselineValues
            .filter { $0.isFinite && $0 > 0 }
            .sorted()

        if let meanValue = Self.mean(sortedValues),
           let p95Value = Self.percentile(sortedValues, percentile: 0.95) {
            baselineMeanValue = meanValue
            baselineP95Value = p95Value
        }
    }

    private func chartOriginElapsed() -> Double {
        if let sampleOriginScenarioElapsed {
            return sampleOriginScenarioElapsed
        }

        if let sampleOriginAbsoluteTime,
           let estimatedElapsed = Self.estimatedScenarioElapsed(
            at: sampleOriginAbsoluteTime,
            using: timelineMarkers
           ) {
            return estimatedElapsed
        }

        return workloadStartElapsed()
    }

    private func resolveSampleOriginScenarioElapsedIfNeeded() {
        guard sampleOriginScenarioElapsed == nil,
              let sampleOriginAbsoluteTime,
              let estimatedElapsed = Self.estimatedScenarioElapsed(
                at: sampleOriginAbsoluteTime,
                using: timelineMarkers
              ) else {
            return
        }

        sampleOriginScenarioElapsed = estimatedElapsed
    }

    private func workloadStartElapsed() -> Double {
        timelineMarkers.first(where: { $0.label == "Foreground Only Start" })?.elapsedTime ?? 0
    }

    private static func percentile(_ sortedValues: [Double], percentile: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        guard sortedValues.count > 1 else { return sortedValues[0] }

        let clampedPercentile = min(1, max(0, percentile))
        let position = clampedPercentile * Double(sortedValues.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))

        if lowerIndex == upperIndex {
            return sortedValues[lowerIndex]
        }

        let fraction = position - Double(lowerIndex)
        return sortedValues[lowerIndex] + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * fraction
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func estimatedScenarioElapsed(
        at absoluteTime: TimeInterval,
        using timelineMarkers: [TimelineMarker]
    ) -> Double? {
        guard let nearestMarker = timelineMarkers.min(by: {
            abs($0.createdAt - absoluteTime) < abs($1.createdAt - absoluteTime)
        }) else {
            return nil
        }

        return max(0, nearestMarker.elapsedTime + absoluteTime - nearestMarker.createdAt)
    }
}

struct WorkloadMetricChart: View {
    @ObservedObject var monitor: WorkloadMetricSeriesMonitor
    let title: String
    let yAxisLabel: String
    let lineColor: Color
    var trailingText: String?
    var sloDirection: WorkloadMetricSLODirection = .none
    var height: CGFloat = 220

    var body: some View {
        let yDomain = monitor.chartYDomain()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart {
                ForEach(monitor.samples) { sample in
                    let xPosition = sample.elapsedSeconds - monitor.chartWindowStart()

                    AreaMark(
                        x: .value("Elapsed", xPosition),
                        yStart: .value(yAxisLabel, yDomain.lowerBound),
                        yEnd: .value(yAxisLabel, sample.value)
                    )
                    .foregroundStyle(lineColor.opacity(0.18))

                    LineMark(
                        x: .value("Elapsed", xPosition),
                        y: .value(yAxisLabel, sample.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineColor)
                }

                if let baselineMeanValue = monitor.baselineMeanValue {
                    RuleMark(y: .value("Baseline Mean", baselineMeanValue))
                        .foregroundStyle(.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .annotation(position: .overlay, alignment: .leading, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                            lineLabel("Baseline Mean", color: .yellow)
                        }
                }

                if let baselineP95Value = monitor.baselineP95Value {
                    RuleMark(y: .value("Baseline P95", baselineP95Value))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .annotation(position: .overlay, alignment: .leading, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                            lineLabel(
                                p95Label,
                                color: .blue
                            )
                        }
                }

                ForEach(monitor.chartEventMarkers()) { marker in
                    RuleMark(x: .value("Event", monitor.chartEventXPosition(for: marker)))
                        .foregroundStyle(WorkloadChartAnnotations.eventColor(for: marker.label))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text(WorkloadChartAnnotations.displayLabel(for: marker.label))
                                .font(.caption2.monospaced())
                                .foregroundStyle(WorkloadChartAnnotations.eventColor(for: marker.label))
                        }
                }
            }
            .chartXScale(domain: monitor.chartXDomain())
            .chartYScale(domain: yDomain)
            .chartXAxisLabel(monitor.chartXAxisLabel())
            .chartYAxisLabel(yAxisLabel)
            .frame(height: height)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var p95Label: String {
        switch sloDirection {
        case .lowerIsBetter:
            return "SLO (Baseline P95)"
        case .higherIsBetter, .none:
            return "Baseline P95"
        }
    }

    private func lineLabel(_ label: String, color: Color, yOffset: CGFloat = -12) -> some View {
        Text(label)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .offset(x: 8, y: yOffset)
    }
}

struct ForegroundFrameRateSummaryPanel: View {
    @ObservedObject var monitor: ForegroundFrameRateMonitor
    let isActive: Bool
    let tokensPerSecond: Double
    var additionalMetrics: [WorkloadSummaryMetric] = []

    var body: some View {
        WorkloadSummaryPanel(metrics: baseMetrics + additionalMetrics)
    }

    private var baseMetrics: [WorkloadSummaryMetric] {
        [
            WorkloadSummaryMetric("State", value: isActive ? "Running" : "Idle"),
            WorkloadSummaryMetric("Live FPS", value: String(format: "%.1f", monitor.currentFPS)),
            WorkloadSummaryMetric("Recent FPS", value: String(format: "%.1f", monitor.recentFPS)),
            WorkloadSummaryMetric("Run Avg FPS", value: String(format: "%.1f", monitor.averageFPS)),
            WorkloadSummaryMetric("SLO Target", value: monitor.foregroundSLOTargetText),
            WorkloadSummaryMetric(
                "Current SLO Deficit",
                value: monitor.currentSLOViolationText(isActive: isActive),
                valueColor: monitor.currentSLOViolationColor(isActive: isActive)
            ),
            WorkloadSummaryMetric(
                "Cumulative SLO Deficit",
                value: monitor.cumulativeSLOViolationText,
                valueColor: monitor.cumulativeSLOViolationColor
            ),
            WorkloadSummaryMetric(
                "SLO Violation Time",
                value: monitor.sloViolationTimeText,
                valueColor: monitor.sloViolationTimeColor
            ),
            .llmTokensPerSecond(tokensPerSecond)
        ]
    }
}

struct ForegroundFrameRateChart: View {
    @ObservedObject var monitor: ForegroundFrameRateMonitor
    let lineColor: Color

    var body: some View {
        let yDomain = monitor.chartYDomain()

        VStack(alignment: .leading, spacing: 12) {
            Text("Frame Rate")
                .font(.headline)

            Chart {
                ForEach(monitor.samples) { sample in
                    let xPosition = sample.elapsedSeconds - monitor.chartWindowStart()

                    AreaMark(
                        x: .value("Elapsed", xPosition),
                        yStart: .value("FPS", yDomain.lowerBound),
                        yEnd: .value("FPS", sample.smoothFPS)
                    )
                    .foregroundStyle(lineColor.opacity(0.16))

                    LineMark(
                        x: .value("Elapsed", xPosition),
                        y: .value("FPS", sample.smoothFPS)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineColor)
                }

                if let baselineMeanFPS = monitor.foregroundBaselineMeanFPS {
                    RuleMark(y: .value("Baseline Mean", baselineMeanFPS))
                        .foregroundStyle(.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .annotation(position: .overlay, alignment: .leading, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                            lineLabel("Baseline Mean", color: .yellow)
                        }
                }

                if let sloFPS = monitor.foregroundSLOFPS() {
                    RuleMark(y: .value("SLO", sloFPS))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .annotation(position: .overlay, alignment: .leading, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                            lineLabel(monitor.foregroundSLOLabel(), color: .blue)
                        }
                }

                ForEach(monitor.chartEventMarkers()) { marker in
                    RuleMark(x: .value("Event", monitor.chartEventXPosition(for: marker)))
                        .foregroundStyle(WorkloadChartAnnotations.eventColor(for: marker.label))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text(WorkloadChartAnnotations.displayLabel(for: marker.label))
                                .font(.caption2.monospaced())
                                .foregroundStyle(WorkloadChartAnnotations.eventColor(for: marker.label))
                        }
                }
            }
            .chartXScale(domain: monitor.chartXDomain())
            .chartYScale(domain: yDomain)
            .chartXAxisLabel(monitor.chartXAxisLabel())
            .chartYAxisLabel("FPS (Frames Per Second)")
            .frame(height: 230)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func lineLabel(_ label: String, color: Color, yOffset: CGFloat = -12) -> some View {
        Text(label)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .offset(x: 8, y: yOffset)
    }

}
