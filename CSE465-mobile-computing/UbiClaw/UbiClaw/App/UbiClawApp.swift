import SwiftUI

@main
struct UbiClawApp: App {
    @State private var config: AppConfig
    @State private var runner: ScenarioRunner
    @State private var mactopTelemetry: MactopTelemetryManager

    init() {
        let cfg = AppConfig()
        let mactopTelemetryManager = MactopTelemetryManager()
        _config = State(initialValue: cfg)
        _mactopTelemetry = State(initialValue: mactopTelemetryManager)
        _runner = State(initialValue: ScenarioRunner(config: cfg, mactopTelemetry: mactopTelemetryManager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(config: config, runner: runner, mactopTelemetry: mactopTelemetry)
        }
    }
}
