import Foundation

// MARK: - Type Enums

enum ScenarioType: String, CaseIterable, Identifiable {
    case foregroundOnly = "foreground_only"
    case overlap = "overlap"
    case llmInferenceOnly = "llm_inference_only"

    var id: String { rawValue }
    var displayName: String {
        if self == .llmInferenceOnly {
            return "LLM Inferece Only"
        }
        return rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

enum WorkloadType: String, CaseIterable, Identifiable {
    case animation
    case game3D = "game_3d"
    case hexGLRace = "hexgl_race"
    case scroll
    case filter
    case memoryCPU = "memory_cpu"
    case memoryMetal = "memory_metal"
    case video

    var id: String { rawValue }
    var displayName: String {
        if self == .hexGLRace {
            return "HexGL Race"
        }
        return rawValue.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }
}

enum HexGLQuality: Int, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2
    case veryHigh = 3

    var id: Int { rawValue }

    static let selectionOrder: [HexGLQuality] = [.veryHigh, .high, .medium, .low]

    var displayName: String {
        switch self {
        case .low:
            return "LOW"
        case .medium:
            return "MID"
        case .high:
            return "HIGH"
        case .veryHigh:
            return "VERY HIGH"
        }
    }

    var queryValue: String {
        String(rawValue)
    }

    static func parse(_ value: String) -> HexGLQuality? {
        if let intValue = Int(value),
           let quality = HexGLQuality(rawValue: intValue) {
            return quality
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        switch normalized {
        case "low":
            return .low
        case "mid", "medium":
            return .medium
        case "high":
            return .high
        case "very-high", "veryhigh":
            return .veryHigh
        default:
            return nil
        }
    }
}

enum LLMBackendType: String, CaseIterable, Identifiable {
    case external
    case inProcess = "in_process"
    var id: String { rawValue }
}

enum DecodeDelayDefaults {
    static let minimumMs = 0
    static let maximumMs = 200
    static let stepMs = 10

    static func clamp(_ value: Int) -> Int {
        min(maximumMs, max(minimumMs, value))
    }
}

enum ForegroundSLOBasis: String, CaseIterable, Identifiable {
    case baselineMean = "baseline_mean"
    case baselinePercentile = "baseline_percentile"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baselineMean:
            return "Mean"
        case .baselinePercentile:
            return "Percentile"
        }
    }

    var baselineLabel: String {
        switch self {
        case .baselineMean:
            return "Baseline Mean"
        case .baselinePercentile:
            return "Baseline Percentile"
        }
    }

    static func parse(_ value: String) -> ForegroundSLOBasis? {
        if let basis = ForegroundSLOBasis(rawValue: value) {
            return basis
        }

        switch value.lowercased() {
        case "mean":
            return .baselineMean
        case "baseline_p95", "p95", "percentile":
            return .baselinePercentile
        default:
            return nil
        }
    }
}

enum ForegroundSLODefaults {
    static let multiplier: Double = 0.9
    static let multiplierRange: ClosedRange<Double> = 0.8...1.0
    static let percentile: Double = 0.95
    static let percentileRange: ClosedRange<Double> = 0.8...0.99

    static func clampMultiplier(_ value: Double) -> Double {
        min(multiplierRange.upperBound, max(multiplierRange.lowerBound, value))
    }

    static func clampPercentile(_ value: Double) -> Double {
        min(percentileRange.upperBound, max(percentileRange.lowerBound, value))
    }
}

// MARK: - Phase Durations

struct PhaseDurations {
    var startDelay: TimeInterval = 3
    var foreground: TimeInterval = 10
    var llmInference: TimeInterval = 60
    var recovery: TimeInterval = 10

}

// MARK: - AppConfig

@Observable
final class AppConfig {
    var scenario: ScenarioType = .overlap
    var workload: WorkloadType = .animation
    var chartDisplayMode: WorkloadChartDisplayMode = .recent
    var animationParticleCount: Int = 2500
    var game3DBallCount: Int = 2500
    var hexGLQuality: HexGLQuality = .veryHigh
    var scrollRowsPerTick: Int = 5
    var scrollShowsColorSwatches: Bool = true
    var filterImageSize: Int = 2048
    var filterBlurSigma: Double = 20
    var memoryCPUWorkingSetMiB: Int = 192
    var memoryMetalWorkingSetMiB: Int = 192
    var llmBackend: LLMBackendType = .inProcess
    var politeLLMEnabled: Bool = true
    /// Ablation selector for the Polite LLM study. When set to a non-`.none`
    /// value the single-lever `PoliteLLMAblationController` runs instead of the
    /// full controller. Mutually exclusive with `politeLLMEnabled`.
    var politeLLMAblation: PoliteLLMAblationKind = .none
    var foregroundSLOBasis: ForegroundSLOBasis = .baselineMean
    var foregroundSLOMultiplier: Double = ForegroundSLODefaults.multiplier
    var foregroundSLOPercentile: Double = ForegroundSLODefaults.percentile
    var outputDir: String
    var durations = PhaseDurations()
    var externalCommand: String = "/opt/homebrew/bin/llama-cli"
    var externalModelPath: String
    var externalPrompt: String = "What is Mobile Computing?"
    var externalArgs: String = "-cnv -st"

