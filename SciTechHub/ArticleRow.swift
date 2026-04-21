import SwiftUI

struct ArticleRow: View {
    let article: Article
    let isLoggedIn: Bool
    let onRestrictedAction: () -> Void

    @EnvironmentObject var bookmarkManager: BookmarkManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageString = article.urlToImage,
               let imageUrl = URL(string: imageString) {
                AsyncImage(url: imageUrl) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .cornerRadius(10)
                            .clipped()
                    } else if phase.error != nil {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                            .frame(width: 80, height: 80)
                            .background(AppTheme.cardBackground.opacity(0.7))
                            .cornerRadius(10)
                    } else {
                        ProgressView()
                            .frame(width: 80, height: 80)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.titleText)

                if let description = article.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.subtitleText)
                        .lineLimit(3)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if isLoggedIn {
                        HapticFeedback.tap(.light)
                        bookmarkManager.toggleArticleLove(article: article)
                    } else {
                        onRestrictedAction()
                    }
                } label: {
                    Image(systemName: loveIconName)
                        .foregroundColor(loveIconColor)
                        .padding(8)
                }
                .buttonStyle(BorderlessButtonStyle())

                Button {
                    if isLoggedIn {
                        HapticFeedback.tap(.light)
                        bookmarkManager.toggleArticleBookmark(article: article)
                    } else {
                        onRestrictedAction()
                    }
                } label: {
                    Image(systemName: bookmarkIconName)
                        .foregroundColor(bookmarkIconColor)
                        .padding(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private var loveIconName: String {
        if isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? "heart.fill" : "heart"
        }
        return "heart"
    }

    private var loveIconColor: Color {
        if isLoggedIn {
            return bookmarkManager.isArticleLoved(article: article) ? .red : .gray
        }
        return .gray
    }

    private var bookmarkIconName: String {
        if isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? "bookmark.fill" : "bookmark"
        }
        return "bookmark"
    }

    private var bookmarkIconColor: Color {
        if isLoggedIn {
            return bookmarkManager.isArticleBookmarked(article: article) ? AppTheme.accentPrimary : .gray
        }
        return .gray
    }
}
