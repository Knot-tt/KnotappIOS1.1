import SwiftUI
import UIKit

// MARK: - Listing Type
enum ListingType: String, CaseIterable, Identifiable {
    case item          = "Item"
    case service       = "Service"
    case advertisement = "Advertisement"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .item:          return "tag.fill"
        case .service:       return "wrench.and.screwdriver.fill"
        case .advertisement: return "megaphone.fill"
        }
    }
}

// MARK: - Shop Category
enum ShopCategory: String, CaseIterable, Identifiable {
    case electronics     = "Electronics"
    case furniture       = "Furniture"
    case clothing        = "Clothing & Accessories"
    case sports          = "Sports & Fitness"
    case books           = "Books & Media"
    case homeGarden      = "Home & Garden"
    case toysGames       = "Toys & Games"
    case food            = "Food & Beverages"
    case other           = "Other"
    var id: String { rawValue }

    var dbValue: String {
        switch self {
        case .electronics: return "electronics"
        case .furniture:   return "furniture"
        case .clothing:    return "clothing"
        case .sports:      return "sports"
        case .books:       return "books"
        case .homeGarden:  return "home_garden"
        case .toysGames:   return "toys_games"
        case .food:        return "food"
        case .other:       return "other"
        }
    }
    static func fromDB(_ v: String) -> ShopCategory {
        switch v {
        case "electronics": return .electronics
        case "furniture":   return .furniture
        case "clothing":    return .clothing
        case "sports":      return .sports
        case "books":       return .books
        case "home_garden": return .homeGarden
        case "toys_games":  return .toysGames
        case "food":        return .food
        default:            return .other
        }
    }
}

// MARK: - Item Condition
enum ItemCondition: String, CaseIterable, Identifiable {
    case notSpecified  = "Not Specified"
    case brandNew      = "Brand New"
    case likeNew       = "Like New"
    case lightlyUsed   = "Lightly Used"
    case wellUsed      = "Well Used"
    case heavilyUsed   = "Heavily Used"
    var id: String { rawValue }

    var dbValue: String {
        switch self {
        case .notSpecified: return "not_specified"
        case .brandNew:     return "brand_new"
        case .likeNew:      return "like_new"
        case .lightlyUsed:  return "lightly_used"
        case .wellUsed:     return "well_used"
        case .heavilyUsed:  return "heavily_used"
        }
    }
    static func fromDB(_ v: String) -> ItemCondition {
        switch v {
        case "brand_new":    return .brandNew
        case "like_new":     return .likeNew
        case "lightly_used": return .lightlyUsed
        case "well_used":    return .wellUsed
        case "heavily_used": return .heavilyUsed
        default:             return .notSpecified
        }
    }
    var description: String {
        switch self {
        case .notSpecified: return "No condition specified"
        case .brandNew:    return "Never used, in original packaging"
        case .likeNew:     return "Used once or twice, no visible wear"
        case .lightlyUsed: return "Minimal signs of use, works perfectly"
        case .wellUsed:    return "Visible wear, fully functional"
        case .heavilyUsed: return "Significant wear, may have minor faults"
        }
    }
}

// MARK: - Shop Listing Model
struct ShopListing: Identifiable {
    var id          : UUID          = UUID()
    var type        : ListingType   = .item
    var category    : ShopCategory  = .other
    var condition   : ItemCondition = .notSpecified
    var name        : String        = ""
    var description : String        = ""
    var link        : String        = ""
    var price       : Int           = 0
    var sellerName  : String        = ""
    var sellerID    : UUID?         = nil
    var isActive    : Bool          = true  // false = soft-deleted; only visible in "My Listings"
    var isRecurring : Bool          = false // true = stays listed after a sale; false = removed when sold
    var acceptsCash : Bool          = true
    var acceptsCard : Bool          = false
    var images      : [UIImage]     = []   // locally selected (before upload)
    var imageURLs   : [String]      = []   // Supabase Storage public URLs
    var date        : Date          = Date()
}

// MARK: - Shop Filter
enum ShopFilter: String, CaseIterable {
    case all            = "All"
    case items          = "Items"
    case services       = "Services"
    case advertisements = "Advertisements"
    case myListings     = "My Listings"

    var listingType: ListingType? {
        switch self {
        case .all, .myListings: return nil
        case .items:            return .item
        case .services:         return .service
        case .advertisements:   return .advertisement
        }
    }
}

