import SwiftUI

struct ArticleCardView: View {
    let article: Article

    @State private var didAppear = false
    @GestureState private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                coverImage

                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.24), Color.black.opacity(0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(sourceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())

                    Text(article.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                if let description = article.description,
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                        .lineLimit(3)
                } else {
                    Text("No description available.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                }

                HStack(spacing: 10) {
                    Label("\(estimatedReadMinutes) min", systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.subtitleText)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .padding(8)
                        .background(AppTheme.accentPrimary.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .glassCard(cornerRadius: 24)
        .scaleEffect(isPressed ? 0.985 : 1)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isPressed)
        .animation(.easeOut(duration: 0.34), value: didAppear)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressed) { _, pressed, _ in
                    pressed = true
                }
        )
        .onAppear {
            if !didAppear {
                didAppear = true
            }
        }
    }

    private var coverImage: some View {
        Group {
            if let imageUrl = article.urlToImage,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        fallbackImage
                    } else {
                        Rectangle()
                            .fill(AppTheme.cardBackground)
                            .shimmering()
                    }
                }
            } else {
                fallbackImage
            }
        }
    }

    private var fallbackImage: some View {
        ZStack {
            AppTheme.accentGradient

            Image(systemName: "newspaper.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.82))
        }
    }

    private var sourceName: String {
        guard let urlString = article.url,
              let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty else {
            return "Latest Update"
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var estimatedReadMinutes: Int {
        let bodyText = [article.title, article.description ?? ""]
            .joined(separator: " ")
            .split(separator: " ")
            .count

        return max(1, Int(ceil(Double(bodyText) / 200.0)))
    }
}

struct ArticleCardSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.55))
                .frame(height: 210)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.55))
                .frame(height: 18)

            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.45))
                .frame(height: 16)

            HStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.48))
                    .frame(width: 70, height: 14)

                Spacer()

                Circle()
                    .fill(AppTheme.cardBackground.opacity(0.5))
                    .frame(width: 28, height: 28)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 24)
        .shimmering()
    }
}
