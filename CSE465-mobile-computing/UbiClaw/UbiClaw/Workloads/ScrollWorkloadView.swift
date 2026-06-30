import os
import SwiftUI

/// A long SwiftUI List with programmatic auto-scroll at a repeatable pace.
/// Signpost interval fg_scroll wraps the active scroll phase.
struct ScrollWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double = 0
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Binding var rowsPerTick: Int
    @Binding var showColorSwatches: Bool
    var foregroundSLOBasis: ForegroundSLOBasis = .baselineMean
    var foregroundSLOMultiplier: Double = ForegroundSLODefaults.multiplier
    var foregroundSLOPercentile: Double = ForegroundSLODefaults.percentile
    var frameRateObserver: (ForegroundFrameRateObservation) -> Void = { _ in }

    @State private var currentRow = 0
    @StateObject private var frameMonitor = ForegroundFrameRateMonitor(workloadID: "scroll")

    private let rowCount = 10_000
    private var safeRowsPerTick: Int {
        max(1, rowsPerTick)
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            settingsControl
            fpsChart

            ScrollViewReader { proxy in
                List(0..<rowCount, id: \.self) { i in
                    HStack {
                        Text("Row \(i)")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if showColorSwatches {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    Color(
                                        hue: Double(i % 360) / 360.0,
                                        saturation: 0.7,
                                        brightness: 0.85
                                    )
                                )
                                .frame(width: 80, height: 22)
                        }
                    }
                    .id(i)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.08))
                }
                .task(id: isActive) {
                    guard isActive else { return }

                    currentRow = 0
                    updateFrameMonitorSLOConfig()
                    frameMonitor.updateChartDisplayMode(chartDisplayMode)
                    frameMonitor.reset()
                    frameMonitor.updateTimelineMarkers(timelineMarkers)

                    let state = Signposts.beginScroll()
                    logger?.log(event: "fg_task_start", workload: "scroll")

                    var row = 0
                    var direction = 1
                    let runStart = CFAbsoluteTimeGetCurrent()
                    frameMonitor.beginSampling(at: runStart)

                    while !Task.isCancelled {
                        let now = CFAbsoluteTimeGetCurrent()

                        row += direction * safeRowsPerTick
                        if row >= rowCount - 1 {
                            row = rowCount - 1
                            direction = -1
                        } else if row <= 0 {
                            row = 0
                            direction = 1
                        }

                        proxy.scrollTo(row, anchor: .center)

                        currentRow = row
                        let elapsed = now - runStart
                        if let observation = frameMonitor.recordFrame(
                            elapsed: elapsed,
                            isActive: isActive,
                            logger: logger
                        ) {
                            frameRateObserver(observation)
                        }

                        try? await Task.sleep(for: .milliseconds(16))
                    }

                    Signposts.endScroll(state)
                    frameMonitor.stopLogging(logger: logger)
                }
            }
        }
        .onChange(of: timelineMarkers.count) { _, _ in
            frameMonitor.updateTimelineMarkers(timelineMarkers)
        }
        .onChange(of: chartDisplayMode) { _, mode in
            frameMonitor.updateChartDisplayMode(mode)
        }
        .onChange(of: foregroundSLOBasis) { _, _ in
            updateFrameMonitorSLOConfig()
        }
        .onChange(of: foregroundSLOMultiplier) { _, _ in
            updateFrameMonitorSLOConfig()
        }
        .onChange(of: foregroundSLOPercentile) { _, _ in
            updateFrameMonitorSLOConfig()
        }
        .onAppear {
            updateFrameMonitorSLOConfig()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        WorkloadHeaderView(
            title: "Scroll Streaming",
            subtitle: "Programmatic list traversal with a live FPS trace to expose UI smoothness under contention."
        )
    }

    private var summaryPanel: some View {
        ForegroundFrameRateSummaryPanel(
            monitor: frameMonitor,
            isActive: isActive,
            tokensPerSecond: tokensPerSecond,
            additionalMetrics: [
                WorkloadSummaryMetric("Viewport", value: "\(currentRow)"),
                WorkloadSummaryMetric("Rows/Tick", value: "\(safeRowsPerTick)"),
                WorkloadSummaryMetric("Colors", value: showColorSwatches ? "On" : "Off")
            ]
        )
    }

    private var settingsControl: some View {
        WorkloadSettingsBar {
            WorkloadIntegerSettingField(
                title: "Rows / Tick",
                value: $rowsPerTick
            )

            Toggle("Color Bars", isOn: $showColorSwatches)
                .toggleStyle(.switch)
        }
        .disabled(isActive)
    }

    private var fpsChart: some View {
        ForegroundFrameRateChart(
            monitor: frameMonitor,
            lineColor: .mint
        )
    }

    private func updateFrameMonitorSLOConfig() {
        frameMonitor.updateSLOConfig(
            basis: foregroundSLOBasis,
            multiplier: foregroundSLOMultiplier,
            percentile: foregroundSLOPercentile
        )
    }
}
