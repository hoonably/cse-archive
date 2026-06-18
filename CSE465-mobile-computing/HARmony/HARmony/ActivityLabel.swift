import Foundation

/// Supported activity labels for data collection and rule-based detection.
enum ActivityLabel: String, CaseIterable, Identifiable, Codable {
    case still = "Still"
    case walk = "Walk"
    case running = "Running"
    case stairsUp = "Stairs Up"
    case stairsDown = "Stairs Down"
    case moonwalk = "Moonwalk"

    var id: String { rawValue }

    /// Short display title suitable for buttons and CSV.
    var title: String { rawValue }
}
