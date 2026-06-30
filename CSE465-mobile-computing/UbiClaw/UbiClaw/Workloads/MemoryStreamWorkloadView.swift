import Accelerate
import SwiftUI
import os

/// Streams large CPU-side arrays so DRAM bandwidth dominates over cache locality.
struct MemoryStreamWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double = 0
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Binding var workingSetMiB: Int

    @State private var iterationCount = 0
    @State private var lastLatencyMs: Double = 0
    @State private var averageLatencyMs: Double = 0
    @State private var throughputGBs: Double = 0
    @State private var workerTask: Task<Void, Never>?
    @StateObject private var latencyMonitor = WorkloadMetricSeriesMonitor()
    @StateObject private var throughputMonitor = WorkloadMetricSeriesMonitor()

    private var effectiveElementCount: Int {
        Self.elementCount(forWorkingSetMiB: workingSetMiB)
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            settingsControl
            latencyChart
            throughputChart
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                startWorkload()
            } else {
                stopWorkload()
            }
        }
        .onDisappear {
            stopWorkload()
        }
        .onChange(of: chartDisplayMode) { _, mode in
            latencyMonitor.updateChartDisplayMode(mode)
            throughputMonitor.updateChartDisplayMode(mode)
        }
        .onChange(of: timelineMarkers.count) { _, _ in
            latencyMonitor.updateTimelineMarkers(timelineMarkers)
            throughputMonitor.updateTimelineMarkers(timelineMarkers)
        }
    }

    private var header: some View {
        WorkloadHeaderView(
            title: "CPU Memory Streaming",
            subtitle: "Large-array read/write on a configurable working set with charts centered on latency and estimated DRAM throughput."
        )
    }

    private var summaryPanel: some View {
        WorkloadSummaryPanel(
            metrics: [
                WorkloadSummaryMetric("State", value: isActive ? "Running" : "Idle"),
                WorkloadSummaryMetric("Last", value: String(format: "%.2f ms", lastLatencyMs)),
                WorkloadSummaryMetric("Average", value: String(format: "%.2f ms", averageLatencyMs)),
                WorkloadSummaryMetric("Bandwidth", value: String(format: "%.2f GB/s", throughputGBs)),
                WorkloadSummaryMetric("Set", value: Self.workingSetText(forElementCount: effectiveElementCount)),
                .llmTokensPerSecond(tokensPerSecond)
            ]
        )
    }

    private var settingsControl: some View {
        WorkloadSettingsBar {
            WorkloadIntegerSettingField(
                title: "Set MiB",
                value: $workingSetMiB
            )
        }
        .disabled(isActive)
    }

    private var latencyChart: some View {
        WorkloadMetricChart(
            monitor: latencyMonitor,
            title: "Iteration Latency",
            yAxisLabel: "ms",
            lineColor: .orange,
            sloDirection: .lowerIsBetter
        )
    }

    private var throughputChart: some View {
        WorkloadMetricChart(
            monitor: throughputMonitor,
            title: "Estimated Throughput",
            yAxisLabel: "GB/s",
            lineColor: .blue,
            trailingText: "Iterations \(iterationCount)",
            sloDirection: .higherIsBetter
        )
    }

    private func startWorkload() {
        guard workerTask == nil else { return }

        iterationCount = 0
        lastLatencyMs = 0
        averageLatencyMs = 0
        throughputGBs = 0
        latencyMonitor.updateChartDisplayMode(chartDisplayMode)
        throughputMonitor.updateChartDisplayMode(chartDisplayMode)
        latencyMonitor.reset()
        throughputMonitor.reset()
        latencyMonitor.updateTimelineMarkers(timelineMarkers)
        throughputMonitor.updateTimelineMarkers(timelineMarkers)

        let logger = logger
        let signpostState = Signposts.beginMemoryCPU()
        let elementCount = effectiveElementCount
        logger?.log(
            event: "fg_task_start",
            workload: "memory_cpu",
            params: "working_set_mib=\(workingSetMiB),elements=\(elementCount)"
        )

        workerTask = Task.detached(priority: .userInitiated) {
            let runStart = CFAbsoluteTimeGetCurrent()
            await MainActor.run {
                latencyMonitor.beginSampling(at: runStart)
                throughputMonitor.beginSampling(at: runStart)
            }

            var sourceA = Array(repeating: Float(0.125), count: elementCount)
            var sourceB = Array(repeating: Float(0.25), count: elementCount)
            var destination = Array(repeating: Float.zero, count: elementCount)

            let bytesPerBuffer = Double(elementCount * MemoryLayout<Float>.stride)
            let bytesPerIteration = bytesPerBuffer * 3
            var localIteration = 0
            var totalLatencyMs = 0.0

            while !Task.isCancelled {
                let start = CFAbsoluteTimeGetCurrent()

                vDSP.add(sourceA, sourceB, result: &destination)
                let checksum = vDSP.sum(destination)
                vDSP.multiply(0.999_9 + checksum * 1e-12, destination, result: &sourceA)
                swap(&sourceA, &sourceB)

                let end = CFAbsoluteTimeGetCurrent()
                let latencyMs = (end - start) * 1000
                localIteration += 1
                totalLatencyMs += latencyMs
                let gbPerSecond = (bytesPerIteration / 1_000_000_000) / max(latencyMs / 1000, 0.000_001)
                let iterationParams = "iteration=\(localIteration),throughput_gbps=\(String(format: "%.2f", gbPerSecond))"
                let sampleStartElapsed = start - runStart
                let sampleEndElapsed = end - runStart

                await MainActor.run {
                    logger?.log(
                        event: "fg_iteration_latency",
                        workload: "memory_cpu",
                        durationMs: latencyMs,
                        params: iterationParams
                    )
                }

                let iterationSnapshot = localIteration
                let averageSnapshot = totalLatencyMs / Double(localIteration)
                await MainActor.run {
                    iterationCount = iterationSnapshot
                    lastLatencyMs = latencyMs
                    averageLatencyMs = averageSnapshot
                    throughputGBs = gbPerSecond
                    latencyMonitor.record(
                        iteration: iterationSnapshot,
                        value: latencyMs,
                        sampleStartElapsed: sampleStartElapsed,
                        sampleEndElapsed: sampleEndElapsed
                    )
                    throughputMonitor.record(
                        iteration: iterationSnapshot,
                        value: gbPerSecond,
                        sampleStartElapsed: sampleStartElapsed,
                        sampleEndElapsed: sampleEndElapsed
                    )
                }

                try? await Task.sleep(for: .milliseconds(1))
            }

            let totalIterations = localIteration
            await MainActor.run {
                Signposts.endMemoryCPU(signpostState)
                logger?.log(event: "fg_task_end", workload: "memory_cpu", params: "total_iterations=\(totalIterations)")
            }
        }
    }

    private func stopWorkload() {
        workerTask?.cancel()
        workerTask = nil
    }

    private static func elementCount(forWorkingSetMiB workingSetMiB: Int) -> Int {
        let safeWorkingSetMiB = max(1, workingSetMiB)
        let totalBytes = safeWorkingSetMiB * 1024 * 1024
        let bytesPerElementAcrossBuffers = MemoryLayout<Float>.stride * 3
        return max(1, totalBytes / bytesPerElementAcrossBuffers)
    }

    private static func workingSetText(forElementCount elementCount: Int) -> String {
        let bytes = Double(elementCount * MemoryLayout<Float>.stride * 3)
        return String(format: "%.0f MiB", bytes / 1_048_576)
    }

}
