import SwiftUI

/// Dashboard stat card — title / large value / unit
struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(accent ? Color.accentTeal : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }
}

/// Compact label-value pair (used in Live Summary grid)
struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HStack {
        StatCard(title: "Avg latency", value: "316.11", unit: "ms")
        StatCard(title: "Target rate", value: "100%", unit: "", accent: true)
    }
    .padding()
    .background(Color.appBg)
}
