import SwiftUI
import PhotosUI

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
    @State private var streetAddress = ""
    @State private var city          = ""
    @State private var postalCode    = ""
    @State private var country       = ""
    @State private var hideLocationFromNonMembers = false
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

    // Photos (optional)
    @State private var selectedPhotos : [PhotosPickerItem] = []
    @State private var groupImages    : [UIImage]          = []

    // Join Form
    @State private var showFormBuilder = false
    @State private var questions       : [FormQuestion]    = []

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

                // ── Photos (optional) ────────────────────────────────────
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)).frame(width: 80, height: 80)
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus").font(.system(size: 22)).foregroundColor(.gray)
                                        Text("Add").font(.caption2).foregroundColor(.gray)
                                    }
                                }
                            }
                            .onChange(of: selectedPhotos) { _, items in
                                Task {
                                    groupImages = []
                                    for item in items {
                                        if let data = try? await item.loadTransferable(type: Data.self),
                                           let img = UIImage(data: data) { groupImages.append(img) }
                                    }
                                }
                            }

                            ForEach(groupImages.indices, id: \.self) { i in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: groupImages[i])
                                        .resizable().scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button(action: { groupImages.remove(at: i) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.black.opacity(0.7))
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: { Text("Photos (optional)") }
                  footer: { Text("Add up to 6 photos. The first will be the cover.") }

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
                            Text(category.isEmpty ? "Select" : category).foregroundColor(.gray)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.gray)
                        }
                        .contentShape(Rectangle())
                    }
                    TextField("Max members (optional)", text: $maxMembersText).keyboardType(.numberPad)
                }

                // ── Location ─────────────────────────────────────────────
                Section {
                    TextField("Street address (optional)", text: $streetAddress)
                    TextField("City", text: $city)
                    TextField("Postal code (optional)", text: $postalCode).keyboardType(.numberPad)
                    TextField("Country", text: $country)
                    Toggle("Hide precise location from non-members", isOn: $hideLocationFromNonMembers)
                } header: { Text("Location") }
                  footer: { Text(hideLocationFromNonMembers
                      ? "Only members will see the full address. Others will see the city only."
                      : "Everyone can see the full address.") }

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
                            Text(ageGroup.rawValue).foregroundColor(.gray)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.gray)
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
                    Toggle("Paid Knot", isOn: $isPaid)
                        .onChange(of: isPaid) { _, paid in
                            // If toggling paid ON and type is still .free, default to per session
                            if paid && paymentType == .free { paymentType = .perSession }
                        }

                    if isPaid {
                        Menu {
                            Button("Per Session") { paymentType = .perSession }
                            Button("One Time")    { paymentType = .oneTime }
                        } label: {
                            HStack {
                                Text("Charge type").foregroundColor(.primary)
                                Spacer()
                                Text(paymentType == .perSession ? "Per Session" : "One Time")
                                    .foregroundColor(.gray)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2).foregroundColor(.gray)
                            }
                            .contentShape(Rectangle())
                        }
                        HStack {
                            Text("$").foregroundColor(Color(.systemGray))
                            TextField("Amount", text: $priceText).keyboardType(.numberPad)
                        }
                    }
                } header: { Text("Options") }
                  footer: {
                      if isPaid {
                          Text("Members will be charged $" + priceText + " " + (paymentType == .perSession ? "each session" : "once") + ".")
                      } else if isPrivate {
                          Text("Only people connected to you can see this Knot.")
                      } else {
                          Text("Anyone can discover this Knot.")
                      }
                  }

                // ── Join Form ─────────────────────────────────────────────
                Section {
                    Button(action: { showFormBuilder = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus").foregroundColor(.black)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(questions.isEmpty ? "Create Join Form" : "Edit Join Form (\(questions.count) question\(questions.count == 1 ? "" : "s"))")
                                    .foregroundColor(.black)
                                if !questions.isEmpty {
                                    Text("Tap to edit questions")
                                        .font(.caption).foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(.systemGray3))
                        }
                    }
                    if !questions.isEmpty {
                        Button(role: .destructive, action: { questions.removeAll() }) {
                            Label("Remove Form", systemImage: "trash")
                        }
                    }
                } header: { Text("Join Form") }
                  footer: { Text("Applicants fill this in when requesting to join. Mix open-ended and multiple choice questions.") }
            }
            .navigationTitle(isEditing ? "Edit Knot" : "New Knot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { saveGroup() }) {
                        if isSaving {
                            ProgressView().tint(.black)
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
            .sheet(isPresented: $showFormBuilder) {
                FormBuilderView(questions: $questions)
            }
        }
    }

    // MARK: - Populate for editing
    private func populateIfEditing() {
        guard let g = existingGroup else { return }
        name                          = g.name
        description                   = g.description
        category                      = g.category
        city                          = g.location  // best-effort: put full stored location into city
        hideLocationFromNonMembers    = g.hideLocationFromNonMembers
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
        questions        = g.joinFormQuestions
    }

    @State private var isSaving = false

    // MARK: - Save
    private func saveGroup() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            await saveGroupAsync()
            isSaving = false
        }
    }

    /// Resolves the cover image to upload. Falls back to loading from the picker if
    /// `groupImages` is empty due to a race (user tapped Save before onChange finished).
    private func resolveCoverImage() async -> UIImage? {
        print("[CreateGroupView] resolveCoverImage: groupImages=\(groupImages.count), selectedPhotos=\(selectedPhotos.count)")
        if let img = groupImages.first {
            print("[CreateGroupView] resolveCoverImage: using groupImages[0]")
            return img
        }
        guard let pick = selectedPhotos.first else {
            print("[CreateGroupView] resolveCoverImage: NO image to upload")
            return nil
        }
        do {
            if let data = try await pick.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                print("[CreateGroupView] resolveCoverImage: loaded from picker (\(data.count) bytes)")
                return img
            }
        } catch {
            print("[CreateGroupView] resolveCoverImage: loadTransferable FAILED → \(error)")
        }
        return nil
    }

    private func saveGroupAsync() async {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        let trimDesc = description.trimmingCharacters(in: .whitespaces)
        let trimLoc  = [streetAddress, city, postalCode, country]
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
                location: trimLoc, adminName: profile.name,
                maxMembers: maxMem, requiresApproval: requiresApproval,
                isPublic: !isPrivate, isEvent: isEvent,
                isConnectionsOnly: isPrivate,
                hideLocationFromNonMembers: hideLocationFromNonMembers,
                ageGroup: ageGroup, minAge: resolvedMinAge, maxAge: resolvedMaxAge,
                isPaid: isPaid, paymentType: isPaid ? paymentType : .free,
                price: isPaid ? price : 0,
                joinFormQuestions: questions
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
            let paymentTypeDB: String = {
                if !isPaid { return "free" }
                switch paymentType {
                case .free, .perSession: return "per_session"
                case .oneTime: return "one_time"
                }
            }()
            do {
                try await KnotService.update(
                    knotID: existing.id, name: trimName, description: trimDesc,
                    category: resolvedCategory, location: trimLoc,
                    isPublic: isPublic, isEvent: isEvent,
                    isConnectionsOnly: isConnectionsOnly,
                    hideLocationFromNonMembers: hideLocationFromNonMembers,
                    requiresApproval: requiresApproval, maxMembers: maxMem,
                    ageGroup: ageGroupDB, minAge: resolvedMinAge, maxAge: resolvedMaxAge,
                    isPaid: isPaid, paymentType: paymentTypeDB,
                    priceCents: (isPaid ? price : 0) * 100
                )
            } catch {
                print("[CreateGroupView] KnotService.update error: \(error)")
            }
            // Upload cover photo via UserProfile (same pattern as profile picture)
            if let coverImage = await resolveCoverImage() {
                await profile.uploadKnotCoverImage(knotID: existing.id, image: coverImage)
            }
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
                let paymentTypeDB: String = {
                    if !isPaid { return "free" }
                    switch paymentType {
                    case .free, .perSession: return "per_session"
                    case .oneTime:           return "one_time"
                    }
                }()
                let dbKnot = try await KnotService.create(
                    name                       : trimName,
                    description                : trimDesc,
                    category                   : resolvedCategory,
                    location                   : trimLoc,
                    isPublic                   : !isPrivate,
                    isEvent                    : isEvent,
                    requiresApproval           : requiresApproval,
                    isConnectionsOnly          : isPrivate,
                    hideLocationFromNonMembers : hideLocationFromNonMembers,
                    maxMembers                 : maxMem,
                    ageGroup                   : ageGroupDB,
                    minAge                     : resolvedMinAge,
                    maxAge                     : resolvedMaxAge,
                    isPaid                     : isPaid,
                    paymentType                : isPaid ? paymentTypeDB : "free",
                    priceCents                 : isPaid ? price * 100 : 0
                )
                let newGroup = CommunityGroup(
                    id          : dbKnot.id,
                    name        : dbKnot.name,
                    imageName   : categoryIcon(dbKnot.category),
                    description : dbKnot.description,
                    memberCount : 1,
                    category    : dbKnot.category,
                    location    : dbKnot.location,
                    adminName   : profile.name,
                    maxMembers  : dbKnot.maxMembers,
                    requiresApproval           : dbKnot.requiresApproval,
                    isPublic                   : dbKnot.isPublic,
                    isEvent                    : dbKnot.isEvent,
                    isConnectionsOnly          : dbKnot.isConnectionsOnly,
                    hideLocationFromNonMembers : dbKnot.hideLocationFromNonMembers,
                    ageGroup    : ageGroup,
                    minAge      : dbKnot.minAge,
                    maxAge      : dbKnot.maxAge,
                    isPaid      : dbKnot.isPaid,
                    paymentType : paymentType,
                    price       : dbKnot.priceCents / 100,
                    joinFormQuestions: questions
                )
                profile.addKnot(newGroup)

                // Upload cover photo via UserProfile (same pattern as profile picture)
                if let coverImage = await resolveCoverImage() {
                    await profile.uploadKnotCoverImage(knotID: dbKnot.id, image: coverImage)
                }
            } catch {
                print("[CreateGroupView] KnotService.create error: \(error)")
            }
        }
        dismiss()
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