    /// True when --scenario was provided on the command line, triggering auto-start.
    private(set) var autoStart: Bool = false

    init() {
        let dir = Self.defaultOutputDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        outputDir = dir
        externalModelPath = Self.defaultModelPath()

        let args = CommandLine.arguments
        var foundScenario = false
        var foregroundDurationProvided = false

        var i = 1
        while i < args.count - 1 {
            let key = args[i]
            let val = args[i + 1]
            switch key {
            case "--scenario":
                if let s = ScenarioType(rawValue: val) { scenario = s; foundScenario = true }
            case "--foreground":
                if let w = WorkloadType(rawValue: val) { workload = w }
            case "--chart-mode":
                if let mode = WorkloadChartDisplayMode(rawValue: val) { chartDisplayMode = mode }
            case "--animation-particles":
                if let v = Int(val) { animationParticleCount = max(1, v) }
            case "--game3d-balls":
                if let v = Int(val) { game3DBallCount = max(1, v) }
            case "--hexgl-quality":
                if let quality = HexGLQuality.parse(val) { hexGLQuality = quality }
            case "--scroll-rows-per-tick":
                if let v = Int(val) { scrollRowsPerTick = max(1, v) }
            case "--scroll-color-swatches":
                if let v = Self.parseBool(val) { scrollShowsColorSwatches = v }
            case "--filter-image-size":
                if let v = Int(val) { filterImageSize = max(1, v) }
            case "--filter-blur-sigma":
                if let v = Double(val) { filterBlurSigma = max(0, v) }
            case "--memory-cpu-set-mib":
                if let v = Int(val) { memoryCPUWorkingSetMiB = max(1, v) }
            case "--memory-metal-set-mib":
                if let v = Int(val) { memoryMetalWorkingSetMiB = max(1, v) }
            case "--llm-backend":
                if let b = LLMBackendType(rawValue: val) { llmBackend = b }
            case "--polite-llm":
                if let v = Self.parseBool(val) { politeLLMEnabled = v }
            case "--polite-llm-ablation":
                if let kind = PoliteLLMAblationKind(rawValue: val) {
                    politeLLMAblation = kind
                    if kind.isActive { politeLLMEnabled = false }
                }
            case "--foreground-slo-basis":
                if let basis = ForegroundSLOBasis.parse(val) {
                    foregroundSLOBasis = basis
                }
            case "--foreground-slo-multiplier":
                if let v = Double(val) {
                    foregroundSLOMultiplier = ForegroundSLODefaults.clampMultiplier(v)
                }
            case "--foreground-slo-percentile":
                if let v = Double(val) {
                    foregroundSLOPercentile = ForegroundSLODefaults.clampPercentile(
                        v > 1 ? v / 100 : v
                    )
                }
            case "--output-dir":
                outputDir = val
            case "--duration-start-delay":
                if let v = Double(val) { durations.startDelay = v }
            case "--duration-idle":
                if let v = Double(val) { durations.startDelay = v }
            case "--duration-llm-start-delay":
                if let v = Double(val) {
                    durations.foreground = v
                    foregroundDurationProvided = true
                }
            case "--duration-foreground":
                if let v = Double(val) {
                    durations.foreground = v
                    foregroundDurationProvided = true
                }
            case "--duration-recovery":
                if let v = Double(val) { durations.recovery = v }
            case "--duration-llm-inference":
                if let v = Double(val) { durations.llmInference = max(0, v) }

            case "--external-model":
                externalModelPath = val
            case "--external-prompt":
                externalPrompt = val
            case "--external-command":
                externalCommand = val
            case "--external-args":
                externalArgs = val
            default: break
            }
            i += 2
        }

        if scenario == .foregroundOnly && !foregroundDurationProvided {
            durations.foreground = 60
        }

        autoStart = foundScenario
    }

    private static func defaultOutputDirectory() -> String {
        repoRoot().appendingPathComponent("Logs", isDirectory: true).path
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func defaultModelPath() -> String {
        if let first = availableModelPaths().first {
            return first
        }
        return ""
    }

    static func modelsDirectory() -> URL {
        repoRoot().appendingPathComponent("Models", isDirectory: true)
    }

    static func availableModelPaths() -> [String] {
        let dir = modelsDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .map { $0.path }
            .sorted { lhs, rhs in
                (lhs as NSString).lastPathComponent.localizedCaseInsensitiveCompare(
                    (rhs as NSString).lastPathComponent
                ) == .orderedAscending
            }
    }

    static func repoRoot() -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
