import SwiftUI

@MainActor
final class ResearchDetailViewModel: ObservableObject {
    @Published var simplifiedText: String?
    @Published var isGeneratingExplanation = false

    func explainSimply(for paper: ResearchPaper) {
        guard !isGeneratingExplanation else {
            return
        }

        isGeneratingExplanation = true
        simplifiedText = buildSimplifiedExplanation(for: paper)
        isGeneratingExplanation = false
    }

    private func buildSimplifiedExplanation(for paper: ResearchPaper) -> String {
        let source = paper.abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return "This paper explores \(paper.categoryLabel?.lowercased() ?? "a scientific") topic and explains an approach to solve a research problem."
        }

        let sentenceParts = source
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let selectedParts = sentenceParts.prefix(3)
        if selectedParts.isEmpty {
            return source
        }

        let joined = selectedParts.joined(separator: ". ")
        let normalized = joined.hasSuffix(".") ? joined : joined + "."

        return "In simple words: \(normalized)"
    }
}

struct ResearchDetailView: View {
    let paper: ResearchPaper
    @EnvironmentObject var bookmarkManager: BookmarkManager
    @StateObject private var viewModel = ResearchDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(paper.title)
                    .font(.title3.weight(.bold))

                actionButtons

                HStack(spacing: 8) {
                    detailBadge(label: paper.yearText, symbol: "calendar")
                    detailBadge(label: paper.authorCountText, symbol: "person.2")
                    if let category = paper.categoryLabel {
                        detailBadge(label: category, symbol: "tag")
                    }
                }

                detailRow(title: "Authors", value: paper.authorsText)
                detailRow(title: "Published", value: paper.publishedDate)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Abstract")
                        .font(.headline)

                    Text(paper.abstract.isEmpty ? "No abstract available." : paper.abstract)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Button {
                    viewModel.explainSimply(for: paper)
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isGeneratingExplanation {
                            ProgressView()
                                .scaleEffect(0.9)
                        }

                        Text("Explain Simply")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Image(systemName: "sparkles")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.indigo)
                    .cornerRadius(12)
                }
                .disabled(viewModel.isGeneratingExplanation)

                if let simplifiedText = viewModel.simplifiedText, !simplifiedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Simple Explanation", systemImage: "lightbulb")
                            .font(.headline)
                            .foregroundColor(.indigo)

                        Text(simplifiedText)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.08))
                    .cornerRadius(12)
                }

                if let pdfURL = paper.pdfURL {
                    Link(destination: pdfURL) {
                        Label("Open PDF", systemImage: "doc.richtext")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.top, 4)
                } else {
                    Text("PDF link not available for this paper.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding()
            .tabBarOverlayBottomPadding(extra: 16)
        }
        .navigationTitle("Paper Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            let article = paper.toArticle()
            let isSaved = bookmarkManager.isArticleBookmarked(article: article)
            let isLoved = bookmarkManager.isArticleLoved(article: article)

            Button {
                toggleSave(article: article, wasSaved: isSaved)
            } label: {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSaved ? Color.blue.opacity(0.16) : Color(.secondarySystemBackground))
                    .foregroundColor(isSaved ? .blue : .primary)
                    .clipShape(Capsule())
            }

            Button {
                toggleLove(article: article, wasLoved: isLoved)
            } label: {
                Label(isLoved ? "Loved" : "Love", systemImage: isLoved ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isLoved ? Color.red.opacity(0.15) : Color(.secondarySystemBackground))
                    .foregroundColor(isLoved ? .red : .primary)
                    .clipShape(Capsule())
            }
        }
    }

    private func toggleSave(article: Article, wasSaved: Bool) {
        bookmarkManager.toggleArticleBookmark(article: article)
        if !wasSaved {
            ResearchPreferenceStore.shared.recordInterest(for: paper, weight: 1)
        }
    }

    private func toggleLove(article: Article, wasLoved: Bool) {
        bookmarkManager.toggleArticleLove(article: article)
        if !wasLoved {
            ResearchPreferenceStore.shared.recordInterest(for: paper, weight: 2)
        }
    }

    private func detailBadge(label: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}
