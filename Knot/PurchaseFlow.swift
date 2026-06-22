import SwiftUI

// MARK: - Order Models

enum FulfilmentMethod: String, CaseIterable {
    case meetup   = "Meetup"
    case delivery = "Delivery"
    var icon: String {
        switch self {
        case .meetup:   return "person.2.fill"
        case .delivery: return "shippingbox.fill"
        }
    }
    var dbValue: String {
        switch self {
        case .meetup:   return "meetup"
        case .delivery: return "delivery"
        }
    }
    static func fromDB(_ value: String) -> FulfilmentMethod {
        value.lowercased() == "delivery" ? .delivery : .meetup
    }
}

enum OrderStatus: String {
    case pending              = "pending"
    case sellerAccepted       = "seller_accepted"
    case meetupAgreed         = "meetup_agreed"
    case awaitingConfirmation = "awaiting_confirmation"
    case complete             = "complete"
    case disputed             = "disputed"
    case cancelled            = "cancelled"
}

enum EscrowStatus {
    case held, released
    var label: String  { self == .held ? "Held in Escrow" : "Released" }
    var color: Color   { self == .held ? Color(.systemOrange) : Color(.systemGreen) }
    var icon: String   { self == .held ? "lock.fill" : "checkmark.seal.fill" }
}

struct MeetupProposal {
    var location   : String
    var date       : Date
    var proposedBy : String   // "seller" or "buyer"
}

struct KnotOrder: Identifiable {
    let id          : String
    let listing     : ShopListing
    let buyerName   : String
    let sellerName  : String
    let sellerId    : UUID
    let buyerId     : UUID
    let subtotal    : Int           // cents — buyer pays listing price exactly
    let knotFeeRate : Double        // seller-side deduction
    let fulfilment     : FulfilmentMethod
    let paymentMethod  : String            // "cash" | "card"
    var address        : String
    let date           : Date
    var status         : OrderStatus
    var escrow         : EscrowStatus

    var isCash: Bool { paymentMethod == "cash" }
    var meetupProposal : MeetupProposal?
    var stepDates   : [String: Date] = [:]   // keyed by OrderStatus.rawValue

    var total   : Int { subtotal }
    var knotFee : Int { Int(Double(subtotal) * knotFeeRate) }
    var payout  : Int { subtotal - knotFee }

    // Seller must respond within 24h
    var respondByDate: Date {
        Calendar.current.date(byAdding: .hour, value: 24, to: date) ?? date
    }

    static func makeID() -> String {
        "#KN-\(String(format: "%05d", Int.random(in: 1...99999)))"
    }
}

// MARK: - Formatters

func formatSGD(_ cents: Int) -> String {
    String(format: "S$%.2f", Double(cents) / 100.0)
}

func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM yyyy, h:mm a"
    return f.string(from: date)
}

// MARK: - Screen 1: PurchaseConfirmView

struct PurchaseConfirmView: View {
    let listing: ShopListing
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var fulfilment       : FulfilmentMethod = .meetup
    @State private var meetupLocation   = ""
    @State private var meetupDate       = Date().addingTimeInterval(86_400)
    @FocusState private var focusedField: Field?

    private enum Field { case meetupLocation }
    @State private var navigateToCashOrder = false
    @State private var order           : KnotOrder?
    @State private var isProcessing    = false
    @State private var showPaymentError = false

    private var subtotal: Int { listing.price * 100 }
    private var total   : Int { subtotal }

