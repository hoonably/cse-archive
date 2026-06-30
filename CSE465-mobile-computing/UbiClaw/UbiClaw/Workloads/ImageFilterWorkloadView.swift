import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// Repeatedly applies Core Image filters to a large image, measuring per-iteration latency.
/// Signpost interval fg_filter wraps the active phase.
struct ImageFilterWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double = 0
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Binding var imageSize: Int
    @Binding var blurSigma: Double

    @State private var iterationCount = 0
    @State private var lastLatencyMs: Double = 0
    @State private var avgLatencyMs: Double = 0
    @State private var isProcessing = false
    @StateObject private var latencyMonitor = WorkloadMetricSeriesMonitor()

    private var safeImageSize: Int {
        max(1, imageSize)
    }

    private var safeBlurSigma: Double {
        max(0, blurSigma)
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            settingsControl
            latencyChart
            liveSurface
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: isActive) {
            guard isActive else {
                isProcessing = false
                return
            }

            isProcessing = true
            iterationCount = 0
            lastLatencyMs = 0
            avgLatencyMs = 0
            latencyMonitor.updateChartDisplayMode(chartDisplayMode)
            latencyMonitor.reset()
            latencyMonitor.updateTimelineMarkers(timelineMarkers)
            var totalMs: Double = 0

            let state = Signposts.beginFilter()
            logger?.log(event: "fg_task_start", workload: "filter")

            let ciContext = CIContext()
            let workloadImageSize = safeImageSize
            let workloadBlurSigma = safeBlurSigma
            let extent = CGRect(x: 0, y: 0, width: workloadImageSize, height: workloadImageSize)
            let source = CIImage(color: .red).cropped(to: extent)
            let runStart = CFAbsoluteTimeGetCurrent()
            latencyMonitor.beginSampling(at: runStart)

            while !Task.isCancelled {
                let start = CFAbsoluteTimeGetCurrent()

                let blurred = source
                    .applyingGaussianBlur(sigma: workloadBlurSigma)
                    .cropped(to: extent)

                _ = ciContext.createCGImage(blurred, from: extent)

                let end = CFAbsoluteTimeGetCurrent()
                let elapsed = (end - start) * 1000
                iterationCount += 1
                lastLatencyMs = elapsed
                totalMs += elapsed
                avgLatencyMs = totalMs / Double(iterationCount)
                latencyMonitor.record(
                    iteration: iterationCount,
                    value: elapsed,
                    sampleStartElapsed: start - runStart,
                    sampleEndElapsed: end - runStart
                )

                logger?.log(
                    event: "fg_iteration_latency",
                    workload: "filter",
                    durationMs: elapsed,
                    params: "iteration=\(iterationCount)"
                )

                try? await Task.sleep(for: .milliseconds(1))
            }

            Signposts.endFilter(state)
            logger?.log(event: "fg_task_end", workload: "filter", params: "total_iterations=\(iterationCount)")
            isProcessing = false
        }
        .onChange(of: chartDisplayMode) { _, mode in
            latencyMonitor.updateChartDisplayMode(mode)
        }
        .onChange(of: timelineMarkers.count) { _, _ in
            latencyMonitor.updateTimelineMarkers(timelineMarkers)
        }
    }

    private var header: some View {
        WorkloadHeaderView(
            title: "Image Filter Pipeline",
            subtitle: "Large-frame Core Image processing with the visualization always focused on latency drift."
        )
    }

    private var summaryPanel: some View {
        WorkloadSummaryPanel(
            metrics: [
                WorkloadSummaryMetric("State", value: isProcessing ? "Running" : "Idle"),
                WorkloadSummaryMetric("Last", value: String(format: "%.1f ms", lastLatencyMs)),
                WorkloadSummaryMetric("Average", value: String(format: "%.1f ms", avgLatencyMs)),
                WorkloadSummaryMetric("Iterations", value: "\(iterationCount)"),
                WorkloadSummaryMetric("Image", value: "\(safeImageSize)px"),
                WorkloadSummaryMetric("Sigma", value: String(format: "%.1f", safeBlurSigma)),
                .llmTokensPerSecond(tokensPerSecond)
            ]
        )
    }

    private var settingsControl: some View {
        WorkloadSettingsBar {
            WorkloadIntegerSettingField(
                title: "Image Size",
                value: $imageSize
            )
            WorkloadDoubleSettingField(
                title: "Blur Sigma",
                value: $blurSigma
            )
        }
        .disabled(isActive)
    }

    private var latencyChart: some View {
        WorkloadMetricChart(
            monitor: latencyMonitor,
            title: "Per-Iteration Latency",
            yAxisLabel: "ms",
            lineColor: .orange,
            sloDirection: .lowerIsBetter,
            height: 260
        )
    }

    private var liveSurface: some View {
        ZStack {
            LinearGradient(
                colors: [.red.opacity(0.9), .orange.opacity(0.7), .yellow.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if isProcessing {
                Circle()
                    .fill(.white.opacity(0.18))
                    .blur(radius: 50)
                    .scaleEffect(1.4)

                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
            } else {
                Text("Filter surface idle")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.1))
        }
    }

}
