import SwiftUI

// MARK: - Help & Support View
struct HelpSupportView: View {
    var body: some View {
        List {
            Section("Support") {
                NavigationLink("FAQ") { FAQView() }
                NavigationLink("Send Feedback") { FeedbackView() }
                Button(action: {
                    if let url = URL(string: "mailto:support@knot.app") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Contact Support").foregroundColor(.black)
                }
                Button(action: {
                    // TODO: open in-app report flow
                }) {
                    Text("Report a Problem").foregroundColor(.black)
                }
            }
            Section("About") {
                NavigationLink("Terms of Service") { WebContentView(title: "Terms of Service") }
                NavigationLink("Privacy Policy") { WebContentView(title: "Privacy Policy") }
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0").foregroundColor(.gray)
                }
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Feedback View
struct FeedbackView: View {
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
                Button(action: {
                    // TODO: send to Supabase
                    submitted = true
                }) {
                    Text("Submit")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fontWeight(.semibold)
                        .foregroundColor(feedbackText.isEmpty ? .gray : .black)
                }
                .disabled(feedbackText.isEmpty)
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thank you!", isPresented: $submitted) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your feedback helps us make Knot better for everyone.")
        }
    }
}

// MARK: - FAQ View
struct FAQView: View {
    let faqs: [(q: String, a: String)] = [
        ("How do I join a Knot?",     "Browse Knots in the Knots tab and tap a Knot card to view details. Press Join to become a member."),
        ("How do payments work?",     "Knot uses real-money pricing. When a knot or listing has a price, it is shown in dollars. Payments are processed securely."),
        ("Can I host a class?",       "Yes — once the Classes feature launches, you can list and monetise classes. Payouts are handled via Stripe Connect."),
        ("How do I message someone?", "Go to the Messages tab to start a direct message, or message members from inside a Knot page."),
        ("How do I report someone?",  "Tap their profile and select Report. Our team reviews all reports within 24 hours."),
    ]

    var body: some View {
        List(faqs, id: \.q) { faq in
            VStack(alignment: .leading, spacing: 6) {
                Text(faq.q).font(.subheadline).fontWeight(.semibold)
                Text(faq.a).font(.caption).foregroundColor(.gray)
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
                .foregroundColor(.gray)
                .padding(24)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
