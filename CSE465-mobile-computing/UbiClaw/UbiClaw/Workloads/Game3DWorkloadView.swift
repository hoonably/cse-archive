import Metal
import MetalKit
import QuartzCore
import SwiftUI
import simd
import os

private struct Game3DVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

private struct Game3DInstance {
    var modelMatrix: simd_float4x4
    var color: SIMD4<Float>
}

private struct Game3DUniforms {
    var viewProjectionMatrix: simd_float4x4
    var shadowMatrix: simd_float4x4
    var lightDirection: SIMD3<Float>
    var time: Float
    var cameraPosition: SIMD3<Float>
    var fogDensity: Float
}

struct Game3DWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double = 0
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Binding var ballCount: Int
    var foregroundSLOBasis: ForegroundSLOBasis = .baselineMean
    var foregroundSLOMultiplier: Double = ForegroundSLODefaults.multiplier
    var foregroundSLOPercentile: Double = ForegroundSLODefaults.percentile
    var frameRateObserver: (ForegroundFrameRateObservation) -> Void = { _ in }

    @State private var signpostState: OSSignpostIntervalState?
    @State private var startTime: Date?
    @StateObject private var frameMonitor = ForegroundFrameRateMonitor(workloadID: "game_3d")

    private var safeBallCount: Int {
        max(1, ballCount)
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            settingsControl
            fpsChart

            Game3DMetalView(
                ballCount: safeBallCount,
                isActive: isActive,
                startTime: startTime,
                frameHandler: handleFrame(at:)
            )
            .id(safeBallCount)
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
                signpostState = Signposts.beginGame3D()
                logger?.log(event: "fg_task_start", workload: "game_3d")
            } else if let state = signpostState {
                Signposts.endGame3D(state)
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

    private var header: some View {
        WorkloadHeaderView(
            title: "Game 3D",
            subtitle: "Instanced 3D scene with depth, offscreen rendering, and fullscreen postprocess to approximate a high-end game frame."
        )
    }

    private var summaryPanel: some View {
        ForegroundFrameRateSummaryPanel(
            monitor: frameMonitor,
            isActive: isActive,
            tokensPerSecond: tokensPerSecond,
            additionalMetrics: [
                WorkloadSummaryMetric("Balls", value: "\(safeBallCount)")
            ]
        )
    }

    private var settingsControl: some View {
        WorkloadSettingsBar {
            WorkloadIntegerSettingField(
                title: "Balls",
                value: $ballCount
            )
        }
        .disabled(isActive)
    }

    private var fpsChart: some View {
        ForegroundFrameRateChart(
            monitor: frameMonitor,
            lineColor: .orange
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

private struct Game3DMetalView: NSViewRepresentable {
    let ballCount: Int
    let isActive: Bool
    let startTime: Date?
    let frameHandler: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            ballCount: ballCount,
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
        view.clearColor = MTLClearColor(red: 0.01, green: 0.015, blue: 0.025, alpha: 0.5)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.framebufferOnly = false
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
        let renderer: Game3DRenderer?

        init(
            ballCount: Int,
            frameHandler: @escaping (TimeInterval) -> Void
        ) {
            renderer = Game3DRenderer(
                ballCount: ballCount,
                frameHandler: frameHandler
            )
        }
    }
}

private final class Game3DRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let scenePipelineState: MTLRenderPipelineState?
    private let shadowPipelineState: MTLRenderPipelineState?
    private let compositePipelineState: MTLRenderPipelineState?
    private let depthStencilState: MTLDepthStencilState?
    private let samplerState: MTLSamplerState?
    private let towerVertexBuffer: MTLBuffer?
    private let towerIndexBuffer: MTLBuffer?
    private let towerInstanceBuffer: MTLBuffer?
    private let towerIndexCount: Int
    private let sphereVertexBuffer: MTLBuffer?
    private let sphereIndexBuffer: MTLBuffer?
    private let ballInstanceBuffer: MTLBuffer?
    private let sphereIndexCount: Int
    private let gridSize = 200
    private let renderScale: CGFloat = 1.5
    private let towerInstanceCount = 200 * 200
    private let ballGridWidth: Int
    private let ballGridDepth: Int
    private let ballInstanceCount: Int
    private let instanceUpdateInterval: Float = 1.0 / 30.0

    private var colorTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var shadowDepthTexture: MTLTexture?
    private var isActive = false
    private var startReferenceTime: TimeInterval?
    private var lastInstanceUpdateElapsed: Float?
    private var frameHandler: (TimeInterval) -> Void

    init(
        ballCount: Int,
        frameHandler: @escaping (TimeInterval) -> Void
    ) {
        let device = MTLCreateSystemDefaultDevice()
        let ballLayout = Self.ballGridLayout(for: ballCount)
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.frameHandler = frameHandler
        self.ballGridWidth = ballLayout.width
        self.ballGridDepth = ballLayout.depth
        self.ballInstanceCount = ballLayout.count

        let towerVertices = Self.makeCubeVertices()
        let towerIndices = Self.makeCubeIndices()
        let (sphereVertices, sphereIndices) = Self.makeSphereMesh(latitudes: 10, longitudes: 18)
        self.towerIndexCount = towerIndices.count
        self.sphereIndexCount = sphereIndices.count

        if let device, let library = device.makeDefaultLibrary() {
            self.towerVertexBuffer = device.makeBuffer(bytes: towerVertices, length: MemoryLayout<Game3DVertex>.stride * towerVertices.count)
            self.towerIndexBuffer = device.makeBuffer(bytes: towerIndices, length: MemoryLayout<UInt16>.stride * towerIndices.count)
            self.towerInstanceBuffer = device.makeBuffer(length: MemoryLayout<Game3DInstance>.stride * towerInstanceCount)
            self.sphereVertexBuffer = device.makeBuffer(bytes: sphereVertices, length: MemoryLayout<Game3DVertex>.stride * sphereVertices.count)
            self.sphereIndexBuffer = device.makeBuffer(bytes: sphereIndices, length: MemoryLayout<UInt16>.stride * sphereIndices.count)
            self.ballInstanceBuffer = device.makeBuffer(length: MemoryLayout<Game3DInstance>.stride * ballInstanceCount)
            self.scenePipelineState = Self.makeScenePipeline(device: device, library: library)
            self.shadowPipelineState = Self.makeShadowPipeline(device: device, library: library)
            self.compositePipelineState = Self.makeCompositePipeline(device: device, library: library)
            self.depthStencilState = Self.makeDepthStencilState(device: device)
            self.samplerState = Self.makeSamplerState(device: device)
        } else {
            self.towerVertexBuffer = nil
            self.towerIndexBuffer = nil
            self.towerInstanceBuffer = nil
            self.sphereVertexBuffer = nil
            self.sphereIndexBuffer = nil
            self.ballInstanceBuffer = nil
            self.scenePipelineState = nil
            self.shadowPipelineState = nil
            self.compositePipelineState = nil
            self.depthStencilState = nil
            self.samplerState = nil
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
            lastInstanceUpdateElapsed = nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard let device else { return }
        colorTexture = Self.makeColorTexture(device: device, size: size)
        depthTexture = Self.makeDepthTexture(device: device, size: size)
        shadowDepthTexture = Self.makeShadowDepthTexture(device: device)
    }

    func draw(in view: MTKView) {
        guard
            let device,
            let commandQueue,
            let scenePipelineState,
            let shadowPipelineState,
            let compositePipelineState,
            let depthStencilState,
            let samplerState,
            let towerVertexBuffer,
            let towerIndexBuffer,
            let towerInstanceBuffer,
            let sphereVertexBuffer,
            let sphereIndexBuffer,
            let ballInstanceBuffer,
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        if colorTexture?.width != Int(view.drawableSize.width) || colorTexture?.height != Int(view.drawableSize.height) {
            colorTexture = Self.makeColorTexture(device: device, size: view.drawableSize)
            depthTexture = Self.makeDepthTexture(device: device, size: view.drawableSize)
        }

        if shadowDepthTexture == nil {
            shadowDepthTexture = Self.makeShadowDepthTexture(device: device)
        }

        guard let colorTexture, let depthTexture, let shadowDepthTexture else { return }

        let currentTime = CACurrentMediaTime()
        let elapsed = startReferenceTime.map {
            max(0, currentTime - $0)
        } ?? 0

        let elapsedFloat = Float(elapsed)
        if shouldUpdateInstanceBuffers(elapsed: elapsedFloat) {
            updateTowerInstances(elapsed: elapsedFloat)
            updateBallInstances(elapsed: elapsedFloat)
            lastInstanceUpdateElapsed = elapsedFloat
        }

        let cameraPosition = SIMD3<Float>(
            sin(Float(elapsed) * 0.22) * 34,
            15 + sin(Float(elapsed) * 0.11) * 3,
            cos(Float(elapsed) * 0.22) * 34
        )
        let target = SIMD3<Float>(0, 2.5, 0)
        let viewMatrix = simd_float4x4.lookAt(eye: cameraPosition, center: target, up: SIMD3<Float>(0, 1, 0))
        let aspect = max(0.1, Float(view.drawableSize.width / max(view.drawableSize.height, 1)))
        let projection = simd_float4x4.perspective(fovY: 58 * .pi / 180, aspect: aspect, nearZ: 0.1, farZ: 160)
        var uniforms = Game3DUniforms(
            viewProjectionMatrix: projection * viewMatrix,
            shadowMatrix: matrix_identity_float4x4,
            lightDirection: simd_normalize(SIMD3<Float>(-0.6, 0.85, 0.25)),
            time: Float(elapsed),
            cameraPosition: cameraPosition,
            fogDensity: 0.032
        )
        let lightPosition = SIMD3<Float>(-28, 36, -24)
        let lightViewMatrix = simd_float4x4.lookAt(eye: lightPosition, center: target, up: SIMD3<Float>(0, 1, 0))
        let lightProjection = simd_float4x4.orthographic(
            left: -70,
            right: 70,
            bottom: -70,
            top: 70,
            nearZ: 0.1,
            farZ: 180
        )
        var shadowUniforms = Game3DUniforms(
            viewProjectionMatrix: lightProjection * lightViewMatrix,
            shadowMatrix: matrix_identity_float4x4,
            lightDirection: uniforms.lightDirection,
            time: uniforms.time,
            cameraPosition: lightPosition,
            fogDensity: 0
        )
        let shadowBiasMatrix = simd_float4x4(
            SIMD4<Float>(0.5, 0, 0, 0),
            SIMD4<Float>(0, -0.5, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0.5, 0.5, 0, 1)
        )
        uniforms.shadowMatrix = shadowBiasMatrix * shadowUniforms.viewProjectionMatrix

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let shadowPass = MTLRenderPassDescriptor()
        shadowPass.depthAttachment.texture = shadowDepthTexture
        shadowPass.depthAttachment.loadAction = .clear
        shadowPass.depthAttachment.storeAction = .store
        shadowPass.depthAttachment.clearDepth = 1

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: shadowPass) {
            encoder.setRenderPipelineState(shadowPipelineState)
            encoder.setDepthStencilState(depthStencilState)
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<Game3DUniforms>.stride, index: 2)
            Self.drawInstances(
                encoder: encoder,
                vertexBuffer: towerVertexBuffer,
                instanceBuffer: towerInstanceBuffer,
                indexBuffer: towerIndexBuffer,
                indexCount: towerIndexCount,
                instanceCount: towerInstanceCount
            )
            Self.drawInstances(
                encoder: encoder,
                vertexBuffer: sphereVertexBuffer,
                instanceBuffer: ballInstanceBuffer,
                indexBuffer: sphereIndexBuffer,
                indexCount: sphereIndexCount,
                instanceCount: ballInstanceCount
            )
            encoder.endEncoding()
        }

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = colorTexture
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .store
        scenePass.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.02, blue: 0.04, alpha: 1)
        scenePass.depthAttachment.texture = depthTexture
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.storeAction = .dontCare
        scenePass.depthAttachment.clearDepth = 1

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) {
            encoder.setRenderPipelineState(scenePipelineState)
            encoder.setDepthStencilState(depthStencilState)
            encoder.setCullMode(.back)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Game3DUniforms>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Game3DUniforms>.stride, index: 0)
            encoder.setFragmentTexture(shadowDepthTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            Self.drawInstances(
                encoder: encoder,
                vertexBuffer: towerVertexBuffer,
                instanceBuffer: towerInstanceBuffer,
                indexBuffer: towerIndexBuffer,
                indexCount: towerIndexCount,
                instanceCount: towerInstanceCount
            )
            // A second pass over the same dense instance field raises geometry and shading cost.
            Self.drawInstances(
                encoder: encoder,
                vertexBuffer: towerVertexBuffer,
                instanceBuffer: towerInstanceBuffer,
                indexBuffer: towerIndexBuffer,
                indexCount: towerIndexCount,
                instanceCount: towerInstanceCount
            )
            Self.drawInstances(
                encoder: encoder,
                vertexBuffer: sphereVertexBuffer,
                instanceBuffer: ballInstanceBuffer,
                indexBuffer: sphereIndexBuffer,
                indexCount: sphereIndexCount,
                instanceCount: ballInstanceCount
            )
            encoder.endEncoding()
        }

        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            encoder.setRenderPipelineState(compositePipelineState)
            encoder.setFragmentTexture(colorTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Game3DUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }

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

    private func updateTowerInstances(elapsed: Float) {
        guard let towerInstanceBuffer else { return }

        let instances = towerInstanceBuffer.contents().bindMemory(
            to: Game3DInstance.self,
            capacity: towerInstanceCount
        )
        let spacing: Float = 2.4
        var index = 0
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let fx = Float(x) - Float(gridSize) * 0.5
                let fz = Float(z) - Float(gridSize) * 0.5
                let worldX = fx * spacing
                let worldZ = fz * spacing
                let height = sinf(fx * 0.37 + elapsed * 0.7) * 1.8 + cosf(fz * 0.29 - elapsed * 0.5) * 1.6
                let tower = max(0.6, 1.2 + height)
                let wobble = sinf(elapsed * 1.1 + Float(x + z) * 0.14) * 0.08
                let scale = SIMD3<Float>(1.1, tower + wobble, 1.1)
                let translation = simd_float4x4.translation(SIMD3<Float>(worldX, scale.y * 0.5 - 0.2, worldZ))
                let rotation = simd_float4x4.rotation(radians: elapsed * 0.03 + Float(x ^ z) * 0.02, axis: SIMD3<Float>(0, 1, 0))
                let model = translation * rotation * simd_float4x4.scale(scale)

                let hue = 0.52 + 0.12 * sinf(Float(x) * 0.13 + Float(z) * 0.11)
                let warm = 0.45 + 0.35 * cosf(elapsed * 0.6 + Float(x) * 0.09)
                let color = SIMD4<Float>(
                    0.25 + 0.35 * warm,
                    0.45 + 0.25 * hue,
                    0.72 + 0.18 * sinf(Float(z) * 0.15),
                    1
                )
                instances[index] = Game3DInstance(modelMatrix: model, color: color)
                index += 1
            }
        }
    }

    private func updateBallInstances(elapsed: Float) {
        guard let ballInstanceBuffer else { return }

        let instances = ballInstanceBuffer.contents().bindMemory(
            to: Game3DInstance.self,
            capacity: ballInstanceCount
        )
        let spacing: Float = 4.8
        let gravity: Float = 18
        let restitution: Float = 0.74
        var index = 0
        for z in 0..<ballGridDepth {
            if index >= ballInstanceCount { break }

            for x in 0..<ballGridWidth {
                if index >= ballInstanceCount { break }

                let fx = Float(x) - Float(ballGridWidth - 1) * 0.5
                let fz = Float(z) - Float(ballGridDepth - 1) * 0.5
                let baseX = fx * spacing
                let baseZ = fz * spacing
                let radius = 0.55 + 0.28 * sin(Float(x + z) * 0.37)
                let phase = Float((x * 17 + z * 11) % 19) * 0.23
                let cycle = 2.8 + Float((x + z) % 5) * 0.22
                let localTime = max(0, elapsed + phase)
                let bounceTime = fmod(localTime, cycle)
                let launchVelocity = gravity * (0.9 + 0.16 * Float((x ^ z) % 4))
                let rawHeight = launchVelocity * bounceTime - 0.5 * gravity * bounceTime * bounceTime
                let bounceHeight = max(rawHeight, 0)
                let compressed = rawHeight < 0 ? min(-rawHeight * restitution * 0.16, radius * 0.28) : 0
                let y = radius + bounceHeight + compressed
                let stretch = rawHeight < 0 ? 1.0 - min(compressed / max(radius, 0.001), 0.22) : 1.0 + min(bounceHeight * 0.015, 0.18)
                let scale = SIMD3<Float>(radius / sqrt(stretch), radius * stretch, radius / sqrt(stretch))
                let lateralExtentX: Float = 1.6 + Float((x + z) % 5) * 0.45
                let lateralExtentZ: Float = 1.5 + Float((x * 3 + z) % 5) * 0.42
                let lateralSpeedX: Float = 1.8 + Float((x * 5 + z) % 7) * 0.22
                let lateralSpeedZ: Float = 1.6 + Float((x + z * 3) % 7) * 0.2
                let lateralX = Self.reflectedMotion(time: localTime * lateralSpeedX, extent: lateralExtentX)
                let lateralZ = Self.reflectedMotion(time: localTime * lateralSpeedZ + 0.37 * Float(x ^ z), extent: lateralExtentZ)
                let impactKick = rawHeight < 0 ? min(-rawHeight * 0.18, 1.4) : 0
                let kickDirection = simd_normalize(SIMD3<Float>(
                    sin(Float(x) * 0.71 + phase),
                    0,
                    cos(Float(z) * 0.67 + phase)
                ))
                let drift = SIMD3<Float>(lateralX, 0, lateralZ) + kickDirection * impactKick
                let translation = simd_float4x4.translation(SIMD3<Float>(baseX, y, baseZ) + drift)
                let rotationAxis = simd_normalize(SIMD3<Float>(
                    0.35 + 0.25 * sin(Float(x) * 0.21),
                    1,
                    0.2 + 0.3 * cos(Float(z) * 0.17)
                ))
                let rotation = simd_float4x4.rotation(radians: localTime * (0.9 + Float((x + z) % 7) * 0.08), axis: rotationAxis)
                let model = translation * rotation * simd_float4x4.scale(scale)
                let color = SIMD4<Float>(
                    0.82 + 0.14 * sin(Float(x) * 0.3),
                    0.26 + 0.22 * cos(Float(z) * 0.41 + elapsed * 0.6),
                    0.34 + 0.38 * sin(Float(x + z) * 0.17),
                    1
                )
                instances[index] = Game3DInstance(modelMatrix: model, color: color)
                index += 1
            }
        }
    }

    private func shouldUpdateInstanceBuffers(elapsed: Float) -> Bool {
        guard let lastInstanceUpdateElapsed else { return true }
        return elapsed - lastInstanceUpdateElapsed >= instanceUpdateInterval
    }

    private static func ballGridLayout(for requestedCount: Int) -> (width: Int, depth: Int, count: Int) {
        let count = max(1, requestedCount)
        let width = max(1, Int(Double(count).squareRoot().rounded(.up)))
        let depth = max(1, Int((Double(count) / Double(width)).rounded(.up)))
        return (width, depth, count)
    }

    private static func makeCubeVertices() -> [Game3DVertex] {
        let p: [SIMD3<Float>] = [
            SIMD3(-0.5, -0.5,  0.5), SIMD3( 0.5, -0.5,  0.5), SIMD3( 0.5,  0.5,  0.5), SIMD3(-0.5,  0.5,  0.5),
            SIMD3( 0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5,  0.5, -0.5), SIMD3( 0.5,  0.5, -0.5),
            SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, -0.5,  0.5), SIMD3(-0.5,  0.5,  0.5), SIMD3(-0.5,  0.5, -0.5),
            SIMD3( 0.5, -0.5,  0.5), SIMD3( 0.5, -0.5, -0.5), SIMD3( 0.5,  0.5, -0.5), SIMD3( 0.5,  0.5,  0.5),
            SIMD3(-0.5,  0.5,  0.5), SIMD3( 0.5,  0.5,  0.5), SIMD3( 0.5,  0.5, -0.5), SIMD3(-0.5,  0.5, -0.5),
            SIMD3(-0.5, -0.5, -0.5), SIMD3( 0.5, -0.5, -0.5), SIMD3( 0.5, -0.5,  0.5), SIMD3(-0.5, -0.5,  0.5)
        ]
        let normals: [SIMD3<Float>] = [
            SIMD3(0, 0, 1), SIMD3(0, 0, -1), SIMD3(-1, 0, 0),
            SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -1, 0)
        ]

        var vertices: [Game3DVertex] = []
        for face in 0..<6 {
            for i in 0..<4 {
                vertices.append(Game3DVertex(position: p[face * 4 + i], normal: normals[face]))
            }
        }
        return vertices
    }

    private static func makeCubeIndices() -> [UInt16] {
        var indices: [UInt16] = []
        for face in 0..<6 {
            let base = UInt16(face * 4)
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        return indices
    }

    private static func makeSphereMesh(latitudes: Int, longitudes: Int) -> ([Game3DVertex], [UInt16]) {
        var vertices: [Game3DVertex] = []
        var indices: [UInt16] = []

        for lat in 0...latitudes {
            let v = Float(lat) / Float(latitudes)
            let theta = v * .pi
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for lon in 0...longitudes {
                let u = Float(lon) / Float(longitudes)
                let phi = u * 2 * .pi
                let normal = SIMD3<Float>(
                    sinTheta * cos(phi),
                    cosTheta,
                    sinTheta * sin(phi)
                )
                vertices.append(Game3DVertex(position: normal, normal: simd_normalize(normal)))
            }
        }

        let stride = longitudes + 1
        for lat in 0..<latitudes {
            for lon in 0..<longitudes {
                let a = UInt16(lat * stride + lon)
                let b = UInt16((lat + 1) * stride + lon)
                let c = UInt16(lat * stride + lon + 1)
                let d = UInt16((lat + 1) * stride + lon + 1)
                indices.append(contentsOf: [a, b, c, c, b, d])
            }
        }

        return (vertices, indices)
    }

    private static func drawInstances(
        encoder: MTLRenderCommandEncoder,
        vertexBuffer: MTLBuffer,
        instanceBuffer: MTLBuffer,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        instanceCount: Int
    ) {
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: instanceCount
        )
    }

    private static func reflectedMotion(time: Float, extent: Float) -> Float {
        let cycle = fmod(time, 4)
        let positiveCycle = cycle < 0 ? cycle + 4 : cycle
        let normalized = positiveCycle < 2 ? positiveCycle - 1 : 3 - positiveCycle
        return normalized * extent
    }

    private static func makeScenePipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "game3DVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "game3DFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeShadowPipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "game3DVertex")
        descriptor.fragmentFunction = nil
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeCompositePipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "game3DFullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "game3DCompositeFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeDepthStencilState(device: MTLDevice) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.isDepthWriteEnabled = true
        descriptor.depthCompareFunction = .less
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    private static func makeSamplerState(device: MTLDevice) -> MTLSamplerState? {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: descriptor)
    }

    private static func makeColorTexture(device: MTLDevice, size: CGSize) -> MTLTexture? {
        let renderScale: CGFloat = 1.5
        let scaledWidth = max(1, Int(size.width * renderScale))
        let scaledHeight = max(1, Int(size.height * renderScale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: scaledWidth,
            height: scaledHeight,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage(arrayLiteral: .renderTarget, .shaderRead)
        return device.makeTexture(descriptor: descriptor)
    }

    private static func makeDepthTexture(device: MTLDevice, size: CGSize) -> MTLTexture? {
        let renderScale: CGFloat = 1.5
        let scaledWidth = max(1, Int(size.width * renderScale))
        let scaledHeight = max(1, Int(size.height * renderScale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: scaledWidth,
            height: scaledHeight,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage(arrayLiteral: .renderTarget)
        return device.makeTexture(descriptor: descriptor)
    }

    private static func makeShadowDepthTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: 2048,
            height: 2048,
            mipmapped: false
        )
        descriptor.usage = MTLTextureUsage(arrayLiteral: .renderTarget, .shaderRead)
        return device.makeTexture(descriptor: descriptor)
    }
}

private extension simd_float4x4 {
    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(t.x, t.y, t.z, 1)
        )
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(s.x, 0, 0, 0),
            SIMD4(0, s.y, 0, 0),
            SIMD4(0, 0, s.z, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        let a = simd_normalize(axis)
        let ct = cos(radians)
        let st = sin(radians)
        let ci = 1 - ct

        return simd_float4x4(
            SIMD4(ct + a.x * a.x * ci, a.x * a.y * ci + a.z * st, a.x * a.z * ci - a.y * st, 0),
            SIMD4(a.y * a.x * ci - a.z * st, ct + a.y * a.y * ci, a.y * a.z * ci + a.x * st, 0),
            SIMD4(a.z * a.x * ci + a.y * st, a.z * a.y * ci - a.x * st, ct + a.z * a.z * ci, 0),
            SIMD4(0, 0, 0, 1)
        )
    }

    static func perspective(fovY: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = farZ / (nearZ - farZ)
        return simd_float4x4(
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * nearZ, 0)
        )
    }

    static func orthographic(
        left: Float,
        right: Float,
        bottom: Float,
        top: Float,
        nearZ: Float,
        farZ: Float
    ) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(2 / (right - left), 0, 0, 0),
            SIMD4(0, 2 / (top - bottom), 0, 0),
            SIMD4(0, 0, 1 / (nearZ - farZ), 0),
            SIMD4(
                (left + right) / (left - right),
                (top + bottom) / (bottom - top),
                nearZ / (nearZ - farZ),
                1
            )
        )
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - center)
        let x = simd_normalize(simd_cross(up, z))
        let y = simd_cross(z, x)
        return simd_float4x4(
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        )
    }
}
