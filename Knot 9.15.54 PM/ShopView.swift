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
    let id          = UUID()
    var type        : ListingType   = .item
    var category    : ShopCategory  = .other
    var condition   : ItemCondition = .notSpecified
    var name        : String        = ""
    var description : String        = ""
    var link        : String        = ""
    var price       : Int           = 0
    var sellerName  : String        = ""
    var images      : [UIImage]     = []
    var date        : Date          = Date()
}

// MARK: - Sample Listings
var sampleListings: [ShopListing] = [
    ShopListing(type: .item,          category: .furniture,    condition: .lightlyUsed, name: "Standing Desk",          description: "White IKEA standing desk, adjustable height, barely used. Dimensions 120×60 cm.", price: 150, sellerName: "Wei Ming"),
    ShopListing(type: .item,          category: .sports,       condition: .wellUsed,    name: "Road Bike",              description: "Trek road bike, size M. Includes helmet and lights. Selling due to relocation.",   price: 800, sellerName: "Sarah Tan"),
    ShopListing(type: .service,       category: .other,        condition: .brandNew,    name: "Dog Walking",            description: "Friendly and experienced dog walker. Available mornings and evenings. Up to 2 dogs per walk.", price: 30, sellerName: "James Lim"),
    ShopListing(type: .service,       category: .homeGarden,   condition: .brandNew,    name: "House Cleaning",         description: "Thorough home cleaning service. 3-hour session includes kitchen, bathrooms, and living areas.", price: 80, sellerName: "Priya Nair"),
    ShopListing(type: .advertisement, category: .other,        condition: .brandNew,    name: "Piano Lessons for Kids", description: "Experienced teacher offering piano for children aged 4–12. First trial lesson free!", price: 0,   sellerName: "Lin Hui"),
    ShopListing(type: .item,          category: .electronics,  condition: .likeNew,     name: "Coffee Machine",         description: "Nespresso Vertuo Next, black. Comes with a starter pack of capsules.",             price: 200, sellerName: "James Lim"),
    ShopListing(type: .item,          category: .homeGarden,   condition: .brandNew,    name: "Potted Monstera",        description: "Large monstera deliciosa, healthy and full. Comes with ceramic pot.",               price: 80,  sellerName: "Priya Nair"),
    ShopListing(type: .item,          category: .clothing,     condition: .likeNew,     name: "Lululemon Leggings",     description: "Size S, worn twice. Original price $120.",                                          price: 45,  sellerName: "Ahmad Khalid"),
]

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

    var allListings: [ShopListing] { sampleListings + profile.myListings }

    var displayed: [ShopListing] {
        var base: [ShopListing]
        if filter == .myListings {
            base = profile.myListings
        } else if let type = filter.listingType {
            base = allListings.filter { $0.type == type }
        } else {
            base = allListings
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
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.black)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.systemGray))
                        }
                    }
                    Spacer()
                    Button(action: { showOrders = true }) {
                        Image(systemName: "bag")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
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
    @State private var showPurchase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Images
                    if listing.images.isEmpty {
                        ZStack {
                            Rectangle().fill(Color(.systemGray5)).frame(height: 220)
                            Image(systemName: listing.type.icon)
                                .font(.system(size: 64)).foregroundColor(Color(.systemGray3))
                        }
                    } else {
                        TabView {
                            ForEach(listing.images.indices, id: \.self) { i in
                                Image(uiImage: listing.images[i])
                                    .resizable().scaledToFill()
                                    .frame(height: 260).clipped()
                            }
                        }
                        .tabViewStyle(.page)
                        .frame(height: 260)
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
                    if listing.price > 0 {
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

    private var canCreate: Bool {
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
                Section("Details") {
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
                    Button("Post") { createListing() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func createListing() {
        let price = Int(priceText) ?? 0
        var listing = ShopListing(
            type: type, category: category, condition: condition,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            link: link.trimmingCharacters(in: .whitespaces),
            price: type == .advertisement ? 0 : price,
            sellerName: profile.name
        )
        listing.images = images
        profile.myListings.append(listing)
        dismiss()
    }
}
