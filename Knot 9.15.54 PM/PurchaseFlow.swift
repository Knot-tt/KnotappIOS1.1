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
}

enum OrderStatus: Int, CaseIterable {
    case paymentReceived   = 0
    case inProgress        = 1
    case awaitingConfirm   = 2
    case complete          = 3
}

enum EscrowStatus {
    case held, released
    var label: String  { self == .held ? "Held in Escrow" : "Released" }
    var color: Color   { self == .held ? Color(.systemOrange) : Color(.systemGreen) }
    var icon: String   { self == .held ? "lock.fill" : "checkmark.seal.fill" }
}

struct KnotOrder: Identifiable {
    let id         : String
    let listing    : ShopListing
    let buyerName  : String
    let sellerName : String
    let subtotal   : Int          // buyer pays this; = listing price
    let knotFeeRate: Double       // seller-side deduction (e.g. 0.10)
    let fulfilment : FulfilmentMethod
    let address    : String
    let date       : Date
    var status     : OrderStatus
    var escrow     : EscrowStatus

    // Buyer pays exactly the listing price
    var total: Int { subtotal }

    // Seller-side deduction (not shown to buyer)
    var knotFee: Int  { Int(Double(subtotal) * knotFeeRate) }
    var payout: Int   { subtotal - knotFee }

    static func makeID() -> String {
        "#KN-\(String(format: "%05d", Int.random(in: 1...99999)))"
    }
}

// MARK: - Formatters

private func formatSGD(_ cents: Int) -> String {
    String(format: "S$%.2f", Double(cents))
}

private func formatDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM yyyy, h:mm a"
    return f.string(from: date)
}

// MARK: - Screen 1: PurchaseConfirmView

struct PurchaseConfirmView: View {
    let listing: ShopListing
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    @State private var fulfilment   : FulfilmentMethod = .meetup
    @State private var meetupLocation = ""
    @State private var deliveryAddress = ""
    @State private var navigateToProcessing = false
    @State private var order: KnotOrder?

    private var subtotal: Int { listing.price * 100 }
    private var total   : Int { subtotal }

    private var canConfirm: Bool {
        switch fulfilment {
        case .meetup:   return !meetupLocation.trimmingCharacters(in: .whitespaces).isEmpty
        case .delivery: return !deliveryAddress.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Listing Card ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray5))
                                .frame(width: 72, height: 72)
                                .overlay {
                                    Image(systemName: listing.type.icon)
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(.systemGray2))
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(listing.name)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color(.systemGray4))
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
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
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
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Knot Protection Badge ─────────────────────────────
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(Color(.systemGreen))
                        Text("Your payment is held safely until you confirm receipt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGreen).opacity(0.08))
                    .cornerRadius(10)

                    // ── Fulfilment Selector ───────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fulfilment").font(.headline)

                        Picker("Fulfilment", selection: $fulfilment) {
                            ForEach(FulfilmentMethod.allCases, id: \.self) { method in
                                Label(method.rawValue, systemImage: method.icon).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)

                        if fulfilment == .meetup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Proposed meetup location")
                                    .font(.caption).foregroundColor(.secondary)
                                TextField("e.g. Starbucks, Orchard MRT", text: $meetupLocation)
                                    .padding(12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Delivery address")
                                    .font(.caption).foregroundColor(.secondary)
                                TextField("Enter full delivery address", text: $deliveryAddress)
                                    .padding(12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Actions ───────────────────────────────────────────
                    NavigationLink(destination: processingDestination, isActive: $navigateToProcessing) {
                        EmptyView()
                    }

                    Button(action: confirmAndPay) {
                        Text("Confirm & Pay")
                            .fontWeight(.semibold)
                            .foregroundColor(canConfirm ? .white : Color(.systemGray3))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canConfirm ? Color.black : Color(.systemGray5))
                            .cornerRadius(14)
                    }
                    .disabled(!canConfirm)

                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Review Order")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var processingDestination: some View {
        if let o = order {
            PaymentProcessingView(order: o)
        } else {
            EmptyView()
        }
    }

    private func confirmAndPay() {
        let addr = fulfilment == .meetup ? meetupLocation : deliveryAddress
        order = KnotOrder(
            id          : KnotOrder.makeID(),
            listing     : listing,
            buyerName   : profile.name,
            sellerName  : listing.sellerName,
            subtotal    : subtotal,
            knotFeeRate : 0.10,
            fulfilment  : fulfilment,
            address     : addr,
            date        : Date(),
            status      : .paymentReceived,
            escrow      : .held
        )
        navigateToProcessing = true
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

// MARK: - Screen 2: PaymentProcessingView

struct PaymentProcessingView: View {
    let order: KnotOrder
    @State private var navigateToSuccess = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.6)
                    .padding(.bottom, 8)
                Text("Processing payment...")
                    .font(.title3).fontWeight(.semibold)
                Text("Do not close the app")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            NavigationLink(destination: PurchaseSuccessView(order: order), isActive: $navigateToSuccess) {
                EmptyView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                navigateToSuccess = true
            }
        }
    }
}

