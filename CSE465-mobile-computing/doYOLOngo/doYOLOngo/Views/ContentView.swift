import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .live

    // Shared ViewModels — passed down to child views so they can communicate
    @StateObject private var benchmarkVM = BenchmarkViewModel()
    @StateObject private var exportVM    = ExportViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // ── App Header ─────────────────────────────────────────────
            // AppHeader(tab: selectedTab)

            // ── Tab Bar ────────────────────────────────────────────────
            TopTabBar(selected: $selectedTab)

            Divider()
                .background(Color.cardBg2)

            // ── Content (Swipeable) ────────────────────────────────────
            TabView(selection: $selectedTab) {
                LiveView()
                    .tag(AppTab.live)
                
                BenchmarkView()
                    .tag(AppTab.dashboard)
                
                ExportView()
                    .tag(AppTab.export)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .environmentObject(benchmarkVM)
            .environmentObject(exportVM)
        }
        .background(Color.appBg.ignoresSafeArea())
    }
}

// MARK: - App Header
private struct AppHeader: View {
    let tab: AppTab

    private var subtitle: String {
        switch tab {
        case .live:      return "FP32 active. Tap Start to run."
        case .dashboard: return "Model performance comparison"
        case .export:    return "Export and analyse session logs"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On-device Object Detection")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Color.cardBg)
    }
}

#Preview {
    ContentView()
}
