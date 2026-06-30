import os

/// Centralized signpost emission for Instruments visibility.
/// Subsystem: com.example.PoliteLLM  Category: pointsOfInterest
enum Signposts {
    static let signposter = OSSignposter(
        subsystem: "com.example.PoliteLLM",
        category: "pointsOfInterest"
    )

    // MARK: - Scenario

    static func beginScenario(_ name: String) -> OSSignpostIntervalState {
        signposter.beginInterval("scenario", id: signposter.makeSignpostID())
    }
    static func endScenario(_ state: OSSignpostIntervalState) {
        signposter.endInterval("scenario", state)
    }

    // MARK: - Foreground Workloads

    static func beginScroll() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_scroll", id: signposter.makeSignpostID())
    }
    static func endScroll(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_scroll", state)
    }

    static func beginAnimation() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_animation", id: signposter.makeSignpostID())
    }
    static func endAnimation(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_animation", state)
    }

    static func beginGame3D() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_game_3d", id: signposter.makeSignpostID())
    }
    static func endGame3D(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_game_3d", state)
    }

    static func beginHexGLRace() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_hexgl_race", id: signposter.makeSignpostID())
    }
    static func endHexGLRace(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_hexgl_race", state)
    }

    static func beginFilter() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_filter", id: signposter.makeSignpostID())
    }
    static func endFilter(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_filter", state)
    }

    static func beginMemoryCPU() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_memory_cpu", id: signposter.makeSignpostID())
    }
    static func endMemoryCPU(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_memory_cpu", state)
    }

    static func beginMemoryMetal() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_memory_metal", id: signposter.makeSignpostID())
    }
    static func endMemoryMetal(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_memory_metal", state)
    }

    static func beginVideo() -> OSSignpostIntervalState {
        signposter.beginInterval("fg_video", id: signposter.makeSignpostID())
    }
    static func endVideo(_ state: OSSignpostIntervalState) {
        signposter.endInterval("fg_video", state)
    }

    // MARK: - LLM

    static func beginInference() -> OSSignpostIntervalState {
        signposter.beginInterval("llm_inference", id: signposter.makeSignpostID())
    }
    static func endInference(_ state: OSSignpostIntervalState) {
        signposter.endInterval("llm_inference", state)
    }

    static func emitToken(index: Int) {
        signposter.emitEvent("llm_token")
    }
}
