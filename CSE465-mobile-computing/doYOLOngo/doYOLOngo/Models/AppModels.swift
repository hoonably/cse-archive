import Foundation

// MARK: - Precision Model
enum Precision: String, CaseIterable, Identifiable {
    case fp32 = "FP32"
    case fp16 = "FP16"
    case int8 = "INT8"
    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .fp32: return "yolo26n_fp32"
        case .fp16: return "yolo26n_fp16"
        case .int8: return "yolo26n_int8"
        }
    }
}

// MARK: - Detection Result
struct Detection: Identifiable {
    let id = UUID()
    let classIndex: Int
    let className: String
    let confidence: Float
    /// Normalised rect (0…1) relative to the camera frame
    let boundingBox: CGRect
    var isTarget: Bool = false
}

// MARK: - Benchmark Entry (one frame)
struct BenchmarkEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let frameIndex: Int
    let precision: Precision
    let latencyMs: Double
    let fps: Double
    let targetClass: String?
    let predictions: [String]
    let confidences: [Float]
    let memoryMB: Double
    let thermalState: String
    let batteryLevel: Double
}

// MARK: - Per-precision aggregate stats
struct PrecisionStats: Identifiable {
    let id = UUID()
    let precision: Precision
    
    // Total cumulative metrics (For UI display and Export)
    var totalFrameCount: Int = 0
    var modelSizeMB: Double = 0
    
    // Storage for all frames (For Export analysis)
    var allEntries: [BenchmarkEntry] = []
    
    // Recent 5 seconds of data (Sliding Window)
    var recentEntries: [BenchmarkEntry] = []
    
    var frameCount: Int { recentEntries.count }
    
    var avgLatencyMs: Double {
        guard !recentEntries.isEmpty else { return 0 }
        return recentEntries.reduce(0) { $0 + $1.latencyMs } / Double(recentEntries.count)
    }
    
    var avgFPS: Double {
        guard !recentEntries.isEmpty else { return 0 }
        return recentEntries.reduce(0) { $0 + $1.fps } / Double(recentEntries.count)
    }
    
    var successRate: Double {
        guard !recentEntries.isEmpty else { return 0 }
        let hits = recentEntries.filter { e in
            e.targetClass != nil && e.predictions.contains(e.targetClass!)
        }.count
        return Double(hits) / Double(recentEntries.count) * 100
    }
    
    var meanConfidence: Float {
        let validEntries = recentEntries.filter { !$0.confidences.isEmpty }
        guard !validEntries.isEmpty else { return 0 }
        let totalConf = validEntries.reduce(Float(0)) { sum, e in
            let avg = e.confidences.reduce(0, +) / Float(e.confidences.count)
            return sum + avg
        }
        return totalConf / Float(validEntries.count)
    }

    var p95LatencyMs: Double {
        guard recentEntries.count >= 2 else { return avgLatencyMs }
        let sorted = recentEntries.map { $0.latencyMs }.sorted()
        let idx = Int(Double(sorted.count - 1) * 0.95)
        return sorted[idx]
    }

    var avgMemoryMB: Double {
        let valid = recentEntries.filter { $0.memoryMB > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.memoryMB } / Double(valid.count)
    }

    var latestThermalState: String {
        recentEntries.last?.thermalState ?? "—"
    }
}

// MARK: - Export Log Entry (for history display)
struct ExportLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let precision: Precision
    let frameCount: Int
    let format: ExportFormat
    var filePath: String = ""

    var displayTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: timestamp)
    }
    var summary: String { "\(precision.rawValue) · \(frameCount) frames · \(format.rawValue)" }
}

enum ExportFormat: String { case csv = "CSV"; case json = "JSON" }

// MARK: - Session Summary (shown on Export screen)
struct SessionSummary {
    var framesLogged: Int = 0
    var selectedModel: Precision = .fp32
    var savedSessions: Int = 0
    var targetSuccessRate: Double = 0
    var latestExportPath: String = "No export yet"
}
