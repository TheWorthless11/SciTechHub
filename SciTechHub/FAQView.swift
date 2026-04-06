import SwiftUI

struct FAQView: View {
    struct FAQItem: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }
    
    let faqs = [
        FAQItem(question: "How do I save an article?", answer: "Tap the heart icon on any article or topic to save it to your Bookmarks."),
        FAQItem(question: "Can I read offline?", answer: "Currently, an internet connection is required to fetch the latest news and topics."),
        FAQItem(question: "How do I change my password?", answer: "Go to Profile > Change Password, and we will send a reset link to your email.")
    ]
    
    var body: some View {
        List(faqs) { faq in
            VStack(alignment: .leading, spacing: 8) {
                Text(faq.question)
                    .font(.headline)
                Text(faq.answer)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("FAQ")
    }
}

struct ReportIssueView: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var message: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Describe the issue")) {
                TextEditor(text: $message)
                    .frame(height: 150)
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let success = viewModel.successMessage {
                Text(success)
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            Button(action: {
                viewModel.reportIssue(message: message)
            }) {
                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Submit Report")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .navigationTitle("Report Issue")
        .onAppear {
            viewModel.clearMessages()
        }
    }
}
