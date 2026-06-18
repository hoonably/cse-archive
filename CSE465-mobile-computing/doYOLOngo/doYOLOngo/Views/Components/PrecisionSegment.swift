import SwiftUI

/// FP32 / FP16 / INT8 segment picker (Capture style)
struct PrecisionSegment: View {
    @Binding var selected: Precision

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Precision.allCases) { precision in
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selected = precision } }) {
                    HStack(spacing: 5) {
                        if selected == precision {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(precision.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(selected == precision ? .white : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selected == precision
                            ? precisionColor(precision)
                            : Color.clear
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.cardBg2)
        .cornerRadius(13)
    }

    private func precisionColor(_ p: Precision) -> Color {
        switch p {
        case .fp32: return Color.tagFP32
        case .fp16: return Color.tagFP16
        case .int8: return Color.tagINT8
        }
    }
}

/// Small inline precision badge
struct PrecisionBadge: View {
    let precision: Precision
    var body: some View {
        Text(precision.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor)
            .cornerRadius(6)
    }
    private var badgeColor: Color {
        switch precision {
        case .fp32: return Color.tagFP32
        case .fp16: return Color.tagFP16
        case .int8: return Color.tagINT8
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PrecisionSegment(selected: .constant(.fp32))
        HStack { PrecisionBadge(precision: .fp32); PrecisionBadge(precision: .fp16); PrecisionBadge(precision: .int8) }
    }
    .padding()
    .background(Color.appBg)
}
