import SwiftUI
import Combine
import AVFoundation

final class LiveViewModel: ObservableObject {
    // MARK: - Published state
    @Published var detections: [Detection] = []
    @Published var selectedPrecision: Precision = .fp32
    @Published var isRunning: Bool = false
    @Published var selectedTarget: String? = nil
    @Published var systemMessage: String? = nil
    @Published var easterEggMessage: String? = nil
    @Published var isListeningVoice: Bool = false
    @Published var listeningText: String = ""
    @Published var cameraPermissionDenied: Bool = false

    // Stats
    @Published var currentLatencyMs: Double = 0
    @Published var currentFPS: Double = 0

    let camera = CameraService()
    private let yolo  = YOLOInferenceService(precision: .fp32)
    private let voiceService = VoiceService()
    private var cancellables = Set<AnyCancellable>()
    
    // Benchmark & Export
    weak var benchmarkVM: BenchmarkViewModel?

    // FPS tracking
    private var frameCount: Int = 0
    private var fpsWindowStart: Date = Date()

    // MARK: - Computed helpers
    var latencyString: String { isRunning && currentLatencyMs > 0 ? String(format: "%.1f", currentLatencyMs) : "--" }
    var fpsString: String     { isRunning && currentFPS > 0      ? String(format: "%.1f", currentFPS) : "--" }
    var voiceLabel: String    { selectedTarget.map { $0.capitalized } ?? "Not set" }
    var modelSizeMB: Double   { yolo.modelSizeMB }

    // MARK: - Init
    init() {
        camera.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)

