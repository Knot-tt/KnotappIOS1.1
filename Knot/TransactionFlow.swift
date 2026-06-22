import SwiftUI

// MARK: - Shared Helpers

private struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.knotSurface)
            .cornerRadius(14)
    }
}

private struct PartyRow: View {
    let name: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.knotSurface)
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.headline).fontWeight(.semibold)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private struct ListingMiniCard: View {
    let listing: ShopListing
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.knotSurface)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: listing.type.icon)
                        .foregroundColor(Color.knotMuted)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name).font(.subheadline).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
                Text(formatSGD(listing.price * 100)).font(.caption).fontWeight(.medium)
            }
            Spacer()
        }
        .padding()
        .background(Color.knotSurface)
        .cornerRadius(14)
    }
}

private struct CountdownBadge: View {
    let secondsRemaining: Int
    let icon: String
    let tint: Color
    let prefix: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text("\(prefix)\(formattedTime)")
                .font(.subheadline).fontWeight(.medium)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.1))
        .cornerRadius(10)
    }

    private var formattedTime: String {
        let h = secondsRemaining / 3600
        let m = (secondsRemaining % 3600) / 60
        let s = secondsRemaining % 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m \(s)s"
    }
}

// MARK: - Screen 1: SellerNewOrderView

struct SellerNewOrderView: View {
    @Binding var order: KnotOrder
    var onAccepted: () -> Void = {}
    var onDeclined: () -> Void = {}

    @Environment(UserProfile.self) private var profile
    @State private var secondsRemaining    = 86_400   // 24h
    @State private var timer               : Timer?
    @State private var navigateToPropose   = false
    @State private var navigateToConfirmed = false
    @State private var navigateToTimeline  = false
    @State private var showDeclineConfirm  = false
    @State private var isAccepting         = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Listing Summary ───────────────────────────────
                    ListingMiniCard(listing: order.listing,
                                    subtitle: order.listing.type.rawValue)

                    // ── Buyer Info ────────────────────────────────────
                    SectionCard {
                        PartyRow(name: order.buyerName, subtitle: "Buyer")
                            .padding()
                    }

                    // ── Countdown ────────────────────────────────────
                    CountdownBadge(
                        secondsRemaining: secondsRemaining,
                        icon: "timer",
                        tint: secondsRemaining < 3600 ? Color(.systemRed) : Color(.systemOrange),
                        prefix: "Respond within "
                    )

                    // ── Buyer's Proposed Meetup ───────────────────────
                    if let proposal = order.meetupProposal, proposal.proposedBy == "buyer" {
                        SectionCard {
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(Color(.systemRed))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Buyer's proposed meetup")
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(proposal.location).fontWeight(.medium)
                                    }
                                    Spacer()
                                }
                                .padding()
                                Divider().padding(.horizontal)
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar.circle.fill")
                                        .foregroundColor(Color(.systemBlue))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Date & Time")
                                            .font(.caption).foregroundColor(.secondary)
                                        Text(formatDate(proposal.date)).fontWeight(.medium)
                                    }
                                    Spacer()
                                }
                                .padding()
                            }
                        }
                    }

                    // ── Actions ───────────────────────────────────────
                    NavigationLink(
                        destination: SellerProposeMeetupView(order: $order, onSent: onAccepted),
                        isActive: $navigateToPropose
                    ) { EmptyView() }

                    NavigationLink(
                        destination: MeetupConfirmedView(order: order, isSeller: true),
                        isActive: $navigateToConfirmed
                    ) { EmptyView() }

                    NavigationLink(
                        destination: OrderTimelineView(order: order, isSeller: true),
                        isActive: $navigateToTimeline
                    ) { EmptyView() }

                    if order.status == .pending {
                        Button(action: acceptOrder) {
                            Group {
                                if isAccepting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Label("Accept Order", systemImage: "checkmark.circle.fill")
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isAccepting ? Color(.systemGreen).opacity(0.6) : Color(.systemGreen))
                            .cornerRadius(14)
                        }
                        .disabled(isAccepting)
                    }

                    if order.meetupProposal?.proposedBy == "buyer" {
                        Button(action: acceptBuyerMeetup) {
                            Label("Accept Meetup", systemImage: "mappin.and.ellipse")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.knotSurface)
                                .cornerRadius(14)
                        }
                        Button(action: { navigateToPropose = true }) {
                            Text("Propose New Meetup")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.knotSurface)
                                .cornerRadius(14)
                        }
                    } else if order.fulfilment == .meetup {
                        Button(action: { navigateToPropose = true }) {
                            Label("Propose Meetup", systemImage: "mappin.circle.fill")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.knotSurface)
                                .cornerRadius(14)
                        }
                    }

                    Button(action: { showDeclineConfirm = true }) {
                        Text("Decline Order")
                            .fontWeight(.semibold)
                            .foregroundColor(Color(.systemRed))
                    }
                    .padding(.bottom, 8)
                }
                .padding()
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("New Order")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Decline Order", isPresented: $showDeclineConfirm, titleVisibility: .visible) {
                Button("Decline Order", role: .destructive) {
                    Task {
                        try? await OrderService.cancelOrder(orderID: order.id)
                        order.status = .cancelled
                        order.stepDates["cancelled"] = Date()
                        onDeclined()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text(order.isCash
                ? "This order will be cancelled. This cannot be undone."
                : "The buyer will be refunded. This cannot be undone.") }
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }
        }
    }

    private func acceptOrder() {
        guard !isAccepting else { return }
        isAccepting = true
        Task {
            do {
                try await OrderService.acceptOrder(orderID: order.id)
                order.status = .sellerAccepted
                order.stepDates["seller_accepted"] = Date()
                onAccepted()
                navigateToTimeline = true
            } catch {
                print("[acceptOrder] error: \(error)")
            }
            await MainActor.run { isAccepting = false }
        }
    }

    private func acceptBuyerMeetup() {
        Task {
            do {
                try await OrderService.acceptMeetup(orderID: order.id)
                let now = Date()
                order.status = .meetupAgreed
                order.stepDates["seller_accepted"] = now
                order.stepDates["meetup_agreed"]   = now
                onAccepted()
                await profile.loadOrders()
                // Accepting the meetup goes straight back to the Hub.
                profile.closeOrdersFlowSignal.toggle()
            } catch {
                print("[acceptBuyerMeetup] error: \(error)")
            }
        }
    }

    private func startTimer() {
        let elapsed = Int(Date().timeIntervalSince(order.date))
        secondsRemaining = max(0, 86_400 - elapsed)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
            else {
                timer?.invalidate()
                Task {
                    try? await OrderService.cancelOrder(orderID: order.id)
                    await MainActor.run {
                        order.status = .cancelled
                        order.stepDates["cancelled"] = Date()
                        onDeclined()
                    }
                }
            }
        }
    }
}

