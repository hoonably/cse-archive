import SwiftUI

/// Top Tab Bar — Live / Dashboard / Export
struct TopTabBar: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selected = tab } }) {
                    VStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(size: 14, weight: selected == tab ? .semibold : .regular))
                            .foregroundColor(selected == tab ? Color.accentTeal : Color.textSecondary)

                        // Underline indicator
                        RoundedRectangle(cornerRadius: 2)
                            .fill(selected == tab ? Color.accentTeal : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(Color.cardBg)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case live       = "live"
    case dashboard  = "dashboard"
    case export     = "export"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .live:      return "Live"
        case .dashboard: return "Dashboard"
        case .export:    return "Export"
        }
    }
}

#Preview {
    TopTabBar(selected: .constant(.live))
        .background(Color.appBg)
}