        camera.$permissionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .denied || status == .restricted {
                    self?.cameraPermissionDenied = true
                    self?.systemMessage = "Camera access denied. Enable in Settings."
                }
            }
            .store(in: &cancellables)

        // Route camera frames → YOLO inference (background queue)
        let inferenceQueue = DispatchQueue(label: "yolo.inferenceQueue", qos: .userInitiated)
        camera.framePublisher
            .receive(on: inferenceQueue)
            .sink { [weak self] sampleBuffer in
                self?.processFrame(sampleBuffer)
            }
            .store(in: &cancellables)

        camera.requestPermissionAndConfigure()
    }

    // MARK: - Frame Processing
    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }

        let target = selectedTarget
        let (dets, latency) = yolo.run(sampleBuffer: sampleBuffer, targetClass: target)

        // FPS calculation
        frameCount += 1
        let elapsed = Date().timeIntervalSince(fpsWindowStart)
        let fps: Double
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            fpsWindowStart = Date()
        } else {
            fps = currentFPS   // keep previous until window closes
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.detections = dets
            self.currentLatencyMs = latency
            if fps != self.currentFPS { self.currentFPS = fps }

            // Record to Benchmark Dashboard
            let memMB: Double = {
                    var info = mach_task_basic_info()
                    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
                    let kerr = withUnsafeMutablePointer(to: &info) {
                        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                        }
                    }
                    return kerr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
                }()
                let thermalStr: String = {
                    switch ProcessInfo.processInfo.thermalState {
                    case .nominal:  return "Nominal"
                    case .fair:     return "Fair"
                    case .serious:  return "Serious"
                    case .critical: return "Critical"
                    @unknown default: return "Unknown"
                    }
                }()
                let entry = BenchmarkEntry(
                timestamp: Date(),
                frameIndex: self.frameCount,
                precision: self.selectedPrecision,
                latencyMs: latency,
                fps: fps,
                targetClass: self.selectedTarget,
                predictions: dets.map { $0.className },
                confidences: dets.map { $0.confidence },
                memoryMB: memMB,
                thermalState: thermalStr,
                batteryLevel: Double(UIDevice.current.batteryLevel)
            )
            self.benchmarkVM?.record(entry: entry)

            // Feedback: Target Update
            // Removed unnecessary found/not found spam message updates
        }
    }

    // MARK: - Actions
    func toggleInference() {
        if isRunning {
            camera.stop()
            DispatchQueue.main.async { [weak self] in
                self?.detections = []
                self?.currentLatencyMs = 0
                self?.currentFPS = 0
            }
        } else {
            camera.start()
            frameCount = 0
            fpsWindowStart = Date()
        }
    }

    func triggerVoiceInput() {
        if isListeningVoice {
            voiceService.stopListening()
            isListeningVoice = false
            return
        }
        
        voiceService.requestPermissions { [weak self] granted in
            guard let self = self else { return }
            if granted {
                self.isListeningVoice = true
                self.listeningText = "Listening... (e.g. 'find chair', 'count cups')"
                
                self.voiceService.startListening(
                    onText: { rawText in
                        let correctedText = self.correctPronunciation(rawText)
                        self.processLiveVoiceText(correctedText)
                    },
                    onError: {
                        DispatchQueue.main.async {
                            self.isListeningVoice = false
                        }
                    }
                )
            } else {
                self.systemMessage = "Speech/Mic permission denied."
            }
        }
    }
    
    // Preemptively correct words that Apple's speech recognition often confuses due to Korean pronunciation (for UI display)
    private func correctPronunciation(_ text: String) -> String {
        var t = text.lowercased()
        
        let corrections: [String: String] = [
            "cop": "cup",
            "cub": "cup",
            "cap": "cup",
            "botel": "bottle",
            "bodle": "bottle",
            "cheer": "chair",
            "key board": "keyboard",
            "ki board": "keyboard",
            "form": "phone"
        ]
        
        for (wrong, correct) in corrections {
            // Replace only when it matches word boundaries (\b) to prevent accidental changes
            t = t.replacingOccurrences(of: "\\b\(wrong)\\b", with: correct, options: .regularExpression)
        }
        
        return t
    }

    func clearTarget() {
        selectedTarget = nil
        systemMessage = "Target cleared."
        detections = detections.map { det in
            var d = det; d.isTarget = false; return d
        }
    }

    func switchPrecision(_ p: Precision) {
        selectedPrecision = p
        yolo.switchPrecision(p)
    }

    // Process real-time speech recognition results to extract target class and system control
    private func processLiveVoiceText(_ text: String) {
        let cleanText = text.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 0. Meme exception handling (Triggered immediately when exactly matched)
        if cleanText.contains("phone is hot") || cleanText.contains("phone is burning") {
            DispatchQueue.main.async { self.listeningText = "Command: my phone is hot" }
            switchPrecision(.int8)
            systemMessage = "⚡️ Overdrive Engaged: Speed Mode (INT8)"
            voiceService.stopListening()
            isListeningVoice = false
            return
        }
        
        // 0.5. Flashbang Easter Egg
        let flashbangTriggers = ["flashbang", "flash bang", "flesh bang", "fresh bang", "flush bang", "plus bank", "smash bang"]
        if flashbangTriggers.contains(where: { cleanText.contains($0) }) {
            DispatchQueue.main.async { self.listeningText = "Command: flashbang" }
            camera.setFlashlight(on: true)
            easterEggMessage = "💥 Flashbang Out!"
            voiceService.stopListening()
            isListeningVoice = false
            return
        }
        
        let standDownTriggers = ["stand down", "clear", "turn off", "light off", "shut down"]
        if standDownTriggers.contains(where: { cleanText.contains($0) }) {
            DispatchQueue.main.async { self.listeningText = "Command: stand down" }
            camera.setFlashlight(on: false)
            easterEggMessage = "🌑 Tactical Flashlight Disabled"
            voiceService.stopListening()
            isListeningVoice = false
            return
        }
        
        // 1. Remove unnecessary words that interfere with parsing (to leave only keywords)
        let stopWords: Set<String> = ["a", "an", "the", "my", "some", "please", "are", "there", "for", "me", "is", "many", "to", "at"]
        
        // Split into words after removing punctuation
        let noPunctuation = cleanText.components(separatedBy: CharacterSet.punctuationCharacters).joined(separator: "")
        let words = noPunctuation.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        
        guard !words.isEmpty else { return }
        
        // 2. Process Trigger word (First word)
        // Incorporate variations of "Find" (e.g., "I'm", "fine", "time") as triggers due to Korean pronunciation characteristics!
        let systemTriggers: Set<String> = ["activate", "enable", "disable", "unleash"]
        let objectTriggers: Set<String> = ["count", "how", "where", "search", "look", "show", "find", "target", "detect", "im", "time", "fine", "pine", "sign", "cant", "account"]
        let allTriggers = Array(systemTriggers.union(objectTriggers))
        
        let firstWord = words[0]
        let triggerMaxDist = max(3, firstWord.count) // Significantly relax tolerance to essentially always find the closest trigger
        
        guard let matchedTrigger = findClosestMatch(for: firstWord, candidates: allTriggers, maxDistance: triggerMaxDist) else {
            // Completely ignore if no trigger word exists (No Raw Text exposed)
            DispatchQueue.main.async { self.listeningText = "Listening..." }
            return
        }
        
        // 3. Process Target word (Remaining words)
        let displayTrigger = ["im", "fine", "pine", "sign", "time", "cant", "account"].contains(matchedTrigger) ? "find" : matchedTrigger
        
        if words.count > 1 {
            let remainder = words[1...].joined(separator: " ")
            let remainderSingular = remainder.hasSuffix("s") ? String(remainder.dropLast()) : remainder
            
            // A. If it's a System Control command
            if systemTriggers.contains(matchedTrigger) {
                let speedTargets = ["overdrive", "speed mode"]
                let powerTargets = ["detail mode", "limiters", "maximum power", "full power"]
                let sysCandidates = speedTargets + powerTargets
                
                let targetMaxDist = max(4, remainder.count) // Significantly relax tolerance
                
                if let matchedTarget = findClosestMatch(for: remainder, candidates: sysCandidates, maxDistance: targetMaxDist) {
                    DispatchQueue.main.async { self.listeningText = "Command: \(displayTrigger) \(matchedTarget)" }
                    
                    if speedTargets.contains(matchedTarget) {
                        switchPrecision(.int8)
                        systemMessage = "⚡️ Overdrive Engaged: Speed Mode (INT8)"
                    } else {
                        switchPrecision(.fp32)
                        systemMessage = "🔥 Limiters Disabled: Maximum Power (FP32)"
                    }
                    voiceService.stopListening()
                    isListeningVoice = false
                    return
                } else {
                    DispatchQueue.main.async { self.listeningText = "Command: \(displayTrigger) ... (Unknown System Target)" }
                }
            } 
            // B. If it's an Object Detection (Find/Count) command
            else {
                // Fuzzy matching within YOLO classes
                if let matchedTarget = resolveVoiceAliasFuzzy(remainder) ?? resolveVoiceAliasFuzzy(remainderSingular) {
                    DispatchQueue.main.async { self.listeningText = "Command: \(displayTrigger) \(matchedTarget)" }
                    
                    selectedTarget = matchedTarget
                    systemMessage = nil
                    
                    voiceService.stopListening()
                    isListeningVoice = false
                    return
                } else {
                    DispatchQueue.main.async { self.listeningText = "Command: \(displayTrigger) ... (Unknown Target)" }
                }
            }
        } else {
            // Trigger spoken, but object (Target) not yet mentioned
            DispatchQueue.main.async { self.listeningText = "Command: \(displayTrigger) ..." }
        }
    }
}
