import SwiftUI
import WebKit
import os

struct HexGLRaceWorkloadView: View {
    let isActive: Bool
    let shouldStartGame: Bool
    let logger: CSVLogger?
    let timelineMarkers: [TimelineMarker]
    var tokensPerSecond: Double = 0
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    @Binding var quality: HexGLQuality
    var foregroundSLOBasis: ForegroundSLOBasis = .baselineMean
    var foregroundSLOMultiplier: Double = ForegroundSLODefaults.multiplier
    var foregroundSLOPercentile: Double = ForegroundSLODefaults.percentile
    var frameRateObserver: (ForegroundFrameRateObservation) -> Void = { _ in }

    @State private var signpostState: OSSignpostIntervalState?
    @State private var runStartTime: TimeInterval?
    @State private var webStatus = "Ready"
    @State private var audioVolume = 1.0
    @StateObject private var frameMonitor = ForegroundFrameRateMonitor(workloadID: "hexgl_race")

    var body: some View {
        VStack(spacing: 20) {
            header
            summaryPanel
            controls
            fpsChart

            HexGLWebView(
                isActive: isActive,
                shouldStartGame: shouldStartGame,
                quality: quality,
                audioVolume: audioVolume,
                autoStartDelaySeconds: 0,
                statusHandler: { webStatus = $0 },
                eventHandler: handleWebEvent,
                frameHandler: handleWebFrame
            )
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.08))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: isActive) { _, active in
            if active {
                startRun()
            } else {
                stopRun()
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
            title: "HexGL Race",
            subtitle: "Embedded WebGL racing game. Controls: arrow keys to steer and accelerate, A/D or Q/E for air brakes."
        )
    }

    private var summaryPanel: some View {
        ForegroundFrameRateSummaryPanel(
            monitor: frameMonitor,
            isActive: isActive,
            tokensPerSecond: tokensPerSecond,
            additionalMetrics: [
                WorkloadSummaryMetric("Game", value: "HexGL"),
                WorkloadSummaryMetric("Quality", value: quality.displayName),
                WorkloadSummaryMetric("Volume", value: "\(Int(audioVolume * 100))%"),
                WorkloadSummaryMetric("WebView", value: webStatus)
            ]
        )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            qualityControl
            volumeControl
        }
    }

    private var qualityControl: some View {
        HStack(spacing: 12) {
            Text("Quality")
                .font(.headline)
                .frame(width: 72, alignment: .leading)

            Picker("", selection: $quality) {
                ForEach(HexGLQuality.selectionOrder, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(isActive || shouldStartGame)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Text("Volume")
                .font(.headline)
                .frame(width: 72, alignment: .leading)

            Slider(value: $audioVolume, in: 0...1)

            Text("\(Int(audioVolume * 100))%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var fpsChart: some View {
        ForegroundFrameRateChart(
            monitor: frameMonitor,
            lineColor: .green
        )
    }

    private func startRun() {
        runStartTime = CFAbsoluteTimeGetCurrent()
        webStatus = "Starting"
        updateFrameMonitorSLOConfig()
        frameMonitor.updateChartDisplayMode(chartDisplayMode)
        frameMonitor.reset()
        frameMonitor.updateTimelineMarkers(timelineMarkers)
        signpostState = Signposts.beginHexGLRace()
        logger?.log(event: "fg_task_start", workload: "hexgl_race")
    }

    private func stopRun() {
        if let state = signpostState {
            Signposts.endHexGLRace(state)
        }
        frameMonitor.stopLogging(logger: logger)
        signpostState = nil
        runStartTime = nil
    }

    private func updateFrameMonitorSLOConfig() {
        frameMonitor.updateSLOConfig(
            basis: foregroundSLOBasis,
            multiplier: foregroundSLOMultiplier,
            percentile: foregroundSLOPercentile
        )
    }

    private func handleWebFrame() {
        guard let runStartTime else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - runStartTime
        if let observation = frameMonitor.recordFrame(
            elapsed: elapsed,
            isActive: isActive,
            logger: logger
        ) {
            frameRateObserver(observation)
        }
    }

    private func handleWebEvent(type: String, value: String) {
        let eventName: String
        switch type {
        case "status", "error", "debug":
            eventName = "hexgl_web_\(type)"
        default:
            eventName = "hexgl_web_event"
        }

        logger?.log(
            event: eventName,
            workload: "hexgl_race",
            params: String(value.prefix(800))
        )
    }
}

private struct HexGLWebView: NSViewRepresentable {
    let isActive: Bool
    let shouldStartGame: Bool
    let quality: HexGLQuality
    let audioVolume: Double
    let autoStartDelaySeconds: TimeInterval
    let statusHandler: (String) -> Void
    let eventHandler: (String, String) -> Void
    let frameHandler: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            statusHandler: statusHandler,
            eventHandler: eventHandler,
            frameHandler: frameHandler
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "ubiclawHexGL")
        userContentController.addUserScript(WKUserScript(
            source: HexGLBridgeScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        context.coordinator.webView = webView
        updateNSView(webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.statusHandler = statusHandler
        context.coordinator.eventHandler = eventHandler
        context.coordinator.frameHandler = frameHandler

        context.coordinator.loadHexGLMenuIfNeeded(
            in: webView,
            quality: quality,
            audioVolume: audioVolume
        )
        context.coordinator.updateAudioVolume(audioVolume, in: webView)

        if shouldStartGame {
            context.coordinator.startGameWhenReady(
                in: webView,
                autoStartDelaySeconds: autoStartDelaySeconds
            )
            DispatchQueue.main.async {
                webView.window?.makeFirstResponder(webView)
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        coordinator.stopLocalServer()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ubiclawHexGL")
        webView.configuration.userContentController.removeAllUserScripts()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var statusHandler: (String) -> Void
        var eventHandler: (String, String) -> Void
        var frameHandler: () -> Void
        weak var webView: WKWebView?

        private var isLoaded = false
        private var localBaseURL: URL?
        private var loadedQuality: HexGLQuality?
        private var pendingAudioVolume = 1.0
        private var lastAppliedAudioVolume: Double?
        private var hasGameStartRequest = false
        private var pendingStartDelayMs: Int?
        private var lastStatus = ""
        private var localServer: HexGLLocalHTTPServer?

        init(
            statusHandler: @escaping (String) -> Void,
            eventHandler: @escaping (String, String) -> Void,
            frameHandler: @escaping () -> Void
        ) {
            self.statusHandler = statusHandler
            self.eventHandler = eventHandler
            self.frameHandler = frameHandler
        }

        func loadHexGLMenuIfNeeded(
            in webView: WKWebView,
            quality: HexGLQuality,
            audioVolume: Double
        ) {
            pendingAudioVolume = Self.clampAudioVolume(audioVolume)

            if isLoaded {
                if loadedQuality != quality && !hasGameStartRequest {
                    reloadMenu(in: webView, quality: quality)
                }
                return
            }

            guard let gameRootURL = Self.resolveHexGLRootURL() else {
                sendStatus("Missing")
                return
            }

            isLoaded = true
            loadedQuality = quality
            sendStatus("Starting server")

            let server = HexGLLocalHTTPServer(rootDirectory: gameRootURL)
            localServer = server
            server.start { [weak self, weak webView] result in
                guard let self, self.isLoaded, let webView else { return }

                switch result {
                case .success(let baseURL):
                    self.localBaseURL = baseURL
                    self.eventHandler("debug", "local_http_root=\(baseURL.absoluteString)")
                    self.sendStatus("Loading")

                    let launchURL = Self.launchURL(
                        baseURL: baseURL,
                        quality: quality,
                        audioVolume: self.pendingAudioVolume
                    )
                    webView.load(URLRequest(url: launchURL))
                case .failure(let error):
                    self.eventHandler("error", "Local HexGL server failed: \(error.localizedDescription)")
                    self.sendStatus("Server failed")
                    self.isLoaded = false
                    self.localBaseURL = nil
                    self.loadedQuality = nil
                    self.localServer = nil
                }
            }
        }

        func startGameWhenReady(
            in webView: WKWebView,
            autoStartDelaySeconds: TimeInterval
        ) {
            hasGameStartRequest = true
            pendingStartDelayMs = Int(max(0, autoStartDelaySeconds) * 1000)
            tryStartPendingGame(in: webView)
        }

        func updateAudioVolume(_ volume: Double, in webView: WKWebView) {
            let clamped = Self.clampAudioVolume(volume)
            pendingAudioVolume = clamped
            guard lastAppliedAudioVolume != clamped else { return }
            applyAudioVolume(clamped, in: webView)
        }

        private static func clampAudioVolume(_ value: Double) -> Double {
            min(1, max(0, value))
        }

        private static func resolveHexGLRootURL() -> URL? {
            let externalCheckoutURL = AppConfig.repoRoot()
                .appendingPathComponent("HexGL", isDirectory: true)

            if FileManager.default.fileExists(
                atPath: externalCheckoutURL.appendingPathComponent("index.html").path
            ) {
                return externalCheckoutURL
            }

            return Bundle.main.url(
                forResource: "HexGL",
                withExtension: "bundle"
            )
        }

        private static func launchURL(
            baseURL: URL,
            quality: HexGLQuality,
            audioVolume: Double
        ) -> URL {
            let indexURL = baseURL.appendingPathComponent("index.html")
            var components = URLComponents(url: indexURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "ubiclawFreeRun", value: "1"),
                URLQueryItem(name: "quality", value: quality.queryValue),
                URLQueryItem(name: "godmode", value: "1"),
                URLQueryItem(name: "ubiclawAudioVolume", value: String(Self.clampAudioVolume(audioVolume)))
            ]

            return components?.url ?? indexURL
        }

        private func reloadMenu(in webView: WKWebView, quality: HexGLQuality) {
            guard let baseURL = localBaseURL else { return }
            hasGameStartRequest = false
            pendingStartDelayMs = nil
            loadedQuality = quality
            lastAppliedAudioVolume = nil
            sendStatus("Loading")
            webView.load(URLRequest(url: Self.launchURL(
                baseURL: baseURL,
                quality: quality,
                audioVolume: pendingAudioVolume
            )))
        }

        private func tryStartPendingGame(in webView: WKWebView) {
            guard let delayMs = pendingStartDelayMs else { return }
            let script = "window.ubiclawStartHexGLWhenReady ? window.ubiclawStartHexGLWhenReady(\(delayMs)) : false"

            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard let self, let webView, self.pendingStartDelayMs != nil else { return }
                if let didStart = result as? Bool, didStart {
                    self.pendingStartDelayMs = nil
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.tryStartPendingGame(in: webView)
                }
            }
        }

        private func applyAudioVolume(_ volume: Double, in webView: WKWebView) {
            let script = "window.ubiclawSetAudioVolume ? window.ubiclawSetAudioVolume(\(volume)) : false"
            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard let self else { return }
                if let didApply = result as? Bool, didApply {
                    self.lastAppliedAudioVolume = volume
                    return
                }

                guard self.isLoaded, self.pendingAudioVolume == volume, let webView else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.applyAudioVolume(volume, in: webView)
                }
            }
        }

        func unloadIfNeeded(in webView: WKWebView) {
            guard isLoaded else { return }
            isLoaded = false
            localBaseURL = nil
            loadedQuality = nil
            hasGameStartRequest = false
            pendingStartDelayMs = nil
            stopLocalServer()
            webView.stopLoading()
            webView.loadHTMLString(
                "<!doctype html><html><body style='margin:0;background:#000'></body></html>",
                baseURL: nil
            )
            sendStatus("Stopped")
        }

        func stopLocalServer() {
            localServer?.stop()
            localServer = nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "ubiclawHexGL" else { return }

            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                switch type {
                case "frame":
                    frameHandler()
                case "status":
                    sendStatus(body["value"] as? String ?? "Running")
                case "error":
                    let value = body["value"] as? String ?? "Unknown JavaScript error"
                    eventHandler("error", value)
                    sendStatus("JS Error")
                case "debug":
                    eventHandler("debug", body["value"] as? String ?? "")
                default:
                    break
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            sendLoadedIfStillLoading()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            sendStatus("Load failed")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            sendStatus("Load failed")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.isFileURL || url.scheme == "about" || Self.isLocalHTTPURL(url) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private static func isLocalHTTPURL(_ url: URL) -> Bool {
            guard url.scheme == "http" else { return false }
            return url.host == "127.0.0.1" || url.host == "localhost"
        }

        private func sendStatus(_ status: String) {
            guard status != lastStatus else { return }
            lastStatus = status
            eventHandler("status", status)
            DispatchQueue.main.async {
                self.statusHandler(status)
            }
        }

        private func sendLoadedIfStillLoading() {
            switch lastStatus {
            case "", "Starting server", "Loading":
                sendStatus("Loaded")
                if let webView {
                    applyAudioVolume(pendingAudioVolume, in: webView)
                    tryStartPendingGame(in: webView)
                }
            default:
                break
            }
        }
    }
}

private enum HexGLBridgeScript {
    static let source = #"""
(function() {
  'use strict';

  if (window.__ubiclawHexGLBridgeInstalled) return;
  window.__ubiclawHexGLBridgeInstalled = true;

  var bridge = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.ubiclawHexGL
    : null;
  var lastFramePost = 0;
  var framePostIntervalMs = 0;
  var hasReportedRunning = false;
  var lastStepStatus = '';
  var hasReportedFreeRun = false;
  var hasReportedGameSettings = false;
  var startRequested = false;
  var audioMasterVolume = parseInitialAudioVolume();

  function post(message) {
    if (!bridge) return;
    try {
      bridge.postMessage(message);
    } catch (error) {
      bridge = null;
    }
  }

  function stringify(value) {
    try {
      if (typeof value === 'string') return value;
      if (value && value.message) return value.message;
      return JSON.stringify(value);
    } catch (error) {
      return String(value);
    }
  }

  function status(value) {
    post({ type: 'status', value: value });
  }

  function debug(value) {
    post({ type: 'debug', value: value });
  }

  function error(value) {
    post({ type: 'error', value: value });
  }

  function clampAudioVolume(value) {
    value = Number(value);
    if (!isFinite(value)) return 1;
    return Math.max(0, Math.min(1, value));
  }

  function parseInitialAudioVolume() {
    try {
      return clampAudioVolume(new URLSearchParams(window.location.search).get('ubiclawAudioVolume'));
    } catch (error) {
      return 1;
    }
  }

  function applySoundVolume(sound) {
    if (!sound) return;
    var baseVolume = typeof sound.__ubiclawBaseVolume === 'number'
      ? sound.__ubiclawBaseVolume
      : 1;
    var effectiveVolume = Math.max(0, baseVolume * audioMasterVolume);
    if (sound.gainNode && sound.gainNode.gain) {
      sound.gainNode.gain.value = effectiveVolume;
    } else if (typeof sound.volume !== 'undefined') {
      sound.volume = effectiveVolume;
    }
  }

  function applyAllAudioVolumes() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio.sounds) return;
    for (var id in bkcore.Audio.sounds) {
      if (Object.prototype.hasOwnProperty.call(bkcore.Audio.sounds, id)) {
        applySoundVolume(bkcore.Audio.sounds[id]);
      }
    }
  }

  window.ubiclawSetAudioVolume = function(value) {
    audioMasterVolume = clampAudioVolume(value);
    applyAllAudioVolumes();
    return true;
  };

  function shouldSuppressSystemKeySound(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return false;
    return (event.keyCode || event.which || 0) !== 0;
  }

  function focusGameSurface() {
    var target = document.getElementById('main') || document.body || document.documentElement;
    if (!target || !target.focus) return;
    if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
    try {
      target.focus({ preventScroll: true });
    } catch (error) {
      target.focus();
    }
  }

  function resumeAudioContext() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio._ctx) return;
    var ctx = bkcore.Audio._ctx;
    if (ctx.state === 'suspended' && ctx.resume) {
      try {
        var result = ctx.resume();
        if (result && result.catch) result.catch(function() {});
      } catch (error) {}
    }
  }

  function preventSystemKeySound(event) {
    if (!shouldSuppressSystemKeySound(event)) return;
    event.preventDefault();
    resumeAudioContext();
  }

  function installInputAndAudioGuards() {
    document.addEventListener('keydown', preventSystemKeySound, true);
    document.addEventListener('keyup', preventSystemKeySound, true);
    document.addEventListener('mousedown', function() {
      focusGameSurface();
      resumeAudioContext();
    }, true);
    document.addEventListener('touchstart', function() {
      focusGameSurface();
      resumeAudioContext();
    }, true);
  }

  function installAudioControlsHook() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio.play || !bkcore.Audio.volume || !bkcore.Audio.addSound) {
      window.setTimeout(installAudioControlsHook, 50);
      return;
    }
    if (bkcore.Audio.__ubiclawAudioControlsHooked) return;
    var originalAddSound = bkcore.Audio.addSound;
    var originalPlay = bkcore.Audio.play;
    var originalVolume = bkcore.Audio.volume;
    bkcore.Audio.addSound = function(src, id, loop, callback, usePanner) {
      var wrappedCallback = function() {
        if (bkcore.Audio.sounds[id] && typeof bkcore.Audio.sounds[id].__ubiclawBaseVolume !== 'number') {
          bkcore.Audio.sounds[id].__ubiclawBaseVolume = 1;
        }
        applyAllAudioVolumes();
        if (callback) return callback.apply(this, arguments);
      };
      var result = originalAddSound.call(this, src, id, loop, wrappedCallback, usePanner);
      if (bkcore.Audio.sounds[id] && typeof bkcore.Audio.sounds[id].__ubiclawBaseVolume !== 'number') {
        bkcore.Audio.sounds[id].__ubiclawBaseVolume = 1;
      }
      applySoundVolume(bkcore.Audio.sounds[id]);
      return result;
    };
    bkcore.Audio.play = function() {
      resumeAudioContext();
      var result = originalPlay.apply(this, arguments);
      applyAllAudioVolumes();
      return result;
    };
    bkcore.Audio.volume = function(id, volume) {
      if (bkcore.Audio.sounds[id]) {
        bkcore.Audio.sounds[id].__ubiclawBaseVolume = clampAudioVolume(volume);
      }
      return originalVolume.call(this, id, clampAudioVolume(volume) * audioMasterVolume);
    };
    bkcore.Audio.__ubiclawAudioControlsHooked = true;
    window.ubiclawSetAudioVolume(audioMasterVolume);
    debug('audio_controls_hooked');
  }

  window.addEventListener('error', function(event) {
    error((event.message || 'JavaScript error') + ' @ ' + (event.filename || 'inline') + ':' + (event.lineno || 0));
  });

  window.addEventListener('unhandledrejection', function(event) {
    error('Unhandled promise rejection: ' + stringify(event.reason));
  });

  var originalConsoleError = console.error;
  console.error = function() {
    var args = Array.prototype.slice.call(arguments).map(stringify).join(' ');
    error(args);
    return originalConsoleError.apply(console, arguments);
  };

  function isDisplayed(element) {
    if (!element) return false;
    return window.getComputedStyle(element).display !== 'none';
  }

  function visibleStep() {
    var ids = ['step-1', 'step-2', 'step-3', 'step-4', 'step-5'];
    for (var i = 0; i < ids.length; i++) {
      if (isDisplayed(document.getElementById(ids[i]))) return ids[i];
    }
    return 'unknown';
  }

  function hasVisibleCanvas() {
    var canvas = document.querySelector('#main canvas');
    var step4 = document.getElementById('step-4');
    return !!(canvas && isDisplayed(step4));
  }

  function postFrameIfRunning() {
    if (hasVisibleCanvas()) {
      if (!hasReportedRunning) {
        hasReportedRunning = true;
        status('Running');
      }

      var now = performance.now();
      if (now - lastFramePost >= framePostIntervalMs) {
        lastFramePost = now;
        post({ type: 'frame' });
      }
    }
  }

  function frameLoop() {
    postFrameIfRunning();
    window.requestAnimationFrame(frameLoop);
  }

  function reportStep() {
    var step = visibleStep();
    if (step !== lastStepStatus) {
      lastStepStatus = step;
      debug('visible_step=' + step);
      if (step === 'step-3') status('Loading assets');
      if (step === 'step-4') status('Game visible');
      if (step === 'step-5') status('Finished');
    }
    window.setTimeout(reportStep, 500);
  }

  function clickElement(element) {
    if (!element) return false;
    element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    return true;
  }

  function isFreeRunRequested() {
    return new URLSearchParams(window.location.search).get('ubiclawFreeRun') === '1';
  }

  function recoverShip(shipControls) {
    if (!shipControls) return;
    shipControls.destroyed = false;
    shipControls.falling = false;
    shipControls.active = true;
    shipControls.shield = shipControls.maxShield || 1;
    if (shipControls.collision) {
      shipControls.collision.front = false;
      shipControls.collision.left = false;
      shipControls.collision.right = false;
    }
    if (shipControls.speed && shipControls.maxSpeed) {
      shipControls.speed = Math.min(shipControls.speed, shipControls.maxSpeed * 0.35);
    }
  }

  function installFreeRunMode() {
    if (!isFreeRunRequested()) return;
    if (!window.bkcore || !bkcore.hexgl || !bkcore.hexgl.ShipControls || !bkcore.hexgl.Gameplay) {
      window.setTimeout(installFreeRunMode, 50);
      return;
    }

    var shipPrototype = bkcore.hexgl.ShipControls.prototype;
    if (!shipPrototype.__ubiclawFreeRunPatched) {
      shipPrototype.destroy = function() {
        recoverShip(this);
      };
      shipPrototype.fall = function() {
        recoverShip(this);
        if (this.repulsionForce) this.repulsionForce.z = -Math.max(this.repulsionAmount || 0.8, 1.0);
      };
      shipPrototype.__ubiclawFreeRunPatched = true;
    }

    var gameplayPrototype = bkcore.hexgl.Gameplay.prototype;
    if (!gameplayPrototype.__ubiclawFreeRunPatched) {
      var originalStart = gameplayPrototype.start;
      gameplayPrototype.start = function() {
        var result = originalStart.apply(this, arguments);
        this.maxLaps = 1;
        if (this.hud) this.hud.updateLap(this.lap, this.maxLaps);
        return result;
      };

      var originalEnd = gameplayPrototype.end;
      gameplayPrototype.end = function(result) {
        if (result === this.results.DESTROYED || result === this.results.WRONGWAY) {
          this.result = this.results.NONE;
          this.step = 4;
          recoverShip(this.shipControls);
          if (this.hud) this.hud.display('Recovered', 0.4);
          return;
        }
        return originalEnd.apply(this, arguments);
      };
      gameplayPrototype.__ubiclawFreeRunPatched = true;
    }

    if (!hasReportedFreeRun) {
      hasReportedFreeRun = true;
      debug('free_run_mode=on');
    }
  }

  function reportGameSettings() {
    if (hasReportedGameSettings) return;
    if (!window.hexGL || !hasVisibleCanvas()) {
      window.setTimeout(reportGameSettings, 100);
      return;
    }

    hasReportedGameSettings = true;
    debug(
      'hexgl_settings=quality=' + window.hexGL.quality +
      ',displayHUD=' + window.hexGL.displayHUD +
      ',hud=' + (!!window.hexGL.hud) +
      ',godmode=' + window.hexGL.godmode
    );
  }

  function startHexGLWhenReady(startDelayMs) {
    if (startRequested || hasVisibleCanvas()) return true;
    startRequested = true;

    startDelayMs = Number(startDelayMs || 0);
    if (!isFinite(startDelayMs) || startDelayMs < 0) startDelayMs = 0;
    var deadline = performance.now() + startDelayMs + 7000;
    if (startDelayMs > 0) {
      status('Resting');
      debug('auto_start_delay_ms=' + Math.round(startDelayMs));
    }

    function clickStart() {
      var start = document.getElementById('start');
      if (!start) {
        if (performance.now() < deadline) window.setTimeout(clickStart, 50);
        return;
      }
      if (start.textContent.indexOf('not supported') >= 0) {
        status('WebGL unavailable');
        return;
      }

      status('Starting');
      focusGameSurface();
      resumeAudioContext();
      clickElement(start);
      waitForContinue();
    }

    function waitForContinue() {
      var continueStep = document.getElementById('step-2');
      if (continueStep && isDisplayed(continueStep)) {
        window.setTimeout(function() {
          status('Loading assets');
          focusGameSurface();
          resumeAudioContext();
          clickElement(continueStep);
        }, 120);
        return;
      }
      if (performance.now() < deadline) {
        window.setTimeout(waitForContinue, 50);
      } else {
        error('Auto-start timed out waiting for step-2');
      }
    }

    window.setTimeout(clickStart, startDelayMs + 150);
    return true;
  }

  function autoStartIfRequested() {
    var params = new URLSearchParams(window.location.search);
    if (params.get('ubiclawAutoStart') !== '1') return;
    startHexGLWhenReady(params.get('ubiclawAutoStartDelayMs') || 0);
  }

  function hookHexGL() {
    if (!window.bkcore || !bkcore.hexgl || !bkcore.hexgl.HexGL) {
      window.setTimeout(hookHexGL, 50);
      return;
    }

    var originalUpdate = bkcore.hexgl.HexGL.prototype.update;
    if (!originalUpdate || originalUpdate.__ubiclawHooked) return;

    bkcore.hexgl.HexGL.prototype.update = function() {
      var result = originalUpdate.apply(this, arguments);
      return result;
    };
    bkcore.hexgl.HexGL.prototype.update.__ubiclawHooked = true;
    debug('hexgl_update_hooked');
  }

  installInputAndAudioGuards();
  installAudioControlsHook();
  window.requestAnimationFrame(frameLoop);
  window.ubiclawStartHexGLWhenReady = startHexGLWhenReady;
  reportStep();
  hookHexGL();
  installFreeRunMode();
  reportGameSettings();
  status('Loaded');
  autoStartIfRequested();
})();
"""#
}
