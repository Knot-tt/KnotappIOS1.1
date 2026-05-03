import SwiftUI
import PhotosUI
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
    @State private var searchText      = ""
    @State private var filter          : ShopFilter   = .all
    @State private var selectedListing : ShopListing? = nil
    @State private var showCreate      = false
    @State private var showWallet      = false
    @State private var showOrders      = false

    var displayed: [ShopListing] {
        var base: [ShopListing]
        if filter == .myListings {
            base = profile.myListings
        } else if let type = filter.listingType {
            base = profile.allListings.filter { $0.type == type }
        } else {
            base = profile.allListings
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
                                .foregroundColor(.black)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.systemGray))
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
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                    }
                    Button(action: { showCreate = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Active filter pill
            if filter != .all {
                HStack {
                    let pillIcon = filter.listingType?.icon ?? (filter == .myListings ? "person.fill" : "line.3.horizontal.decrease")
                    Label(filter.rawValue, systemImage: pillIcon)
                        .font(.caption).fontWeight(.medium).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.black).cornerRadius(10)
                    Spacer()
                }
                .padding(.horizontal).padding(.bottom, 4)
            }

            // ── Search ────────────────────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search items, services, ads…", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color(.systemGray3))
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            // ── Grid ──────────────────────────────────────────────────────
            if displayed.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "cart")
                        .font(.system(size: 48)).foregroundColor(Color(.systemGray3))
                    Text("Nothing here yet")
                        .font(.headline).foregroundColor(Color(.systemGray))
                    Text("Tap + to list an item, service, or advertisement")
                        .font(.caption).foregroundColor(Color(.systemGray3))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                Spacer()
            } else {
                ScrollView {
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
        .background(Color(.systemGray6).ignoresSafeArea())
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
        .sheet(isPresented: $showWallet) {
            NavigationStack { WalletPaymentsView() }
        }
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
                        .fill(Color(.systemGray5))
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
                                Color(.systemGray5).frame(height: 110)
                            }
                        }
                    } else {
                        Image(systemName: listing.type.icon)
                            .font(.system(size: 36))
                            .foregroundColor(Color(.systemGray3))
                    }
                    // Type badge (top-left, for ads and services)
                    if listing.type == .advertisement || listing.type == .service {
                        VStack {
                            HStack {
                                Text(listing.type == .advertisement ? "Ad" : "Service")
                                    .font(.caption2).fontWeight(.semibold).foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(listing.type == .advertisement ? Color.orange : Color.blue)
                                    .cornerRadius(6)
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    // Condition badge (bottom-left, items only)
                    if listing.type == .item {
                        VStack {
                            Spacer()
                            HStack {
                                Text(listing.condition.rawValue)
                                    .font(.caption2).fontWeight(.medium).foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.black.opacity(0.55))
                                    .cornerRadius(6)
                                    .padding(6)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(height: 110)
                .clipped()

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(listing.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.black)
                            .lineLimit(1)
                        if isMine {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.green)
                        }
                    }

                    if listing.price > 0 {
                        HStack(spacing: 3) {
                            KnotIcon(size: 11)
                            Text(listing.price == 0 ? "Free" : "$\(listing.price)")
                                .font(.caption).foregroundColor(.black)
                        }
                    } else {
                        Text("Free")
                            .font(.caption).foregroundColor(.green).fontWeight(.semibold)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            }
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 1))
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
                                            Color(.systemGray5).frame(height: 260)
                                        }
                                    }
                                }
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 260)
                    } else {
                        ZStack {
                            Rectangle().fill(Color(.systemGray5)).frame(height: 220)
                            Image(systemName: listing.type.icon)
                                .font(.system(size: 64)).foregroundColor(Color(.systemGray3))
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        // Badges row
                        HStack(spacing: 8) {
                            let typeBadgeColor: Color = listing.type == .item ? .black : listing.type == .service ? .blue : .orange
                            Label(listing.type.rawValue, systemImage: listing.type.icon)
                                .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(typeBadgeColor)
                                .cornerRadius(8)
                            Text(listing.category.rawValue)
                                .font(.caption).fontWeight(.medium).foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            if listing.type == .item {
                                Text(listing.condition.rawValue)
                                    .font(.caption).fontWeight(.medium).foregroundColor(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                            }
                        }

                        // Name + price
                        Text(listing.name)
                            .font(.system(size: 22, weight: .bold)).foregroundColor(.black)

                        if listing.price > 0 {
                            HStack(spacing: 4) {
                                KnotIcon(size: 16)
                                Text(listing.price == 0 ? "Free" : "$\(listing.price)")
                                    .font(.system(size: 18, weight: .semibold)).foregroundColor(.black)
                            }
                        } else {
                            Text("Free")
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.green)
                        }

                        Divider()

                        // Seller
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.black).frame(width: 36, height: 36)
                                Text(String(listing.sellerName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(listing.sellerName).font(.subheadline).fontWeight(.semibold)
                                Text("Seller").font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            if !isMine {
                                Button(action: {
                                    profile.openConversation(with: listing.sellerName)
                                    dismiss()
                                }) {
                                    Text("Message")
                                        .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 7)
                                        .background(Color.black).clipShape(Capsule())
                                }
                            }
                        }

                        // Condition detail (items only)
                        if listing.type == .item {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle").foregroundColor(.gray)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(listing.condition.rawValue).font(.caption).fontWeight(.semibold)
                                    Text(listing.condition.description).font(.caption).foregroundColor(.gray)
                                }
                            }
                        }

                        Divider()

                        // Description
                        Text("Description")
                            .font(.headline).foregroundColor(.black)
                        Text(listing.description)
                            .font(.body).foregroundColor(.black.opacity(0.8)).lineSpacing(5)
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
                        Button(role: .destructive, action: { showDeleteAlert = true }) {
                            Image(systemName: "trash")
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
                                .foregroundColor(.white)
                                .padding(.horizontal, 16).padding(.vertical, 6)
                                .background(Color.black)
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
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var images        : [UIImage]          = []
    @State private var isPosting     = false

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
                        Image(systemName: "link").foregroundColor(Color(.systemGray3)).font(.subheadline)
                        TextField("Link (optional)", text: $link)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    if type == .item || type == .service {
                        HStack {
                            KnotIcon(size: 14)
                            TextField("Price in $ (0 for free)", text: $priceText)
                                .keyboardType(.numberPad)
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if (type == .item || type == .service), let price = Int(priceText), price > 0 {
                        let subtotal = price * 100
                        let fee = Int(Double(subtotal) * 0.10)
                        let payout = subtotal - fee
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Listing price")
                                Spacer()
                                Text(formatSGD(subtotal))
                            }
                            HStack {
                                Text("Knot fee (10%)")
                                    .foregroundColor(Color(.systemOrange))
                                Spacer()
                                Text("−" + formatSGD(fee))
                                    .foregroundColor(Color(.systemOrange))
                            }
                            Divider()
                            HStack {
                                Text("You receive").fontWeight(.semibold)
                                Spacer()
                                Text(formatSGD(payout))
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(.systemGreen))
                            }
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                    }
                }

                // Category
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(ShopCategory.allCases) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                }

                // Condition (items only)
                if type == .item {
                    Section {
                        Picker("Condition", selection: $condition) {
                            ForEach(ItemCondition.allCases) { c in
                                VStack(alignment: .leading) {
                                    Text(c.rawValue)
                                }.tag(c)
                            }
                        }
                        // Description of selected condition
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").foregroundColor(.gray).font(.caption)
                            Text(condition.description).font(.caption).foregroundColor(.gray)
                        }
                    } header: { Text("Condition") }
                }

                // Photos
                Section("Photos") {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhotos) { _, items in
                        Task {
                            var loaded: [UIImage] = []
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let img = UIImage(data: data) {
                                    loaded.append(img)
                                }
                            }
                            await MainActor.run { images = loaded }
                        }
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
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
    }

    private func createListing() async {
        let price = Int(priceText) ?? 0
        await profile.createListing(
            type: type, category: category, condition: condition,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            link: link.trimmingCharacters(in: .whitespaces),
            price: type == .advertisement ? 0 : price,
            images: images
        )
    }
}
