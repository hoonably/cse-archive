import Foundation

/// Writes structured CSV event logs to an output directory.
final class CSVLogger: @unchecked Sendable {
    private var fileHandle: FileHandle?
    private var isClosed = false
    private let queue = DispatchQueue(label: "com.example.PoliteLLM.csvlogger")
    private let startTime = CFAbsoluteTimeGetCurrent()
    let filePath: String

    init(outputDir: String, scenarioName: String) {
        let fileName = "run_\(scenarioName)_\(Self.fileTimestamp()).csv"
        let path = (outputDir as NSString).appendingPathComponent(fileName)
        filePath = path

        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: nil)
        fileHandle = FileHandle(forWritingAtPath: path)

        let header = "timestamp,elapsed_s,scenario,workload,backend,event,duration_ms,token_index,params\n"
        fileHandle?.write(Data(header.utf8))
    }

    func log(
        event: String,
        scenario: String = "",
        workload: String = "",
        backend: String = "",
        durationMs: Double? = nil,
        tokenIndex: Int? = nil,
        params: String = ""
    ) {
        queue.async { [weak self] in
            guard let self, !self.isClosed, let fh = self.fileHandle else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - self.startTime
            let ts = Self.isoTimestamp()
            let dur = durationMs.map { String(format: "%.3f", $0) } ?? ""
            let tok = tokenIndex.map { String($0) } ?? ""
            let escaped = params.replacingOccurrences(of: "\"", with: "\"\"")
            let line = "\(ts),\(String(format: "%.3f", elapsed)),\(scenario),\(workload),\(backend),\(event),\(dur),\(tok),\"\(escaped)\"\n"
            fh.write(Data(line.utf8))
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

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func isoTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
