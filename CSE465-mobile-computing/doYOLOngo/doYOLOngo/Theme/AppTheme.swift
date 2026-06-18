import SwiftUI

// MARK: - Adaptive System Colors
// Light mode -> White background, Dark mode -> Black background (Standard iOS behavior)
extension Color {
    // Backgrounds — UIKit semantic colors, fully adaptive
    static let appBg        = Color(.systemBackground)                  // white / black
    static let cardBg       = Color(.secondarySystemBackground)         // light gray / dark gray
    static let cardBg2      = Color(.tertiarySystemBackground)          // slightly darker card

    // Accent — teal that works on both modes
    static let accentTeal   = Color(.systemTeal)
    static let accentTealBg = Color(.systemTeal).opacity(0.12)

    // Text — fully adaptive
    static let textPrimary   = Color(.label)
    static let textSecondary = Color(.secondaryLabel)

    // Separators
    static let divider = Color(.separator)

    // Bounding box colours
    static let boxTarget = Color(.systemTeal)
    static let boxOther  = Color(.systemOrange)

    // Precision tag colours — vivid but readable on both backgrounds
    static let tagFP32 = Color(.systemTeal)
    static let tagFP16 = Color(.systemBlue)
    static let tagINT8 = Color(.systemPurple)

    // Semantic
    static let success = Color(.systemGreen)
    static let warning = Color(.systemOrange)
    static let danger  = Color(.systemRed)
}

// MARK: - Card Modifier
struct CardStyle: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Color.cardBg2 : Color.cardBg)
            .cornerRadius(16)
    }
}

// MARK: - Button Styles

/// Default filled button — Teal style
struct TealButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 13)
            .padding(.horizontal, 20)
            .background(Color(.systemTeal))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Outlined button — Adaptive tint
struct OutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color(.systemTeal))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color(.systemTeal).opacity(0.10))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemTeal).opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Convenience
extension View {
    func cardStyle(elevated: Bool = false) -> some View {
        modifier(CardStyle(elevated: elevated))
    }
}