// MARK: - Screen 2: SellerProposeMeetupView

struct SellerProposeMeetupView: View {
    @Binding var order: KnotOrder
    var onSent: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) private var profile

    @State private var location = ""
    @State private var meetupDate = Date().addingTimeInterval(86_400)
    @State private var isSending = false
    @State private var errorMessage: String? = nil

    private var canSend: Bool { !location.trimmingCharacters(in: .whitespaces).isEmpty && !isSending }
    private var isReproposal: Bool { order.meetupProposal?.proposedBy == "buyer" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                ListingMiniCard(listing: order.listing,
                                subtitle: "Buyer: \(order.buyerName)")

                SectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(Color(.systemRed))
                            TextField("e.g. Bishan MRT Exit A", text: $location)
                        }
                        .padding()
                        Divider().padding(.horizontal)
                        DatePicker(
                            "Date & Time",
                            selection: $meetupDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(.systemRed))
                        .multilineTextAlignment(.center)
                }

                Button(action: sendProposal) {
                    Group {
                        if isSending {
                            ProgressView().tint(Color.knotOnAccent)
                        } else {
                            Text(isReproposal ? "Send New Proposal" : "Send Proposal")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(canSend ? Color.knotOnAccent : Color.knotMuted)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSend ? Color.knotAccent : Color.knotSurface)
                    .cornerRadius(14)
                }
                .disabled(!canSend)
            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle(isReproposal ? "Propose New Meetup" : "Propose Meetup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if location.isEmpty, let proposal = order.meetupProposal {
                location = proposal.location
                meetupDate = max(proposal.date, Date().addingTimeInterval(60))
            }
        }
    }

    private func sendProposal() {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await OrderService.proposeMeetup(
                    orderID   : order.id,
                    location  : location,
                    date      : meetupDate,
                    proposedBy: "seller",
                    resetProgressToPending: isReproposal
                )
                order.meetupProposal = MeetupProposal(location: location, date: meetupDate, proposedBy: "seller")
                if isReproposal {
                    order.status = .pending
                    order.stepDates.removeValue(forKey: "seller_accepted")
                    order.stepDates.removeValue(forKey: "meetup_agreed")
                } else {
                    order.status = .sellerAccepted
                    order.stepDates["seller_accepted"] = Date()
                }
                await profile.loadOrders()
                if let updated = profile.orders.first(where: { $0.id == order.id }) {
                    order = updated
                }
                if isReproposal {
                    order.status = .pending
                    order.stepDates.removeValue(forKey: "seller_accepted")
                    order.stepDates.removeValue(forKey: "meetup_agreed")
                }
                onSent()
                // Proposing the meetup goes straight back to the Hub.
                profile.closeOrdersFlowSignal.toggle()
            } catch {
                print("[sendProposal] error: \(error)")
                errorMessage = "Could not send meetup proposal. Please try again."
            }
            await MainActor.run { isSending = false }
        }
    }
}

// MARK: - Screen 3: BuyerMeetupProposalView

struct BuyerMeetupProposalView: View {
    @Binding var order: KnotOrder
    var onAccepted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfile.self) private var profile
    @State private var navigateToSuggest   = false
    @State private var showDeclineConfirm  = false
    @State private var isDeclining         = false

    private var proposal: MeetupProposal? { order.meetupProposal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Seller Info ───────────────────────────────────
                    SectionCard {
                        PartyRow(name: order.sellerName, subtitle: "Seller")
                            .padding()
                    }

                    // ── Proposal Details ──────────────────────────────
                    if let p = proposal {
                        SectionCard {
                            VStack(spacing: 0) {
                                proposalRow(icon: "mappin.circle.fill",
                                            color: Color(.systemRed),
                                            label: "Location",
                                            value: p.location)
                                Divider().padding(.horizontal)
                                proposalRow(icon: "calendar.circle.fill",
                                            color: Color(.systemBlue),
                                            label: "Date & Time",
                                            value: formatDate(p.date))
                            }
                        }
                    }

                    // ── Actions ───────────────────────────────────────
                    NavigationLink(
                        destination: BuyerSuggestAlternativeView(order: $order),
                        isActive: $navigateToSuggest
                    ) { EmptyView() }

                    Button(action: acceptMeetup) {
                        Label("Accept Meetup", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGreen))
                            .cornerRadius(14)
                    }

                    Button(action: { navigateToSuggest = true }) {
                        Text("Suggest Different Time")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotSurface)
                            .cornerRadius(14)
                    }

                    Button(action: { showDeclineConfirm = true }) {
                        Group {
                            if isDeclining {
                                ProgressView().tint(.red)
                            } else {
                                Label("Decline & Cancel Order", systemImage: "xmark.circle")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(.systemRed))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemRed).opacity(0.08))
                        .cornerRadius(14)
                    }
                    .disabled(isDeclining)
                }
                .padding()
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Meetup Proposed")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Decline Meetup", isPresented: $showDeclineConfirm, titleVisibility: .visible) {
                Button("Decline & Cancel Order", role: .destructive) {
                    declineOrder()
                }
                Button("Keep Reviewing", role: .cancel) {}
            } message: {
                Text("This cancels the order for both parties. This cannot be undone.")
            }
        }
    }

    private func acceptMeetup() {
        Task {
            do {
                try await OrderService.acceptMeetup(orderID: order.id)
                order.status = .meetupAgreed
                order.stepDates["meetup_agreed"] = Date()
                onAccepted()
                await profile.loadOrders()
                // Accepting the meetup goes straight back to the Hub.
                profile.closeOrdersFlowSignal.toggle()
            } catch {
                print("[acceptMeetup] error: \(error)")
            }
        }
    }

    private func declineOrder() {
        guard !isDeclining else { return }
        isDeclining = true
        Task {
            do {
                try await OrderService.cancelOrder(orderID: order.id)
                order.status = .cancelled
                order.stepDates["cancelled"] = Date()
                dismiss()
            } catch {
                print("[declineOrder] error: \(error)")
            }
            await MainActor.run { isDeclining = false }
        }
    }

    private func proposalRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(value).fontWeight(.medium)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Screen 4: BuyerSuggestAlternativeView

