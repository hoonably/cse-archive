import Foundation

/// A single timestamped sample of accelerometer and gyroscope.
struct SensorSample: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval // seconds since reference date
    let accelX: Double
    let accelY: Double
    let accelZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let label: String? // optional during live view; filled when recording

    init(id: UUID = UUID(), timestamp: TimeInterval, accelX: Double, accelY: Double, accelZ: Double, gyroX: Double, gyroY: Double, gyroZ: Double, label: String?) {
        self.id = id
        self.timestamp = timestamp
        self.accelX = accelX
        self.accelY = accelY
        self.accelZ = accelZ
        self.gyroX = gyroX
        self.gyroY = gyroY
        self.gyroZ = gyroZ
        self.label = label
    }
}

extension Array where Element == SensorSample {
    /// Convert collected samples to CSV text with header.
    func toCSV() -> String {
        var lines: [String] = ["timestamp,label,accelX,accelY,accelZ,gyroX,gyroY,gyroZ"]
        lines.reserveCapacity(count + 1)
        for s in self {
            let t = String(format: "%.6f", s.timestamp)
            let label = s.label ?? ""
            let ax = String(format: "%.6f", s.accelX)
            let ay = String(format: "%.6f", s.accelY)
            let az = String(format: "%.6f", s.accelZ)
            let gx = String(format: "%.6f", s.gyroX)
            let gy = String(format: "%.6f", s.gyroY)
            let gz = String(format: "%.6f", s.gyroZ)
            lines.append([t, label, ax, ay, az, gx, gy, gz].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Chart Modeling

/// A flattened data point used to drive Swift Charts.
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let index: Int      // X-axis (sample index or relative time)
    let axis: String    // "X", "Y", "Z"
    let value: Double   // Magnitude
}
