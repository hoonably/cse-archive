import Metal
import MetalKit
import QuartzCore
import SwiftUI
import os

private struct AnimationParticle {
    let startX: Float
    let startY: Float
    let vx: Float
    let vy: Float
    let hue: Float
    let size: Float

    static func random(sizeMultiplier: Float = 1) -> AnimationParticle {
        AnimationParticle(
            startX: .random(in: 0...1),
            startY: .random(in: 0...1),
            vx: .random(in: -0.25...0.25),
            vy: .random(in: -0.25...0.25),
            hue: .random(in: 0...1),
            size: .random(in: 7...18) * sizeMultiplier
        )
    }

    static func makeConnections(count: Int) -> [AnimationConnection] {
        var result: [AnimationConnection] = []
        result.reserveCapacity(count * 14)

        for sourceIndex in 0..<count {
            for targetIndex in (sourceIndex + 1)..<min(sourceIndex + 15, count) {
                result.append(
                    AnimationConnection(
                        sourceIndex: UInt32(sourceIndex),
                        targetIndex: UInt32(targetIndex)
                    )
                )
            }
        }

        return result
    }

    var gpuValue: GPUParticle {
        GPUParticle(
            startPosition: SIMD2(startX, startY),
            velocity: SIMD2(vx, vy),
            hue: hue,
            size: size
        )
    }
}

private struct AnimationConnection {
    let sourceIndex: UInt32
    let targetIndex: UInt32

    var gpuValue: GPUConnection {
        GPUConnection(sourceIndex: sourceIndex, targetIndex: targetIndex)
    }
}

private struct GPUParticle {
    var startPosition: SIMD2<Float>
    var velocity: SIMD2<Float>
    var hue: Float
    var size: Float
}

private struct GPUConnection {
    var sourceIndex: UInt32
    var targetIndex: UInt32
}

private struct AnimationUniforms {
    var time: Float
    var viewportSize: SIMD2<Float>
}

/// Continuous particle animation using Metal rendering.
/// Stresses the GPU render pipeline enough to observe stutter under contention.
/// Signpost interval fg_animation wraps the active phase.
struct AnimationWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double
    var chartDisplayMode: WorkloadChartDisplayMode
    @Binding var particleCount: Int
    var foregroundSLOBasis: ForegroundSLOBasis
    var foregroundSLOMultiplier: Double
    var foregroundSLOPercentile: Double
    var frameRateObserver: (ForegroundFrameRateObservation) -> Void

    @State private var signpostState: OSSignpostIntervalState?
    @State private var startTime: Date?
    @StateObject private var frameMonitor = ForegroundFrameRateMonitor(workloadID: "animation")

    init(
        isActive: Bool,
        logger: CSVLogger?,
        timelineMarkers: [TimelineMarker],
        tokensPerSecond: Double = 0,
        chartDisplayMode: WorkloadChartDisplayMode = .recent,
        particleCount: Binding<Int>,
        foregroundSLOBasis: ForegroundSLOBasis = .baselineMean,
        foregroundSLOMultiplier: Double = ForegroundSLODefaults.multiplier,
        foregroundSLOPercentile: Double = ForegroundSLODefaults.percentile,
        frameRateObserver: @escaping (ForegroundFrameRateObservation) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.logger = logger
        self.timelineMarkers = timelineMarkers
        self.tokensPerSecond = tokensPerSecond
        self.chartDisplayMode = chartDisplayMode
        self._particleCount = particleCount
        self.foregroundSLOBasis = foregroundSLOBasis
        self.foregroundSLOMultiplier = foregroundSLOMultiplier
        self.foregroundSLOPercentile = foregroundSLOPercentile
        self.frameRateObserver = frameRateObserver
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            settingsControl
            fpsChart

            AnimationMetalView(
                particleCount: safeParticleCount,
                isActive: isActive,
                startTime: startTime,
                frameHandler: handleFrame(at:)
            )
            .id(safeParticleCount)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.08))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: isActive) { _, active in
            if active {
                startTime = Date()
                updateFrameMonitorSLOConfig()
                frameMonitor.updateChartDisplayMode(chartDisplayMode)
                frameMonitor.reset()
                frameMonitor.updateTimelineMarkers(timelineMarkers)
                signpostState = Signposts.beginAnimation()
                logger?.log(event: "fg_task_start", workload: "animation")
            } else if let state = signpostState {
                Signposts.endAnimation(state)
                frameMonitor.stopLogging(logger: logger)
                signpostState = nil
                startTime = nil
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

    private var safeParticleCount: Int {
        max(1, particleCount)
    }

    private var header: some View {
        WorkloadHeaderView(
            title: "Particle Animation",
            subtitle: "Metal-driven motion field with a live FPS trace for render stability and frame pacing."
        )
    }

    private var summaryPanel: some View {
        ForegroundFrameRateSummaryPanel(
            monitor: frameMonitor,
            isActive: isActive,
            tokensPerSecond: tokensPerSecond,
            additionalMetrics: [
                WorkloadSummaryMetric("Particles", value: "\(safeParticleCount)")
            ]
        )
    }

    private var settingsControl: some View {
        WorkloadSettingsBar {
            WorkloadIntegerSettingField(
                title: "Particles",
                value: $particleCount
            )
        }
        .disabled(isActive)
    }

    private var fpsChart: some View {
        ForegroundFrameRateChart(
            monitor: frameMonitor,
            lineColor: .pink
        )
    }

    private func updateFrameMonitorSLOConfig() {
        frameMonitor.updateSLOConfig(
            basis: foregroundSLOBasis,
            multiplier: foregroundSLOMultiplier,
            percentile: foregroundSLOPercentile
        )
    }

    private func handleFrame(at elapsed: TimeInterval) {
        guard startTime != nil else { return }
        if let observation = frameMonitor.recordFrame(
            elapsed: elapsed,
            isActive: isActive,
            logger: logger
        ) {
            frameRateObserver(observation)
        }
    }
}

private struct AnimationMetalView: NSViewRepresentable {
    let particleCount: Int
    let isActive: Bool
    let startTime: Date?
    let frameHandler: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            particleCount: particleCount,
            frameHandler: frameHandler
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.renderer?.device
        view.delegate = context.coordinator.renderer
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = !isActive
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        context.coordinator.renderer?.update(
            isActive: isActive,
            startTime: startTime,
            frameHandler: frameHandler
        )
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.isPaused = !isActive
        context.coordinator.renderer?.update(
            isActive: isActive,
            startTime: startTime,
            frameHandler: frameHandler
        )
    }

    final class Coordinator {
        let renderer: AnimationMetalRenderer?

        init(
            particleCount: Int,
            frameHandler: @escaping (TimeInterval) -> Void
        ) {
            renderer = AnimationMetalRenderer(
                particleCount: particleCount,
                frameHandler: frameHandler
            )
        }
    }
}