struct BuyerSuggestAlternativeView: View {
    @Binding var order: KnotOrder
    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) private var profile

    @State private var location   = ""
    @State private var meetupDate = Date().addingTimeInterval(86_400)
    @State private var sent       = false
    @State private var isSending  = false
    @State private var errorMessage: String? = nil

    private var canSend: Bool { !location.trimmingCharacters(in: .whitespaces).isEmpty && !isSending }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                Text("The seller will be notified of your suggestion and can accept or propose again.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(Color(.systemRed))
                            TextField("e.g. Bishan MRT Exit A", text: $location)
                        }
                        .padding()
                        Divider().padding(.horizontal)
                        DatePicker(
                            "Date & Time",
                            selection: $meetupDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .padding()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(.systemRed))
                        .multilineTextAlignment(.center)
                }

                Button(action: sendSuggestion) {
                    Group {
                        if isSending {
                            ProgressView().tint(Color.knotOnAccent)
                        } else {
                            Text("Send Suggestion")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(canSend ? Color.knotOnAccent : Color.knotMuted)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSend ? Color.knotAccent : Color.knotSurface)
                    .cornerRadius(14)
                }
                .disabled(!canSend)
            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Suggest Alternative")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if location.isEmpty, let proposal = order.meetupProposal {
                location = proposal.location
                meetupDate = max(proposal.date, Date().addingTimeInterval(60))
            }
        }
        .alert("Suggestion Sent", isPresented: $sent) {
            Button("OK") { dismiss() }
        } message: {
            Text("The seller has been notified. You'll hear back shortly.")
        }
    }

    private func sendSuggestion() {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await OrderService.proposeMeetup(
                    orderID   : order.id,
                    location  : location,
                    date      : meetupDate,
                    proposedBy: "buyer"
                )
                order.meetupProposal = MeetupProposal(location: location, date: meetupDate, proposedBy: "buyer")
                order.status = .sellerAccepted
                order.stepDates["seller_accepted"] = order.stepDates["seller_accepted"] ?? Date()
                await profile.loadOrders()
                if let updated = profile.orders.first(where: { $0.id == order.id }) {
                    order = updated
                }
                sent = true
            } catch {
                print("[sendSuggestion] error: \(error)")
                errorMessage = "Could not send meetup suggestion. Please try again."
            }
            await MainActor.run { isSending = false }
        }
    }
}

// MARK: - Screen 5: MeetupConfirmedView

struct MeetupConfirmedView: View {
    let order: KnotOrder
    let isSeller: Bool
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var checkScale:   CGFloat = 0.3
    @State private var checkOpacity: Double  = 0

    private var otherParty: String { isSeller ? order.buyerName : order.sellerName }
    private var otherPartyID: UUID { isSeller ? order.buyerId : order.sellerId }
    private var proposal: MeetupProposal? { order.meetupProposal }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                // ── Animated Checkmark ────────────────────────────────
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(Color(.systemGreen))
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
                    .padding(.top, 24)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            checkScale = 1.0; checkOpacity = 1.0
                        }
                    }

                VStack(spacing: 6) {
                    Text("Meetup Confirmed")
                        .font(.title2).fontWeight(.bold)
                    Text(isSeller
                         ? "Meet up and hand over the item. The order closes once the buyer confirms receipt."
                         : "Meet up and collect the item. Then press \"I Received the Item\" to close the order.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // ── Meetup Details Card ───────────────────────────────
                if let p = proposal {
                    SectionCard {
                        VStack(spacing: 0) {
                            meetupDetailRow(icon: "mappin.circle.fill",
                                            color: Color(.systemRed),
                                            value: p.location)
                            Divider().padding(.horizontal)
                            meetupDetailRow(icon: "calendar.circle.fill",
                                            color: Color(.systemBlue),
                                            value: formatDate(p.date))
                            Divider().padding(.horizontal)
                            HStack(spacing: 12) {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(Color.knotMuted)
                                    .frame(width: 28)
                                Circle()
                                    .fill(Color.knotSurface)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        Text(String(otherParty.prefix(1)))
                                            .font(.caption).fontWeight(.semibold)
                                    }
                                Text(otherParty).fontWeight(.medium)
                                Spacer()
                            }
                            .padding()
                        }
                    }
                }

                // ── Role reminder ─────────────────────────────────────
                HStack(spacing: 10) {
                    Image(systemName: isSeller ? "bell.fill" : "hand.tap.fill")
                        .foregroundColor(isSeller ? Color(.systemOrange) : Color(.systemGreen))
                    Text(isSeller
                         ? "Remind \(otherParty) to tap \"I Received the Item\" in the order page after the exchange."
                         : "After you receive the item, open the order and tap \"I Received the Item\" to close the order.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSeller ? Color(.systemOrange).opacity(0.08) : Color(.systemGreen).opacity(0.08))
                .cornerRadius(14)

                // ── Buttons ───────────────────────────────────────────
                NavigationLink(destination: OrderTimelineView(order: order, isSeller: isSeller)) {
                    Text("View Order")
                        .fontWeight(.semibold)
                        .foregroundColor(Color.knotOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.knotAccent)
                        .cornerRadius(14)
                }

                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        profile.openConversation(withUserID: otherPartyID, name: otherParty)
                    }
                }) {
                    Label("Message \(otherParty)", systemImage: "message.fill")
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.knotSurface)
                        .cornerRadius(14)
                }
            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Meetup Confirmed")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    private func meetupDetailRow(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            Text(value).fontWeight(.medium)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Screen 6: BuyerConfirmReceiptView

