import SwiftUI

struct DetailHeaderView: View {
    let article: Article

    @State private var didAppear = false

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .global).minY
            let height = max(280 + (minY > 0 ? minY : 0), 240)

            ZStack(alignment: .bottomLeading) {
                headerImage
                    .frame(height: height)
                    .offset(y: minY > 0 ? -minY : 0)

                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.35), Color.black.opacity(0.72)],
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
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    Text("Swipe for the full breakdown")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
        }
        .frame(height: 286)
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) {
                didAppear = true
            }
        }
    }

    private var headerImage: some View {
        Group {
            if let imageUrl = article.urlToImage,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        fallbackGraphic
                    } else {
                        Rectangle()
                            .fill(AppTheme.cardBackground)
                            .shimmering()
                    }
                }
            } else {
                fallbackGraphic
            }
        }
    }

    private var fallbackGraphic: some View {
        ZStack {
            AppTheme.accentGradient

            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
        }
    }

    private var sourceName: String {
        guard let urlString = article.url,
              let url = URL(string: urlString),
              let host = url.host,
              !host.isEmpty else {
            return "Featured Story"
        }

        return host.replacingOccurrences(of: "www.", with: "")
    }
}