// MARK: - Screen 3: PurchaseSuccessView

struct PurchaseSuccessView: View {
    let order: KnotOrder
    @State private var showInvoice   = false
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
                    Text("Payment Successful")
                        .font(.title2).fontWeight(.bold)
                    Text("Your payment is held securely until you confirm receipt")
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
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)

                // ── Buttons ───────────────────────────────────────────
                VStack(spacing: 12) {
                    NavigationLink(destination: OrderStatusView(order: order)) {
                        Text("Go to My Orders")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .cornerRadius(14)
                    }

                    Button(action: { showInvoice = true }) {
                        Text("View Invoice")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Order Confirmed")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showInvoice) {
            InvoiceView(order: order)
        }
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

// MARK: - Screen 4: InvoiceView

struct InvoiceView: View {
    let order: KnotOrder
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Header ────────────────────────────────────────
                    VStack(spacing: 6) {
                        KnotIcon(size: 36)
                        Text("Invoice")
                            .font(.title2).fontWeight(.bold)
                        Text(order.id)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(formatDate(order.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Parties ───────────────────────────────────────
                    HStack(alignment: .top, spacing: 0) {
                        partyBlock(role: "Buyer",  name: order.buyerName)
                        Divider()
                        partyBlock(role: "Seller", name: order.sellerName)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Line Item ─────────────────────────────────────
                    VStack(spacing: 0) {
                        HStack {
                            Text("Description").foregroundColor(.secondary).font(.caption)
                            Spacer()
                            Text("Amount").foregroundColor(.secondary).font(.caption)
                        }
                        .padding(.horizontal).padding(.vertical, 10)
                        .background(Color(.systemGray6))

                        HStack {
                            Text(order.listing.name)
                            Spacer()
                            Text(formatSGD(order.subtotal))
                        }
                        .padding()

                        Divider().padding(.horizontal)

                        HStack {
                            Text("Total paid").fontWeight(.semibold)
                            Spacer()
                            Text(formatSGD(order.total)).font(.headline)
                        }
                        .padding()
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Escrow Badge ──────────────────────────────────
                    HStack(spacing: 8) {
                        Image(systemName: order.escrow.icon)
                        Text(order.escrow.label)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(order.escrow.color)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(order.escrow.color.opacity(0.12))
                    .cornerRadius(20)

                    // ── Download ──────────────────────────────────────
                    Button(action: { /* TODO: generate PDF */ }) {
                        Label("Download Invoice", systemImage: "arrow.down.doc")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black)
                            .cornerRadius(14)
                    }
                    .padding(.bottom, 16)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { /* TODO: share sheet */ }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func partyBlock(role: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(name)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

}

// MARK: - Screen 5: OrderStatusView

struct OrderStatusView: View {
    @State var order: KnotOrder
    @State private var showProblemSheet = false
    @State private var timeRemaining    = (41 * 3600) + (23 * 60)   // 41h 23m in seconds
    @State private var timer: Timer?

    private var steps: [(title: String, icon: String)] {
        [
            ("Payment received",
             order.fulfilment == .meetup ? "person.2.fill" : "shippingbox.fill"),
            (order.fulfilment == .meetup ? "Meetup confirmed" : "Delivery in progress",
             order.fulfilment == .meetup ? "mappin.circle.fill" : "truck.box.fill"),
            ("Awaiting your confirmation", "clock.fill"),
            ("Complete",                   "checkmark.circle.fill"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // ── Status Timeline ───────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            // Connector column
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(index <= order.status.rawValue
                                          ? Color.black
                                          : Color(.systemGray4))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Image(systemName: index < order.status.rawValue
                                              ? "checkmark"
                                              : (index == order.status.rawValue ? step.icon : step.icon))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(index <= order.status.rawValue ? .white : Color(.systemGray3))
                                    }
                                if index < steps.count - 1 {
                                    Rectangle()
                                        .fill(index < order.status.rawValue
                                              ? Color.black
                                              : Color(.systemGray5))
                                        .frame(width: 2, height: 36)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.subheadline)
                                    .fontWeight(index == order.status.rawValue ? .semibold : .regular)
                                    .foregroundColor(index <= order.status.rawValue ? .primary : Color(.systemGray3))
                                if index == order.status.rawValue {
                                    Text("In progress")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemOrange))
                                } else if index < order.status.rawValue {
                                    Text("Done")
                                        .font(.caption)
                                        .foregroundColor(Color(.systemGreen))
                                }
                            }
                            .padding(.top, 2)
                            .padding(.bottom, index < steps.count - 1 ? 36 : 0)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)

                // ── Countdown ─────────────────────────────────────────
                if order.escrow == .held {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundColor(Color(.systemOrange))
                        Text("Auto-releases in \(formattedCountdown)")
                            .font(.subheadline)
                            .foregroundColor(Color(.systemOrange))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemOrange).opacity(0.1))
                    .cornerRadius(10)
                }

                // ── Listing Card ──────────────────────────────────────
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: order.listing.type.icon)
                                .foregroundColor(Color(.systemGray2))
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(order.listing.name).font(.subheadline).fontWeight(.semibold)
                        Text(order.id).font(.caption).foregroundColor(.secondary)
                        Text(formatSGD(order.total)).font(.caption).fontWeight(.medium)
                    }
                    Spacer()
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)

                // ── Seller Info ───────────────────────────────────────
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Text(String(order.sellerName.prefix(1)))
                                .font(.subheadline).fontWeight(.semibold)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.sellerName).fontWeight(.semibold)
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(Color(.systemOrange))
                            Text("4.8 · Seller")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: { /* TODO: open message */ }) {
                        Label("Message", systemImage: "message.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color(.systemGray5))
                            .cornerRadius(20)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)

                // ── Action Buttons (step 2 reached) ───────────────────
                if order.status == .awaitingConfirm {
                    VStack(spacing: 12) {
                        Button(action: {
                            withAnimation { order.status = .complete; order.escrow = .released }
                        }) {
                            Label("Confirm Receipt", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGreen))
                                .cornerRadius(14)
                        }

                        Button(action: { showProblemSheet = true }) {
                            Label("There's a Problem", systemImage: "exclamationmark.triangle.fill")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(.systemRed))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemRed).opacity(0.08))
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemRed).opacity(0.3), lineWidth: 1.5))
                        }
                    }
                } else if order.status == .complete {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(.systemGreen))
                        Text("Order Complete")
                            .fontWeight(.semibold)
                            .foregroundColor(Color(.systemGreen))
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGreen).opacity(0.1))
                    .cornerRadius(14)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Order \(order.id)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showProblemSheet) {
            ReportProblemView(orderId: order.id)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private var formattedCountdown: String {
        let h = timeRemaining / 3600
        let m = (timeRemaining % 3600) / 60
        return "\(h)h \(m)m"
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if timeRemaining > 0 { timeRemaining -= 60 }
        }
    }
}

