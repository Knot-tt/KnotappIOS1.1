import SwiftUI

// MARK: - Wallet & Payments View

struct WalletPaymentsView: View {
    @Environment(UserProfile.self) private var profile
    @State private var showAllTransactions   = false

    private var allTransactions: [UserProfile.TransactionItem] { profile.transactionHistory }

    var body: some View {
        List {
            // ── Order History ──────────────────────────────────────────────
            Section("Order History") {
                if allTransactions.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "bag")
                            .foregroundColor(Color.knotMuted)
                        Text("No orders yet")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(allTransactions.prefix(5)) { item in
                        if case .order(let order) = item {
                            orderRow(order)
                        }
                    }
                    if allTransactions.count > 5 {
                        Button(action: { showAllTransactions = true }) {
                            HStack {
                                Text("See all \(allTransactions.count) transactions")
                                    .font(.subheadline)
                                    .foregroundColor(Color.knotAccent)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(Color.knotAccent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        }
        .navigationTitle("Wallet & Payments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await profile.loadOrders() }
        .sheet(isPresented: $showAllTransactions) {
            AllTransactionsView(
                transactions : allTransactions,
                currentUserID: profile.currentUserID
            )
        }
    }

    // MARK: - Subviews

    private func orderRow(_ order: KnotOrder) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.knotWell)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: order.listing.type.icon)
                        .font(.system(size: 14))
                        .foregroundColor(Color.knotMuted)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(order.listing.name)
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(order.buyerId == profile.currentUserID ? "Purchased" : "Sold")
                        .font(.caption).foregroundColor(.secondary)
                    Text("·")
                        .font(.caption).foregroundColor(.secondary)
                    Text(order.status == .complete ? "Complete" : order.status == .cancelled ? "Cancelled" : "Active")
                        .font(.caption).foregroundColor(
                            order.status == .complete ? Color(.systemGreen) :
                            order.status == .cancelled ? Color(.systemRed) :
                            Color(.systemOrange)
                        )
                }
            }
            Spacer()
            Text(formatSGD(order.total))
                .font(.subheadline).fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - All Transactions Sheet

private struct AllTransactionsView: View {
    let transactions  : [UserProfile.TransactionItem]
    let currentUserID : UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(transactions) { item in
                    if case .order(let order) = item {
                        orderRow(order)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("All Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func orderRow(_ order: KnotOrder) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.knotWell)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: order.listing.type.icon)
                        .font(.system(size: 14))
                        .foregroundColor(Color.knotMuted)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(order.listing.name)
                    .font(.subheadline).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(order.buyerId == currentUserID ? "Purchased" : "Sold")
                        .font(.caption).foregroundColor(.secondary)
                    Text("·")
                        .font(.caption).foregroundColor(.secondary)
                    Text(order.status == .complete ? "Complete" : order.status == .cancelled ? "Cancelled" : "Active")
                        .font(.caption).foregroundColor(
                            order.status == .complete ? Color(.systemGreen) :
                            order.status == .cancelled ? Color(.systemRed) :
                            Color(.systemOrange)
                        )
                }
            }
            Spacer()
            Text(formatSGD(order.total))
                .font(.subheadline).fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}
