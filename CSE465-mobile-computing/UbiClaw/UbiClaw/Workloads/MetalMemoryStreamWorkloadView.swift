import Metal
import SwiftUI
import os

/// Streams large Metal buffers with a simple compute kernel to exercise UMA bandwidth.
struct MetalMemoryStreamWorkloadView: View {
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
    @State private var statusText = "Idle"
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
            title: "Metal Memory Streaming",
            subtitle: "Compute-driven configurable buffer streaming with charts focused on latency and estimated UMA bandwidth."
        )
    }

    private var summaryPanel: some View {
        WorkloadSummaryPanel(
            metrics: [
                WorkloadSummaryMetric("State", value: statusText),
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
        statusText = "Preparing"
        latencyMonitor.updateChartDisplayMode(chartDisplayMode)
        throughputMonitor.updateChartDisplayMode(chartDisplayMode)
        latencyMonitor.reset()
        throughputMonitor.reset()
        latencyMonitor.updateTimelineMarkers(timelineMarkers)
        throughputMonitor.updateTimelineMarkers(timelineMarkers)

        let logger = logger
        let signpostState = Signposts.beginMemoryMetal()
        let elementCount = effectiveElementCount
        logger?.log(
            event: "fg_task_start",
            workload: "memory_metal",
            params: "working_set_mib=\(workingSetMiB),elements=\(elementCount)"
        )

        workerTask = Task.detached(priority: .userInitiated) {
            guard
                let device = MTLCreateSystemDefaultDevice(),
                let commandQueue = device.makeCommandQueue(),
                let library = device.makeDefaultLibrary(),
                let function = library.makeFunction(name: "memoryStreamKernel")
            else {
                await MainActor.run {
                    statusText = "Metal unavailable"
                    Signposts.endMemoryMetal(signpostState)
                }
                return
            }

            let pipeline: MTLComputePipelineState
            do {
                pipeline = try await device.makeComputePipelineState(function: function)
            } catch {
                await MainActor.run {
                    statusText = "Pipeline creation failed"
                    Signposts.endMemoryMetal(signpostState)
                }
                return
            }

            let bufferLength = elementCount * MemoryLayout<Float>.stride
            guard
                let inputABuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
                let inputBBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared),
                let outputBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared)
            else {
                await MainActor.run {
                    statusText = "Buffer allocation failed"
                    Signposts.endMemoryMetal(signpostState)
                }
                return
            }

            let inputAPointer = inputABuffer.contents().bindMemory(to: Float.self, capacity: elementCount)
            let inputBPointer = inputBBuffer.contents().bindMemory(to: Float.self, capacity: elementCount)
            for i in 0..<elementCount {
                inputAPointer[i] = Float(i % 1024) * 0.001
                inputBPointer[i] = Float(i % 1024) * 0.002
            }

            var currentInputA = inputABuffer
            var currentInputB = inputBBuffer
            var currentOutput = outputBuffer

            let bytesPerIteration = Double(bufferLength * 3)
            let threadsPerThreadgroup = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
            let threadgroups = MTLSize(
                width: (elementCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: 1,
                depth: 1
            )

            var localIteration = 0
            var totalLatencyMs = 0.0

            await MainActor.run {
                statusText = "Running"
            }
            let runStart = CFAbsoluteTimeGetCurrent()
            await MainActor.run {
                latencyMonitor.beginSampling(at: runStart)
                throughputMonitor.beginSampling(at: runStart)
            }

            while !Task.isCancelled {
                guard
                    let commandBuffer = commandQueue.makeCommandBuffer(),
                    let encoder = commandBuffer.makeComputeCommandEncoder()
                else {
                    break
                }

                let start = CFAbsoluteTimeGetCurrent()
                var elementCountValue = UInt32(clamping: elementCount)
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(currentInputA, offset: 0, index: 0)
                encoder.setBuffer(currentInputB, offset: 0, index: 1)
                encoder.setBuffer(currentOutput, offset: 0, index: 2)
                encoder.setBytes(&elementCountValue, length: MemoryLayout<UInt32>.stride, index: 3)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                encoder.endEncoding()

                commandBuffer.commit()
                await commandBuffer.completed()

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
                        workload: "memory_metal",
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

                let recycled = currentInputA
                currentInputA = currentInputB
                currentInputB = currentOutput
                currentOutput = recycled
            }

            let totalIterations = localIteration
            await MainActor.run {
                Signposts.endMemoryMetal(signpostState)
                statusText = "Idle"
                logger?.log(event: "fg_task_end", workload: "memory_metal", params: "total_iterations=\(totalIterations)")
            }
        }
    }

    private func stopWorkload() {
        workerTask?.cancel()
        workerTask = nil
        statusText = "Idle"
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