    private var canConfirm: Bool {
        !meetupLocation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Listing Card ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.knotSurface)
                                .frame(width: 72, height: 72)
                                .overlay {
                                    Image(systemName: listing.type.icon)
                                        .font(.system(size: 24))
                                        .foregroundColor(Color.knotMuted)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(listing.name)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.knotSurface)
                                        .frame(width: 22, height: 22)
                                        .overlay {
                                            Text(String(listing.sellerName.prefix(1)))
                                                .font(.caption2).fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                        }
                                    Text(listing.sellerName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 2) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundColor(Color(.systemOrange))
                                        Text("4.8")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Label(listing.type.rawValue, systemImage: listing.type.icon)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.knotSurface)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                    .background(Color.knotSurface)
                    .cornerRadius(14)

                    // ── Price Breakdown ───────────────────────────────────
                    VStack(spacing: 0) {
                        priceRow(label: "Item price", amount: subtotal)
                        Divider().padding(.horizontal)
                        HStack {
                            Text("Total").font(.headline)
                            Spacer()
                            Text(formatSGD(total))
                                .font(.title3).fontWeight(.bold)
                        }
                        .padding()
                    }
                    .background(Color.knotSurface)
                    .cornerRadius(14)

                    // ── Meetup Details ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meetup").font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Proposed meetup location")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("e.g. Starbucks, Orchard MRT", text: $meetupLocation)
                                .focused($focusedField, equals: .meetupLocation)
                                .padding(12)
                                .background(Color.knotSurface)
                                .cornerRadius(10)
                            DatePicker(
                                "Proposed date & time",
                                selection: $meetupDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color.knotSurface)
                    .cornerRadius(14)

                    // ── Actions ───────────────────────────────────────────
                    NavigationLink(destination: cashOrderDestination, isActive: $navigateToCashOrder) {
                        EmptyView()
                    }

                    Button(action: confirmCash) {
                        Group {
                            if isProcessing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Confirm Order")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(canConfirm ? Color.knotOnAccent : Color.knotMuted)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canConfirm ? Color.knotAccent : Color.knotSurface)
                        .cornerRadius(14)
                    }
                    .disabled(!canConfirm || isProcessing)

                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Review Order")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Order Failed", isPresented: $showPaymentError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not create your order. Please try again.")
            }
        }
    }

    @ViewBuilder
    private var cashOrderDestination: some View {
        if let o = order {
            OrderTimelineView(order: o, isSeller: false)
        } else {
            EmptyView()
        }
    }

    private func confirmCash() {
        guard !isProcessing else { return }
        isProcessing = true
        let addr = meetupLocation
        Task {
            do {
                let orderID = try await OrderService.createCashOrder(
                    listingID      : listing.id,
                    fulfilment     : fulfilment,
                    deliveryAddress: "",
                    meetupLocation : meetupLocation
                )
                let newOrder = KnotOrder(
                    id            : orderID,
                    listing       : listing,
                    buyerName     : profile.name,
                    sellerName    : listing.sellerName,
                    sellerId      : listing.sellerID ?? UUID(),
                    buyerId       : profile.currentUserID ?? UUID(),
                    subtotal      : subtotal,
                    knotFeeRate   : 0.10,
                    fulfilment    : fulfilment,
                    paymentMethod : "cash",
                    address       : addr,
                    date          : Date(),
                    status        : .pending,
                    escrow        : .held
                )
                order = newOrder
                navigateToCashOrder = true
            } catch {
                print("[PurchaseConfirmView] createCashOrder error: \(error)")
                showPaymentError = true
                isProcessing = false
            }
        }
    }

    private func priceRow(label: String, amount: Int) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(formatSGD(amount))
        }
        .padding()
    }
}

// MARK: - Screen 2: PurchaseSuccessView

struct PurchaseSuccessView: View {
    let order: KnotOrder
    @State private var checkScale    : CGFloat = 0.3
    @State private var checkOpacity  : Double  = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // ── Checkmark Animation ───────────────────────────────
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(.systemGreen))
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
                    .padding(.top, 32)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            checkScale   = 1.0
                            checkOpacity = 1.0
                        }
                    }

                VStack(spacing: 8) {
                    Text("Order Placed")
                        .font(.title2).fontWeight(.bold)
                    Text("Coordinate with the seller to arrange collection or delivery.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // ── Transaction Summary ───────────────────────────────
                VStack(spacing: 0) {
                    summaryRow(label: "Order ID",   value: order.id)
                    Divider().padding(.horizontal)
                    summaryRow(label: "Item",       value: order.listing.name)
                    Divider().padding(.horizontal)
                    summaryRow(label: "Amount paid", value: formatSGD(order.total))
                    Divider().padding(.horizontal)
                    summaryRow(label: "Date",       value: formatDate(order.date))
                    Divider().padding(.horizontal)
                    summaryRow(label: "Seller",     value: order.sellerName)
                    Divider().padding(.horizontal)
                    summaryRow(label: "Fulfilment", value: order.fulfilment.rawValue)
                }
                .background(Color.knotSurface)
                .cornerRadius(14)

                // ── Buttons ───────────────────────────────────────────
                VStack(spacing: 12) {
                    NavigationLink(destination: OrderTimelineView(order: order, isSeller: false)) {
                        Text("Go to My Orders")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotAccent)
                            .cornerRadius(14)
                    }

                }
            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Order Confirmed")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}


#Preview {
    let listing = ShopListing(name: "Standing Desk", price: 150, sellerName: "Wei Ming")
    PurchaseConfirmView(listing: listing)
        .environment(UserProfile(name: "Ruhaan"))
}
