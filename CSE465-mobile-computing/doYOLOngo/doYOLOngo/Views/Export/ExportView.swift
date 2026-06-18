import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var benchmarkVM: BenchmarkViewModel
    @StateObject private var vm = ExportViewModel()
    
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── Export & Analysis Card ─────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    Text("Export & Analysis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    // Buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            if let url = vm.exportCSV(stats: benchmarkVM.stats) {
                                shareURL = url
                                showShareSheet = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "tablecells")
                                Text("Export CSV")
                            }
                        }
                        .buttonStyle(TealButtonStyle())

                        Button(action: {
                            if let url = vm.exportJSON(stats: benchmarkVM.stats) {
                                shareURL = url
                                showShareSheet = true
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "curlybraces")
                                Text("Export JSON")
                            }
                        }
                        .buttonStyle(OutlinedButtonStyle())
                    }

                    // Export feedback
                    if let msg = vm.exportMessage {
                        Text(msg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.success)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
                .cardStyle()


                // ── Export History ────────────────────────────────────
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export history")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    if vm.exportHistory.isEmpty {
                        Text("No exported sessions yet.")
                            .font(.system(size: 14))
                            .foregroundColor(Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(vm.exportHistory) { log in
                            HStack(spacing: 12) {
                                PrecisionBadge(precision: log.precision)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.summary)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                    Text(log.displayTimestamp)
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.textSecondary)
                                }
                                Spacer()
                                Image(systemName: log.format == .csv ? "tablecells" : "curlybraces")
                                    .foregroundColor(Color.textSecondary)
                                    .font(.system(size: 14))
                            }
                            .padding(12)
                            .cardStyle(elevated: true)
                        }
                    }
                }
                .padding(16)
                .cardStyle()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color.appBg.ignoresSafeArea())
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func sessionRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView()
}
