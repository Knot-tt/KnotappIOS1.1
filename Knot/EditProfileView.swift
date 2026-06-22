import SwiftUI

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(UserProfile.self) var profile
    @State private var editName        = ""
    @State private var editBio         = ""

    @State private var editImage       : UIImage? = nil
    @State private var didPickNewPhoto = false
    @State private var showPhotoPicker = false
    @State private var isSaving        = false
    @State private var didLoadInitialState = false
    @Environment(\.dismiss) var dismiss

    var displayInitial: String { String(editName.prefix(1)).uppercased() }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Profile Picture Picker
                Button(action: { showPhotoPicker = true }) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            Circle().fill(Color.knotAccent).frame(width: 90, height: 90)
                            if let img = editImage {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                            } else {
                                Text(displayInitial)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(Color.knotOnAccent)
                            }
                        }
                        ZStack {
                            Circle().fill(Color.knotSurface).frame(width: 28, height: 28)
                                .shadow(color: Color.black.opacity(0.1), radius: 2)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                .sheet(isPresented: $showPhotoPicker) {
                    SingleImagePicker { img in
                        showPhotoPicker = false
                        editImage       = img
                        didPickNewPhoto = true
                    }
                }
                .padding(.top, 24)

                // Fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Your name", text: $editName)
                            .padding()
                            .background(Color.knotSurface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotBorder, lineWidth: 1))
                            .onChange(of: editName) { _, new in
                                if new.count > 50 { editName = String(new.prefix(50)) }
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Description")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("\(editBio.count) / 500")
                                .font(.caption2).foregroundColor(editBio.count > 500 ? .red : .secondary)
                        }
                        TextField("Tell your neighbours a bit about yourself...", text: $editBio, axis: .vertical)
                            .lineLimit(4...6)
                            .padding()
                            .background(Color.knotSurface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.knotBorder, lineWidth: 1))
                            .onChange(of: editBio) { _, new in
                                if new.count > 500 { editBio = String(new.prefix(500)) }
                            }
                    }

                }
                .padding(.horizontal)

                Button(action: {
                    guard !isSaving else { return }
                    isSaving = true
                    profile.name       = editName
                    profile.bio        = editBio
                    Task {
                        if let newImage = editImage, didPickNewPhoto {
                            await profile.uploadProfileImage(newImage)
                        } else {
                            await profile.saveProfileToSupabase()
                        }
                        dismiss()
                    }
                }) {
                    ZStack {
                        Text("Save Changes")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                            .opacity(isSaving ? 0 : 1)
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(editName.isEmpty ? Color.gray : Color.knotAccent)
                    .cornerRadius(12)
                }
                .disabled(editName.isEmpty || isSaving)
                .padding(.horizontal)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoadInitialState else { return }
            editName  = profile.name
            editBio   = profile.bio
            editImage = profile.profileImage
            didLoadInitialState = true
        }
    }
}