// MARK: - Report Problem Sheet

struct ReportProblemView: View {
    let orderId: String
    @Environment(\.dismiss) var dismiss
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                }
                Section {
                    Button(action: { dismiss() }) {
                        Text("Submit")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .fontWeight(.semibold)
                            .foregroundColor(description.isEmpty ? .gray : .white)
                    }
                    .listRowBackground(description.isEmpty ? Color(.systemGray5) : Color(.systemRed))
                    .disabled(description.isEmpty)
                } footer: {
                    Text("Our team will review your report and reach out within 24 hours.")
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}


// MARK: - SellerPayoutView

struct SellerPayoutView: View {
    let order: KnotOrder
    @Environment(\.dismiss) var dismiss

    private var expectedPayoutDate: String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .hour, value: 72, to: order.date) ?? order.date
        return formatDate(date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Payout Breakdown ──────────────────────────────
                    VStack(spacing: 0) {
                        payoutRow(
                            label  : "Listing price",
                            value  : formatSGD(order.subtotal),
                            color  : .primary
                        )
                        Divider().padding(.horizontal)
                        payoutRow(
                            label  : "Knot fee (\(Int(order.knotFeeRate * 100))%)",
                            value  : "-" + formatSGD(order.knotFee),
                            color  : Color(.systemOrange)
                        )
                        Divider().padding(.horizontal)
                        HStack {
                            Text("You receive")
                                .font(.headline)
                            Spacer()
                            Text(formatSGD(order.payout))
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(Color(.systemGreen))
                        }
                        .padding()
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)

                    // ── Payout Status Badge ───────────────────────────
                    HStack(spacing: 10) {
                        Image(systemName: order.escrow.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.escrow == .held ? "Held in Escrow" : "Released to your account")
                                .fontWeight(.semibold)
                            if order.escrow == .held {
                                Text("Expected release: \(expectedPayoutDate)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .foregroundColor(order.escrow.color)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(order.escrow.color.opacity(0.1))
                    .cornerRadius(14)

                    // ── Order Summary ─────────────────────────────────
                    VStack(spacing: 0) {
                        summaryRow(label: "Order",      value: order.id)
                        Divider().padding(.horizontal)
                        summaryRow(label: "Item",       value: order.listing.name)
                        Divider().padding(.horizontal)
                        summaryRow(label: "Buyer",      value: order.buyerName)
                        Divider().padding(.horizontal)
                        summaryRow(label: "Fulfilment", value: order.fulfilment.rawValue)
                        Divider().padding(.horizontal)
                        summaryRow(label: "Date",       value: formatDate(order.date))
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Payout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func payoutRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(color).fontWeight(.medium)
        }
        .padding()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}

#Preview {
    let listing = sampleListings[0]
    PurchaseConfirmView(listing: listing)
        .environment(UserProfile(name: "Ruhaan"))
}
