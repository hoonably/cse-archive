import SwiftUI

struct DetectView: View {
    @StateObject private var vm = DetectViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                livePanel
                detectionPanel
                Spacer()
            }
            .padding()
            .navigationTitle("Recognition")
        }
    }

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Sensors", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text("Live")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Divider()
            VStack(spacing: 20) {
                SensorChartView(title: "Accelerometer (G)", 
                               data: vm.accelHistory, 
                               yRange: -2...2)
                
                SensorChartView(title: "Gyroscope (rad/s)", 
                               data: vm.gyroHistory, 
                               yRange: -4...4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var detectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Current Activity", systemImage: "figure.walk")
                    .font(.headline)
                Spacer()
            }
            Divider()
            Text(vm.currentActivity)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    DetectView()
}
