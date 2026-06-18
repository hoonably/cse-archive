import SwiftUI
import UIKit

struct BenchmarkView: View {
    @EnvironmentObject private var vm: BenchmarkViewModel

    // Battery monitoring
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    private var batteryString: String {
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "N/A" }
        return String(format: "%.0f%%", level * 100)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Info text for 5-second sliding window
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .padding(.top, 2)
                    Text("All metrics below are calculated based on a 5-second sliding window to accurately reflect real-time sustained performance without initial warmup overhead.")
                }
                .font(.system(size: 13))
                .foregroundColor(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

                // System-wide info card
                VStack(alignment: .leading, spacing: 10) {
                    Text("System")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 10) {
                        sysRow(label: "Battery",    value: batteryString)
                        sysRow(label: "Delegate",   value: "CPU (TFLite)")
                        sysRow(label: "Input Size", value: "640 × 640")
                    }
                }
                .padding(16)
                .cardStyle()

                ForEach(Precision.allCases) { precision in
                    if let stat = vm.stats[precision] {
                        PrecisionStatSection(stat: stat)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color.appBg.ignoresSafeArea())
    }

    private func sysRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Per-precision card
private struct PrecisionStatSection: View {
    let stat: PrecisionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                PrecisionBadge(precision: stat.precision)
                Spacer()
                if stat.frameCount == 0 {
                    Text("No data yet")
                        .font(.system(size: 12))
                        .foregroundColor(Color.textSecondary)
                }
            }

            // Stats grid — 2×N
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                statRow(label: "Frames",              value: stat.frameCount == 0 ? "—" : "\(stat.frameCount)")
                statRow(label: "Model Size",          value: String(format: "%.1f MB", stat.modelSizeMB))
                statRow(label: "Avg Latency",         value: stat.frameCount == 0 ? "—" : String(format: "%.2f ms", stat.avgLatencyMs))
                statRow(label: "p95 Latency",         value: stat.frameCount == 0 ? "—" : String(format: "%.2f ms", stat.p95LatencyMs))
                statRow(label: "Avg FPS",             value: stat.frameCount == 0 ? "—" : String(format: "%.2f", stat.avgFPS))
                statRow(label: "Memory Usage",        value: stat.avgMemoryMB == 0 ? "—" : String(format: "%.1f MB", stat.avgMemoryMB))
                statRow(label: "Thermal State",       value: stat.frameCount == 0 ? "—" : stat.latestThermalState)
                statRow(label: "Target Detection",    value: stat.frameCount == 0 ? "—" : String(format: "%.0f%%", stat.successRate))
                statRow(label: "Mean Confidence",     value: stat.meanConfidence == 0 ? "—" : "\(Int(stat.meanConfidence * 100))%")
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func statRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    BenchmarkView()
}

