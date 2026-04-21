import SwiftUI

enum AppRootTab: String, CaseIterable, Identifiable {
    case home
    case trending
    case saved
    case community
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .trending:
            return "Trending"
        case .saved:
            return "Saved"
        case .community:
            return "Community"
        case .more:
            return "More"
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house.fill"
        case .trending:
            return "flame.fill"
        case .saved:
            return "bookmark.fill"
        case .community:
            return "person.3.sequence.fill"
        case .more:
            return "ellipsis.circle.fill"
        }
    }
}

struct AnimatedTabBar: View {
    @Binding var selectedTab: AppRootTab
    let namespace: Namespace.ID

    @State private var dropScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppRootTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(AppTheme.cardBorder.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)
        )
        .padding(.horizontal, 10)
    }

    private func tabButton(for tab: AppRootTab) -> some View {
        let isActive = selectedTab == tab

        return Button {
            guard !isActive else { return }
            HapticFeedback.tap(.medium)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                selectedTab = tab
                dropScale = 1.32
            }

            withAnimation(.easeOut(duration: 0.28).delay(0.04)) {
                dropScale = 1
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isActive {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.accentGradient)
                            .frame(width: 64, height: 38)
                            .matchedGeometryEffect(id: "active_tab_indicator", in: namespace)

                        Circle()
                            .fill(AppTheme.accentPrimary.opacity(0.32))
                            .frame(width: 13, height: 13)
                            .offset(y: 16)
                            .scaleEffect(dropScale)
                    }

                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isActive ? Color.white : AppTheme.subtitleText)
                }
                .frame(height: 42)

                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isActive ? AppTheme.titleText : AppTheme.subtitleText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
