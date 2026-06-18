import SwiftUI

struct LiveView: View {
    @StateObject private var vm = LiveViewModel()
    @EnvironmentObject private var benchmarkVM: BenchmarkViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Camera Preview ─────────────────────────────────────
                ZStack {
                    if vm.cameraPermissionDenied {
                        // Permission denied state
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill.badge.ellipsis")
                                .font(.system(size: 42))
                                .foregroundColor(Color.danger)
                            Text("Camera access denied")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text("Go to Settings → doYOLOngo → Camera")
                                .font(.system(size: 13))
                                .foregroundColor(Color.textSecondary)
                                .multilineTextAlignment(.center)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(TealButtonStyle(fullWidth: false))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(4/3, contentMode: .fit)
                        .background(Color.cardBg)
                    } else {
                        // Camera preview
                        CameraPreviewView(session: vm.camera.session)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()

                        // Overlay: only when running
                        if vm.isRunning {
                            GeometryReader { geo in
                                DetectionOverlay(
                                    detections: vm.detections,
                                    frameSize: geo.size
                                )
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        } else {
                            // Idle dim overlay
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                                .aspectRatio(1, contentMode: .fill)
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("Tap \"Start inference\" button to begin")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }

                // ── Live Controls Section ──────────────────────────────
                VStack(alignment: .leading, spacing: 14) {

                    // Precision Picker
                    PrecisionSegment(selected: Binding(
                        get: { vm.selectedPrecision },
                        set: { vm.switchPrecision($0) }
                    )).padding(.top, 18)

                    // Action Buttons
                    HStack(spacing: 12) {
                        if vm.isRunning {
                            Button(action: { vm.toggleInference() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pause.fill")
                                    Text("Pause inference")
                                }
                            }
                            .buttonStyle(OutlinedButtonStyle())
                        } else {
                            Button(action: { vm.toggleInference() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                    Text("Start inference")
                                }
                            }
                            .buttonStyle(TealButtonStyle())
                        }

                        // Keep Voice Target button visible (Clear button removed)
                        Button(action: { vm.triggerVoiceInput() }) {
                            HStack(spacing: 6) {
                                Image(systemName: vm.isListeningVoice ? "waveform" : "mic.fill")
                                Text("Voice command")
                            }
                        }
                        .buttonStyle(TealButtonStyle())
                    }

                    // ── 3-Tier Dynamic Feedback Banners ────────────────────────
                    VStack(spacing: 8) {
                        // 1. Listening Banner
                        if vm.isListeningVoice {
                            HStack(spacing: 8) {
                                Circle().fill(Color.blue).frame(width: 7, height: 7)
                                Text(vm.listeningText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.blue.opacity(0.12)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        }
                        
                        // 2. Target Banner (Maintained when Find command succeeds, includes X button)
                        if let target = vm.selectedTarget {
                            let count = vm.detections.filter { $0.isTarget }.count
                            HStack(spacing: 8) {
                                Circle().fill(Color.orange).frame(width: 7, height: 7)
                                Text("Target: \(target.capitalized) (\(count) found)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Button(action: { vm.selectedTarget = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.orange.opacity(0.12)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        }
                        
                        // 3. System Message Banner (Status messages like Count, Overdrive, etc.)
                        if let sysMsg = vm.systemMessage {
                            HStack(spacing: 8) {
                                Circle().fill(Color.accentTeal).frame(width: 7, height: 7)
                                Text(sysMsg)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.accentTeal.opacity(0.12)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentTeal.opacity(0.3), lineWidth: 1))
                        }
                        
                        // 4. Easter Egg Banner (Flashbang, etc., dismissible)
                        if let eggMsg = vm.easterEggMessage {
                            HStack(spacing: 8) {
                                Circle().fill(Color.yellow).frame(width: 7, height: 7)
                                Text(eggMsg)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Button(action: {
                                    vm.easterEggMessage = nil
                                    vm.camera.setFlashlight(on: false) // Turn off flashlight when closed
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.yellow.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Color.yellow.opacity(0.12)).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                        }
                    }

                    // ── Live Summary ───────────────────────────────────
                    Text("Live Summary")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(.top, 4)

                    let columns = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: columns, spacing: 10) {
                        summaryCard(label: "Target",      value: vm.voiceLabel)
                        summaryCard(label: "Voice",       value: vm.isListeningVoice ? "Listening…" : (vm.selectedTarget != nil ? "active" : "—"))
                        summaryCard(label: "Avg latency", value: vm.latencyString + " ms")
                        summaryCard(label: "FPS",         value: vm.fpsString)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBg.ignoresSafeArea())
        .onAppear {
            vm.benchmarkVM = benchmarkVM
        }
    }

    // MARK: - Helpers
    private func summaryCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardStyle()
    }
}

#Preview {
    LiveView()
}