struct BuyerConfirmReceiptView: View {
    @Binding var order: KnotOrder
    var onConfirmed: () -> Void = {}
    @Environment(\.dismiss) var dismiss

    @State private var secondsRemaining = (41 * 3600) + (23 * 60)
    @State private var timer: Timer?
    @State private var navigateToProblem  = false
    @State private var navigateToComplete = false
    @State private var isConfirming       = false
    @State private var confirmError       = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Listing + Seller ──────────────────────────────
                    ListingMiniCard(listing: order.listing,
                                    subtitle: "Seller: \(order.sellerName)")

                    // ── Payment reminder ──────────────────────────────
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "banknote")
                            .font(.title2)
                            .foregroundColor(Color(.systemGreen))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cash payment")
                                .fontWeight(.semibold)
                            Text("Confirm you've collected the item and paid the seller in cash.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGreen).opacity(0.08))
                    .cornerRadius(14)

                    // ── Actions ───────────────────────────────────────
                    NavigationLink(
                        destination: ProblemReportView(order: $order),
                        isActive: $navigateToProblem
                    ) { EmptyView() }

                    Button(action: { Task { await confirmReceipt() } }) {
                        Group {
                            if isConfirming {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Label("I Received the Item",
                                      systemImage: "checkmark.circle.fill")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isConfirming ? Color(.systemGreen).opacity(0.6) : Color(.systemGreen))
                        .cornerRadius(14)
                    }
                    .disabled(isConfirming)

                    Button(action: { navigateToProblem = true }) {
                        Text("There's a Problem")
                            .fontWeight(.semibold)
                            .foregroundColor(Color(.systemRed))
                    }
                    .padding(.bottom, 8)
                }
                .padding()
            }
            .background(Color.knotBackground.ignoresSafeArea())
            .navigationTitle("Did you receive your item?")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }
            .navigationDestination(isPresented: $navigateToComplete) {
                TransactionCompleteView(order: order, isSeller: false)
            }
            .alert("Could not close order", isPresented: $confirmError) {
                Button("Try Again") { Task { await confirmReceipt() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Something went wrong. Please try again.")
            }
        }
    }

    private func confirmReceipt() async {
        guard !isConfirming else { return }
        isConfirming = true
        do {
            try await OrderService.markCashOrderComplete(orderID: order.id)
            timer?.invalidate()
            order.status = .complete
            order.escrow = .released
            order.stepDates["awaiting_confirmation"] = Date()
            order.stepDates["complete"] = Date()
            onConfirmed()
            navigateToComplete = true
        } catch {
            confirmError = true
            isConfirming = false
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
            else {
                timer?.invalidate()
                Task { await confirmReceipt() }
            }
        }
    }
}

// MARK: - Screen 7: ProblemReportView

struct ProblemReportView: View {
    @Binding var order: KnotOrder
    @Environment(\.dismiss) var dismiss

    enum ProblemType: String, CaseIterable {
        case notAsDescribed = "Item not as described"
        case noShow         = "Seller did not show up"
        case damaged        = "Item damaged"
        case other          = "Other"
    }

    @State private var problemType : ProblemType? = nil
    @State private var description = ""
    @State private var submitted   = false

    private var canSubmit: Bool {
        problemType != nil && !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(Color(.systemOrange))
                    Text("Your payment will remain frozen until this is resolved by Knot.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemOrange).opacity(0.1))
                .cornerRadius(12)

                // ── Problem Type ──────────────────────────────────────
                SectionCard {
                    VStack(spacing: 0) {
                        ForEach(ProblemType.allCases, id: \.self) { type in
                            Button(action: { problemType = type }) {
                                HStack {
                                    Text(type.rawValue)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if problemType == type {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(.systemBlue))
                                    }
                                }
                                .padding()
                            }
                            if type != ProblemType.allCases.last {
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                }

                // ── Description ───────────────────────────────────────
                SectionCard {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .padding(8)
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Describe the issue...")
                                    .foregroundColor(Color.knotMuted)
                                    .padding(14)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // ── Submit ────────────────────────────────────────────
                Button(action: submitReport) {
                    Text("Submit Report")
                        .fontWeight(.semibold)
                        .foregroundColor(canSubmit ? .white : Color.knotMuted)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSubmit ? Color(.systemRed) : Color.knotSurface)
                        .cornerRadius(14)
                }
                .disabled(!canSubmit)

                Button("Cancel") { dismiss() }
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Report Submitted", isPresented: $submitted) {
            Button("OK") { dismiss() }
        } message: {
            Text("Our team will review your report within 24 hours. Your payment remains frozen.")
        }
    }

    private func submitReport() {
        Task {
            try? await OrderService.disputeOrder(orderID: order.id)
            order.status = .disputed
            submitted = true
        }
    }
}

// MARK: - Screen 8: TransactionCompleteView

struct TransactionCompleteView: View {
    let order: KnotOrder
    let isSeller: Bool
    @State private var checkScale    : CGFloat = 0.3
    @State private var checkOpacity  : Double  = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(.systemGreen))
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
                    .padding(.top, 32)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            checkScale = 1.0; checkOpacity = 1.0
                        }
                    }

                VStack(spacing: 8) {
                    Text("Transaction Complete")
                        .font(.title2).fontWeight(.bold)
                    Text("Thanks for using Knot!")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

            }
            .padding()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Transaction Complete")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Screen 9: TransactionCancelledView

