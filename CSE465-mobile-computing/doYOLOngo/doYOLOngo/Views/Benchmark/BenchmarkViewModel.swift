import SwiftUI
import Combine

final class BenchmarkViewModel: ObservableObject {
    @Published var stats: [Precision: PrecisionStats] = {
        var d: [Precision: PrecisionStats] = [:]
        for p in Precision.allCases { d[p] = PrecisionStats(precision: p) }
        return d
    }()

    init() {
        var fp32 = PrecisionStats(precision: .fp32)
        fp32.totalFrameCount = 0; fp32.modelSizeMB = 10.3
        var fp16 = PrecisionStats(precision: .fp16)
        fp16.totalFrameCount = 0; fp16.modelSizeMB = 5.4
        var int8 = PrecisionStats(precision: .int8)
        int8.totalFrameCount = 0; int8.modelSizeMB = 3.3
        stats = [.fp32: fp32, .fp16: fp16, .int8: int8]
    }

    // Called from inference pipeline
    func record(entry: BenchmarkEntry) {
        var s = stats[entry.precision] ?? PrecisionStats(precision: entry.precision)
        
        s.totalFrameCount += 1
        s.allEntries.append(entry)
        s.recentEntries.append(entry)
        
        // 5s Sliding Window: Remove data older than 5 seconds from now
        let cutoff = Date().addingTimeInterval(-5.0)
        s.recentEntries.removeAll { $0.timestamp < cutoff }
        
        stats[entry.precision] = s
    }
}