private final class AnimationMetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let particlePipelineState: MTLRenderPipelineState?
    private let linePipelineState: MTLRenderPipelineState?
    private let particleBuffer: MTLBuffer?
    private let connectionBuffer: MTLBuffer?
    private let particleCount: Int
    private let connectionCount: Int

    private var isActive = false
    private var startReferenceTime: TimeInterval?
    private var frameHandler: (TimeInterval) -> Void

    init(
        particleCount: Int,
        frameHandler: @escaping (TimeInterval) -> Void
    ) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.frameHandler = frameHandler
        let particles = (0..<max(1, particleCount)).map { _ in
            AnimationParticle.random(sizeMultiplier: 3).gpuValue
        }
        let connections = AnimationParticle
            .makeConnections(count: min(500, particles.count))
            .map(\.gpuValue)
        self.particleCount = particles.count
        self.connectionCount = connections.count

        if let device {
            self.particleBuffer = device.makeBuffer(
                bytes: particles,
                length: MemoryLayout<GPUParticle>.stride * particles.count
            )
            let safeConnections = connections.isEmpty
                ? [GPUConnection(sourceIndex: 0, targetIndex: 0)]
                : connections
            self.connectionBuffer = device.makeBuffer(
                bytes: safeConnections,
                length: MemoryLayout<GPUConnection>.stride * safeConnections.count
            )

            if let library = device.makeDefaultLibrary() {
                self.particlePipelineState = AnimationMetalRenderer.makeParticlePipeline(
                    device: device,
                    library: library
                )
                self.linePipelineState = AnimationMetalRenderer.makeLinePipeline(
                    device: device,
                    library: library
                )
            } else {
                self.particlePipelineState = nil
                self.linePipelineState = nil
            }
        } else {
            self.particleBuffer = nil
            self.connectionBuffer = nil
            self.particlePipelineState = nil
            self.linePipelineState = nil
        }
    }

    func update(
        isActive: Bool,
        startTime: Date?,
        frameHandler: @escaping (TimeInterval) -> Void
    ) {
        self.isActive = isActive
        self.frameHandler = frameHandler
        if isActive {
            if startReferenceTime == nil {
                startReferenceTime = CACurrentMediaTime()
            }
        } else {
            startReferenceTime = nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let commandQueue,
            let particlePipelineState,
            let linePipelineState,
            let particleBuffer,
            let connectionBuffer,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        let currentTime = CACurrentMediaTime()
        let elapsed = startReferenceTime.map {
            max(0, currentTime - $0)
        } ?? 0
        var uniforms = AnimationUniforms(
            time: isActive ? Float(elapsed) : 0,
            viewportSize: SIMD2(
                Float(view.drawableSize.width),
                Float(view.drawableSize.height)
            )
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(linePipelineState)
        encoder.setVertexBuffer(connectionBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<AnimationUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2, instanceCount: connectionCount)

        encoder.setRenderPipelineState(particlePipelineState)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<AnimationUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        guard isActive else { return }
        if Thread.isMainThread {
            frameHandler(elapsed)
        } else {
            DispatchQueue.main.async { [frameHandler] in
                frameHandler(elapsed)
            }
        }
    }

    private static func makeParticlePipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "animationParticleVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "animationParticleFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        configureBlending(for: descriptor)
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeLinePipeline(
        device: MTLDevice,
        library: MTLLibrary
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "animationLineVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "animationColorFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        configureBlending(for: descriptor)
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func configureBlending(for descriptor: MTLRenderPipelineDescriptor) {
        let attachment = descriptor.colorAttachments[0]
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .sourceAlpha
        attachment?.sourceAlphaBlendFactor = .sourceAlpha
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
}