// MARK: - Shop View
struct ShopView: View {
    @Environment(UserProfile.self) var profile
    @State private var searchText           = ""
    @State private var filter               : ShopFilter   = .all
    @State private var selectedListing      : ShopListing? = nil
    @State private var showCreate           = false
    @State private var showOrders           = false

    var displayed: [ShopListing] {
        var base: [ShopListing]
        if filter == .myListings {
            base = profile.myListings
        } else if let type = filter.listingType {
            base = profile.allListings.filter { $0.type == type && $0.isActive }
        } else {
            base = profile.allListings.filter { $0.isActive }
        }
        if !searchText.isEmpty {
            base = base.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.sellerName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return base
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            ZStack {

                HStack {
                    Menu {
                        ForEach(ShopFilter.allCases, id: \.self) { f in
                            Button(action: { filter = f }) {
                                if filter == f { Label(f.rawValue, systemImage: "checkmark") }
                                else           { Text(f.rawValue) }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Hub")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.knotMuted)
                        }
                    }
                    Spacer()
                    Button(action: { showOrders = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bag")
                                .font(.system(size: 13, weight: .semibold))
                            Text("My Orders")
                                .font(.system(size: 13, weight: .semibold))
                            if profile.orders.filter({ $0.status != .complete && $0.status != .cancelled }).count > 0 {
                                Text("\(profile.orders.filter({ $0.status != .complete && $0.status != .cancelled }).count)")
                                    .font(.caption2).fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color(.systemRed))
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.knotSurface)
                        .cornerRadius(20)
                        .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                    }
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .padding(8)
                            .background(Color.knotSurface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.separator), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // ── Scrollable content ────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    // Active filter pill
                    if filter != .all {
                        HStack {
                            let pillIcon = filter.listingType?.icon ?? (filter == .myListings ? "person.fill" : "line.3.horizontal.decrease")
                            Label(filter.rawValue, systemImage: pillIcon)
                                .font(.caption).fontWeight(.medium).foregroundColor(Color.knotOnAccent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.knotAccent).cornerRadius(10)
                            Spacer()
                        }
                        .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)
                    }

                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search items, services, ads…", text: $searchText)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(Color.knotMuted)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.knotWell)
                    .cornerRadius(12)
                    .knotSurfaceBorder(cornerRadius: 12)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)


                    Divider()

                    if displayed.isEmpty && !profile.hasLoadedListings {
                        // First load still in flight — spinner, not "nothing here".
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if displayed.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cart")
                                .font(.system(size: 48)).foregroundColor(Color.knotMuted)
                            Text("Nothing here yet")
                                .font(.headline).foregroundColor(Color.knotMuted)
                            Text("Tap + to list an item, service, or advertisement")
                                .font(.caption).foregroundColor(Color.knotMuted)
                                .multilineTextAlignment(.center).padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(displayed) { listing in
                                ShopItemCard(listing: listing,
                                             isMine: profile.myListings.contains(where: { $0.id == listing.id })) { selectedListing = listing }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .task { await profile.loadListings() }
        .onAppear { openPendingOrdersIfNeeded() }
        .onChange(of: profile.pendingOrderNotificationID) { _, _ in
            openPendingOrdersIfNeeded()
        }
        .sheet(item: $selectedListing) { listing in
            ShopItemDetailView(listing: listing).environment(profile)
        }
        .sheet(isPresented: $showCreate) {
            CreateListingView().environment(profile)
        }
        .sheet(isPresented: $showOrders) {
            NavigationStack {
                MyOrdersView().environment(profile)
            }
        }
    }

    private func openPendingOrdersIfNeeded() {
        guard profile.pendingOrderNotificationID != nil else { return }
        profile.pendingOrderNotificationID = nil
        showOrders = true
    }

}

// MARK: - Shop Item Card
struct ShopItemCard: View {
    let listing: ShopListing
    var isMine : Bool = false
    let onTap  : () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Image area
                ZStack {
                    Rectangle()
                        .fill(Color.knotSurface)
                        .frame(height: 110)
                    if let img = listing.images.first {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(height: 110)
                            .clipped()
                    } else if let urlString = listing.imageURLs.first,
                              let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                                    .frame(height: 110).clipped()
                            } else {
                                Color.knotSurface.frame(height: 110)
                            }
                        }
                    } else {
                        Image(systemName: listing.type.icon)
                            .font(.system(size: 36))
                            .foregroundColor(Color.knotMuted)
                    }
                    // Type badge (top-left, for ads and services)
                    if listing.type == .advertisement || listing.type == .service {
                        VStack {
                            HStack {
                                Text(listing.type == .advertisement ? "Ad" : "Service")
                                    .font(.caption2).fontWeight(.semibold)
                                    .foregroundColor(listing.type == .advertisement ? .white : Color.knotOnAccent)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(listing.type == .advertisement ? Color.orange : Color.knotAccent)
                                    .cornerRadius(6)
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    // Condition badge (bottom-left, items only). White-on-dark-scrim works
                    // on every background — light, dark, or photo content.
                    if listing.type == .item {
                        VStack {
                            Spacer()
                            HStack {
                                Text(listing.condition.rawValue)
                                    .font(.caption2).fontWeight(.semibold).foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.black.opacity(0.65))
                                    .cornerRadius(6)
                                    .padding(6)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(height: 110)
                .clipped()

                Rectangle()
                    .fill(Color.knotBorder)
                    .frame(height: 1.5)

                // Info
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(listing.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if isMine {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }

                    if listing.price > 0 {
                        Text("$\(listing.price)")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.primary)
                    } else {
                        Text("Free")
                            .font(.caption).foregroundColor(.green).fontWeight(.semibold)
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.knotSurface)
            }
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.knotBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shop Item Detail View
struct ShopItemDetailView: View {
    let listing: ShopListing
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss
    @State private var showPurchase    = false
    @State private var showDeleteAlert = false
    @State private var confirmDelete   = false
    @State private var showOrderSheet  = false
    @State private var showEditSheet   = false

    var isMine: Bool { listing.sellerID == profile.currentUserID }

    var existingOrder: KnotOrder? {
        profile.orders.first {
            $0.listing.id == listing.id &&
            $0.buyerId == profile.currentUserID &&
            $0.status != .cancelled
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Images — local UIImage takes priority (just-created listing), then URLs
                    if !listing.images.isEmpty {
                        TabView {
                            ForEach(listing.images.indices, id: \.self) { i in
                                Image(uiImage: listing.images[i])
                                    .resizable().scaledToFill()
                                    .frame(height: 260).clipped()
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 260)
                    } else if !listing.imageURLs.isEmpty {
                        TabView {
                            ForEach(listing.imageURLs, id: \.self) { urlString in
                                if let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable().scaledToFill()
                                                .frame(height: 260).clipped()
                                        } else {
                                            Color.knotSurface.frame(height: 260)
                                        }
                                    }
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 260)
                    } else {
                        ZStack {
                            Rectangle().fill(Color.knotSurface).frame(height: 220)
                            Image(systemName: listing.type.icon)
                                .font(.system(size: 64)).foregroundColor(Color.knotMuted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Badges row
                        HStack(spacing: 8) {
                            let isAccentBadge = listing.type == .item || listing.type == .service
                            let typeBadgeColor: Color = isAccentBadge ? Color.knotAccent : .orange
                            Label(listing.type.rawValue, systemImage: listing.type.icon)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(isAccentBadge ? Color.knotOnAccent : .white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(typeBadgeColor)
                                .cornerRadius(8)
                            Text(listing.category.rawValue)
                                .font(.caption).fontWeight(.medium).foregroundColor(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.knotSurface)
                                .cornerRadius(8)
                            if listing.type == .item {
                                Text(listing.condition.rawValue)
                                    .font(.caption).fontWeight(.medium).foregroundColor(.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.knotSurface)
                                    .cornerRadius(8)
                            }
                        }

                        // Name + price
                        Text(listing.name)
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.primary)

                        if listing.price > 0 {
                            Text("$\(listing.price)")
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.primary)
                        } else {
                            Text("Free")
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.green)
                        }

                        Divider()

                        // Seller
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.knotAccent).frame(width: 36, height: 36)
                                Text(String(listing.sellerName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(listing.sellerName).font(.subheadline).fontWeight(.semibold)
                                Text("Seller").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if !isMine {
                                Button(action: {
                                    // Prefer the UUID-based path — listing already carries
                                    // sellerID, no need for a fragile name search.
                                    if let sid = listing.sellerID {
                                        profile.openConversation(withUserID: sid,
                                                                 name: listing.sellerName,
                                                                 listingContext: ListingMessageContext(
                                                                    listingID: listing.id,
                                                                    listingName: listing.name
                                                                 ))
                                    } else {
                                        profile.openConversation(
                                            with: listing.sellerName,
                                            listingContext: ListingMessageContext(
                                                listingID: listing.id,
                                                listingName: listing.name
                                            )
                                        )
                                    }
                                    dismiss()
                                }) {
                                    Text("Message")
                                        .font(.caption).fontWeight(.semibold).foregroundColor(Color.knotOnAccent)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(Color.knotAccent).clipShape(Capsule())
                                }
                            }
                        }

                        // Condition detail (items only)
                        if listing.type == .item {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle").foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(listing.condition.rawValue).font(.caption).fontWeight(.semibold)
                                    Text(listing.condition.description).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }

                        Divider()

                        // Description
                        Text("Description")
                            .font(.headline).foregroundColor(.primary)
                        Text(listing.description)
                            .font(.body).foregroundColor(.primary.opacity(0.8)).lineSpacing(5)
                        if !listing.link.isEmpty {
                            Link(destination: URL(string: listing.link.hasPrefix("http") ? listing.link : "https://\(listing.link)") ?? URL(string: "https://")!) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                    Text(listing.link)
                                        .lineLimit(1)
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationTitle(listing.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isMine {
                        Menu {
                            Button(action: { showEditSheet = true }) {
                                Label("Edit Listing", systemImage: "pencil")
                            }
                            Button(role: .destructive, action: { showDeleteAlert = true }) {
                                Label("Delete Listing", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    } else if existingOrder != nil {
                        Button(action: { showOrderSheet = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "bag.fill").font(.system(size: 12))
                                Text("Ordered")
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color(.systemGreen))
                            .clipShape(Capsule())
                        }
                    } else if listing.price > 0 {
                        Button(action: { showPurchase = true }) {
                            Text("Buy")
                                .fontWeight(.semibold)
                                .foregroundColor(Color.knotOnAccent)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color.knotAccent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $showPurchase) {
                PurchaseConfirmView(listing: listing)
                    .environment(profile)
            }
            .sheet(isPresented: $showOrderSheet) {
                if let order = existingOrder {
                    NavigationStack {
                        OrderTimelineView(order: order, isSeller: false)
                    }
                    .environment(profile)
                }
            }
            .alert("Delete Listing", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) { confirmDelete = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This listing will be removed from the Hub.")
            }
            .sheet(isPresented: $showEditSheet) {
                EditListingView(listing: listing).environment(profile)
            }
            .onChange(of: confirmDelete) { _, confirmed in
                guard confirmed else { return }
                confirmDelete = false
                Task {
                    await profile.deleteListing(listingID: listing.id)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Create Listing View
struct CreateListingView: View {
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    @State private var type          : ListingType    = .item
    @State private var category      : ShopCategory   = .other
    @State private var condition     : ItemCondition  = .notSpecified
    @State private var name          = ""
    @State private var description   = ""
    @State private var link          = ""
    @State private var priceText     = ""
    @State private var showPhotoPicker = false
    @State private var showImageSourceChoice = false
    @State private var showCamera      = false
    @State private var images          : [UIImage] = []
    @State private var isPosting        = false
    @State private var createError      : String? = nil
    @State private var isRecurring      = false
    /// Only items/services can be priced — ads are always free.
    private var isSellableType: Bool { type == .item || type == .service }

    private var canCreate: Bool {
        !isPosting &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Type selector
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ListingType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Listing Type")
                } footer: {
                    if type == .service {
                        Text("Services are for things like dog walking, house cleaning, or tutoring. Classes and interactive sessions (yoga, group lessons) belong in Knots instead.")
                    } else if type == .advertisement {
                        Text("Advertisements are free to post and ideal for promoting events, notices, or general community announcements.")
                    }
                }


                // Details
                Section {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    HStack(spacing: 8) {
                        Image(systemName: "link").foregroundColor(Color.knotMuted).font(.subheadline)
                        TextField("Link (optional)", text: $link)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    if type == .item || type == .service {
                        HStack {
                            Text("$").foregroundColor(.secondary)
                            TextField("Price (0 for free)", text: $priceText)
                                .keyboardType(.numberPad)
                        }
                    }
                    if type == .item || type == .service {
                        Toggle("Recurring listing", isOn: $isRecurring)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if isRecurring {
                        Text("Recurring listings stay visible after each sale — great for services or items you sell repeatedly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if type == .item || type == .service {
                        Text("This listing will be automatically removed from the Hub once it's sold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Category
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ShopCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Condition (items only)
                if type == .item {
                    Section {
                        Picker("Condition", selection: $condition) {
                            ForEach(ItemCondition.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                            Text(condition.description).font(.caption).foregroundColor(.secondary)
                        }
                    } header: { Text("Condition") }
                }

                Section("Photos") {
                    Button(action: {
                        if CameraPicker.isAvailable { showImageSourceChoice = true }
                        else { showPhotoPicker = true }
                    }) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { i in
                                    Image(uiImage: images[i])
                                        .resizable().scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        guard !isPosting else { return }
                        isPosting = true
                        Task {
                            await createListing()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
            .confirmationDialog("Add Photos", isPresented: $showImageSourceChoice, titleVisibility: .visible) {
                Button("Take Photo") { showCamera = true }
                Button("Choose from Library") { showPhotoPicker = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPhotoPicker) {
                MultiImagePicker(maxSelectionCount: 6) { imgs in
                    showPhotoPicker = false
                    if !imgs.isEmpty {
                        images = imgs
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                // Camera adds a single shot; keep the same 6-photo cap as the library.
                CameraPicker { img in
                    if images.count < 6 { images.append(img) }
                }
            }
            .alert("Couldn't Save Listing", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {
                Button("OK", role: .cancel) { createError = nil }
            } message: {
                Text(createError ?? "")
            }
        }
    }

    private func createListing() async {
        let price = Int(priceText) ?? 0
        defer { isPosting = false }
        do {
            try await profile.createListing(
                type: type, category: category, condition: condition,
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces),
                link: link.trimmingCharacters(in: .whitespaces),
                price: type == .advertisement ? 0 : price,
                images: images,
                isRecurring: isRecurring,
                acceptsCash: type != .advertisement,
                acceptsCard: false
            )
            images.removeAll(keepingCapacity: false)
            dismiss()
            // The newly created listing is already inserted into local state by
            // UserProfile.createListing(). Refresh in the background so a slow or
            // stuck fetch cannot block sheet dismissal and make "Post" feel frozen.
            Task { await profile.loadListings() }
        } catch {
            createError = error.localizedDescription
        }
    }
}

// MARK: - Edit Listing View
struct EditListingView: View {
    @Environment(UserProfile.self) var profile
    @Environment(\.dismiss) var dismiss

    let listing: ShopListing

    @State private var type        : ListingType
    @State private var category    : ShopCategory
    @State private var condition   : ItemCondition
    @State private var name        : String
    @State private var description : String
    @State private var link        : String
    @State private var priceText   : String
    @State private var isSaving    = false

    init(listing: ShopListing) {
        self.listing      = listing
        _type        = State(initialValue: listing.type)
        _category    = State(initialValue: listing.category)
        _condition   = State(initialValue: listing.condition)
        _name        = State(initialValue: listing.name)
        _description = State(initialValue: listing.description)
        _link        = State(initialValue: listing.link)
        _priceText   = State(initialValue: listing.price > 0 ? String(listing.price) : "")
    }

    private var canSave: Bool {
        !isSaving &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ListingType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Listing Type") }

                Section {
                    TextField("Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    HStack(spacing: 8) {
                        Image(systemName: "link").foregroundColor(Color.knotMuted).font(.subheadline)
                        TextField("Link (optional)", text: $link)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    if type == .item || type == .service {
                        HStack {
                            Text("$").foregroundColor(.secondary)
                            TextField("Price (0 for free)", text: $priceText)
                                .keyboardType(.numberPad)
                        }
                    }
                } header: { Text("Details") }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ShopCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if type == .item {
                    Section {
                        Picker("Condition", selection: $condition) {
                            ForEach(ItemCondition.allCases) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                            Text(condition.description).font(.caption).foregroundColor(.secondary)
                        }
                    } header: { Text("Condition") }
                }

                Section {
                    Text("Photos can't be changed from this screen. To swap photos, delete and re-create the listing.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { Task { await save() } }) {
                        if isSaving { ProgressView() }
                        else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let price = Int(priceText) ?? 0
        await profile.updateListing(
            listingID  : listing.id,
            type       : type,
            category   : category,
            condition  : condition,
            name       : name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            link       : link.trimmingCharacters(in: .whitespaces),
            price      : type == .advertisement ? 0 : price
        )
        dismiss()
    }
}
