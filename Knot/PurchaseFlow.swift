import SwiftUI
import StripePaymentSheet

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
    let fulfilment  : FulfilmentMethod
    var address     : String
    let date        : Date
    var status      : OrderStatus
    var escrow      : EscrowStatus
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
    @State private var deliveryAddress  = ""
    @State private var navigateToProcessing = false
    @State private var order            : KnotOrder?
    @State private var clientSecret     : String?
    @State private var customerId       : String?
    @State private var ephemeralKey     : String?
    @State private var isProcessing     = false
    @State private var showPaymentError = false

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
                                DatePicker(
                                    "Proposed date & time",
                                    selection: $meetupDate,
                                    in: Date()...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .padding(.top, 4)
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
                        Group {
                            if isProcessing {
                                ProgressView().tint(.white)
                            } else {
                                Text("Confirm & Pay").fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(canConfirm ? .white : Color(.systemGray3))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canConfirm ? Color.black : Color(.systemGray5))
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
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Review Order")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Payment Failed", isPresented: $showPaymentError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not create your order. Please try again.")
            }
        }
    }

    @ViewBuilder
    private var processingDestination: some View {
        if let o = order, let cs = clientSecret, let cid = customerId, let ek = ephemeralKey {
            PaymentProcessingView(order: o, clientSecret: cs, customerId: cid, ephemeralKey: ek)
        } else {
            EmptyView()
        }
    }

    private func confirmAndPay() {
        guard !isProcessing else { return }
        isProcessing = true
        let addr = fulfilment == .meetup ? meetupLocation : deliveryAddress
        Task {
            do {
                let (orderID, cs, cid, ek) = try await OrderService.createOrder(
                    listingID      : listing.id,
                    fulfilment     : fulfilment,
                    deliveryAddress: fulfilment == .delivery ? deliveryAddress : "",
                    meetupLocation : fulfilment == .meetup ? meetupLocation : "",
                    meetupDate     : fulfilment == .meetup ? meetupDate : nil
                )
                let newOrder = KnotOrder(
                    id          : orderID,
                    listing     : listing,
                    buyerName   : profile.name,
                    sellerName  : listing.sellerName,
                    sellerId    : listing.sellerID ?? UUID(),
                    buyerId     : profile.currentUserID ?? UUID(),
                    subtotal    : subtotal,
                    knotFeeRate : 0.10,
                    fulfilment  : fulfilment,
                    address     : addr,
                    date        : Date(),
                    status      : .pending,
                    escrow      : .held
                )
                order = newOrder
                clientSecret = cs
                customerId   = cid
                ephemeralKey = ek
                navigateToProcessing = true
            } catch {
                print("[PurchaseConfirmView] createOrder error: \(error)")
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

// MARK: - Screen 2: PaymentProcessingView

struct PaymentProcessingView: View {
    let order: KnotOrder
    let clientSecret: String
    let customerId   : String
    let ephemeralKey : String
    @Environment(UserProfile.self) var profile
    @State private var navigateToSuccess = false
    @State private var paymentSheet: PaymentSheet?
    @State private var showPaymentError = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if let sheet = paymentSheet {
                PaymentSheetWrapper(paymentSheet: sheet, onResult: handlePaymentResult)
            } else {
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
            }

            NavigationLink(destination: PurchaseSuccessView(order: order), isActive: $navigateToSuccess) {
                EmptyView()
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Payment Failed", isPresented: $showPaymentError) {
            Button("Try Again", role: .cancel) {}
        } message: {
            Text("Your payment could not be processed. Please try again.")
        }
        .onAppear {
            profile.orders.insert(order, at: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                initializePaymentSheet()
            }
        }
    }

    private func initializePaymentSheet() {
        var config = PaymentSheet.Configuration()
        config.merchantDisplayName = "Knot"
        config.customer = .init(id: customerId, ephemeralKeySecret: ephemeralKey)
        paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: config)
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            navigateToSuccess = true
        case .canceled:
            showPaymentError = true
        case .failed(let error):
            print("[PaymentProcessingView] Payment failed: \(error)")
            showPaymentError = true
        }
    }
}

