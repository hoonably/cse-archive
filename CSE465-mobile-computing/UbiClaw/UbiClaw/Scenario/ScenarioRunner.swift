import Foundation
import os

struct TimelineMarker: Identifiable {
    let id = UUID()
    let elapsedTime: Double
    let label: String
    let createdAt: TimeInterval

    init(elapsedTime: Double, label: String, createdAt: TimeInterval = CFAbsoluteTimeGetCurrent()) {
        self.elapsedTime = elapsedTime
        self.label = label
        self.createdAt = createdAt
    }
}

enum ScenarioStatusStepState {
    case running
    case completed
    case failed
    case cancelled
}

struct ScenarioStatusStep: Identifiable {
    let id = UUID()
    let title: String
    let startedAt: TimeInterval
    var elapsedSeconds: TimeInterval = 0
    var state: ScenarioStatusStepState = .running

    init(title: String, startedAt: TimeInterval = CFAbsoluteTimeGetCurrent()) {
        self.title = title
        self.startedAt = startedAt
    }
}

enum LLMQoSMode: Int, CaseIterable, Identifiable {
    case userInitiated = 0
    case utility = 1
    case background = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .userInitiated:
            return "Normal"
        case .utility:
            return "Utility"
        case .background:
            return "Background"
        }
    }

    var markerLabel: String {
        switch self {
        case .userInitiated:
            return "QoS Normal"
        case .utility:
            return "QoS Utility"
        case .background:
            return "QoS Background"
        }
    }

    var bridgeMode: Int {
        rawValue
    }
}

/// Orchestrates the scenario timeline across idle, foreground, and LLM phases.
/// Drives workload activation and LLM engine lifecycle.
@Observable
@MainActor
final class ScenarioRunner {
    var config: AppConfig
    let mactopTelemetry: MactopTelemetryManager
    var currentPhase: ScenarioPhase = .notStarted
    var isRunning = false
    var isWorkloadActive = false
    var isLLMActive = false
    var statusMessage = "Ready"
    var statusSteps: [ScenarioStatusStep] = []
    var timelineMarkers: [TimelineMarker] = []
    var externalProcessOutput = ""
    var elapsedTime: TimeInterval = 0
    var isManualGenerationRunning = false
    var decodeDelayMs: Int = DecodeDelayDefaults.minimumMs
    var llmQoSMode: LLMQoSMode = .userInitiated
    var isGenerationPaused: Bool = false
    var llmTokensPerSecond: Double = 0
    var llmAverageTokensPerSecond: Double = 0
    var llmDisplayedTokensPerSecond: Double {
        isLLMActive || isManualGenerationRunning ? llmTokensPerSecond : llmAverageTokensPerSecond
    }
    var politeLLMStatusText = "Idle"
    var politeLLMProfileText = "No profile"
    var politeLLMLastActionText = "—"
    var isMeasurementActive: Bool {
        isRunning && logger != nil
    }

    private(set) var logger: CSVLogger?
    private(set) var mactopLogFilePath: String?
    private var llmEngine: (any LLMEngine)?
    private var inProcessEngine: InProcessLLMEngine?
    private var runTask: Task<Void, Never>?
    private var llmTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var statusStepTask: Task<Void, Never>?
    private var mactopLogTask: Task<Void, Never>?
    private var outputFlushTask: Task<Void, Never>?
    private var mactopLogger: MactopTelemetryCSVLogger?
    private var llmOutputUnits = 0
    private var llmRateWindowStart = CFAbsoluteTimeGetCurrent()
    private var llmRateWindowUnits = 0
    private var llmPhaseStartTime: TimeInterval?
    private var llmPhaseStartOutputUnits = 0
    private var pendingExternalOutput = ""
    private var measurementStartTime: TimeInterval?
    private let outputFlushInterval: Duration = .milliseconds(75)
    private let politeLLMController = PoliteLLMController()
    private let politeLLMAblationController = PoliteLLMAblationController()

