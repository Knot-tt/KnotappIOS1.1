import SwiftUI

// MARK: - Help & Support View
struct HelpSupportView: View {
    private let supportEmail = "joinknot.app@gmail.com"

    var body: some View {
        List {
            Section("Support") {
                NavigationLink("FAQ") { FAQView() }
                NavigationLink("Send Feedback") { FeedbackView() }
                Button(action: {
                    openMail(subject: "Knot Support Request", body: "Hi Knot team,\n\n")
                }) {
                    Text("Contact Support").foregroundColor(.primary)
                }
                Button(action: {
                    openMail(
                        subject: "Knot Problem Report",
                        body: "Hi Knot team,\n\nI found a problem in the app:\n\nWhat happened:\n\nWhat I expected:\n\nSteps to reproduce:\n1. \n2. \n3. \n\nDevice / iOS version:\n"
                    )
                }) {
                    Text("Report a Problem").foregroundColor(.primary)
                }
            }
            Section("About") {
                NavigationLink("Terms of Service") { LegalDocumentView(kind: .terms) }
                NavigationLink("Privacy Policy") { LegalDocumentView(kind: .privacy) }
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0").foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openMail(subject: String, body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Feedback View
struct FeedbackView: View {
    private let supportEmail = "joinknot.app@gmail.com"

    @State private var rating      = 0
    @State private var feedbackText = ""
    @State private var submitted   = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: { rating = star }) {
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.system(size: 28))
                                .foregroundColor(star <= rating ? .orange : Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } header: {
                Text("How are you finding Knot?")
            }

            Section("Your Feedback") {
                TextEditor(text: $feedbackText)
                    .frame(minHeight: 120)
            }

            Section {
                Button(action: sendFeedback) {
                    Text("Submit")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fontWeight(.semibold)
                        .foregroundColor(feedbackText.isEmpty ? .gray : .primary)
                }
                .disabled(feedbackText.isEmpty)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thank you!", isPresented: $submitted) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your feedback helps us make Knot better for everyone.")
        }
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Knot Feedback"),
            URLQueryItem(name: "body", value: "Rating: \(rating)/5\n\nFeedback:\n\(feedbackText)")
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
        submitted = true
    }
}

// MARK: - FAQ View
struct FAQView: View {
    let faqs: [(q: String, a: String)] = [
        ("How do I join a Knot?",     "Browse Knots in the Knots tab and tap a Knot card to view details. Press Join to become a member."),
        ("How do payments work?",     "Knot uses real-money pricing. When a knot or listing has a price, it is shown in dollars. Payments are processed securely."),
        ("Can I host a class?",       "Yes — once the Classes feature launches, you can list and monetise classes. Payouts are handled via Stripe Connect."),
        ("How do I message someone?", "Go to the Messages tab to start a direct message, or message members from inside a Knot page."),
        ("How do I report someone?",  "Open their profile, tap the ••• menu at the top right, and choose Report. You can also Block them from the same menu. Our team reviews all reports within 24 hours."),
    ]

    var body: some View {
        List(faqs, id: \.q) { faq in
            VStack(alignment: .leading, spacing: 6) {
                Text(faq.q).font(.subheadline).fontWeight(.semibold)
                Text(faq.a).font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Web Content View (Terms / Privacy Policy placeholder)
struct WebContentView: View {
    let title: String

    var body: some View {
        ScrollView {
            Text("[\(title) content will be loaded here]")
                .foregroundColor(.secondary)
                .padding(24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
