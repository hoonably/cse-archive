import AVFoundation
import AVKit
import AppKit
import QuartzCore
import SwiftUI
import os

/// 4K H.264 video playback workload backed by AVPlayer + AVPlayerItemVideoOutput.
/// FPS is sampled from the display link whenever a new decoded pixel buffer becomes
/// available, so the chart reflects presented decoded frames (drops as Media Engine
/// or main-thread compositor falls behind).
/// Signpost interval fg_video wraps the active playback phase.
struct VideoPlaybackWorkloadView: View {
    let isActive: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double
    var chartDisplayMode: WorkloadChartDisplayMode
    var foregroundSLOBasis: ForegroundSLOBasis
    var foregroundSLOMultiplier: Double
    var foregroundSLOPercentile: Double
    var frameRateObserver: (ForegroundFrameRateObservation) -> Void

    @State private var signpostState: OSSignpostIntervalState?
    @State private var startTime: Date?
    @State private var info = VideoPlaybackInfo()
    @StateObject private var frameMonitor = ForegroundFrameRateMonitor(workloadID: "video")

    init(
        isActive: Bool,
        logger: CSVLogger?,
        timelineMarkers: [TimelineMarker],
        tokensPerSecond: Double = 0,
        chartDisplayMode: WorkloadChartDisplayMode = .recent,
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
        self.foregroundSLOBasis = foregroundSLOBasis
        self.foregroundSLOMultiplier = foregroundSLOMultiplier
        self.foregroundSLOPercentile = foregroundSLOPercentile
        self.frameRateObserver = frameRateObserver
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            fpsChart

            VideoPlaybackPlayerView(
                videoURL: VideoPlaybackWorkloadView.videoURL,
                isActive: isActive,
                startTime: startTime,
                frameHandler: handleFrame(at:),
                infoHandler: { info = $0 }
            )
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
                signpostState = Signposts.beginVideo()
                logger?.log(event: "fg_task_start", workload: "video")
            } else if let state = signpostState {
                Signposts.endVideo(state)
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
            title: "Video Playback",
            subtitle: "4K H.264 decode via VideoToolbox with display-linked FPS capture for stutter and dropped-frame detection."
        )
    }

    private var summaryPanel: some View {
        ForegroundFrameRateSummaryPanel(
            monitor: frameMonitor,
            isActive: isActive,
            tokensPerSecond: tokensPerSecond,
            additionalMetrics: [
                WorkloadSummaryMetric(
                    "Source",
                    value: info.resolutionText
                ),
                WorkloadSummaryMetric(
                    "Source FPS",
                    value: info.nominalFPS > 0 ? String(format: "%.1f", info.nominalFPS) : "—"
                ),
                WorkloadSummaryMetric(
                    "Dropped",
                    value: "\(info.droppedFrames)",
                    valueColor: info.droppedFrames > 0 ? .red : .primary
                )
            ]
        )
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

    static let videoFileName = "whiplash_8k.mp4"

    static var videoURL: URL? {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            Bundle.main.url(forResource: "whiplash_8k", withExtension: "mp4"),
            videosDirectory()?.appendingPathComponent(videoFileName),
            repoRoot()?.appendingPathComponent(videoFileName),
            // Fall back to the 4K source if 8K hasn't been generated yet.
            videosDirectory()?.appendingPathComponent("whiplash_4k.mp4"),
            repoRoot()?.appendingPathComponent("whiplash_4k.mp4")
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func videosDirectory() -> URL? {
        repoRoot()?.appendingPathComponent("Videos", isDirectory: true)
    }

    private static func repoRoot() -> URL? {
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

struct VideoPlaybackInfo: Equatable {
    var resolution: CGSize = .zero
    var nominalFPS: Double = 0
    var droppedFrames: Int = 0

    var resolutionText: String {
        guard resolution.width > 0, resolution.height > 0 else { return "—" }
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }
}

private struct VideoPlaybackPlayerView: NSViewRepresentable {
    let videoURL: URL?
    let isActive: Bool
    let startTime: Date?
    let frameHandler: (TimeInterval) -> Void
    let infoHandler: (VideoPlaybackInfo) -> Void

    func makeCoordinator() -> VideoPlaybackCoordinator {
        VideoPlaybackCoordinator(
            videoURL: videoURL,
            frameHandler: frameHandler,
            infoHandler: infoHandler
        )
    }

    func makeNSView(context: Context) -> VideoPlaybackHostView {
        let view = VideoPlaybackHostView()
        view.attach(coordinator: context.coordinator)
        context.coordinator.update(isActive: isActive, startTime: startTime)
        return view
    }

    func updateNSView(_ nsView: VideoPlaybackHostView, context: Context) {
        context.coordinator.frameHandler = frameHandler
        context.coordinator.infoHandler = infoHandler
        context.coordinator.update(isActive: isActive, startTime: startTime)
    }

    static func dismantleNSView(_ nsView: VideoPlaybackHostView, coordinator: VideoPlaybackCoordinator) {
        coordinator.shutdown()
    }
}

private final class VideoPlaybackHostView: NSView {
    private weak var coordinator: VideoPlaybackCoordinator?
    private let playerView = AVPlayerView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var displayLink: CADisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.videoGravity = .resizeAspect
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.isHidden = true
        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func attach(coordinator: VideoPlaybackCoordinator) {
        self.coordinator = coordinator
        coordinator.install(playerHost: { [weak self] player in
            self?.playerView.player = player
        }, fallbackHandler: { [weak self] message in
            self?.showFallback(message: message)
        })
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil, let coordinator else { return }
        let link = displayLink(target: coordinator, selector: #selector(VideoPlaybackCoordinator.handleDisplayLinkTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func showFallback(message: String) {
        messageLabel.stringValue = message
        messageLabel.isHidden = false
    }

    deinit {
        displayLink?.invalidate()
    }
}

private final class VideoPlaybackCoordinator: NSObject {
    static let playbackRate: Float = 1.0

    var frameHandler: (TimeInterval) -> Void
    var infoHandler: (VideoPlaybackInfo) -> Void

    private let videoURL: URL?
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var endObserver: NSObjectProtocol?

    private var isActive = false
    private var startReferenceTime: TimeInterval?
    private var info = VideoPlaybackInfo()
    private var lastDroppedFramesReport: Int = 0
    private var fallbackHandler: ((String) -> Void)?

    init(
        videoURL: URL?,
        frameHandler: @escaping (TimeInterval) -> Void,
        infoHandler: @escaping (VideoPlaybackInfo) -> Void
    ) {
        self.videoURL = videoURL
        self.frameHandler = frameHandler
        self.infoHandler = infoHandler
        super.init()
    }

    func install(
        playerHost: (AVPlayer) -> Void,
        fallbackHandler: @escaping (String) -> Void
    ) {
        self.fallbackHandler = fallbackHandler

        guard let videoURL else {
            fallbackHandler("Place \(VideoPlaybackWorkloadView.videoFileName) in the Videos/ directory.")
            publishInfo()
            return
        }

        let item = AVPlayerItem(url: videoURL)
        // Empty attributes lets the output use the source's native pixel format,
        // avoiding a per-frame BGRA conversion that fights AVPlayerView's compositor.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [:])
        item.add(output)

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none

        self.player = player
        self.playerItem = item
        self.videoOutput = output
        playerHost(player)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player?.seek(to: .zero)
            if self.isActive {
                self.player?.rate = Self.playbackRate
            }
        }

        captureTrackMetadata(for: item)
    }

    func update(isActive: Bool, startTime: Date?) {
        let wasActive = self.isActive
        self.isActive = isActive

        if isActive {
            if startReferenceTime == nil {
                startReferenceTime = CACurrentMediaTime()
            }
            if !wasActive {
                player?.seek(to: .zero)
                lastDroppedFramesReport = 0
            }
            player?.rate = Self.playbackRate
        } else {
            player?.pause()
            startReferenceTime = nil
        }
    }

    func shutdown() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        playerItem = nil
        videoOutput = nil
    }

    deinit {
        shutdown()
    }

    private func captureTrackMetadata(for item: AVPlayerItem) {
        Task { [weak self] in
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else { return }
                let size = try await track.load(.naturalSize)
                let fps = try await track.load(.nominalFrameRate)
                await MainActor.run {
                    guard let self else { return }
                    self.info.resolution = size
                    self.info.nominalFPS = Double(fps)
                    self.infoHandler(self.info)
                }
            } catch {
                // metadata load failure is non-fatal; chart still works
            }
        }
    }

    @objc func handleDisplayLinkTick(_ link: CADisplayLink) {
        guard isActive,
              let videoOutput,
              let startReferenceTime else { return }

        let hostTime = link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime()
        let itemTime = videoOutput.itemTime(forHostTime: hostTime)
        // Probe-only: don't copy/consume the pixel buffer, otherwise AVPlayerView's
        // own compositor can be starved of frames on high-rate sources.
        guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { return }

        let elapsed = max(0, CACurrentMediaTime() - startReferenceTime)
        let droppedFrames = currentDroppedFrames()
        if droppedFrames != lastDroppedFramesReport {
            info.droppedFrames = droppedFrames
            lastDroppedFramesReport = droppedFrames
            publishInfo()
        }
        DispatchQueue.main.async { [weak self] in
            self?.frameHandler(elapsed)
        }
    }

    private func currentDroppedFrames() -> Int {
        guard let events = playerItem?.accessLog()?.events else { return lastDroppedFramesReport }
        return events.reduce(0) { acc, event in
            let dropped = event.numberOfDroppedVideoFrames
            return dropped > 0 ? acc + dropped : acc
        }
    }

    private func publishInfo() {
        let snapshot = info
        DispatchQueue.main.async { [weak self] in
            self?.infoHandler(snapshot)
        }
    }
}