    init(config: AppConfig, mactopTelemetry: MactopTelemetryManager) {
        self.config = config
        self.mactopTelemetry = mactopTelemetry
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timelineMarkers = []
        externalProcessOutput = ""
        elapsedTime = 0
        llmTokensPerSecond = 0
        llmAverageTokensPerSecond = 0
        llmOutputUnits = 0
        llmRateWindowUnits = 0
        llmRateWindowStart = CFAbsoluteTimeGetCurrent()
        llmPhaseStartTime = nil
        llmPhaseStartOutputUnits = 0
        pendingExternalOutput = ""
        // Restore LLM throttle to a clean baseline so polite-mode adjustments
        // from a previous run can't leak into the next measurement.
        decodeDelayMs = DecodeDelayDefaults.minimumMs
        llmQoSMode = .userInitiated
        isGenerationPaused = false
        resetPoliteLLMForRun()
        resetPoliteLLMAblationForRun()
        currentPhase = .notStarted
        statusMessage = "Preparing"
        resetStatusSteps()
        timerTask?.cancel()
        timerTask = nil
        mactopLogTask?.cancel()
        mactopLogTask = nil
        logger?.close()
        logger = nil
        mactopLogger?.close()
        mactopLogger = nil
        outputFlushTask?.cancel()
        outputFlushTask = nil
        mactopLogFilePath = nil
        measurementStartTime = nil
        inProcessEngine?.setLogger(nil)
        llmEngine = nil
        inProcessEngine = nil

        runTask = Task { await runScenario() }
    }

    func stop() {
        runTask?.cancel()
        llmTask?.cancel()
        timerTask?.cancel()
        statusStepTask?.cancel()
        statusStepTask = nil
        mactopLogTask?.cancel()
        outputFlushTask?.cancel()
        llmEngine?.cancel()
        isRunning = false
        isWorkloadActive = false
        isLLMActive = false
        currentPhase = .notStarted
        statusMessage = "Stopped"
        finishActiveStatusStep(as: .cancelled)
        externalProcessOutput = ""
        pendingExternalOutput = ""
        llmTokensPerSecond = 0
        llmAverageTokensPerSecond = 0
        llmPhaseStartTime = nil
        llmPhaseStartOutputUnits = 0
        isGenerationPaused = false
        politeLLMStatusText = "Idle"
        logger?.close()
        logger = nil
        mactopLogger?.close()
        mactopLogger = nil
        measurementStartTime = nil
        inProcessEngine?.setLogger(nil)
    }

    // MARK: - Private

    private func resetStatusSteps() {
        statusStepTask?.cancel()
        statusStepTask = nil
        statusSteps = []
    }

    private func startStatusStep(_ title: String) {
        finishActiveStatusStep(as: .completed)
        statusSteps.append(ScenarioStatusStep(title: title))
        startStatusStepTimerIfNeeded()
    }

    private func finishActiveStatusStep(as state: ScenarioStatusStepState) {
        guard let index = statusSteps.indices.last,
              statusSteps[index].state == .running else { return }

        statusSteps[index].elapsedSeconds = CFAbsoluteTimeGetCurrent() - statusSteps[index].startedAt
        statusSteps[index].state = state
    }

    private func appendCompletedStatusStep(_ title: String) {
        statusSteps.append(ScenarioStatusStep(title: title))
        finishActiveStatusStep(as: .completed)
    }

