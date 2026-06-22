
import SwiftUI

// MARK: - Create / Edit Knot View
struct CreateGroupView: View {
    var existingGroup: CommunityGroup? = nil

    @Environment(\.dismiss) var dismiss
    @Environment(UserProfile.self) var profile

    // Basic Info (compulsory)
    @State private var name        = ""
    @State private var description = ""

    // Prevent populateIfEditing from re-running on navigation back
    @State private var didPopulate = false

    // Details
    @State private var category     = ""
    @State private var city          = ""
    @State private var country       = ""
    @State private var maxMembersText = ""

    // Age
    @State private var ageGroup  : AgeGroup = .any
    @State private var minAge    : Double   = 13
    @State private var maxAge    : Double   = 99

    // Options
    @State private var isPrivate            = false   // false = Public, true = Connections Only
    @State private var requiresApproval     = false
    @State private var isEvent              = false
    @State private var isPaid           = false
    @State private var paymentType      : KnotPaymentType = .perSession
    @State private var priceText         = ""

    let categories = ["Photography","Food","Fitness","Reading","Gaming","Arts",
                      "Music","Education","Gardening","Entertainment","Technology","Outdoors","Other"]

    var isEditing : Bool { existingGroup != nil }

    var canSave   : Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Knot Type ────────────────────────────────────────────
                Section {
                    Picker("Knot Type", selection: $isEvent) {
                        Text("Knot").tag(false)
                        Text("Event").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: { Text("Type") }
                  footer: {
                      Text(isEvent
                        ? "An Event is a time-limited gathering or activity."
                        : "A Knot is an ongoing community group.")
                  }

                // ── Basic Info (compulsory) ───────────────────────────────
                Section {
                    TextField("Knot name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                } header: { Text("Basic Info") }
                  footer: { Text("Name and description are required.") }

                // ── Details ──────────────────────────────────────────────
                Section("Details") {
                    Menu {
                        Button("Select") { category = "" }
                        ForEach(categories, id: \.self) { cat in
                            Button(cat) { category = cat }
                        }
                    } label: {
                        HStack {
                            Text("Category").foregroundColor(.primary)
                            Spacer()
                            Text(category.isEmpty ? "Select" : category).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    TextField("Max members (optional)", text: $maxMembersText).keyboardType(.numberPad)
                }

                // ── Location ─────────────────────────────────────────────
                Section {
                    TextField("City", text: $city)
                    TextField("Country", text: $country)
                } header: { Text("Location") }
                  footer: { Text("Use a broad location only. Do not enter a home address.") }

                // ── Age Range ────────────────────────────────────────────
                Section {
                    Menu {
                        ForEach(AgeGroup.allCases, id: \.self) { ag in
                            Button(ag.rawValue) { ageGroup = ag }
                        }
                    } label: {
                        HStack {
                            Text("Age Group").foregroundColor(.primary)
                            Spacer()
                            Text(ageGroup.rawValue).foregroundColor(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    if ageGroup == .custom {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Min age: \(Int(minAge))")
                                .font(.subheadline)
                            Slider(value: $minAge, in: 13...99, step: 1)
                                .onChange(of: minAge) { _, v in if v > maxAge { maxAge = v } }
                            Text("Max age: \(Int(maxAge))")
                                .font(.subheadline)
                            Slider(value: $maxAge, in: 13...99, step: 1)
                                .onChange(of: maxAge) { _, v in if v < minAge { minAge = v } }
                        }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Age Range") }
                  footer: { Text("Who should be able to join this Knot?") }

                // ── Options ───────────────────────────────────────────────
                Section {
                    Picker("Visibility", selection: $isPrivate) {
                        Text("Public").tag(false)
                        Text("Connections Only").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Require approval to join", isOn: $requiresApproval)
                } header: { Text("Options") }
                  footer: {
                      if isPrivate {
                          Text("Only people connected to you can see this Knot.")
                      } else {
                          Text("Anyone can discover this Knot.")
                      }
                  }

            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Knot" : "New Knot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { saveGroup() }) {
                        if isSaving {
                            ProgressView().tint(.primary)
                        } else {
                            Text(isEditing ? "Save" : "Create").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear {
                guard !didPopulate else { return }
                populateIfEditing()
                didPopulate = true
            }
            .alert("Couldn't Save Knot", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Populate for editing
    private func populateIfEditing() {
        guard let g = existingGroup else { return }
        name                          = g.name
        description                   = g.description
        category                      = g.category
        city                          = g.location  // best-effort: put stored broad location into city
        maxMembersText                = g.maxMembers.map { String($0) } ?? ""
        requiresApproval              = g.requiresApproval
        isPrivate                     = g.isConnectionsOnly
        isEvent                       = g.isEvent
        ageGroup         = g.ageGroup
        minAge           = Double(g.minAge)
        maxAge           = Double(g.maxAge)
        isPaid           = g.isPaid
        paymentType      = g.paymentType
        priceText     = g.price > 0 ? String(g.price) : ""
    }

    @State private var isSaving = false
    @State private var saveError: String? = nil

    // MARK: - Save
    private func saveGroup() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await saveGroupAsync()
            isSaving = false
        }
    }

    private func saveGroupAsync() async {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        let trimDesc = description.trimmingCharacters(in: .whitespaces)
        let trimLoc  = [city, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let maxMem   = Int(maxMembersText)
        let price    = Int(priceText) ?? 0

        let resolvedMinAge = ageGroup == .custom ? Int(minAge) : defaultMinAge(ageGroup)
        let resolvedMaxAge = ageGroup == .custom ? Int(maxAge) : defaultMaxAge(ageGroup)
        let resolvedCategory = category.isEmpty ? "Other" : category

        if isEditing, let existing = existingGroup {
            // Preserve existing imageURL — it gets set later if a new photo is selected
            var updated = CommunityGroup(
                id: existing.id, name: trimName,
                imageName: categoryIcon(resolvedCategory),
                description: trimDesc, memberCount: existing.memberCount,
                category: resolvedCategory,
                location: trimLoc, creatorID: existing.creatorID, adminName: profile.name,
                maxMembers: maxMem, requiresApproval: requiresApproval,
                isPublic: !isPrivate, isEvent: isEvent,
                isConnectionsOnly: isPrivate,
                hideLocationFromNonMembers: false,
                ageGroup: ageGroup, minAge: resolvedMinAge, maxAge: resolvedMaxAge,
                isPaid: isPaid, paymentType: isPaid ? paymentType : .free,
                price: isPaid ? price : 0
            )
            updated.imageURL = existing.imageURL   // don't wipe the old cover photo
            profile.updateCreatedGroup(updated)
            let isPublic        = !isPrivate
            let isConnectionsOnly = isPrivate
            let ageGroupDB: String = {
                switch ageGroup {
                case .any: return "any"; case .teen: return "teen"; case .young: return "young"
                case .adult: return "adult"; case .senior: return "senior"; case .custom: return "custom"
                }
            }()
            do {
                try await KnotService.update(
                    knotID: existing.id, name: trimName, description: trimDesc,
                    category: resolvedCategory, location: trimLoc,
                    isPublic: isPublic, isEvent: isEvent,
                    isConnectionsOnly: isConnectionsOnly,
                    hideLocationFromNonMembers: false,
                    requiresApproval: requiresApproval, maxMembers: maxMem,
                    ageGroup: ageGroupDB, minAge: resolvedMinAge, maxAge: resolvedMaxAge,
                    isPaid: false, paymentType: "free",
                    priceCents: 0
                )
            } catch {
                print("[CreateGroupView] KnotService.update error: \(error)")
                saveError = error.localizedDescription
                return
            }
            await profile.loadKnots()
            dismiss()
        } else {
            do {
                let ageGroupDB: String = {
                    switch ageGroup {
                    case .any:    return "any"
                    case .teen:   return "teen"
                    case .young:  return "young"
                    case .adult:  return "adult"
                    case .senior: return "senior"
                    case .custom: return "custom"
                    }
                }()
                _ = try await KnotService.create(
                    name                       : trimName,
                    description                : trimDesc,
                    category                   : resolvedCategory,
                    location                   : trimLoc,
                    isPublic                   : !isPrivate,
                    isEvent                    : isEvent,
                    requiresApproval           : requiresApproval,
                    isConnectionsOnly          : isPrivate,
                    hideLocationFromNonMembers : false,
                    maxMembers                 : maxMem,
                    ageGroup                   : ageGroupDB,
                    minAge                     : resolvedMinAge,
                    maxAge                     : resolvedMaxAge,
                    isPaid                     : false,
                    paymentType                : "free",
                    priceCents                 : 0
                )
                await profile.loadKnots()
                dismiss()
            } catch {
                print("[CreateGroupView] KnotService.create error: \(error)")
                saveError = error.localizedDescription
            }
        }
    }

    private func defaultMinAge(_ ag: AgeGroup) -> Int {
        switch ag {
        case .any: return 13; case .teen: return 13; case .young: return 18
        case .adult: return 26; case .senior: return 55; case .custom: return Int(minAge)
        }
    }
    private func defaultMaxAge(_ ag: AgeGroup) -> Int {
        switch ag {
        case .any: return 99; case .teen: return 17; case .young: return 25
        case .adult: return 54; case .senior: return 99; case .custom: return Int(maxAge)
        }
    }
}
