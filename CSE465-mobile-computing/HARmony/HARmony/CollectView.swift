import SwiftUI
import UIKit

struct CollectView: View {
    @StateObject private var vm = CollectViewModel()
    @State private var showShare = false
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    livePanel
                    optionsSection
                    labelPicker
                    trialControls
                    exportSection
                }
                .padding()
                .navigationTitle("Data Collection")
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportedURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Live Sensor Panel

    private var livePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Sensors", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                statusBadge
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

    /// Small colored badge summarising the current recording state.
    @ViewBuilder
    private var statusBadge: some View {
        switch vm.recordingState {
        case .idle:
            Text("Idle")
                .font(.caption).bold()
                .foregroundStyle(.secondary)

        case .countdown(let s):
            Label("Ready in \(s)…", systemImage: "timer")
                .font(.caption).bold()
                .foregroundStyle(.orange)

        case .recording(let s):
            Label("Rec \(s)s left", systemImage: "record.circle.fill")
                .font(.caption).bold()
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

        case .finished:
            Text("Done — unsaved")
                .font(.caption).bold()
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Label Picker

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Label").font(.headline)
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ActivityLabel.allCases) { label in
                    Button {
                        vm.selectedLabel = label
                    } label: {
                        HStack {
                            Text(label.title)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if vm.selectedLabel == label {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(vm.selectedLabel == label ? Color.accentColor : Color(.tertiarySystemFill))
                        )
                        .foregroundStyle(vm.selectedLabel == label ? Color.white : Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    vm.selectedLabel == label
                                        ? Color.accentColor.opacity(0.001)
                                        : Color(.separator).opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(vm.selectedLabel == label ? 0.08 : 0.0),
                            radius: 6, x: 0, y: 3
                        )
                    }
                    .buttonStyle(.plain)
                    // Disable label switching while a trial is active.
                    .disabled(vm.isTrialInProgress)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Options (Duration)

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording Options").font(.headline)
            HStack {
                Label {
                    Text("Duration: \(vm.recordingDuration)s")
                } icon: {
                    Image(systemName: "timer")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
                
                Spacer()
                
                Stepper("Duration", value: $vm.recordingDuration, in: 1...60)
                    .labelsHidden()
                    .disabled(vm.isTrialInProgress)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill).cornerRadius(10))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Trial Controls

    private var trialControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording").font(.headline)

            // ── State-specific status banner ───────────────────────────
            stateBanner

            // ── Primary action row ────────────────────────────────────
            HStack(spacing: 12) {
                startButton
                cancelButton
            }

            // ── Post-trial action row (only visible when finished) ────
            if case .finished = vm.recordingState {
                HStack(spacing: 12) {
                    saveButton
                    discardButton
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Sample counts
            HStack {
                Text("Trial samples: \(pendingCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Saved samples: \(vm.savedSamples.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .animation(.easeInOut(duration: 0.25), value: vm.recordingState)
    }

    // MARK: Control sub-views

    @ViewBuilder
    private var stateBanner: some View {
        switch vm.recordingState {
        case .idle:
            EmptyView()

        case .countdown(let s):
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Get ready… \(s)s")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .recording(let s):
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse)
                Text("Recording — \(s)s remaining")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .finished(let count):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                Text("Trial complete — \(count) samples captured")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startButton: some View {
        Button(action: vm.startTrial) {
            Label("Start", systemImage: "record.circle")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        // Enabled only when idle or after a finished trial (Record Again).
        .disabled(vm.isTrialInProgress)
    }

    private var cancelButton: some View {
        Button(action: vm.cancelTrial) {
            Label(cancelLabel, systemImage: "xmark.circle")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        // Enabled during countdown or recording only.
        .disabled(!vm.isTrialInProgress)
    }

    private var saveButton: some View {
        Button(action: vm.saveTrial) {
            Label("Save", systemImage: "square.and.arrow.down")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private var discardButton: some View {
        Button(action: vm.discardTrial) {
            Label("Discard", systemImage: "trash")
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    // MARK: Helpers

    /// Dynamic label for the cancel button.
    private var cancelLabel: String {
        switch vm.recordingState {
        case .countdown: return "Cancel"
        case .recording: return "Cancel"
        default:         return "Stop"
        }
    }

    private var pendingCount: Int {
        vm.pendingTrial?.count ?? 0
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export").font(.headline)
            Text("Exports all saved trials.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    do {
                        let url = try vm.saveCSVToDocuments()
                        exportedURL = url
                        showShare = true
                    } catch {
                        print("Share error: \(error)")
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(vm.savedSamples.isEmpty)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - ViewModel extension for View-layer helpers

extension CollectViewModel {
    /// True while a trial is mid-flight (countdown or recording).
    var isTrialInProgress: Bool {
        switch recordingState {
        case .countdown, .recording: return true
        default: return false
        }
    }
}

// MARK: - UIKit share sheet wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    CollectView()
}
