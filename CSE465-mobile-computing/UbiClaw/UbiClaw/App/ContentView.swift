import Charts
import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var config: AppConfig
    @Bindable var runner: ScenarioRunner
    @Bindable var mactopTelemetry: MactopTelemetryManager
    @State private var availableModelPaths: [String] = AppConfig.availableModelPaths()

    var body: some View {
        HSplitView {
            controlPanel
                .frame(minWidth: 280, maxWidth: 640)

            workloadArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightPanel
                .frame(minWidth: 280, maxWidth: 640)
        }
        .frame(minWidth: 1180, minHeight: 600)
        .onAppear {
            mactopTelemetry.start()
            if config.autoStart {
                runner.start()
            }
        }
        .onDisappear {
            mactopTelemetry.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            mactopTelemetry.stop()
        }
        .onChange(of: config.scenario) { oldValue, newValue in
            if newValue == .foregroundOnly && oldValue != .foregroundOnly {
                config.durations.foreground = 60
            } else if newValue == .overlap && oldValue != .overlap {
                config.durations.foreground = 10
            }
        }
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                appHeader

                GroupBox("Scenario") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Type", selection: $config.scenario) {
                            ForEach(ScenarioType.allCases) { s in
                                Text(s.displayName).tag(s)
                            }
                        }

                        if config.scenario != .llmInferenceOnly {
                            Picker("Foreground", selection: $config.workload) {
                                ForEach(WorkloadType.allCases, id: \.self) { w in
                                    Text(w.displayName).tag(w)
                                }
                            }
                        }
                    }
                }
                .disabled(runner.isRunning)

                if config.scenario != .llmInferenceOnly {
                    foregroundSLOControlPanel
                        .disabled(runner.isRunning)
                }

                GroupBox("Charts") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Range", selection: $config.chartDisplayMode) {
                            ForEach(WorkloadChartDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Recent keeps live charts light; Full Run keeps every visible sample for the whole run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(runner.isRunning)

                GroupBox("LLM Backend") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Backend", selection: $config.llmBackend) {
                            Text("llama.cpp").tag(LLMBackendType.inProcess)
                            Text("External CLI").tag(LLMBackendType.external)
                        }
                        .pickerStyle(.segmented)

                        if config.llmBackend == .external {
                            LabeledContent("Command") {
                                TextField("llama-cli", text: $config.externalCommand)
                            }
                            LabeledContent("Args") {
                                TextField("-cnv -st", text: $config.externalArgs, axis: .vertical)
                                    .lineLimit(2...4)
                            }
                        }

                        LabeledContent("Model") {
                            HStack(spacing: 6) {
                                Picker("", selection: modelPickerBinding) {
                                    if availableModelPaths.isEmpty {
                                        Text("").tag("" as String)
                                    } else {
                                        ForEach(availableModelPaths, id: \.self) { path in
                                            Text((path as NSString).lastPathComponent).tag(path)
                                        }
                                    }
                                    if !availableModelPaths.contains(config.externalModelPath)
                                        && !config.externalModelPath.isEmpty {
                                        Divider()
                                        Text("Custom: \((config.externalModelPath as NSString).lastPathComponent)")
                                            .tag(config.externalModelPath)
                                    }
                                }
                                .labelsHidden()

                                Button {
                                    let paths = AppConfig.availableModelPaths()
                                    availableModelPaths = paths
                                    if config.externalModelPath.isEmpty,
                                       let first = paths.first {
                                        config.externalModelPath = first
                                    }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Rescan Models/ directory")
                            }
                        }
                        if availableModelPaths.isEmpty {
                            Text("Place a .gguf model file in \(AppConfig.modelsDirectory().path), then rescan.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Path") {
                            TextField("model.gguf path", text: $config.externalModelPath)
                                .font(.system(.caption, design: .monospaced))
                        }
                        LabeledContent("Prompt") {
                            TextField("prompt", text: $config.externalPrompt, axis: .vertical)
                                .lineLimit(2...4)
                        }
                        if config.llmBackend == .external {
                            Text("External llama-cli arguments are passed through as-is.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(runner.isRunning)

                if config.llmBackend == .inProcess {
                    decodeDelayControlPanel
                }

                GroupBox("Phase Durations (s)") {
                    VStack(alignment: .leading, spacing: 6) {
                        durationField("Start Delay", value: $config.durations.startDelay)
                        if config.scenario == .llmInferenceOnly {
                            durationField("LLM Start Delay", value: $config.durations.foreground)
                            durationField("Inference (max)", value: $config.durations.llmInference)
                            durationField("Post-LLM", value: $config.durations.recovery)
                        } else if config.scenario == .foregroundOnly {
                            durationField("Foreground", value: $config.durations.foreground)
                        } else {
                            durationField("LLM Start Delay", value: $config.durations.foreground)
                            if config.scenario == .overlap {
                                durationField("Overlap (max)", value: $config.durations.llmInference)
                            }
                            durationField("Post-LLM", value: $config.durations.recovery)
                        }
                    }
                }
                .disabled(runner.isRunning)

                GroupBox("Output") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(config.outputDir)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(2)
                            .textSelection(.enabled)

                        if let mactopLogFilePath = runner.mactopLogFilePath {
                            Divider()
                            Text("mactop CSV")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(mactopLogFilePath)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }

                statusPanel

                HStack {
                    Spacer()
                    Button(runner.isRunning ? "Stop" : "Start Scenario") {
                        if runner.isRunning {
                            runner.stop()
                        } else {
                            runner.start()
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlSize(.large)
                    Spacer()
                }
            }
            .padding()
        }
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("UbiClaw")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var foregroundSLOControlPanel: some View {
        GroupBox("Foreground SLO") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Basis", selection: $config.foregroundSLOBasis) {
                    ForEach(ForegroundSLOBasis.allCases) { basis in
                        Text(basis.displayName).tag(basis)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Target") {
                    Text(foregroundSLOTargetText)
                        .font(.system(.body, design: .monospaced).bold())
                }

                if config.foregroundSLOBasis == .baselineMean {
                    HStack(spacing: 10) {
                        Text(String(format: "%.2f", ForegroundSLODefaults.multiplierRange.lowerBound))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: foregroundSLOMultiplierBinding,
                            in: ForegroundSLODefaults.multiplierRange,
                            step: 0.01
                        )
                        Text(String(format: "%.2f", ForegroundSLODefaults.multiplierRange.upperBound))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))

                    LabeledContent("Multiplier") {
                        TextField(
                            "",
                            value: foregroundSLOMultiplierBinding,
                            format: .number.precision(.fractionLength(2))
                        )
                        .frame(width: 60)
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(percentileText(ForegroundSLODefaults.percentileRange.lowerBound))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: foregroundSLOPercentilePercentBinding,
                            in: percentilePercentRange,
                            step: 1
                        )
                        Text(percentileText(ForegroundSLODefaults.percentileRange.upperBound))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))

                    LabeledContent("Percentile") {
                        TextField(
                            "",
                            value: foregroundSLOPercentilePercentBinding,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 60)
                    }
                }
            }
        }
    }

    private var foregroundSLOTargetText: String {
        switch config.foregroundSLOBasis {
        case .baselineMean:
            return String(
                format: "Mean x %.2f",
                config.foregroundSLOMultiplier
            )
        case .baselinePercentile:
            return "\(percentileText(config.foregroundSLOPercentile)) frame time"
        }
    }

    private func positiveIntBinding(_ keyPath: ReferenceWritableKeyPath<AppConfig, Int>) -> Binding<Int> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { config[keyPath: keyPath] = max(1, $0) }
        )
    }

    private var modelPickerBinding: Binding<String> {
        Binding(
            get: { config.externalModelPath },
            set: { config.externalModelPath = $0 }
        )
    }

    private func nonnegativeDoubleBinding(_ keyPath: ReferenceWritableKeyPath<AppConfig, Double>) -> Binding<Double> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { config[keyPath: keyPath] = max(0, $0) }
        )
    }

    private var foregroundSLOMultiplierBinding: Binding<Double> {
        Binding(
            get: { config.foregroundSLOMultiplier },
            set: { config.foregroundSLOMultiplier = ForegroundSLODefaults.clampMultiplier($0) }
        )
    }

    private var foregroundSLOPercentilePercentBinding: Binding<Double> {
        Binding(
            get: { config.foregroundSLOPercentile * 100 },
            set: {
                config.foregroundSLOPercentile = ForegroundSLODefaults.clampPercentile(
                    $0 / 100
                )
            }
        )
    }

    private var percentilePercentRange: ClosedRange<Double> {
        ForegroundSLODefaults.percentileRange.lowerBound * 100
            ... ForegroundSLODefaults.percentileRange.upperBound * 100
    }

    private func percentileText(_ percentile: Double) -> String {
        String(format: "P%.0f", percentile * 100)
    }

    private func durationField(_ label: String, value: Binding<TimeInterval>) -> some View {
        LabeledContent(label) {
            TextField("", value: value, format: .number)
                .frame(width: 60)
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if runner.statusSteps.isEmpty {
                        HStack {
                            Circle()
                                .fill(runner.isRunning ? .green : .gray)
                                .frame(width: 9, height: 9)
                            Text(runner.currentPhase.rawValue)
                            Spacer()
                            Text(String(format: "%.1fs", runner.elapsedTime))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(runner.statusSteps) { step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(statusColor(for: step.state))
                                    .frame(width: 8, height: 8)
                                Text(step.title)
                                    .foregroundStyle(step.state == .running ? .primary : .secondary)
                                Spacer(minLength: 8)
                                Text(statusLabel(for: step.state))
                                    .foregroundStyle(statusColor(for: step.state))
                                Text(String(format: "%.1fs", step.elapsedSeconds))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Measured")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1fs", runner.elapsedTime))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func statusColor(for state: ScenarioStatusStepState) -> Color {
        switch state {
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    private func statusLabel(for state: ScenarioStatusStepState) -> String {
        switch state {
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Stopped"
        }
    }

    // MARK: - LLM Throttle Control

    private var decodeDelayControlPanel: some View {
        GroupBox("LLM Throttle") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Polite LLM", isOn: $config.politeLLMEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: config.politeLLMEnabled) { _, isOn in
                        // Full Polite LLM and the ablations are mutually exclusive.
                        if isOn { config.politeLLMAblation = .none }
                    }

                Picker("Ablation:", selection: politeLLMAblationBinding) {
                    ForEach(PoliteLLMAblationKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(.caption, design: .monospaced))

                Text("Ablation runs a single-lever Polite LLM (delay only or QoS only) instead of the full controller.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Auto status:")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(runner.politeLLMStatusText)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(config.politeLLMEnabled || config.politeLLMAblation.isActive ? .blue : .secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Profile:")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(runner.politeLLMProfileText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Auto action:")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(runner.politeLLMLastActionText)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Divider()

                HStack {
                    Text("Decode delay:")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(runner.decodeDelayMs) ms")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(decodeDelayTint(for: runner.decodeDelayMs))
                }

                HStack(spacing: 10) {
                    Text("\(DecodeDelayDefaults.minimumMs)")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: decodeDelayBinding,
                        in: Double(DecodeDelayDefaults.minimumMs)...Double(DecodeDelayDefaults.maximumMs),
                        step: Double(DecodeDelayDefaults.stepMs),
                        onEditingChanged: { isEditing in
                            guard !isEditing else { return }
                            applyDecodeDelay(runner.decodeDelayMs)
                        }
                    )
                    .tint(decodeDelayTint(for: runner.decodeDelayMs))
                    Text("\(DecodeDelayDefaults.maximumMs)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption, design: .monospaced))

                HStack {
                    Button("Pause") {
                        runner.setGenerationPaused(!runner.isGenerationPaused)
                    }
                    .buttonStyle(.bordered)
                    .tint(runner.isGenerationPaused ? .purple : .gray.opacity(0.35))
                }

                Text("Delay sleeps between decodes. Pause halts token generation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("QoS mode:")
                        .font(.system(.body, design: .monospaced))
                    Text(runner.llmQoSMode.displayName)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(qosModeTint(for: runner.llmQoSMode))
                }

                HStack(spacing: 8) {
                    ForEach(LLMQoSMode.allCases) { mode in
                        Button(mode.displayName) {
                            runner.setLLMQoSMode(mode)
                        }
                        .buttonStyle(.bordered)
                        .tint(runner.llmQoSMode == mode ? qosModeTint(for: mode) : .gray.opacity(0.35))
                    }
                }

                Text("QoS changes the LLM worker scheduling priority and may take effect at token boundaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var politeLLMAblationBinding: Binding<PoliteLLMAblationKind> {
        Binding(
            get: { config.politeLLMAblation },
            set: { newValue in
                config.politeLLMAblation = newValue
                // Selecting an ablation disables the full Polite LLM controller.
                if newValue.isActive { config.politeLLMEnabled = false }
            }
        )
    }

    private var decodeDelayBinding: Binding<Double> {
        Binding(
            get: { Double(runner.decodeDelayMs) },
            set: { runner.decodeDelayMs = DecodeDelayDefaults.clamp(Int($0.rounded())) }
        )
    }

    private func applyDecodeDelay(_ delayMs: Int) {
        if runner.isGenerationPaused {
            runner.setGenerationPaused(false)
        }
        runner.setDecodeDelay(delayMs)
    }

    private func qosModeTint(for mode: LLMQoSMode) -> Color {
        switch mode {
        case .userInitiated:
            return .green
        case .utility:
            return .orange
        case .background:
            return .red
        }
    }

    private func decodeDelayTint(for delayMs: Int) -> Color {
        switch delayMs {
        case ..<90:
            return .green
        case ..<150:
            return .orange
        default:
            return .red
        }
    }

    // MARK: - Workload Area

    @ViewBuilder
    private var workloadArea: some View {
        if config.scenario == .llmInferenceOnly {
            LLMInferenceMonitorView(
                isActive: runner.isMeasurementActive,
                logger: runner.logger,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                timelineMarkers: runner.timelineMarkers,
                chartDisplayMode: config.chartDisplayMode,
                title: "LLM Inference Monitor",
                subtitle: "Display-linked FPS capture during idle and inference without a foreground workload selection."
            )
        } else {
            selectedWorkloadView
        }
    }

    @ViewBuilder
    private var selectedWorkloadView: some View {
        switch config.workload {
        case .scroll:
            ScrollWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                rowsPerTick: positiveIntBinding(\.scrollRowsPerTick),
                showColorSwatches: $config.scrollShowsColorSwatches,
                foregroundSLOBasis: config.foregroundSLOBasis,
                foregroundSLOMultiplier: config.foregroundSLOMultiplier,
                foregroundSLOPercentile: config.foregroundSLOPercentile,
                frameRateObserver: runner.observeForegroundFrameRate
            )
        case .animation:
            AnimationWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                particleCount: positiveIntBinding(\.animationParticleCount),
                foregroundSLOBasis: config.foregroundSLOBasis,
                foregroundSLOMultiplier: config.foregroundSLOMultiplier,
                foregroundSLOPercentile: config.foregroundSLOPercentile,
                frameRateObserver: runner.observeForegroundFrameRate
            )
        case .game3D:
            Game3DWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                ballCount: positiveIntBinding(\.game3DBallCount),
                foregroundSLOBasis: config.foregroundSLOBasis,
                foregroundSLOMultiplier: config.foregroundSLOMultiplier,
                foregroundSLOPercentile: config.foregroundSLOPercentile,
                frameRateObserver: runner.observeForegroundFrameRate
            )
        case .hexGLRace:
            HexGLRaceWorkloadView(
                isActive: runner.isWorkloadActive,
                shouldStartGame: runner.currentPhase == .startDelay || runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                quality: $config.hexGLQuality,
                foregroundSLOBasis: config.foregroundSLOBasis,
                foregroundSLOMultiplier: config.foregroundSLOMultiplier,
                foregroundSLOPercentile: config.foregroundSLOPercentile,
                frameRateObserver: runner.observeForegroundFrameRate
            )
        case .filter:
            ImageFilterWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                imageSize: positiveIntBinding(\.filterImageSize),
                blurSigma: nonnegativeDoubleBinding(\.filterBlurSigma)
            )
        case .memoryCPU:
            MemoryStreamWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                workingSetMiB: positiveIntBinding(\.memoryCPUWorkingSetMiB)
            )
        case .memoryMetal:
            MetalMemoryStreamWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                workingSetMiB: positiveIntBinding(\.memoryMetalWorkingSetMiB)
            )
        case .video:
            VideoPlaybackWorkloadView(
                isActive: runner.isWorkloadActive,
                logger: runner.logger,
                timelineMarkers: runner.timelineMarkers,
                tokensPerSecond: runner.llmDisplayedTokensPerSecond,
                chartDisplayMode: config.chartDisplayMode,
                foregroundSLOBasis: config.foregroundSLOBasis,
                foregroundSLOMultiplier: config.foregroundSLOMultiplier,
                foregroundSLOPercentile: config.foregroundSLOPercentile,
                frameRateObserver: runner.observeForegroundFrameRate
            )
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    mactopPanel
                }
                .padding([.top, .horizontal], 8)
            }
            .frame(maxHeight: 560)

            Divider()

            externalProcessOutputPanel
                .frame(minHeight: 120)
                .frame(maxHeight: .infinity)
        }
    }

    private var mactopPanel: some View {
        let snapshot = mactopTelemetry.snapshot

        return GroupBox("mactop") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(snapshot.isAvailable ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(snapshot.isAvailable ? "Live" : "Waiting")
                    Spacer(minLength: 8)
                    Text("100 ms poll / 500 ms UI")
                        .foregroundStyle(.secondary)
                }

                if let error = snapshot.lastError, !snapshot.isAvailable {
                    Text(error)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("mactop is auto-launched; check install/PATH if this stays unavailable.")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                telemetryMetric("Source", value: snapshot.sourceName ?? "—")

                Divider()

                telemetrySectionTitle("Compute")
                telemetryMetric("CPU", value: rawPercentage(snapshot.cpuUsagePercent))
                telemetryMetric("GPU", value: rawPercentage(snapshot.gpuUsagePercent))
                telemetryMetric("App CPU", value: rawPercentage(snapshot.ubiClawProcessCPUPercent))
                telemetryMetric("App GPU", value: millisecondsPerSecond(snapshot.ubiClawProcessGPUmsPerSecond))

                Divider()

                telemetrySectionTitle("DRAM BW")
                telemetryMetric("Read", value: gigabytesPerSecond(snapshot.dramReadBandwidthGBs))
                telemetryMetric("Write", value: gigabytesPerSecond(snapshot.dramWriteBandwidthGBs))
                telemetryMetric("Total", value: gigabytesPerSecond(snapshot.dramCombinedBandwidthGBs))

                Divider()

                telemetrySectionTitle("Memory")
                telemetryMetric("Used", value: bytes(snapshot.memoryUsedBytes))
                telemetryMetric("Available", value: bytes(snapshot.memoryAvailableBytes))
                telemetryMetric("Swap Used", value: bytes(snapshot.swapUsedBytes))
                telemetryMetric("App RSS", value: bytes(snapshot.ubiClawProcessRSSBytes))

                Divider()

                telemetrySectionTitle("Power/Thermal")
                telemetryMetric("Total Power", value: watts(snapshot.totalPowerW))
                telemetryMetric("GPU Power", value: watts(snapshot.gpuPowerW))
                telemetryMetric("DRAM Power", value: watts(snapshot.dramPowerW))
                telemetryMetric("Thermal", value: snapshot.thermalState ?? "—")
                telemetryMetric("SoC Temp", value: celsius(snapshot.socTemperatureC))
            }
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func telemetrySectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func telemetryMetric(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func rawPercentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f W", value)
    }

    private func gigabytesPerSecond(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f GB/s", value)
    }

    private func celsius(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f C", value)
    }

    private func millisecondsPerSecond(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f ms/s", value)
    }

    private var externalProcessOutputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LLM Output")
                    .font(.headline)
                Spacer()
                if runner.externalProcessOutput.isEmpty {
                    Text("No output")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(runner.externalProcessOutput.isEmpty ? "External backend stdout will appear here." : runner.externalProcessOutput)
                        .font(.system(size: 16.5, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .padding(8)
                        .id("stdout-bottom")
                }
                .onChange(of: runner.externalProcessOutput) { _, _ in
                    proxy.scrollTo("stdout-bottom", anchor: .bottom)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct LLMInferenceFPSSample: Identifiable {
    let id = UUID()
    let elapsedSeconds: Double
    let fps: Double
    let smoothFPS: Double
}

private struct LLMInferenceMonitorView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let tokensPerSecond: Double
    let timelineMarkers: [TimelineMarker]
    let chartDisplayMode: WorkloadChartDisplayMode
    let title: String
    let subtitle: String

    @State private var startTime: Date?
    @State private var currentFPS: Double = 0
    @State private var averageFPS: Double = 0
    @State private var frameCount = 0
    @State private var lastFrameDate: Date?
    @State private var lastFPSLogDate: Date?
    @State private var fpsHistory: [LLMInferenceFPSSample] = []
    @State private var recentRawFPS: [Double] = []

    private let maWindow = 60
    private let chartWindowSeconds = WorkloadChartDefaults.recentWindowSeconds
    private let maxFPSHistorySamples = WorkloadChartDefaults.recentMaxHistorySamples

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            fpsChart
            fpsTicker
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                startTime = Date()
                lastFrameDate = nil
                lastFPSLogDate = nil
                frameCount = 0
                currentFPS = 0
                averageFPS = 0
                fpsHistory = []
                recentRawFPS = []
                logger?.log(event: "fps_monitor_start", workload: "llm_inference_only")
            } else {
                logger?.log(
                    event: "fps_monitor_end",
                    workload: "llm_inference_only",
                    params: "avg_fps=\(String(format: "%.2f", averageFPS))"
                )
                startTime = nil
                lastFrameDate = nil
                lastFPSLogDate = nil
            }
        }
        .onChange(of: chartDisplayMode) { _, _ in
            trimFPSHistoryToDisplayMode()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryPanel: some View {
        HStack(spacing: 18) {
            summaryMetric("State", value: isActive ? "Running" : "Idle")
            summaryMetric("Live FPS", value: String(format: "%.1f", currentFPS))
            summaryMetric("Average FPS", value: String(format: "%.1f", averageFPS))
            summaryMetric("Token/s", value: String(format: "%.1f", tokensPerSecond))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var fpsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frame Rate")
                .font(.headline)

            Chart {
                ForEach(fpsHistory) { sample in
                    LineMark(
                        x: .value("Elapsed", sample.elapsedSeconds - chartWindowStart),
                        y: .value("FPS", sample.smoothFPS)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.cyan)
                }

                ForEach(chartEventMarkers) { marker in
                    RuleMark(x: .value("Event", marker.elapsedTime - chartWindowStart))
                        .foregroundStyle(eventColor(for: marker.label))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text(marker.label)
                                .font(.caption2.monospaced())
                                .foregroundStyle(eventColor(for: marker.label))
                        }
                }
            }
            .chartXScale(domain: fpsChartXDomain)
            .chartYScale(domain: fpsChartYDomain)
            .chartXAxisLabel(fpsChartXAxisLabel)
            .chartYAxisLabel("FPS (MA\(maWindow))")
            .frame(height: 230)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var fpsTicker: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { context in
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: context.date, initial: false) { _, date in
                    handleFrame(at: date)
                }
        }
    }

    private func handleFrame(at date: Date) {
        guard isActive, let startTime else { return }

        var rawFPS = currentFPS
        if let lastFrameDate {
            let delta = date.timeIntervalSince(lastFrameDate)
            rawFPS = delta > 0 ? 1.0 / delta : 0
        }
        rawFPS = min(rawFPS, 120)
        lastFrameDate = date
        frameCount += 1
        recentRawFPS.append(rawFPS)
        if recentRawFPS.count > maWindow { recentRawFPS.removeFirst() }
        let smoothed = recentRawFPS.reduce(0, +) / Double(recentRawFPS.count)
        currentFPS = smoothed

        let elapsed = date.timeIntervalSince(startTime)
        if elapsed >= WorkloadChartDefaults.warmupHiddenSeconds {
            fpsHistory.append(LLMInferenceFPSSample(elapsedSeconds: elapsed, fps: rawFPS, smoothFPS: smoothed))
            trimFPSHistoryToDisplayMode(currentElapsed: elapsed)
        }

        averageFPS = elapsed > 0 ? Double(frameCount) / elapsed : 0

        if let lastFPSLogDate, date.timeIntervalSince(lastFPSLogDate) < 1.0 {
            return
        }

        logger?.log(
            event: "fg_fps",
            workload: "llm_inference_only",
            params: "current_fps=\(String(format: "%.2f", rawFPS)),smooth_fps=\(String(format: "%.2f", smoothed)),avg_fps=\(String(format: "%.2f", averageFPS))"
        )
        lastFPSLogDate = date
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartWindowStart: Double {
        switch chartDisplayMode {
        case .recent:
            return max(0, (fpsHistory.last?.elapsedSeconds ?? 0) - chartWindowSeconds)
        case .fullRun:
            return 0
        }
    }

    private var fpsChartXDomain: ClosedRange<Double> {
        switch chartDisplayMode {
        case .recent:
            return 0...chartWindowSeconds
        case .fullRun:
            return 0...max(1, fpsHistory.last?.elapsedSeconds ?? 1)
        }
    }

    private var fpsChartXAxisLabel: String {
        switch chartDisplayMode {
        case .recent:
            return "Last 5s"
        case .fullRun:
            return "Full run"
        }
    }

    private var fpsChartYDomain: ClosedRange<Double> {
        WorkloadChartDefaults.dynamicYDomain(for: fpsHistory.map(\.smoothFPS))
    }

    private var chartEventMarkers: [TimelineMarker] {
        timelineMarkers.filter {
            let xPosition = $0.elapsedTime - chartWindowStart
            let xUpperBound = fpsChartXDomain.upperBound
            return xPosition > 0
                && xPosition < xUpperBound
                && ($0.label.hasPrefix("Delay ") || $0.label.hasPrefix("QoS ")
                    || $0.label == "Gen Pause" || $0.label == "Gen Resume")
        }
    }

    private func trimFPSHistoryToDisplayMode(currentElapsed: Double? = nil) {
        guard chartDisplayMode == .recent else { return }

        let latestElapsed = currentElapsed ?? fpsHistory.last?.elapsedSeconds ?? 0
        fpsHistory.removeAll { latestElapsed - $0.elapsedSeconds > chartWindowSeconds }
        if fpsHistory.count > maxFPSHistorySamples {
            fpsHistory.removeFirst(fpsHistory.count - maxFPSHistorySamples)
        }
    }

    private func eventColor(for label: String) -> Color {
        if label == "Gen Pause" {
            return .purple
        }
        if label == "Gen Resume" {
            return .mint
        }
        if label == "QoS Background" {
            return .red
        }
        if label == "QoS Utility" {
            return .orange
        }
        if label == "QoS Normal" {
            return .green
        }
        if let delayMs = delayMilliseconds(from: label) {
            return delayColor(for: delayMs)
        }
        return .green
    }

    private func delayMilliseconds(from label: String) -> Int? {
        guard label.hasPrefix("Delay ") else { return nil }
        let numberText = label
            .replacingOccurrences(of: "Delay ", with: "")
            .replacingOccurrences(of: "ms", with: "")
        return Int(numberText)
    }

    private func delayColor(for delayMs: Int) -> Color {
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
