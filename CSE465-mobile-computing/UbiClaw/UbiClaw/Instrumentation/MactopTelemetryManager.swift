import Foundation
import Observation

nonisolated struct MactopTelemetrySnapshot: Equatable, Sendable {
    var isAvailable = false
    var sampleCount = 0
    var lastAttemptTime: Date?
    var lastSampleTime: Date?
    var lastError: String?
    var sourceName: String?

    var cpuUsagePercent: Double?
    var gpuUsagePercent: Double?
    var aneUsagePercent: Double?

    var cpuPowerW: Double?
    var gpuPowerW: Double?
    var anePowerW: Double?
    var dramPowerW: Double?
    var systemPowerW: Double?
    var totalPowerW: Double?

    var dramReadBandwidthGBs: Double?
    var dramWriteBandwidthGBs: Double?
    var dramCombinedBandwidthGBs: Double?

    var memoryTotalBytes: UInt64?
    var memoryUsedBytes: UInt64?
    var memoryAvailableBytes: UInt64?
    var swapTotalBytes: UInt64?
    var swapUsedBytes: UInt64?

    var diskReadBytesPerSecond: Double?
    var diskWriteBytesPerSecond: Double?
    var networkInBytesPerSecond: Double?
    var networkOutBytesPerSecond: Double?

    var gpuFrequencyMHz: Double?
    var eClusterActivePercent: Double?
    var pClusterActivePercent: Double?
    var eClusterFrequencyMHz: Double?
    var pClusterFrequencyMHz: Double?
    var socTemperatureC: Double?
    var cpuTemperatureC: Double?
    var gpuTemperatureC: Double?
    var thermalState: String?

    var ubiClawProcessCPUPercent: Double?
    var ubiClawProcessGPUmsPerSecond: Double?
    var ubiClawProcessMemoryPercent: Double?
    var ubiClawProcessRSSBytes: UInt64?
}

@MainActor
@Observable
final class MactopTelemetryManager {
    private(set) var snapshot = MactopTelemetrySnapshot()

    let endpointURL: URL

    @ObservationIgnored private var workingSnapshot = MactopTelemetrySnapshot()
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let pollInterval: TimeInterval
    @ObservationIgnored private let publishInterval: TimeInterval
    @ObservationIgnored private let failureRetryInterval: TimeInterval
    @ObservationIgnored private let mactopExecutableURL: URL
    @ObservationIgnored private let prometheusPortArgument: String
    @ObservationIgnored private var nextPublishTime = CFAbsoluteTimeGetCurrent()
    @ObservationIgnored private var prometheusProcess: Process?
    @ObservationIgnored private var prometheusOutputPipe: Pipe?
    @ObservationIgnored private var prometheusErrorPipe: Pipe?
    @ObservationIgnored private var prometheusLaunchTime: Date?
    @ObservationIgnored private var fallbackProcess: Process?
    @ObservationIgnored private var fallbackOutputPipe: Pipe?
    @ObservationIgnored private var fallbackErrorPipe: Pipe?
    @ObservationIgnored private var fallbackTextBuffer = ""