    private func startStatusStepTimerIfNeeded() {
        guard statusStepTask == nil else { return }

        statusStepTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshActiveStatusStep()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopStatusStepTimer() {
        statusStepTask?.cancel()
        statusStepTask = nil
    }

    private func refreshActiveStatusStep() {
        guard let index = statusSteps.indices.last,
              statusSteps[index].state == .running else { return }

        statusSteps[index].elapsedSeconds = CFAbsoluteTimeGetCurrent() - statusSteps[index].startedAt
    }

    private func prepareModelIfNeeded(wantsLLM: Bool) async -> Bool {
        guard wantsLLM else { return true }

        switch config.llmBackend {
        case .inProcess:
            currentPhase = .loadingModel
            statusMessage = "Loading model"
            startStatusStep("Model Load")
            llmEngine = makeLLMEngine(logger: nil)

            guard let inProcessEngine else { return false }
            let loaded = await inProcessEngine.preloadModelAsync()
            guard loaded else {
                finishActiveStatusStep(as: .failed)
                return false
            }

            finishActiveStatusStep(as: .completed)
            statusMessage = "Model loaded"
            return true

        case .external:
            appendCompletedStatusStep("External Backend Ready")
            statusMessage = "External backend ready"
            return true
        }
    }

    private func runPreMeasurementStartDelay() async {
        let delay = max(0, config.durations.startDelay)
        guard delay > 0 else { return }

        currentPhase = .startDelay
        statusMessage = "Starting in \(String(format: "%.1f", delay))s"
        startStatusStep("Start Delay")
        try? await Task.sleep(for: .seconds(delay))
        finishActiveStatusStep(as: .completed)
    }

    private func startMeasurement() {
        logger = CSVLogger(outputDir: config.outputDir, scenarioName: config.scenario.rawValue)
        mactopLogger = MactopTelemetryCSVLogger(outputDir: config.outputDir, scenarioName: config.scenario.rawValue)
        mactopLogFilePath = mactopLogger?.filePath
        inProcessEngine?.setLogger(logger)

        elapsedTime = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        measurementStartTime = startTime
        timerTask = Task {
            while !Task.isCancelled {
                elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        mactopLogTask = Task { await runMactopLoggingLoop() }
    }

    private func makeLLMEngine(logger: CSVLogger?) -> any LLMEngine {
        switch config.llmBackend {
        case .inProcess:
            let engine = InProcessLLMEngine(
                modelPath: config.externalModelPath,
                nCtx: 2048,
                logger: logger,
                outputHandler: { [weak self] chunk in
                    guard let runner = self else { return }
                    Task { @MainActor in
                        runner.appendExternalOutput(chunk)
                    }
                }
            )
            inProcessEngine = engine
            engine.setDecodeDelayMs(decodeDelayMs)
            engine.setQoSMode(llmQoSMode)
            engine.setGenerationPaused(isGenerationPaused)
            return engine

        case .external:
            inProcessEngine = nil
            return ExternalProcessLLMEngine(
                command: config.externalCommand,
                modelPath: config.externalModelPath,
                extraArguments: config.externalArgs,
                logger: logger,
                outputHandler: { [weak self] chunk in
                    guard let runner = self else { return }
                    Task { @MainActor in
                        runner.appendExternalOutput(chunk)
                    }
                }
            )
        }
    }

    func setDecodeDelay(_ ms: Int, source: String = "manual", reason: String = "") {
        let clampedMs = DecodeDelayDefaults.clamp(ms)
        let changed = decodeDelayMs != clampedMs
        decodeDelayMs = clampedMs
        if let engine = inProcessEngine {
            engine.setDecodeDelayMs(clampedMs)
        }
        if changed || source == "manual" {
            appendMarker("Delay \(clampedMs)ms")
        }
        logPoliteLLMActionIfNeeded(source: source, kind: "delay", value: "\(clampedMs)ms", reason: reason)
    }

    func setLLMQoSMode(_ mode: LLMQoSMode, source: String = "manual", reason: String = "") {
        guard llmQoSMode != mode else { return }
        llmQoSMode = mode
        if let engine = inProcessEngine {
            engine.setQoSMode(mode)
        }
        appendMarker(mode.markerLabel)
        logPoliteLLMActionIfNeeded(source: source, kind: "qos", value: mode.displayName, reason: reason)
    }

    func setGenerationPaused(_ paused: Bool) {
        guard isGenerationPaused != paused else { return }
        isGenerationPaused = paused
        if let engine = inProcessEngine {
            engine.setGenerationPaused(paused)
        }
        if paused {
            llmTokensPerSecond = 0
        } else {
            llmRateWindowStart = CFAbsoluteTimeGetCurrent()
            llmRateWindowUnits = 0
        }
        appendMarker(paused ? "Gen Pause" : "Gen Resume")
    }

    func startManualGeneration() {
        guard !isManualGenerationRunning else { return }

        externalProcessOutput = ""
        isManualGenerationRunning = true
        llmTokensPerSecond = 0
        llmAverageTokensPerSecond = 0
        llmOutputUnits = 0
        llmRateWindowUnits = 0
        llmRateWindowStart = CFAbsoluteTimeGetCurrent()
        llmPhaseStartTime = nil
        llmPhaseStartOutputUnits = 0
        pendingExternalOutput = ""
        outputFlushTask?.cancel()
        outputFlushTask = nil
        isGenerationPaused = false
        appendMarker("Gen Start")

        let engine = llmEngine ?? makeLLMEngine(logger: logger)
        llmEngine = engine
        inProcessEngine?.setGenerationPaused(false)
        let prompt = config.externalPrompt

        llmTask = Task.detached { [weak self] in
            do {
                try await engine.inference(prompt: prompt)
            } catch {
                let runner = self
                await MainActor.run {
                    runner?.recordManualGenerationError()
                }
            }

            let runner = self
            await MainActor.run {
                runner?.finishManualGeneration()
            }
        }
    }

    func stopManualGeneration() {
        inProcessEngine?.setGenerationPaused(false)
        llmEngine?.cancel()
        llmTask?.cancel()
        llmTask = nil
        isManualGenerationRunning = false
        isGenerationPaused = false
        appendMarker("Gen Cancel")
    }

    private func runScenario() async {
        let wantsForeground = config.scenario == .foregroundOnly || config.scenario == .overlap
        let wantsLLM = config.scenario == .overlap || config.scenario == .llmInferenceOnly
        let wantsRecovery = wantsLLM

        guard await prepareModelIfNeeded(wantsLLM: wantsLLM) else {
            statusMessage = "Model load failed"
            currentPhase = .notStarted
            isRunning = false
            stopStatusStepTimer()
            return
        }
        guard !Task.isCancelled else { return }

        await runPreMeasurementStartDelay()
        guard !Task.isCancelled else { return }

        startMeasurement()
        let scenarioState = Signposts.beginScenario(config.scenario.rawValue)
        appendMarker("Scenario Start")
        logCSV("scenario_start")

        if wantsLLM && llmEngine == nil {
            llmEngine = makeLLMEngine(logger: logger)
        }

        if config.scenario == .foregroundOnly {
            isWorkloadActive = true
            await runPhase(.foreground, duration: config.durations.foreground)
            finalizePoliteLLMForegroundProfileIfNeeded()
            guard !Task.isCancelled else { return finish(scenarioState) }
            isWorkloadActive = false
            finish(scenarioState)
            currentPhase = .completed
            statusMessage = "Scenario completed"
            isRunning = false
            timerTask?.cancel()
            return
        }

        // Foreground lead-in or LLM-only monitor lead-in before background inference starts.
        if config.scenario == .overlap {
            isWorkloadActive = true
            await runPhase(.foreground, duration: config.durations.foreground)
            applyInitialPoliteLLMProfileIfNeeded()
            applyInitialPoliteLLMAblationProfileIfNeeded()
            guard !Task.isCancelled else { return finish(scenarioState) }
        } else if config.scenario == .llmInferenceOnly {
            await runPhase(.idle, duration: config.durations.foreground)
            guard !Task.isCancelled else { return finish(scenarioState) }
        }

        if wantsLLM {
            llmTokensPerSecond = 0
            llmAverageTokensPerSecond = 0
            llmRateWindowUnits = 0
            llmRateWindowStart = CFAbsoluteTimeGetCurrent()
            llmPhaseStartTime = nil
            llmPhaseStartOutputUnits = llmOutputUnits
            isLLMActive = true
            let engine = llmEngine
            let prompt = config.externalPrompt
            llmTask = Task.detached {
                do {
                    try await engine?.inference(prompt: prompt)
                } catch {
                    // LLM cancelled or errored — expected on stop
                }
            }
            await runLLMPhase(config.scenario == .llmInferenceOnly ? .llmInferenceOnly : .overlap)
            isLLMActive = false
            llmTask = nil
            llmTokensPerSecond = 0
            guard !Task.isCancelled else { return finish(scenarioState) }
        }

        // Phase 4: post-LLM recovery. In overlap scenarios, foreground keeps running
        // while only the LLM is stopped; in LLM-only scenarios, measurement stays active.
        if wantsRecovery {
            await runPhase(.recovery, duration: config.durations.recovery)
            isWorkloadActive = false
            guard !Task.isCancelled else { return finish(scenarioState) }
        }

        if wantsForeground && !wantsRecovery {
            isWorkloadActive = false
        }

        finish(scenarioState)
        currentPhase = .completed
        statusMessage = "Scenario completed"
        isRunning = false
        timerTask?.cancel()
        stopStatusStepTimer()
    }

    private func runPhase(_ phase: ScenarioPhase, duration: TimeInterval) async {
        beginPhase(phase)
        try? await Task.sleep(for: .seconds(max(0, duration)))
        endPhase(phase)
    }

    private func runLLMPhase(_ phase: ScenarioPhase) async {
        beginPhase(phase)
        beginLLMThroughputMeasurement()

        let cap = max(0, config.durations.llmInference)
        let llmTask = self.llmTask

        // Side task that fires after `cap` seconds and force-stops the LLM if it
        // is still running. We can't race inside withTaskGroup because
        // `Task<Void, Never>.value` is non-cancellable — cancelling the group
        // would block until the LLM finished anyway.
        let capTask: Task<Void, Never>? = (cap > 0 && llmTask != nil)
            ? Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(cap))
                guard !Task.isCancelled else { return }
                self?.enforceLLMCap(cap: cap)
            }
            : nil

        await llmTask?.value
        capTask?.cancel()

        logLLMThroughputSummary(phase: phase)
        endPhase(phase)
    }

    private func enforceLLMCap(cap: Double) {
        guard isLLMActive else { return }
        llmEngine?.cancel()
        logCSV("llm_inference_capped", params: "cap_seconds=\(String(format: "%.1f", cap))")
        appendMarker("LLM Capped")
    }

    private func beginPhase(_ phase: ScenarioPhase) {
        currentPhase = phase
        statusMessage = "Phase: \(phase.rawValue)"
        startStatusStep(statusTitle(for: phase))
        appendMarker("\(phase.rawValue) Start")
        logCSV("phase_start", params: phase.rawValue)
    }

    private func endPhase(_ phase: ScenarioPhase) {
        finishActiveStatusStep(as: .completed)
        appendMarker("\(phase.rawValue) End")
        logCSV("phase_end", params: phase.rawValue)
    }

    private func statusTitle(for phase: ScenarioPhase) -> String {
        switch phase {
        case .idle:
            return "LLM Baseline"
        case .foreground:
            return config.scenario == .foregroundOnly ? "Foreground" : "Foreground Baseline"
        case .overlap:
            return "Foreground + LLM"
        case .llmInferenceOnly:
            return "LLM Inference"
        case .recovery:
            return "LLM Stopped"
        case .loadingModel:
            return "Model Load"
        case .startDelay:
            return "Start Delay"
        case .notStarted:
            return "Ready"
        case .completed:
            return "Completed"
        }
    }

    private func finish(_ scenarioState: OSSignpostIntervalState) {
        guard isRunning else { return }
        finishActiveStatusStep(as: .completed)
        isWorkloadActive = false
        isLLMActive = false
        flushExternalOutput()
        appendMarker("Scenario End")
        logCSV("scenario_end")
        Signposts.endScenario(scenarioState)
        appendCompletedStatusStep("Scenario Complete")
        logger?.close()
        logger = nil
        mactopLogger?.close()
        mactopLogger = nil
        inProcessEngine?.setLogger(nil)
        measurementStartTime = nil
        outputFlushTask = nil
        mactopLogTask?.cancel()
        mactopLogTask = nil
        timerTask?.cancel()
        timerTask = nil
        stopStatusStepTimer()
    }

    private func appendMarker(_ label: String) {
        let now = CFAbsoluteTimeGetCurrent()
        let markerElapsedTime = measurementStartTime.map { max(0, now - $0) } ?? elapsedTime
        elapsedTime = markerElapsedTime
        timelineMarkers.append(TimelineMarker(elapsedTime: markerElapsedTime, label: label, createdAt: now))
    }

    private func appendExternalOutput(_ chunk: String) {
        if !chunk.isEmpty {
            pendingExternalOutput.append(chunk)
            scheduleOutputFlush()
        }

        llmOutputUnits += 1
        llmRateWindowUnits += 1

        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - llmRateWindowStart
        if elapsed >= 1.0 {
            llmTokensPerSecond = Double(llmRateWindowUnits) / elapsed
            llmRateWindowStart = now
            llmRateWindowUnits = 0
        }
    }

    private func beginLLMThroughputMeasurement() {
        llmPhaseStartTime = CFAbsoluteTimeGetCurrent()
        llmPhaseStartOutputUnits = llmOutputUnits
        llmAverageTokensPerSecond = 0
    }

    private func logLLMThroughputSummary(phase: ScenarioPhase) {
        guard let startTime = llmPhaseStartTime else { return }

        let elapsed = max(0, CFAbsoluteTimeGetCurrent() - startTime)
        let outputUnits = max(0, llmOutputUnits - llmPhaseStartOutputUnits)
        let averageTokensPerSecond = elapsed > 0 ? Double(outputUnits) / elapsed : 0
        llmAverageTokensPerSecond = averageTokensPerSecond

        logCSV(
            "llm_throughput_summary",
            params: [
                "phase=\(phase.rawValue)",
                "avg_tok_s=\(String(format: "%.3f", averageTokensPerSecond))",
                "tokens=\(outputUnits)",
                "elapsed_s=\(String(format: "%.3f", elapsed))",
                "live_tok_s=\(String(format: "%.3f", llmTokensPerSecond))"
            ].joined(separator: ",")
        )

        llmPhaseStartTime = nil
        llmPhaseStartOutputUnits = llmOutputUnits
    }

    private func scheduleOutputFlush() {
        guard outputFlushTask == nil else { return }

        outputFlushTask = Task { [weak self, interval = outputFlushInterval] in
            try? await Task.sleep(for: interval)
            self?.flushExternalOutput()
        }
    }

    private func flushExternalOutput() {
        outputFlushTask = nil
        guard !pendingExternalOutput.isEmpty else { return }

        externalProcessOutput.append(pendingExternalOutput)
        pendingExternalOutput.removeAll(keepingCapacity: true)

        if externalProcessOutput.count > 120_000 {
            externalProcessOutput.removeFirst(externalProcessOutput.count - 120_000)
        }
    }

    private func finishManualGeneration() {
        flushExternalOutput()
        isManualGenerationRunning = false
        appendMarker("Gen End")
    }

    private func recordManualGenerationError() {
        flushExternalOutput()
        appendMarker("Gen Error")
    }

    private func logCSV(_ event: String, params: String = "") {
        logger?.log(
            event: event,
            scenario: config.scenario.rawValue,
            workload: config.workload.rawValue,
            backend: config.llmBackend.rawValue,
            params: params
        )
    }

    func observeForegroundFrameRate(_ observation: ForegroundFrameRateObservation) {
        if shouldRunPoliteLLMAblationController {
            observeForegroundFrameRateForAblation(observation)
            return
        }

        guard shouldRunPoliteLLMController else { return }

        guard let action = politeLLMController.actionForFrame(
            observation,
            isLLMActive: isLLMActive,
            currentDelayMs: decodeDelayMs,
            currentQoSMode: llmQoSMode
        ) else {
            politeLLMStatusText = politeLLMController.statusText
            return
        }

        applyPoliteLLMAction(action)
    }

    private var shouldRunPoliteLLMController: Bool {
        config.politeLLMEnabled
            && config.llmBackend == .inProcess
            && config.scenario == .overlap
    }

    private func resetPoliteLLMForRun() {
        politeLLMController.resetForRun()
        politeLLMStatusText = config.politeLLMEnabled ? politeLLMController.statusText : "Off"
        politeLLMProfileText = "No profile"
        politeLLMLastActionText = "—"
    }

    private func observePoliteLLMHardwareSnapshot(_ snapshot: MactopTelemetrySnapshot) {
        guard config.politeLLMEnabled,
              config.llmBackend == .inProcess,
              config.scenario != .llmInferenceOnly else {
            return
        }

        politeLLMController.observeHardwareSnapshot(snapshot, phase: currentPhase)
    }

    private func finalizePoliteLLMForegroundProfileIfNeeded() {
        guard config.politeLLMEnabled,
              config.llmBackend == .inProcess else {
            return
        }

        guard let profile = politeLLMController.finalizeForegroundProfile(for: config.workload) else {
            politeLLMProfileText = "No profile"
            politeLLMStatusText = politeLLMController.statusText
            return
        }

        politeLLMProfileText = profile.summaryText
        politeLLMStatusText = politeLLMController.statusText
        logCSV("polite_llm_profile", params: profileLogParams(profile))
    }

    private func applyInitialPoliteLLMProfileIfNeeded() {
        guard shouldRunPoliteLLMController else { return }

        finalizePoliteLLMForegroundProfileIfNeeded()
        guard let profile = politeLLMController.bestProfile(for: config.workload) else { return }

        setLLMQoSMode(
            profile.suggestedQoSMode,
            source: "polite",
            reason: "foreground_profile_score=\(String(format: "%.3f", profile.pressureScore))"
        )
        politeLLMLastActionText = "Initial QoS \(profile.suggestedQoSMode.displayName)"
    }

    private func applyPoliteLLMAction(_ action: PoliteLLMAction) {
        var appliedDescriptions: [String] = []

        for command in action.commands {
            switch command {
            case .setDelay(let delayMs):
                guard delayMs != decodeDelayMs else { continue }
                setDecodeDelay(delayMs, source: "polite", reason: action.reason)
                appliedDescriptions.append("Delay \(delayMs)ms")
            case .setQoS(let mode):
                guard mode != llmQoSMode else { continue }
                setLLMQoSMode(mode, source: "polite", reason: action.reason)
                appliedDescriptions.append("QoS \(mode.displayName)")
            }
        }

        guard !appliedDescriptions.isEmpty else { return }
        politeLLMLastActionText = appliedDescriptions.joined(separator: " + ")
        politeLLMStatusText = politeLLMController.statusText
    }

    // MARK: - Polite LLM Ablation (Delay-Only / QoS-Only)

    private var shouldRunPoliteLLMAblationController: Bool {
        config.politeLLMAblation.isActive
            && config.llmBackend == .inProcess
            && config.scenario == .overlap
    }

    private func resetPoliteLLMAblationForRun() {
        politeLLMAblationController.configure(mode: config.politeLLMAblation)
        politeLLMAblationController.resetForRun()

        guard config.politeLLMAblation.isActive else { return }
        // Ablation runs in place of the full controller, so it owns the UI fields.
        politeLLMStatusText = politeLLMAblationController.statusText
        politeLLMProfileText = "No profile"
        politeLLMLastActionText = "—"
    }

    private func observePoliteLLMAblationHardwareSnapshot(_ snapshot: MactopTelemetrySnapshot) {
        guard config.politeLLMAblation.isActive,
              config.llmBackend == .inProcess,
              config.scenario != .llmInferenceOnly else {
            return
        }

        politeLLMAblationController.observeHardwareSnapshot(snapshot, phase: currentPhase)
    }

    private func applyInitialPoliteLLMAblationProfileIfNeeded() {
        guard shouldRunPoliteLLMAblationController else { return }

        guard let profile = politeLLMAblationController.finalizeForegroundProfile(for: config.workload) else {
            politeLLMProfileText = "No profile"
            politeLLMStatusText = politeLLMAblationController.statusText
            return
        }

        politeLLMProfileText = profile.summaryText
        politeLLMStatusText = politeLLMAblationController.statusText
        logCSV(
            "polite_llm_ablation_profile",
            params: "mode=\(config.politeLLMAblation.rawValue)," + profileLogParams(profile)
        )

        // Only the QoS-Only ablation seeds an initial QoS mode from the profile;
        // the Delay-Only ablation must never touch QoS.
        guard config.politeLLMAblation == .qosOnly else { return }

        setLLMQoSMode(
            profile.suggestedQoSMode,
            source: config.politeLLMAblation.logSource,
            reason: "foreground_profile_score=\(String(format: "%.3f", profile.pressureScore))"
        )
        logPoliteLLMAblationAction(kind: "qos", value: profile.suggestedQoSMode.displayName, reason: "initial_profile")
        politeLLMLastActionText = "Initial QoS \(profile.suggestedQoSMode.displayName)"
    }

    private func observeForegroundFrameRateForAblation(_ observation: ForegroundFrameRateObservation) {
        guard let action = politeLLMAblationController.actionForFrame(
            observation,
            isLLMActive: isLLMActive,
            currentDelayMs: decodeDelayMs,
            currentQoSMode: llmQoSMode
        ) else {
            politeLLMStatusText = politeLLMAblationController.statusText
            return
        }

        applyPoliteLLMAblationAction(action)
    }

    private func applyPoliteLLMAblationAction(_ action: PoliteLLMAction) {
        let source = config.politeLLMAblation.logSource
        var appliedDescriptions: [String] = []

        for command in action.commands {
            switch command {
            case .setDelay(let delayMs):
                guard delayMs != decodeDelayMs else { continue }
                setDecodeDelay(delayMs, source: source, reason: action.reason)
                logPoliteLLMAblationAction(kind: "delay", value: "\(delayMs)ms", reason: action.reason)
                appliedDescriptions.append("Delay \(delayMs)ms")
            case .setQoS(let mode):
                guard mode != llmQoSMode else { continue }
                setLLMQoSMode(mode, source: source, reason: action.reason)
                logPoliteLLMAblationAction(kind: "qos", value: mode.displayName, reason: action.reason)
                appliedDescriptions.append("QoS \(mode.displayName)")
            }
        }

        guard !appliedDescriptions.isEmpty else { return }
        politeLLMLastActionText = appliedDescriptions.joined(separator: " + ")
        politeLLMStatusText = politeLLMAblationController.statusText
    }

    private func logPoliteLLMAblationAction(kind: String, value: String, reason: String) {
        logCSV(
            "polite_llm_ablation_action",
            params: "mode=\(config.politeLLMAblation.rawValue),kind=\(kind),value=\(value),reason=\(reason),delay_ms=\(decodeDelayMs),qos=\(llmQoSMode.displayName)"
        )
    }

    private func logPoliteLLMActionIfNeeded(
        source: String,
        kind: String,
        value: String,
        reason: String
    ) {
        guard source == "polite" else { return }
        logCSV(
            "polite_llm_action",
            params: "kind=\(kind),value=\(value),reason=\(reason),delay_ms=\(decodeDelayMs),qos=\(llmQoSMode.displayName)"
        )
    }

    private func profileLogParams(_ profile: PoliteLLMHardwareProfile) -> String {
        [
            "samples=\(profile.sampleCount)",
            "score=\(String(format: "%.3f", profile.pressureScore))",
            "suggested_qos=\(profile.suggestedQoSMode.displayName)",
            "avg_cpu_percent=\(formattedOptional(profile.averageCPUUsagePercent))",
            "avg_gpu_percent=\(formattedOptional(profile.averageGPUUsagePercent))",
            "avg_process_gpu_ms_per_s=\(formattedOptional(profile.averageProcessGPUmsPerSecond))",
            "avg_dram_gbs=\(formattedOptional(profile.averageDRAMBandwidthGBs))"
        ].joined(separator: ",")
    }

    private func formattedOptional(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.3f", value)
    }

    private func runMactopLoggingLoop() async {
        while !Task.isCancelled {
            let snapshot = mactopTelemetry.currentSnapshot()
            mactopLogger?.log(
                snapshot: snapshot,
                elapsedTime: elapsedTime,
                scenario: config.scenario,
                workload: config.workload,
                backend: config.llmBackend,
                phase: currentPhase,
                llmTokensPerSecond: llmTokensPerSecond
            )
            observePoliteLLMHardwareSnapshot(snapshot)
            observePoliteLLMAblationHardwareSnapshot(snapshot)
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