// MARK: - Form Builder View (Google Forms style)
struct FormBuilderView: View {
    @Binding var questions: [FormQuestion]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if questions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text").font(.system(size: 40)).foregroundColor(Color(.systemGray3))
                        Text("No questions yet").font(.headline).foregroundColor(Color(.systemGray))
                        Text("Add open-ended or multiple choice questions below.")
                            .font(.caption).foregroundColor(Color(.systemGray3)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(40)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach($questions) { $q in
                        QuestionBuilderRow(question: $q) {
                            questions.removeAll { $0.id == q.id }
                        }
                    }
                    .onMove { from, to in questions.move(fromOffsets: from, toOffset: to) }
                }
            }
            .navigationTitle("Join Form")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: { questions.append(FormQuestion(type: .openEnded, prompt: "")) }) {
                        Label("Open Ended", systemImage: "text.alignleft")
                    }
                    Spacer()
                    Button(action: { questions.append(FormQuestion(type: .mcq, prompt: "", options: ["Option 1", "Option 2"])) }) {
                        Label("Multiple Choice", systemImage: "list.bullet")
                    }
                }
            }
        }
    }
}

// MARK: - Question Builder Row
struct QuestionBuilderRow: View {
    @Binding var question: FormQuestion
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Picker("", selection: $question.type) {
                    ForEach(FormQuestion.QuestionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden()
                Spacer()
                HStack(spacing: 4) {
                    Toggle("", isOn: $question.required).labelsHidden()
                    Text("Required").font(.caption).foregroundColor(.gray)
                }
                Button(action: onDelete) { Image(systemName: "trash").foregroundColor(.red) }.padding(.leading, 8)
            }

            TextField("Question", text: $question.prompt, axis: .vertical)
                .lineLimit(1...3).padding(10).background(Color(.systemGray6)).cornerRadius(8)

            if question.type == .mcq {
                VStack(spacing: 6) {
                    ForEach(question.options.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Image(systemName: "circle").foregroundColor(.gray).font(.caption)
                            TextField("Option \(i + 1)", text: $question.options[i])
                            if question.options.count > 2 {
                                Button(action: { question.options.remove(at: i) }) {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                Button(action: { question.options.append("") }) {
                    Label("Add Option", systemImage: "plus").font(.caption).foregroundColor(.black)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
