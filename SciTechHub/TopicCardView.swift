import SwiftUI

struct TopicCardView: View {
    let title: String
    let icon: String
    var isSelected: Bool = false
    var isLocked: Bool = false
    var appearDelay: Double = 0

    @State private var didAppear = false
    @State private var shouldFloatIcon = false

    private let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(spacing: 12) {
            iconContainer

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.accentPrimary.opacity(0.45), lineWidth: 1.2)
                    .shadow(color: AppTheme.accentPrimary.opacity(0.35), radius: 14, x: 0, y: 0)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 10)
        .shadow(color: AppTheme.accentPrimary.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 16 : 8, x: 0, y: 0)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .animation(.easeOut(duration: 0.34).delay(appearDelay), value: didAppear)
        .animation(.easeInOut(duration: 0.25), value: isSelected)
        .hoverEffect(.lift)
        .onAppear {
            if !didAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + appearDelay) {
                    didAppear = true
                }
            }

            if !shouldFloatIcon {
                shouldFloatIcon = true
            }
        }
    }

    private var iconContainer: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .stroke(Color.white.opacity(0.26), lineWidth: 0.9)

            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.primary)
                .shadow(color: AppTheme.accentPrimary.opacity(0.34), radius: 8, x: 0, y: 0)
        }
        .frame(width: 78, height: 78)
        .shadow(color: AppTheme.accentPrimary.opacity(0.26), radius: 12, x: 0, y: 0)
        .shadow(color: AppTheme.accentSecondary.opacity(0.18), radius: 20, x: 0, y: 0)
        .offset(y: shouldFloatIcon ? -2 : 2)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: shouldFloatIcon)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color("Card").opacity(0.42))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.26), Color.black.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 14)
                .opacity(isSelected ? 0.65 : 0.35)
                .padding(8)
        }
    }
}

struct TopicCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(configuration.isPressed ? 0.18 : 0), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: 140
                        )
                    )
                    .allowsHitTesting(false)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
