import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        switch sanitized.count {
        case 8:
            red = CGFloat((value & 0xFF000000) >> 24) / 255
            green = CGFloat((value & 0x00FF0000) >> 16) / 255
            blue = CGFloat((value & 0x0000FF00) >> 8) / 255
            alpha = CGFloat(value & 0x000000FF) / 255
        default:
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct TabBarOverlayHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarOverlayHeight: CGFloat {
        get { self[TabBarOverlayHeightEnvironmentKey.self] }
        set { self[TabBarOverlayHeightEnvironmentKey.self] = newValue }
    }
}

private struct TabBarOverlayBottomPaddingModifier: ViewModifier {
    @Environment(\.tabBarOverlayHeight) private var tabBarOverlayHeight
    let extra: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.bottom, tabBarOverlayHeight + extra)
    }
}

enum AppTheme {
    static var background: Color {
        adaptiveColor(named: "Background", lightHex: "F4F7FB", darkHex: "0A111F")
    }

    static var cardBackground: Color {
        adaptiveColor(named: "CardBackground", lightHex: "FFFFFF", darkHex: "111C2F")
    }

    static var cardBorder: Color {
        adaptiveColor(named: "CardBorder", lightHex: "DCE5F2", darkHex: "243451")
    }

    static var accentPrimary: Color {
        adaptiveColor(named: "AccentPrimary", lightHex: "0089E6", darkHex: "3AB2FF")
    }

    static var accentSecondary: Color {
        adaptiveColor(named: "AccentSecondary", lightHex: "00C9A8", darkHex: "49E1C6")
    }

    static var titleText: Color {
        adaptiveColor(named: "TitleText", lightHex: "0D1B2A", darkHex: "F3F8FF")
    }

    static var subtitleText: Color {
        adaptiveColor(named: "SubtitleText", lightHex: "51657E", darkHex: "A5B4CB")
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentPrimary, accentSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptiveColor(named: String, lightHex: String, darkHex: String) -> Color {
        let fallback = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        }

        return Color(uiColor: UIColor(named: named) ?? fallback)
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder.opacity(0.35), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func shimmering(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }

    func tabBarOverlayBottomPadding(extra: CGFloat = 0) -> some View {
        modifier(TabBarOverlayBottomPaddingModifier(extra: extra))
    }
}

struct SpringyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.66), value: configuration.isPressed)
    }
}

struct ShimmerModifier: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -0.9

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.46),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .rotationEffect(.degrees(22))
                        .offset(x: phase * width * 2.1)
                    }
                    .blendMode(.plusLighter)
                }
            }
            .mask(content)
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 0.9
                }
            }
    }
}

enum HapticFeedback {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