struct TransactionCancelledView: View {
    var onBrowse: () -> Void = {}
    @State private var xScale   : CGFloat = 0.3
    @State private var xOpacity : Double  = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(Color(.systemRed))
                .scaleEffect(xScale)
                .opacity(xOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        xScale = 1.0; xOpacity = 1.0
                    }
                }

            VStack(spacing: 10) {
                Text("Order Cancelled")
                    .font(.title2).fontWeight(.bold)
                Text("The seller did not respond in time.\nThis order has been cancelled.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onBrowse) {
                Text("Browse More Listings")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(14)
            }
            .padding(.horizontal)

            Spacer()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Order Cancelled")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Screen 10: OrderTimelineView

struct OrderTimelineView: View {
    var order: KnotOrder
    let isSeller: Bool
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var navigateToReceipt      = false
    @State private var navigateToComplete     = false
    @State private var navigateToAccept       = false
    @State private var navigateToMeetupReview = false
    @State private var showBuyerCancelConfirm = false
    @State private var isCancelling           = false
    @State private var mutableOrder: KnotOrder? = nil
    @State private var refreshTimer: Timer?     = nil

    private var liveOrder: KnotOrder { mutableOrder ?? order }
    private var isAwaitingBuyerOnSellerProposal: Bool {
        liveOrder.fulfilment == .meetup &&
        liveOrder.meetupProposal?.proposedBy == "seller" &&
        (liveOrder.status == .pending || liveOrder.status == .sellerAccepted)
    }

    private struct TimelineStep {
        let status  : String
        let label   : String
        let icon    : String
    }

    private let steps: [TimelineStep] = [
        TimelineStep(status: "pending",               label: "Order placed",         icon: "bag.fill"),
        TimelineStep(status: "seller_accepted",        label: "Seller accepted",      icon: "person.badge.checkmark.fill"),
        TimelineStep(status: "meetup_agreed",          label: "Meetup agreed",        icon: "mappin.circle.fill"),
        TimelineStep(status: "awaiting_confirmation",  label: "Receipt confirmed",    icon: "checkmark.circle.fill"),
        TimelineStep(status: "complete",               label: "Complete",             icon: "star.circle.fill"),
    ]

    private func isComplete(_ step: TimelineStep) -> Bool {
        if isAwaitingBuyerOnSellerProposal && step.status == OrderStatus.pending.rawValue {
            return false
        }
        if isAwaitingBuyerOnSellerProposal && step.status == OrderStatus.sellerAccepted.rawValue {
            return false
        }
        return liveOrder.stepDates[step.status] != nil || liveOrder.status.rawValue == step.status
    }

    private func isCurrent(_ step: TimelineStep) -> Bool {
        if isAwaitingBuyerOnSellerProposal && step.status == OrderStatus.pending.rawValue {
            return true
        }
        let currentStatus = isAwaitingBuyerOnSellerProposal ? OrderStatus.pending.rawValue : liveOrder.status.rawValue
        return currentStatus == step.status && liveOrder.stepDates[step.status] == nil
    }

    private var proposal: MeetupProposal? { liveOrder.meetupProposal }

    private var currentActionLabel: String {
        switch liveOrder.status {
        case .pending:
            return isAwaitingBuyerOnSellerProposal
                ? "Meetup proposed — waiting for buyer response"
                : "Waiting for seller to accept"
        case .sellerAccepted:
            return isAwaitingBuyerOnSellerProposal
                ? "Meetup proposed — waiting for buyer response"
                : "Meetup proposed — waiting for your confirmation"
        case .meetupAgreed:         return isSeller ? "Message Buyer" : "Message Seller"
        case .awaitingConfirmation: return isSeller ? "Awaiting buyer confirmation" : "Confirm Receipt"
        case .complete:             return "Done"
        case .disputed:             return "Under Review by Knot"
        case .cancelled:            return "Browse Listings"
        }
    }

    /// Statuses where we want the bottom action button pinned to the safe area
    /// (i.e. anything that needs an active CTA — pending, accept, review meetup,
    /// confirm receipt). Terminal states (complete/cancelled/disputed) just show
    /// their static banner inline, no pinned footer needed.
    private var hasPinnedAction: Bool {
        switch liveOrder.status {
        case .complete, .cancelled, .disputed: return false
        default: return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Cash payment badge ────────────────────────────────
                if liveOrder.isCash && liveOrder.status != .cancelled && liveOrder.status != .complete {
                    HStack(spacing: 10) {
                        Image(systemName: "banknote")
                            .foregroundColor(Color(.systemGreen))
                        Text("Cash payment — pay the \(isSeller ? "buyer" : "seller") in person when you meet.")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(14)
                    .background(Color(.systemGreen).opacity(0.08))
                    .cornerRadius(14)
                }

                // ── Timeline ──────────────────────────────────────────
                SectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        if liveOrder.status == .disputed {
                            disputedBanner
                        } else if liveOrder.status == .cancelled {
                            cancelledBanner
                        } else {
                            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                                timelineRow(step: step, idx: idx)
                            }
                        }
                    }
                    .padding()
                }

                // ── Meetup Details ────────────────────────────────────
                if let p = proposal, liveOrder.status == .meetupAgreed || liveOrder.status == .awaitingConfirmation || liveOrder.status == .complete {
                    SectionCard {
                        VStack(spacing: 0) {
                            detailRow(icon: "mappin.circle.fill", color: Color(.systemRed),  label: "Location", value: p.location)
                            Divider().padding(.horizontal)
                            detailRow(icon: "calendar.circle.fill", color: Color(.systemBlue), label: "Date & Time", value: formatDate(p.date))
                        }
                    }
                }

                // ── Listing Summary ───────────────────────────────────
                ListingMiniCard(listing: liveOrder.listing, subtitle: liveOrder.id)

                // ── Other Party ───────────────────────────────────────
                SectionCard {
                    HStack(spacing: 12) {
                        PartyRow(name: isSeller ? order.buyerName : order.sellerName,
                                 subtitle: isSeller ? "Buyer" : "Seller")
                        Button(action: openMessage) {
                            Label("Message", systemImage: "message.fill")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.knotSurface)
                                .cornerRadius(20)
                        }
                    }
                    .padding()
                }

                // ── Current Action Button ─────────────────────────────
                NavigationLink(
                    destination: BuyerConfirmReceiptView(
                        order: Binding(
                            get: { mutableOrder ?? order },
                            set: { mutableOrder = $0 }
                        ),
                        onConfirmed: {
                            // Remove the listing from the Hub once the sale is confirmed,
                            // unless the seller marked it as recurring.
                            Task { await profile.deleteSoldListing(listingID: liveOrder.listing.id) }
                        }
                    ),
                    isActive: $navigateToReceipt
                ) { EmptyView() }

                NavigationLink(
                    destination: TransactionCompleteView(order: liveOrder, isSeller: isSeller),
                    isActive: $navigateToComplete
                ) { EmptyView() }

                if !isSeller && isAwaitingBuyerOnSellerProposal {
                    NavigationLink(
                        destination: BuyerMeetupProposalView(
                            order: Binding(
                                get: { mutableOrder ?? order },
                                set: { mutableOrder = $0 }
                            )
                        ),
                        isActive: $navigateToMeetupReview
                    ) { EmptyView() }
                }

                if isSeller && (
                    liveOrder.status == .pending ||
                    (liveOrder.status == .sellerAccepted && liveOrder.fulfilment == .meetup && (
                        liveOrder.meetupProposal == nil || liveOrder.meetupProposal?.proposedBy == "buyer"
                    ))
                ) {
                    NavigationLink(
                        destination: SellerNewOrderView(
                            order: Binding(
                                get: { mutableOrder ?? order },
                                set: { mutableOrder = $0 }
                            )
                        ),
                        isActive: $navigateToAccept
                    ) { EmptyView() }
                }

                // ── Complete banner (seller) ──────────────────────────
                if isSeller && liveOrder.status == .complete {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundColor(Color(.systemGreen))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Order Complete")
                                .fontWeight(.semibold)
                            Text("This transaction has been completed successfully.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.systemGreen).opacity(0.1))
                    .cornerRadius(14)
                }

                // Add bottom spacing for terminal states so the inline action
                // button isn't flush against the navigation bar.
                if !hasPinnedAction { actionButton }
            }
            .padding()
        }
        // Pin the action button to the bottom safe area for active states.
        // safeAreaInset is the SwiftUI-native way to keep a CTA visible
        // above a ScrollView — same pattern as Apple Pay / Wallet.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasPinnedAction {
                VStack(spacing: 0) {
                    Divider()
                    actionButton
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        // Anchor the cancel confirmation popover directly to
                        // the action button so it visibly points at what
                        // triggered it — not floating mid-screen or pinned
                        // to the bottom.
                        .popover(isPresented: $showBuyerCancelConfirm, arrowEdge: .bottom) {
                            ConfirmPopoverContent(
                                title  : "Cancel Order?",
                                message: liveOrder.isCash
                                    ? "This order will be cancelled. This cannot be undone."
                                    : "Your payment will be refunded within 3–5 business days. This cannot be undone.",
                                confirmLabel: liveOrder.isCash ? "Cancel Order" : "Cancel & Get a Refund",
                                onConfirm: {
                                    showBuyerCancelConfirm = false
                                    cancelOrderNow()
                                },
                                onCancel: { showBuyerCancelConfirm = false }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                }
                .background(Color.knotBackground)
            }
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Order \(liveOrder.id)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if mutableOrder == nil { mutableOrder = order }
            await profile.loadOrders()
            if let updated = profile.orders.first(where: { $0.id == order.id }) {
                mutableOrder = updated
            }
            // Poll every 12s while meetup is agreed — waiting for buyer to confirm receipt
            if liveOrder.status == .meetupAgreed || liveOrder.status == .awaitingConfirmation {
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { _ in
                    Task {
                        await profile.loadOrders()
                        await MainActor.run {
                            if let updated = profile.orders.first(where: { $0.id == order.id }) {
                                mutableOrder = updated
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { refreshTimer?.invalidate(); refreshTimer = nil }
        // Cancel confirmation is now a popover anchored to the action button
        // (see safeAreaInset above) — visually points at its trigger instead
        // of appearing as a centered alert or bottom sheet.
    }

    private func cancelOrderNow() {
        isCancelling = true
        Task {
            try? await OrderService.cancelOrder(orderID: liveOrder.id)
            await profile.loadOrders()
            await MainActor.run {
                if let updated = profile.orders.first(where: { $0.id == liveOrder.id }) {
                    mutableOrder = updated
                }
                isCancelling = false
                profile.closeOrdersFlowSignal.toggle()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch liveOrder.status {
        case .pending where isSeller && isAwaitingBuyerOnSellerProposal:
            VStack(spacing: 10) {
                statusPill(label: "Waiting for buyer to accept or re-propose your meetup", color: Color(.systemBlue))
                Button(action: openMessage) {
                    Label("Message Buyer", systemImage: "message.fill")
                        .fontWeight(.semibold)
                        .foregroundColor(Color.knotOnAccent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.knotAccent)
                        .cornerRadius(14)
                }
            }

        case .pending where !isSeller && isAwaitingBuyerOnSellerProposal:
            VStack(spacing: 10) {
                Button(action: { navigateToMeetupReview = true }) {
                    Label("Review Meetup", systemImage: "mappin.and.ellipse")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.knotAccent)
                        .cornerRadius(14)
                }
                Button(action: { showBuyerCancelConfirm = true }) {
                    Group {
                        if isCancelling {
                            ProgressView().tint(.red)
                        } else {
                            Label("Cancel Order", systemImage: "xmark.circle")
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemRed).opacity(0.08))
                    .cornerRadius(14)
                }
                .disabled(isCancelling)
            }

        case .pending where isSeller:
            Button(action: { navigateToAccept = true }) {
                Label("Review & Accept Order", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGreen))
                    .cornerRadius(14)
            }

        case .pending:
            // Buyer is waiting — show status + allow cancel while no meetup is locked in.
            VStack(spacing: 10) {
                statusPill(label: "Waiting for seller to accept", color: Color(.systemOrange))
                Button(action: { showBuyerCancelConfirm = true }) {
                    Group {
                        if isCancelling {
                            ProgressView().tint(.red)
                        } else {
                            Label("Cancel Order", systemImage: "xmark.circle")
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemRed).opacity(0.08))
                    .cornerRadius(14)
                }
                .disabled(isCancelling)
            }

        case .sellerAccepted where !isSeller:
            // Buyer: seller has proposed or counter-proposed a meetup.
            VStack(spacing: 10) {
                if liveOrder.meetupProposal?.proposedBy == "seller" {
                    Button(action: { navigateToMeetupReview = true }) {
                        Label("Review Meetup", systemImage: "mappin.and.ellipse")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotAccent)
                            .cornerRadius(14)
                    }
                } else {
                    statusPill(label: "Meetup proposed — awaiting your confirmation", color: Color(.systemBlue))
                }

                Button(action: { showBuyerCancelConfirm = true }) {
                    Group {
                        if isCancelling {
                            ProgressView().tint(.red)
                        } else {
                            Label("Cancel Order", systemImage: "xmark.circle")
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemRed).opacity(0.08))
                    .cornerRadius(14)
                }
                .disabled(isCancelling)
            }

        case .sellerAccepted:
            if isSeller && liveOrder.fulfilment == .meetup && liveOrder.meetupProposal?.proposedBy == "buyer" {
                VStack(spacing: 12) {
                    statusPill(label: "Buyer proposed a meetup — send a new proposal or accept it", color: Color(.systemBlue))
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(Color(.systemOrange))
                        Text("After the handoff, remind the buyer to tap \"I Received the Item\" to close the order.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemOrange).opacity(0.08))
                    .cornerRadius(12)

                    Button(action: { navigateToAccept = true }) {
                        Label("Propose New Meetup", systemImage: "mappin.and.ellipse")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotAccent)
                            .cornerRadius(14)
                    }
                }
            } else if isSeller && liveOrder.fulfilment == .meetup && liveOrder.meetupProposal == nil {
                VStack(spacing: 12) {
                    statusPill(label: "Order accepted — progress updated", color: Color(.systemBlue))
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(Color(.systemOrange))
                        Text("When you've handed over the item, remind the buyer to tap \"I Received the Item\" to close the order.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemOrange).opacity(0.08))
                    .cornerRadius(12)

                    Button(action: { navigateToAccept = true }) {
                        Label("Set Meetup Details", systemImage: "mappin.circle.fill")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.knotAccent)
                            .cornerRadius(14)
                    }
                }
            } else {
                // Seller: waiting for buyer to confirm the meetup they proposed.
                VStack(spacing: 12) {
                    statusPill(label: "Waiting for buyer to confirm meetup", color: Color(.systemBlue))
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(Color(.systemOrange))
                        Text("After the exchange, remind the buyer to tap \"I Received the Item\" in the order page.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemOrange).opacity(0.08))
                    .cornerRadius(12)
                }
            }

        case .meetupAgreed where !isSeller:
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(.systemBlue))
                    Text("Once you have the item, tap below to close the order.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBlue).opacity(0.08))
                .cornerRadius(12)

                Button(action: { navigateToReceipt = true }) {
                    Label("I Received the Item", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGreen)).cornerRadius(14)
                }
            }

        case .meetupAgreed:
            VStack(spacing: 12) {
                if isSeller {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(Color(.systemOrange))
                        Text("Meet the buyer and collect cash. The buyer will confirm collection.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemOrange).opacity(0.08))
                    .cornerRadius(12)
                }
                // Cash buyer can mark collected directly from meetup_agreed
                if !isSeller && liveOrder.isCash {
                    Button(action: { navigateToReceipt = true }) {
                        Label("I've Collected the Item", systemImage: "checkmark.circle.fill")
                            .fontWeight(.semibold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGreen)).cornerRadius(14)
                    }
                }
                Button(action: openMessage) {
                    Label(isSeller ? "Message Buyer" : "Message Seller", systemImage: "message.fill")
                        .fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.knotAccent).cornerRadius(14)
                }
            }

        case .awaitingConfirmation where !isSeller:
            Button(action: { navigateToReceipt = true }) {
                Label("I've Collected the Item",
                      systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(.systemGreen)).cornerRadius(14)
            }

        case .awaitingConfirmation:
            statusPill(label: "Awaiting buyer confirmation", color: Color(.systemOrange))

        case .complete:
            statusPill(label: "Transaction complete", color: Color(.systemGreen))

        case .disputed:
            statusPill(label: "Under Review by Knot", color: Color(.systemOrange))

        case .cancelled:
            statusPill(label: liveOrder.isCash ? "Order Cancelled" : "Order Cancelled — Refund in 3–5 days", color: Color(.systemRed))
        }
    }

    private func openMessage() {
        // Use the UUID-based opener — the name-based one fails silently if the
        // stored name doesn't match exactly (casing/whitespace/rename).
        let otherID   = isSeller ? order.buyerId   : order.sellerId
        let otherName = isSeller ? order.buyerName : order.sellerName

        // Switch tab first so MessagesView mounts and its .onChange observer
        // is ready. Then dismiss the current view. Finally, after the dismiss
        // animation completes, set the pending ID to navigate into the chat.
        profile.selectedTab = .messages
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            profile.openConversation(withUserID: otherID, name: otherName)
        }
    }

    private func statusPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.subheadline).fontWeight(.medium)
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(14)
    }

    private func timelineRow(step: TimelineStep, idx: Int) -> some View {
        let done    = isComplete(step)
        let current = isCurrent(step)

        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(done || current ? Color(.systemBlue) : Color.knotSurface)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: done ? "checkmark" : step.icon)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(done || current ? Color.knotOnAccent : Color.knotMuted)
                    }
                if idx < steps.count - 1 {
                    // Stretch the connector to the full row height so it always
                    // meets the next circle — a fixed height leaves a gap when the
                    // text column (label + date + bottom padding) is taller.
                    Rectangle()
                        .fill(done ? Color(.systemBlue) : Color.knotSurface)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.label)
                    .font(.subheadline)
                    .fontWeight(current ? .semibold : .regular)
                    .foregroundColor(done || current ? .primary : Color.knotMuted)
                if let date = liveOrder.stepDates[step.status] {
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundColor(Color(.systemBlue))
                } else if current {
                    Text("In progress")
                        .font(.caption)
                        .foregroundColor(Color(.systemOrange))
                }
            }
            .padding(.top, 2)
            .padding(.bottom, idx < steps.count - 1 ? 36 : 0)
        }
    }

    private var disputedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2).foregroundColor(Color(.systemOrange))
            VStack(alignment: .leading, spacing: 3) {
                Text("Under Review").fontWeight(.semibold)
                Text("Knot's team is reviewing this dispute. Payment is frozen.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var cancelledBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2).foregroundColor(Color(.systemRed))
            VStack(alignment: .leading, spacing: 3) {
                Text("Order Cancelled").fontWeight(.semibold)
                Text(order.isCash
                     ? "Seller did not respond. This order has been cancelled."
                     : "Seller did not respond. Refund in 3–5 business days.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func detailRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundColor(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(value).fontWeight(.medium)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - MyOrdersView

struct MyOrdersView: View {
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) private var dismiss

    private var active: [KnotOrder] {
        profile.orders.filter { $0.status != .complete && $0.status != .cancelled }
    }
    private var past: [KnotOrder] {
        profile.orders.filter { $0.status == .complete || $0.status == .cancelled }
    }

    private func isSeller(_ order: KnotOrder) -> Bool {
        order.sellerId == profile.currentUserID
    }

    var body: some View {
        Group {
            if profile.orders.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bag")
                        .font(.system(size: 52))
                        .foregroundColor(Color.knotMuted)
                    Text("No orders yet")
                        .font(.headline)
                        .foregroundColor(Color.knotMuted)
                    Text("Buy or sell something and it will appear here.")
                        .font(.subheadline)
                        .foregroundColor(Color.knotMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.knotBackground)
            } else {
                List {
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active) { order in
                                NavigationLink(destination:
                                    OrderTimelineView(order: order, isSeller: isSeller(order))
                                        .environment(profile)
                                ) {
                                    OrderRow(order: order)
                                }
                            }
                        }
                    }
                    if !past.isEmpty {
                        Section("Past Orders") {
                            ForEach(past) { order in
                                NavigationLink(destination:
                                    OrderTimelineView(order: order, isSeller: isSeller(order))
                                        .environment(profile)
                                ) {
                                    OrderRow(order: order)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My Orders")
        .navigationBarTitleDisplayMode(.inline)
        .task { await profile.loadOrders() }
        .onChange(of: profile.pendingChatConversationID) { _, id in
            if id != nil { dismiss() }
        }
        // Close the whole orders sheet back to the Hub (e.g. after accepting a meetup).
        .onChange(of: profile.closeOrdersFlowSignal) { _, _ in dismiss() }
    }
}

private struct OrderRow: View {
    let order: KnotOrder

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.knotSurface)
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: order.listing.type.icon)
                        .foregroundColor(Color.knotMuted)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(order.listing.name)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(order.id)
                    .font(.caption).foregroundColor(.secondary)
                Text(formatSGD(order.total))
                    .font(.caption).fontWeight(.medium)
            }
            Spacer()
            statusBadge(order.status)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ status: OrderStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .pending:              return ("Pending",    Color(.systemOrange))
            case .sellerAccepted:       return ("Accepted",   Color(.systemBlue))
            case .meetupAgreed:         return ("Meetup set", Color(.systemBlue))
            case .awaitingConfirmation: return ("Confirm",    Color(.systemGreen))
            case .complete:             return ("Complete",   Color(.systemGreen))
            case .disputed:             return ("Dispute",    Color(.systemRed))
            case .cancelled:            return ("Cancelled",  Color(.systemRed))
            }
        }()
        Text(label)
            .font(.caption2).fontWeight(.semibold)
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(8)
    }
}

#Preview {
    let listing = ShopListing(name: "Standing Desk", price: 150, sellerName: "Wei Ming")
    let order = KnotOrder(
        id: "#KN-00123", listing: listing,
        buyerName: "Ruhaan", sellerName: listing.sellerName,
        sellerId: UUID(), buyerId: UUID(),
        subtotal: listing.price * 100, knotFeeRate: 0.10,
        fulfilment: .meetup, paymentMethod: "cash", address: "Bishan MRT",
        date: Date(), status: .meetupAgreed, escrow: .held,
        meetupProposal: MeetupProposal(location: "Bishan MRT Exit A",
                                       date: Date().addingTimeInterval(86400),
                                       proposedBy: "seller"),
        stepDates: ["pending": Date(), "seller_accepted": Date(), "meetup_agreed": Date()]
    )
    OrderTimelineView(order: order, isSeller: false)
        .environment(UserProfile(name: "Ruhaan"))
}
