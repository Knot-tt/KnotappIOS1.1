import SwiftUI

// MARK: - Wallet & Payments View

struct WalletPaymentsView: View {
    @Environment(UserProfile.self) private var profile
    @State private var invoiceOrder: KnotOrder? = nil

    private var allOrders: [KnotOrder] { profile.orders }

    private var totalSpent: Int {
        allOrders
            .filter { $0.buyerId == profile.currentUserID }
            .filter { $0.status == .complete }
            .reduce(0) { $0 + $1.total }
    }

    private var totalEarned: Int {
        allOrders
            .filter { $0.sellerId == profile.currentUserID }
            .filter { $0.status == .complete }
            .reduce(0) { $0 + $1.payout }
    }

    var body: some View {
        List {
            // ── Summary Cards ──────────────────────────────────────────────
            Section {
                HStack(spacing: 12) {
                    summaryCard(
                        icon   : "arrow.up.circle.fill",
                        color  : Color(.systemBlue),
                        label  : "Total Spent",
                        amount : totalSpent
                    )
                    summaryCard(
                        icon   : "arrow.down.circle.fill",
                        color  : Color(.systemGreen),
                        label  : "Total Earned",
                        amount : totalEarned
                    )
                }
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // ── Order History ──────────────────────────────────────────────
            Section("Order History") {
                if allOrders.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "bag")
                            .foregroundColor(Color(.systemGray3))
                        Text("No orders yet")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(allOrders) { order in
                        Button(action: { invoiceOrder = order }) {
                            orderRow(order)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // ── Payment Method ─────────────────────────────────────────────
            Section("Payment Method") {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cards managed by Stripe")
                            .font(.subheadline)
                        Text("Saved cards appear automatically at checkout")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Wallet & Payments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await profile.loadOrders() }
        .sheet(item: $invoiceOrder) { order in
            InvoiceView(order: order)
        }
    }

    // MARK: - Subviews

    private func summaryCard(icon: String, color: Color, label: String, amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(formatSGD(amount))
                .font(.title3).fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func orderRow(_ order: KnotOrder) -> some View {
        let isBuyer = order.buyerId == profile.currentUserID
        HStack(spacing: 12) {
            Image(systemName: isBuyer ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.title3)
                .foregroundColor(isBuyer ? Color(.systemBlue) : Color(.systemGreen))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(order.listing.name)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                Text(isBuyer ? "Bought from \(order.sellerName)" : "Sold to \(order.buyerName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatDate(order.date))
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }

            Spacer()

            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    let amountText = isBuyer
                        ? "-\(formatSGD(order.total))"
                        : (order.status == .complete ? "+\(formatSGD(order.payout))" : formatSGD(order.payout))
                    let amountColor: Color = isBuyer
                        ? .primary
                        : (order.status == .complete ? Color(.systemGreen) : Color(.tertiaryLabel))
                    Text(amountText)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(amountColor)
                    statusBadge(order.status, isBuyer: isBuyer)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(_ status: OrderStatus, isBuyer: Bool = true) -> some View {
        let (label, color): (String, Color) = switch status {
        case .pending:              ("Pending",      Color(.systemOrange))
        case .sellerAccepted:       ("Accepted",     Color(.systemBlue))
        case .meetupAgreed:         ("Meetup Set",   Color(.systemBlue))
        case .awaitingConfirmation: ("In Escrow",    Color(.systemPurple))
        case .complete:             (isBuyer ? "Paid" : "Paid Out", Color(.systemGreen))
        case .disputed:             ("Disputed",     Color(.systemRed))
        case .cancelled:            ("Cancelled",    Color(.systemGray))
        }
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(5)
    }
}
