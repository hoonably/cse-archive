import Foundation

final class MactopTelemetryCSVLogger: @unchecked Sendable {
    private var fileHandle: FileHandle?
    private var isClosed = false
    private let queue = DispatchQueue(label: "unist.jam.UbiClaw.mactop-csv")
    let filePath: String

    init(outputDir: String, scenarioName: String) {
        let fileName = "mactop_\(scenarioName)_\(Self.fileTimestamp()).csv"
        let path = (outputDir as NSString).appendingPathComponent(fileName)
        filePath = path

        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: path)
        fileHandle?.write(Data((Self.header + "\n").utf8))
    }

    func log(
        snapshot: MactopTelemetrySnapshot,
        elapsedTime: TimeInterval,
        scenario: ScenarioType,
        workload: WorkloadType,
        backend: LLMBackendType,
        phase: ScenarioPhase,
        llmTokensPerSecond: Double
    ) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, let fileHandle = self.fileHandle else { return }

            let values = [
                Self.isoTimestamp(),
                Self.format(elapsedTime),
                scenario.rawValue,
                workload.rawValue,
                backend.rawValue,
                phase.rawValue,
                Self.format(llmTokensPerSecond),
                snapshot.sourceName ?? "",
                snapshot.isAvailable ? "1" : "0",
                Self.format(snapshot.cpuUsagePercent),
                Self.format(snapshot.gpuUsagePercent),
                Self.format(snapshot.ubiClawProcessCPUPercent),
                Self.format(snapshot.ubiClawProcessGPUmsPerSecond),
                Self.format(snapshot.dramReadBandwidthGBs),
                Self.format(snapshot.dramWriteBandwidthGBs),
                Self.format(snapshot.dramCombinedBandwidthGBs),
                Self.format(snapshot.memoryUsedBytes),
                Self.format(snapshot.memoryAvailableBytes),
                Self.format(snapshot.swapUsedBytes),
                Self.format(snapshot.ubiClawProcessRSSBytes),
                Self.format(snapshot.totalPowerW),
                Self.format(snapshot.gpuPowerW),
                Self.format(snapshot.dramPowerW),
                snapshot.thermalState ?? "",
                Self.format(snapshot.socTemperatureC),
                snapshot.lastError ?? ""
            ]

            fileHandle.write(Data(Self.csvLine(values).utf8))
        }
    }

    func close() {
        queue.sync {
            guard !isClosed else { return }
            isClosed = true
            fileHandle?.closeFile()
            fileHandle = nil
        }
    }

    private nonisolated static let header = """
timestamp,elapsed_s,scenario,workload,backend,phase,llm_tokens_per_s,mactop_source,mactop_available,cpu_usage_percent,gpu_usage_percent,ubiclaw_process_cpu_percent,ubiclaw_process_gpu_ms_per_s,dram_read_bw_gbs,dram_write_bw_gbs,dram_combined_bw_gbs,memory_used_bytes,memory_available_bytes,swap_used_bytes,ubiclaw_process_rss_bytes,total_power_w,gpu_power_w,dram_power_w,thermal_state,soc_temperature_c,last_error
"""

    private nonisolated static func csvLine(_ values: [String]) -> String {
        values.map(escape).joined(separator: ",") + "\n"
    }

    private nonisolated static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private nonisolated static func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.6f", value)
    }

    private nonisolated static func format(_ value: UInt64?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private nonisolated static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }

    private nonisolated static func isoTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