struct PaymentSheetWrapper: UIViewControllerRepresentable {
    let paymentSheet: PaymentSheet
    let onResult: (PaymentSheetResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemGroupedBackground
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard !context.coordinator.didPresent else { return }
        context.coordinator.didPresent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let presenter = topViewController() else { return }
            paymentSheet.present(from: presenter) { result in
                onResult(result)
            }
        }
    }

    class Coordinator { var didPresent = false }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return nil }
        guard let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
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
                    NavigationLink(destination: OrderTimelineView(order: order, isSeller: false)) {
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

// MARK: - Invoice Document (renderable content, no chrome)

struct InvoiceDocument: View {
    let order: KnotOrder

    var body: some View {
        VStack(spacing: 20) {

            // Header
            VStack(spacing: 6) {
                KnotIcon(size: 32)
                Text("Invoice").font(.title2).fontWeight(.bold)
                Text(order.id).font(.subheadline).foregroundColor(.secondary)
                Text(formatDate(order.date)).font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Parties
            HStack(alignment: .top, spacing: 0) {
                partyBlock(role: "Buyer",  name: order.buyerName)
                Divider()
                partyBlock(role: "Seller", name: order.sellerName)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Line item
            VStack(spacing: 0) {
                HStack {
                    Text("Description").foregroundColor(.secondary).font(.caption)
                    Spacer()
                    Text("Amount").foregroundColor(.secondary).font(.caption)
                }
                .padding(.horizontal).padding(.vertical, 10)
                .background(Color(UIColor.systemGray6))

                HStack {
                    Text(order.listing.name)
                    Spacer()
                    Text(formatSGD(order.subtotal))
                }
                .padding()

                Divider().padding(.horizontal)

                HStack {
                    Text("Knot service fee")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Charged to seller")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal).padding(.vertical, 10)

                Divider().padding(.horizontal)

                HStack {
                    Text("Total paid").fontWeight(.semibold)
                    Spacer()
                    Text(formatSGD(order.total)).font(.headline)
                }
                .padding()
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)

            // Escrow badge
            HStack(spacing: 8) {
                Image(systemName: order.escrow.icon)
                Text(order.escrow.label).fontWeight(.semibold)
            }
            .foregroundColor(order.escrow.color)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(order.escrow.color.opacity(0.12))
            .cornerRadius(18)

            // Footer
            Text("Generated by Knot · knot.app")
                .font(.caption2)
                .foregroundColor(Color(UIColor.systemGray3))
        }
        .padding(20)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func partyBlock(role: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role).font(.caption).foregroundColor(.secondary)
            Text(name).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

// MARK: - InvoiceView

struct InvoiceView: View {
    let order: KnotOrder
    @Environment(\.dismiss) var dismiss

    @State private var shareImage   : UIImage?   = nil
    @State private var showShare    = false
    @State private var savedToPhoto = false
    @State private var saveError    = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    InvoiceDocument(order: order)
                        .padding(.bottom, 8)

                    // ── Actions ───────────────────────────────────────
                    VStack(spacing: 12) {
                        Button(action: saveToPhotos) {
                            Label("Save as Photo", systemImage: "photo.badge.arrow.down")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.black)
                                .cornerRadius(14)
                        }

                        Button(action: shareInvoice) {
                            Label("Share Invoice", systemImage: "square.and.arrow.up")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(14)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: shareInvoice) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let img = shareImage {
                    ShareSheet(items: [img])
                }
            }
            .alert("Saved to Photos", isPresented: $savedToPhoto) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The invoice has been saved to your photo library.")
            }
            .alert("Could Not Save", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please allow photo library access in Settings and try again.")
            }
        }
    }

    // ── Render invoice to UIImage via ImageRenderer ───────────────
    @MainActor
    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: InvoiceDocument(order: order)
                .frame(width: 390)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3.0   // 3× for crisp @3x output
        return renderer.uiImage
    }

    private func saveToPhotos() {
        guard let img = renderImage() else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        savedToPhoto = true
        // NOTE: add NSPhotoLibraryAddUsageDescription to Info.plist
    }

    private func shareInvoice() {
        guard let img = renderImage() else { return }
        shareImage = img
        showShare  = true
    }
}

// MARK: - UIActivityViewController wrapper

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
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
    let listing = ShopListing(name: "Standing Desk", price: 150, sellerName: "Wei Ming")
    PurchaseConfirmView(listing: listing)
        .environment(UserProfile(name: "Ruhaan"))
}
