import Foundation

@MainActor
final class ArticleViewModel: ObservableObject {
    @Published var summaryText: String = ""
    @Published var simplifiedText: String = ""
    @Published var isProcessing: Bool = false
    @Published var processingError: String? = nil

    @Published private(set) var isSummarizing: Bool = false
    @Published private(set) var isSimplifying: Bool = false

    private let textService: TextProcessingServicing

    init(textService: TextProcessingServicing? = nil) {
        self.textService = textService ?? TextProcessingService()
    }

    func generateSummary(for article: Article) {
        Task {
            await runSummary(for: article)
        }
    }

    func generateSimplifiedText(for article: Article) {
        Task {
            await runSimplifiedText(for: article)
        }
    }

    private func runSummary(for article: Article) async {
        guard !isProcessing else {
            return
        }

        let source = sourceText(for: article)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            summaryText = "No content available to summarize."
            processingError = "This article does not contain enough text."
            return
        }

        isProcessing = true
        isSummarizing = true
        isSimplifying = false
        processingError = nil

        let output = await textService.summarize(text: source)
        summaryText = output
        processingError = textService.lastErrorMessage

        isSummarizing = false
        isProcessing = false
    }

    private func runSimplifiedText(for article: Article) async {
        guard !isProcessing else {
            return
        }

        let source = sourceText(for: article)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            simplifiedText = "No content available to simplify."
            processingError = "This article does not contain enough text."
            return
        }

        isProcessing = true
        isSimplifying = true
        isSummarizing = false
        processingError = nil

        let output = await textService.simplify(text: source)
        simplifiedText = output
        processingError = textService.lastErrorMessage

        isSimplifying = false
        isProcessing = false
    }

    private func sourceText(for article: Article) -> String {
        let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = article.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !title.isEmpty && !description.isEmpty {
            return "\(title)\n\n\(description)"
        }

        if !description.isEmpty {
            return description
        }

        return title
    }
}
