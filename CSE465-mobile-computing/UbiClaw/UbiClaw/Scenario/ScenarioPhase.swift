import Foundation

enum ScenarioPhase: String {
    case notStarted = "Not Started"
    case loadingModel = "Loading Model"
    case startDelay = "Start Delay"
    case idle = "Idle"
    case foreground = "Foreground Only"
    case overlap = "Foreground + LLM"
    case llmInferenceOnly = "LLM Inference Only"
    case recovery = "Recovery"
    case completed = "Completed"

    var isActive: Bool {
        switch self {
        case .notStarted, .completed: return false
        default: return true
        }
    }
}
