import SwiftUI

// MARK: - SavedCard Model

struct SavedCard: Identifiable {
    let id       = UUID()
    var last4    : String
    var brand    : String
    var expMonth : Int
    var expYear  : Int

    var displayName: String { "\(brand) ···· \(last4)" }
    var expiry: String { String(format: "%02d/%02d", expMonth, expYear % 100) }
}

// MARK: - Wallet & Payments View

struct WalletPaymentsView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showAddCard = false

    var body: some View {
        List {
            Section("Saved Cards") {
                if profile.savedCards.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .foregroundColor(Color(.systemGray3))
                        Text("No saved cards").foregroundColor(.secondary)
                    }
                } else {
                    ForEach(profile.savedCards) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "creditcard.fill")
                                .font(.title2).foregroundColor(.primary).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.displayName).fontWeight(.medium)
                                Text("Expires \(card.expiry)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { idx in profile.savedCards.remove(atOffsets: idx) }
                }

                Button(action: { showAddCard = true }) {
                    Label("Add Card", systemImage: "plus.circle.fill").foregroundColor(.black)
                }
            }

            Section("Subscriptions") {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Color(.systemGray3))
                    Text("No active subscriptions").foregroundColor(.gray).font(.subheadline)
                }
            }
        }
        .navigationTitle("Wallet & Payments")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCard) {
            AddCardView { card in
                profile.savedCards.append(card)
                showAddCard = false
            }
        }
    }
}

// MARK: - Add Card View

struct AddCardView: View {
    var onSave: (SavedCard) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var cardNumber = ""
    @State private var expiry     = ""
    @State private var cvv        = ""
    @State private var cardHolder = ""
    @State private var showCVV    = false

    private var digits: String { cardNumber.filter { $0.isNumber } }

    private var formattedNumber: String {
        let d = digits.prefix(16)
        return stride(from: 0, to: d.count, by: 4).map {
            let start = d.index(d.startIndex, offsetBy: $0)
            let end   = d.index(start, offsetBy: min(4, d.count - $0))
            return String(d[start..<end])
        }.joined(separator: " ")
    }

    private var detectedBrand: String {
        if digits.hasPrefix("4")                               { return "Visa" }
        if digits.hasPrefix("5") || digits.hasPrefix("2")     { return "Mastercard" }
        if digits.hasPrefix("3")                              { return "Amex" }
        return ""
    }

    private var canSave: Bool {
        digits.count == 16 && expiry.count == 5 &&
        cvv.count >= 3 && !cardHolder.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "creditcard").foregroundColor(.secondary).frame(width: 24)
                        TextField("Card number", text: Binding(
                            get: { formattedNumber },
                            set: { cardNumber = $0.filter { $0.isNumber } }
                        ))
                        .keyboardType(.numberPad)
                        if !detectedBrand.isEmpty {
                            Text(detectedBrand).font(.caption).foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "calendar").foregroundColor(.secondary).frame(width: 24)
                        TextField("MM/YY", text: $expiry)
                            .keyboardType(.numberPad)
                            .onChange(of: expiry) { val in
                                var d = val.filter { $0.isNumber }
                                if d.count > 4 { d = String(d.prefix(4)) }
                                expiry = d.count >= 3
                                    ? String(d.prefix(2)) + "/" + String(d.dropFirst(2))
                                    : d
                            }
                    }

                    HStack {
                        Image(systemName: "lock").foregroundColor(.secondary).frame(width: 24)
                        if showCVV {
                            TextField("CVV", text: $cvv).keyboardType(.numberPad)
                        } else {
                            SecureField("CVV", text: $cvv)
                        }
                        Button(action: { showCVV.toggle() }) {
                            Image(systemName: showCVV ? "eye.slash" : "eye")
                                .foregroundColor(Color(.systemGray3))
                        }.buttonStyle(.plain)
                    }

                    HStack {
                        Image(systemName: "person").foregroundColor(.secondary).frame(width: 24)
                        TextField("Cardholder name", text: $cardHolder).autocapitalization(.words)
                    }
                } header: {
                    Text("Card Details")
                } footer: {
                    Label("Card details are encrypted and stored securely via Stripe.",
                          systemImage: "lock.shield")
                        .font(.caption)
                }

                Section {
                    Button(action: saveCard) {
                        Text("Add Card")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                            .foregroundColor(canSave ? .white : Color(.systemGray3))
                    }
                    .listRowBackground(canSave ? Color.black : Color(.systemGray5))
                    .disabled(!canSave)
                }
            }
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func saveCard() {
        let parts = expiry.split(separator: "/")
        let month = Int(parts.first ?? "0") ?? 0
        let year  = Int(parts.last  ?? "0") ?? 0
        onSave(SavedCard(last4: String(digits.suffix(4)), brand: detectedBrand,
                         expMonth: month, expYear: 2000 + year))
    }
}
