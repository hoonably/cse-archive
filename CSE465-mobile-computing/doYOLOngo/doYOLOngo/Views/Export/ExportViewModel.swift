import SwiftUI
import Combine

final class ExportViewModel: ObservableObject {
    @Published var session = SessionSummary()
    @Published var exportHistory: [ExportLog] = []
    @Published var exportMessage: String? = nil

    // Called by inference pipeline to update session stats
    func updateSession(frames: Int, model: Precision, successRate: Double) {
        session.framesLogged = frames
        session.selectedModel = model
        session.targetSuccessRate = successRate
    }

    func exportCSV(stats: [Precision: PrecisionStats]) -> URL? {
        var csvString = "FrameIndex,Timestamp,Precision,LatencyMs,FPS,TargetClass,Predictions,Confidences,MemoryMB,ThermalState,BatteryLevel\n"
        let ts = timestamp()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        
        var allEntries: [BenchmarkEntry] = []
        for p in Precision.allCases {
            if let s = stats[p] { allEntries.append(contentsOf: s.allEntries) }
        }
        allEntries.sort { $0.timestamp < $1.timestamp }
        
        for e in allEntries {
            let timeStr = formatter.string(from: e.timestamp)
            let target = e.targetClass ?? "None"
            let preds = e.predictions.joined(separator: "|")
            let confs = e.confidences.map { String(format: "%.2f", $0) }.joined(separator: "|")
            
            csvString += "\(e.frameIndex),\(timeStr),\(e.precision.rawValue),\(String(format: "%.1f", e.latencyMs)),\(String(format: "%.1f", e.fps)),\(target),\(preds),\(confs),\(String(format: "%.1f", e.memoryMB)),\(e.thermalState),\(String(format: "%.2f", e.batteryLevel))\n"
        }
        
        let fileName = "doYOLOngo_\(ts).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
            let log = ExportLog(timestamp: Date(), precision: .fp32, frameCount: allEntries.count, format: .csv, filePath: fileName)
            exportHistory.insert(log, at: 0)
            session.savedSessions += 1
            session.latestExportPath = fileName
            exportMessage = "CSV ready to share ✓"
            return tempURL
        } catch {
            exportMessage = "Failed to create CSV."
            return nil
        }
    }

    func exportJSON(stats: [Precision: PrecisionStats]) -> URL? {
        var allEntries: [BenchmarkEntry] = []
        for p in Precision.allCases {
            if let s = stats[p] { allEntries.append(contentsOf: s.allEntries) }
        }
        allEntries.sort { $0.timestamp < $1.timestamp }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        var jsonArray: [[String: Any]] = []
        for e in allEntries {
            let dict: [String: Any] = [
                "FrameIndex": e.frameIndex,
                "Timestamp": formatter.string(from: e.timestamp),
                "Precision": e.precision.rawValue,
                "LatencyMs": e.latencyMs,
                "FPS": e.fps,
                "TargetClass": e.targetClass ?? "None",
                "Predictions": e.predictions,
                "Confidences": e.confidences,
                "MemoryMB": e.memoryMB,
                "ThermalState": e.thermalState,
                "BatteryLevel": e.batteryLevel
            ]
            jsonArray.append(dict)
        }
        
        let fileName = "doYOLOngo_\(timestamp()).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
            try data.write(to: tempURL)
            let log = ExportLog(timestamp: Date(), precision: .fp32, frameCount: allEntries.count, format: .json, filePath: fileName)
            exportHistory.insert(log, at: 0)
            session.savedSessions += 1
            session.latestExportPath = fileName
            exportMessage = "JSON ready to share ✓"
            return tempURL
        } catch {
            exportMessage = "Failed to create JSON."
            return nil
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