    init(
        endpointURL: URL = URL(string: "http://localhost:2112/metrics")!,
        pollInterval: TimeInterval = 0.2,
        publishInterval: TimeInterval = 0.5,
        failureRetryInterval: TimeInterval = 1.0,
        mactopExecutableURL: URL? = nil,
        prometheusPortArgument: String = ":2112"
    ) {
        self.endpointURL = endpointURL
        self.pollInterval = pollInterval
        self.publishInterval = publishInterval
        self.failureRetryInterval = failureRetryInterval
        self.mactopExecutableURL = mactopExecutableURL ?? Self.defaultMactopExecutableURL()
        self.prometheusPortArgument = prometheusPortArgument

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.25
        configuration.timeoutIntervalForResource = 0.25
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func start() {
        guard pollingTask == nil else { return }

        startPrometheusProcessIfNeeded()
        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        stopPrometheusProcess()
        stopProcessFallback()
    }

    func currentSnapshot() -> MactopTelemetrySnapshot {
        snapshot
    }

    private func pollingLoop() async {
        while !Task.isCancelled {
            let nextDelay: TimeInterval
            do {
                let fetchedSnapshot = try await fetchSnapshot()
                if fallbackProcess != nil {
                    stopProcessFallback()
                }
                publish(fetchedSnapshot, force: false)
                nextDelay = pollInterval
            } catch {
                if shouldWaitForPrometheusStartup() {
                    publishPrometheusStartupWait(error)
                    nextDelay = 0.25
                } else {
                    if prometheusProcess != nil {
                        stopPrometheusProcess()
                    }
                    startProcessFallback(after: error)
                    nextDelay = failureRetryInterval
                }
            }

            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: nextDelay))
        }
    }

    private func fetchSnapshot() async throws -> MactopTelemetrySnapshot {
        let (data, response) = try await session.data(from: endpointURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw MactopTelemetryError.httpStatus(httpResponse.statusCode)
        }

        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        let sampleCount = workingSnapshot.sampleCount
        return try await Task.detached(priority: .utility) {
            var parsedSnapshot = try Self.parseSnapshot(
                from: data,
                processIdentifier: processIdentifier
            )
            let now = Date()
            parsedSnapshot.isAvailable = true
            parsedSnapshot.sampleCount = sampleCount + 1
            parsedSnapshot.lastAttemptTime = now
            parsedSnapshot.lastSampleTime = now
            parsedSnapshot.lastError = nil
            parsedSnapshot.sourceName = "HTTP"
            return parsedSnapshot
        }.value
    }

    private func startPrometheusProcessIfNeeded() {
        guard prometheusProcess == nil else { return }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = mactopExecutableURL
        process.arguments = mactopArguments([
            "--interval", String(Int(pollInterval * 1000)),
            "--prometheus", prometheusPortArgument
        ])
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = Self.mactopProcessEnvironment()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.recordPrometheusProcessError(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.recordPrometheusProcessTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            prometheusProcess = process
            prometheusOutputPipe = outputPipe
            prometheusErrorPipe = errorPipe
            prometheusLaunchTime = Date()
        } catch {
            var snapshot = workingSnapshot
            snapshot.isAvailable = false
            snapshot.lastAttemptTime = Date()
            snapshot.lastError = "Could not launch mactop prometheus server: \(Self.errorSummary(error))"
            snapshot.sourceName = "HTTP"
            publish(snapshot, force: true)
        }
    }

    private func stopPrometheusProcess() {
        prometheusOutputPipe?.fileHandleForReading.readabilityHandler = nil
        prometheusErrorPipe?.fileHandleForReading.readabilityHandler = nil
        prometheusProcess?.terminationHandler = nil
        prometheusProcess?.terminate()
        prometheusProcess = nil
        prometheusOutputPipe = nil
        prometheusErrorPipe = nil
        prometheusLaunchTime = nil
    }

    private func shouldWaitForPrometheusStartup() -> Bool {
        guard prometheusProcess != nil, let prometheusLaunchTime else { return false }
        return Date().timeIntervalSince(prometheusLaunchTime) < 2.0
    }

    private func publishPrometheusStartupWait(_ error: Error) {
        var snapshot = workingSnapshot
        snapshot.isAvailable = false
        snapshot.lastAttemptTime = Date()
        snapshot.lastError = "Waiting for app-launched mactop prometheus server: \(Self.errorSummary(error))"
        snapshot.sourceName = "HTTP"
        publish(snapshot, force: true)
    }

    private func recordPrometheusProcessError(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var snapshot = workingSnapshot
        snapshot.lastAttemptTime = Date()
        snapshot.lastError = trimmed
        snapshot.sourceName = "HTTP"
        publish(snapshot, force: true)
    }

    private func recordPrometheusProcessTermination(status: Int32) {
        prometheusOutputPipe?.fileHandleForReading.readabilityHandler = nil
        prometheusErrorPipe?.fileHandleForReading.readabilityHandler = nil
        prometheusProcess = nil
        prometheusOutputPipe = nil
        prometheusErrorPipe = nil
        prometheusLaunchTime = nil

        var snapshot = workingSnapshot
        snapshot.lastAttemptTime = Date()
        snapshot.lastError = "app-launched mactop prometheus server exited with status \(status)"
        snapshot.sourceName = "HTTP"
        publish(snapshot, force: true)
    }

    private func startProcessFallback(after error: Error) {
        if fallbackProcess != nil {
            return
        }

        var failedSnapshot = workingSnapshot
        failedSnapshot.isAvailable = false
        failedSnapshot.lastAttemptTime = Date()
        failedSnapshot.lastError = "\(Self.errorSummary(error)); falling back to headless mactop"
        failedSnapshot.sourceName = "headless"
        publish(failedSnapshot, force: true)

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = mactopExecutableURL
        process.arguments = mactopArguments([
            "--headless",
            "--format", "json",
            "--interval", String(Int(pollInterval * 1000)),
            "--count", "0"
        ])
        process.environment = Self.mactopProcessEnvironment()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeProcessOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.recordProcessFallbackError(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.recordProcessFallbackTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            fallbackProcess = process
            fallbackOutputPipe = outputPipe
            fallbackErrorPipe = errorPipe
            fallbackTextBuffer = ""
        } catch {
            var snapshot = workingSnapshot
            snapshot.isAvailable = false
            snapshot.lastAttemptTime = Date()
            snapshot.lastError = "Could not launch headless mactop: \(Self.errorSummary(error))"
            snapshot.sourceName = "headless"
            publish(snapshot, force: true)
        }
    }

    private func stopProcessFallback() {
        fallbackOutputPipe?.fileHandleForReading.readabilityHandler = nil
        fallbackErrorPipe?.fileHandleForReading.readabilityHandler = nil
        fallbackProcess?.terminationHandler = nil
        fallbackProcess?.terminate()
        fallbackProcess = nil
        fallbackOutputPipe = nil
        fallbackErrorPipe = nil
        fallbackTextBuffer = ""
    }

    private func consumeProcessOutput(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        fallbackTextBuffer += chunk
        let objectStrings = Self.extractJSONObjectStrings(from: &fallbackTextBuffer)
        for objectString in objectStrings {
            guard let objectData = objectString.data(using: .utf8) else { continue }

            do {
                var parsedSnapshot = try Self.parseSnapshot(
                    from: objectData,
                    processIdentifier: ProcessInfo.processInfo.processIdentifier
                )
                let now = Date()
                parsedSnapshot.isAvailable = true
                parsedSnapshot.sampleCount = workingSnapshot.sampleCount + 1
                parsedSnapshot.lastAttemptTime = now
                parsedSnapshot.lastSampleTime = now
                parsedSnapshot.lastError = nil
                parsedSnapshot.sourceName = "headless"
                publish(parsedSnapshot, force: false)
            } catch {
                recordProcessFallbackError("Could not parse headless mactop sample: \(Self.errorSummary(error))")
            }
        }
    }

    private func recordProcessFallbackError(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var snapshot = workingSnapshot
        snapshot.lastAttemptTime = Date()
        snapshot.lastError = trimmed
        snapshot.sourceName = "headless"
        publish(snapshot, force: true)
    }

    private func mactopArguments(_ arguments: [String]) -> [String] {
        if mactopExecutableURL.path == "/usr/bin/env" {
            return ["mactop"] + arguments
        }
        return arguments
    }

    private func recordProcessFallbackTermination(status: Int32) {
        fallbackOutputPipe?.fileHandleForReading.readabilityHandler = nil
        fallbackErrorPipe?.fileHandleForReading.readabilityHandler = nil
        fallbackProcess = nil
        fallbackOutputPipe = nil
        fallbackErrorPipe = nil

        var snapshot = workingSnapshot
        snapshot.isAvailable = false
        snapshot.lastAttemptTime = Date()
        snapshot.lastError = "headless mactop exited with status \(status)"
        snapshot.sourceName = "headless"
        publish(snapshot, force: true)
    }

    private func publish(_ newSnapshot: MactopTelemetrySnapshot, force: Bool) {
        workingSnapshot = newSnapshot

        let now = CFAbsoluteTimeGetCurrent()
        guard force || now >= nextPublishTime else { return }

        nextPublishTime = now + publishInterval
        snapshot = newSnapshot
    }

    nonisolated private static func parseSnapshot(from data: Data, processIdentifier: Int32) throws -> MactopTelemetrySnapshot {
        let trimmedPrefix = String(decoding: data.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPrefix.first == "{" || trimmedPrefix.first == "[" {
            return try parseJSONSnapshot(from: data, processIdentifier: processIdentifier)
        }

        return parsePrometheusSnapshot(from: String(decoding: data, as: UTF8.self), processIdentifier: processIdentifier)
    }

    nonisolated private static func parseJSONSnapshot(from data: Data, processIdentifier: Int32) throws -> MactopTelemetrySnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        let root: [String: Any]
        if let dictionary = object as? [String: Any] {
            root = dictionary
        } else if let array = object as? [[String: Any]], let latest = array.last {
            root = latest
        } else {
            throw MactopTelemetryError.invalidPayload
        }

        var snapshot = MactopTelemetrySnapshot()
        let socMetrics = root["soc_metrics"] as? [String: Any] ?? [:]
        let memory = root["memory"] as? [String: Any] ?? [:]
        let netDisk = root["net_disk"] as? [String: Any] ?? [:]
        let gpuMetrics = root["gpu_metrics"] as? [String: Any] ?? [:]

        snapshot.cpuUsagePercent = double(root["cpu_usage"])
        snapshot.gpuUsagePercent = double(root["gpu_usage"]) ?? double(socMetrics["gpu_active"])
        snapshot.aneUsagePercent = double(root["ane_usage"]) ?? double(socMetrics["ane_active"])

        snapshot.cpuPowerW = double(socMetrics["cpu_power"])
        snapshot.gpuPowerW = double(socMetrics["gpu_power"])
        snapshot.anePowerW = double(socMetrics["ane_power"])
        snapshot.dramPowerW = double(socMetrics["dram_power"])
        snapshot.systemPowerW = double(socMetrics["system_power"])
        snapshot.totalPowerW = double(socMetrics["total_power"])

        snapshot.dramReadBandwidthGBs = double(socMetrics["dram_read_bw_gbs"])
        snapshot.dramWriteBandwidthGBs = double(socMetrics["dram_write_bw_gbs"])
        snapshot.dramCombinedBandwidthGBs = double(socMetrics["dram_bw_combined_gbs"])

        snapshot.memoryTotalBytes = bytes(memory["total"])
        snapshot.memoryUsedBytes = bytes(memory["used"])
        snapshot.memoryAvailableBytes = bytes(memory["available"])
        snapshot.swapTotalBytes = bytes(memory["swap_total"])
        snapshot.swapUsedBytes = bytes(memory["swap_used"])

        snapshot.networkOutBytesPerSecond = double(netDisk["out_bytes_per_sec"])
        snapshot.networkInBytesPerSecond = double(netDisk["in_bytes_per_sec"])
        snapshot.diskReadBytesPerSecond = double(netDisk["read_kbytes_per_sec"]).map { $0 * 1024 }
        snapshot.diskWriteBytesPerSecond = double(netDisk["write_kbytes_per_sec"]).map { $0 * 1024 }

        snapshot.gpuFrequencyMHz = double(gpuMetrics["freq_mhz"]) ?? double(socMetrics["gpu_freq_mhz"])
        snapshot.eClusterActivePercent = double(socMetrics["e_cluster_active"])
        snapshot.pClusterActivePercent = double(socMetrics["p_cluster_active"])
        snapshot.eClusterFrequencyMHz = double(socMetrics["e_cluster_freq_mhz"])
        snapshot.pClusterFrequencyMHz = double(socMetrics["p_cluster_freq_mhz"])
        snapshot.socTemperatureC = double(socMetrics["soc_temp"])
        snapshot.cpuTemperatureC = double(socMetrics["cpu_temp"])
        snapshot.gpuTemperatureC = double(socMetrics["gpu_temp"])
        snapshot.thermalState = root["thermal_state"] as? String

        if let process = matchingProcess(in: root["processes"], processIdentifier: processIdentifier) {
            snapshot.ubiClawProcessCPUPercent = double(process["cpu_percent"])
            snapshot.ubiClawProcessGPUmsPerSecond = double(process["gpu_ms_per_sec"])
            snapshot.ubiClawProcessMemoryPercent = double(process["memory_percent"])
            snapshot.ubiClawProcessRSSBytes = double(process["rss_kb"]).map { bytes in
                UInt64(max(0, bytes * 1024))
            }
        }

        return snapshot
    }

    nonisolated private static func parsePrometheusSnapshot(from text: String, processIdentifier: Int32) -> MactopTelemetrySnapshot {
        let samples = parsePrometheusSamples(from: text)
        var snapshot = MactopTelemetrySnapshot()

        snapshot.cpuUsagePercent = metricValue(
            samples,
            exact: ["cpu_usage", "cpu_usage_percent", "mactop_cpu_usage", "mactop_cpu_usage_percent"],
            includeSets: [["cpu", "usage"], ["cpu", "active"]],
            excludes: ["process", "power", "freq", "temperature", "temp", "thermal"]
        )
        snapshot.gpuUsagePercent = metricValue(
            samples,
            exact: ["gpu_usage", "gpu_usage_percent", "mactop_gpu_usage", "mactop_gpu_usage_percent"],
            includeSets: [["gpu", "usage"], ["gpu", "active"]],
            excludes: ["process", "power", "freq", "temperature", "temp", "thermal", "sram"]
        )
        snapshot.aneUsagePercent = metricValue(
            samples,
            exact: ["ane_usage", "ane_usage_percent", "mactop_ane_usage", "mactop_ane_usage_percent"],
            includeSets: [["ane", "usage"], ["ane", "active"]],
            excludes: ["process", "power", "freq", "temperature", "temp", "thermal"]
        )

        snapshot.cpuPowerW = metricValue(samples, includeSets: [["cpu", "power"]], excludes: ["gpu", "ane", "dram", "sram"])
        snapshot.gpuPowerW = metricValue(samples, includeSets: [["gpu", "power"]], excludes: ["cpu", "ane", "dram", "sram"])
        snapshot.anePowerW = metricValue(samples, includeSets: [["ane", "power"]], excludes: ["cpu", "gpu", "dram", "sram"])
        snapshot.dramPowerW = metricValue(samples, includeSets: [["dram", "power"]], excludes: ["cpu", "gpu", "ane"])
        snapshot.systemPowerW = metricValue(samples, includeSets: [["system", "power"]])
        snapshot.totalPowerW = metricValue(samples, includeSets: [["total", "power"]])

        snapshot.dramReadBandwidthGBs = metricValue(
            samples,
            exact: ["dram_read_bw_gbs", "mactop_dram_read_bw_gbs"],
            includeSets: [["dram", "read", "bw"], ["dram", "read", "bandwidth"]]
        )
        snapshot.dramWriteBandwidthGBs = metricValue(
            samples,
            exact: ["dram_write_bw_gbs", "mactop_dram_write_bw_gbs"],
            includeSets: [["dram", "write", "bw"], ["dram", "write", "bandwidth"]]
        )
        snapshot.dramCombinedBandwidthGBs = metricValue(
            samples,
            exact: ["dram_bw_combined_gbs", "mactop_dram_bw_combined_gbs"],
            includeSets: [["dram", "combined", "bw"], ["dram", "combined", "bandwidth"], ["dram", "total", "bw"]]
        )

        snapshot.memoryTotalBytes = bytes(metricValue(samples, includeSets: [["memory", "total"]], excludes: ["swap", "percent"]))
        snapshot.memoryUsedBytes = bytes(metricValue(samples, includeSets: [["memory", "used"]], excludes: ["swap", "percent"]))
        snapshot.memoryAvailableBytes = bytes(metricValue(samples, includeSets: [["memory", "available"]], excludes: ["swap", "percent"]))
        snapshot.swapTotalBytes = bytes(metricValue(samples, includeSets: [["swap", "total"]], excludes: ["percent"]))
        snapshot.swapUsedBytes = bytes(metricValue(samples, includeSets: [["swap", "used"]], excludes: ["percent"]))

        snapshot.networkInBytesPerSecond = metricValue(samples, includeSets: [["in", "bytes", "sec"], ["network", "in", "bytes"]])
        snapshot.networkOutBytesPerSecond = metricValue(samples, includeSets: [["out", "bytes", "sec"], ["network", "out", "bytes"]])
        snapshot.diskReadBytesPerSecond = bytesPerSecondValue(samples, kbytesTerms: ["read", "kbytes", "sec"], bytesTerms: ["read", "bytes", "sec"])
        snapshot.diskWriteBytesPerSecond = bytesPerSecondValue(samples, kbytesTerms: ["write", "kbytes", "sec"], bytesTerms: ["write", "bytes", "sec"])

        snapshot.gpuFrequencyMHz = metricValue(samples, includeSets: [["gpu", "freq"], ["gpu", "mhz"]], excludes: ["active", "usage"])
        snapshot.eClusterActivePercent = metricValue(samples, includeSets: [["e", "cluster", "active"]])
        snapshot.pClusterActivePercent = metricValue(samples, includeSets: [["p", "cluster", "active"]])
        snapshot.eClusterFrequencyMHz = metricValue(samples, includeSets: [["e", "cluster", "freq"]])
        snapshot.pClusterFrequencyMHz = metricValue(samples, includeSets: [["p", "cluster", "freq"]])
        snapshot.socTemperatureC = metricValue(samples, includeSets: [["soc", "temp"]])
        snapshot.cpuTemperatureC = metricValue(samples, includeSets: [["cpu", "temp"]], excludes: ["soc"])
        snapshot.gpuTemperatureC = metricValue(samples, includeSets: [["gpu", "temp"]])

        if let thermalSample = samples.first(where: { $0.normalizedName.contains("thermal_state") || $0.normalizedName.contains("thermal") }) {
            snapshot.thermalState = String(format: "%.0f", thermalSample.value)
        }

        snapshot.ubiClawProcessCPUPercent = processMetricValue(
            samples,
            processIdentifier: processIdentifier,
            includeSets: [["cpu", "percent"], ["cpu", "usage"]]
        )
        snapshot.ubiClawProcessGPUmsPerSecond = processMetricValue(
            samples,
            processIdentifier: processIdentifier,
            includeSets: [["gpu", "ms"], ["gpu", "time"]]
        )
        snapshot.ubiClawProcessMemoryPercent = processMetricValue(
            samples,
            processIdentifier: processIdentifier,
            includeSets: [["memory", "percent"]]
        )
        snapshot.ubiClawProcessRSSBytes = processMetricValue(
            samples,
            processIdentifier: processIdentifier,
            includeSets: [["rss"], ["resident"]]
        ).map { value in
            value < 1_000_000 ? UInt64(max(0, value * 1024)) : UInt64(max(0, value))
        }

        return snapshot
    }

    nonisolated private static func parsePrometheusSamples(from text: String) -> [PrometheusSample] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, let lastPart = parts.last, let value = Double(String(lastPart)) else { return nil }
            guard value.isFinite else { return nil }

            let head = String(parts[0])
            let parsedHead = parsePrometheusMetricHead(head)
            return PrometheusSample(
                name: parsedHead.name,
                normalizedName: normalize(parsedHead.name),
                labels: parsedHead.labels,
                value: value
            )
        }
    }

    nonisolated private static func extractJSONObjectStrings(from buffer: inout String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var objectStart: String.Index?
        var removeThrough: String.Index?

        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                index = buffer.index(after: index)
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 {
                    objectStart = index
                }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let start = objectStart {
                    objects.append(String(buffer[start...index]))
                    removeThrough = index
                    objectStart = nil
                }
            }

            index = buffer.index(after: index)
        }

        if let removeThrough {
            buffer.removeSubrange(buffer.startIndex...removeThrough)
        } else if buffer.count > 1_000_000 {
            buffer = String(buffer.suffix(65_536))
        }

        return objects
    }

    nonisolated private static func parsePrometheusMetricHead(_ head: String) -> (name: String, labels: [String: String]) {
        guard let labelsStart = head.firstIndex(of: "{"),
              head.hasSuffix("}") else {
            return (head, [:])
        }

        let name = String(head[..<labelsStart])
        let labelsText = String(head[head.index(after: labelsStart)..<head.index(before: head.endIndex)])
        var labels: [String: String] = [:]

        for label in labelsText.split(separator: ",") {
            let pair = label.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }

            let key = String(pair[0])
            var value = String(pair[1])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            labels[key] = value
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }

        return (name, labels)
    }

    nonisolated private static func metricValue(
        _ samples: [PrometheusSample],
        exact: [String] = [],
        includeSets: [[String]],
        excludes: [String] = [],
        filter: ((PrometheusSample) -> Bool)? = nil
    ) -> Double? {
        let exactNames = Set(exact.map(normalize))
        let normalizedExcludes = excludes.map(normalize)

        if let exactMatch = samples.first(where: { sample in
            exactNames.contains(sample.normalizedName)
                && !normalizedExcludes.contains { sample.normalizedName.contains($0) }
                && (filter?(sample) ?? true)
        }) {
            return exactMatch.value
        }

        for includeSet in includeSets {
            let normalizedIncludes = includeSet.map(normalize)
            if let match = samples.first(where: { sample in
                normalizedIncludes.allSatisfy { sample.normalizedName.contains($0) }
                    && !normalizedExcludes.contains { sample.normalizedName.contains($0) }
                    && (filter?(sample) ?? true)
            }) {
                return match.value
            }
        }

        return nil
    }

    nonisolated private static func processMetricValue(
        _ samples: [PrometheusSample],
        processIdentifier: Int32,
        includeSets: [[String]]
    ) -> Double? {
        metricValue(samples, includeSets: includeSets, excludes: [], filter: { sample in
            isUbiClawProcess(sample, processIdentifier: processIdentifier)
        })
    }

    nonisolated private static func bytesPerSecondValue(
        _ samples: [PrometheusSample],
        kbytesTerms: [String],
        bytesTerms: [String]
    ) -> Double? {
        if let value = metricValue(samples, includeSets: [kbytesTerms]) {
            return value * 1024
        }
        return metricValue(samples, includeSets: [bytesTerms])
    }

    nonisolated private static func isUbiClawProcess(_ sample: PrometheusSample, processIdentifier: Int32) -> Bool {
        let currentPID = String(processIdentifier)
        if sample.labels["pid"] == currentPID {
            return true
        }

        let processLabelKeys = ["process", "command", "comm", "name", "app", "executable"]
        return processLabelKeys.contains { key in
            sample.labels[key]?.localizedCaseInsensitiveContains("UbiClaw") == true
        }
    }

    nonisolated private static func matchingProcess(in object: Any?, processIdentifier: Int32) -> [String: Any]? {
        guard let processes = object as? [[String: Any]] else { return nil }
        let currentPID = Int(processIdentifier)

        return processes.first { process in
            if let pid = double(process["pid"]), Int(pid) == currentPID {
                return true
            }

            if let command = process["command"] as? String {
                return command.localizedCaseInsensitiveContains("UbiClaw")
            }

            return false
        }
    }

    nonisolated private static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value.isFinite ? value : nil
        case let value as Float:
            let converted = Double(value)
            return converted.isFinite ? converted : nil
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        case let value as NSNumber:
            let converted = value.doubleValue
            return converted.isFinite ? converted : nil
        case let value as String:
            guard let converted = Double(value), converted.isFinite else { return nil }
            return converted
        default:
            return nil
        }
    }

    nonisolated private static func bytes(_ value: Any?) -> UInt64? {
        double(value).map { UInt64(max(0, $0)) }
    }

    nonisolated private static func bytes(_ value: Double?) -> UInt64? {
        value.map { UInt64(max(0, $0)) }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        var normalized = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
            } else {
                normalized.append("_")
            }
        }
        return normalized.lowercased()
    }

    nonisolated private static func defaultMactopExecutableURL() -> URL {
        let fileManager = FileManager.default
        for path in ["/opt/homebrew/bin/mactop", "/usr/local/bin/mactop"] where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/env")
    }

    nonisolated private static func mactopProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let homebrewPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(homebrewPaths):\(path)"
        } else {
            environment["PATH"] = "\(homebrewPaths):/usr/bin:/bin:/usr/sbin:/sbin"
        }
        return environment
    }

    nonisolated private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }

    nonisolated private static func errorSummary(_ error: Error) -> String {
        if let mactopError = error as? MactopTelemetryError {
            return mactopError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost {
            return "mactop metrics endpoint is not reachable"
        }

        return nsError.localizedDescription
    }
}

private enum MactopTelemetryError: LocalizedError {
    case httpStatus(Int)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case let .httpStatus(status):
            return "mactop metrics endpoint returned HTTP \(status)"
        case .invalidPayload:
            return "mactop metrics payload could not be parsed"
        }
    }
}

nonisolated private struct PrometheusSample {
    let name: String
    let normalizedName: String
    let labels: [String: String]
    let value: Double
}
