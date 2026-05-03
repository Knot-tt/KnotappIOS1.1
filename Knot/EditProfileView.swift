import SwiftUI
import PhotosUI

// MARK: - Edit Profile View
struct EditProfileView: View {
    @Environment(UserProfile.self) var profile
    @State private var editName       = ""
    @State private var editBio        = ""
    @State private var editStreet     = ""
    @State private var editCity       = ""
    @State private var editPostalCode = ""
    @State private var editCountry    = ""
    @State private var editImage      : UIImage? = nil
    @State private var selectedPhoto  : PhotosPickerItem? = nil
    @State private var isSaving       = false
    @Environment(\.dismiss) var dismiss

    var displayInitial: String { String(editName.prefix(1)).uppercased() }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Profile Picture Picker
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            Circle().fill(Color.black).frame(width: 90, height: 90)
                            if let img = editImage {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                            } else {
                                Text(displayInitial)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        ZStack {
                            Circle().fill(Color.white).frame(width: 28, height: 28)
                                .shadow(color: Color.black.opacity(0.1), radius: 2)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            editImage = uiImage
                        }
                    }
                }
                .padding(.top, 24)

                // Fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("Your name", text: $editName)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.gray)
                        TextField("Tell your neighbours a bit about yourself...", text: $editBio, axis: .vertical)
                            .lineLimit(4...6)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Address")
                            .font(.caption)
                            .foregroundColor(.gray)
                        VStack(spacing: 8) {
                            TextField("Street address", text: $editStreet)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                            HStack(spacing: 8) {
                                TextField("City", text: $editCity)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                                TextField("Postal Code", text: $editPostalCode)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                                    .frame(maxWidth: 130)
                            }
                            TextField("Country", text: $editCountry)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                        }
                        Text("Your address is private and only used to show you relevant local content.")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)

                Button(action: {
                    guard !isSaving else { return }
                    isSaving = true
                    profile.name       = editName
                    profile.bio        = editBio
                    profile.street     = editStreet
                    profile.city       = editCity
                    profile.postalCode = editPostalCode
                    profile.country    = editCountry
                    Task {
                        if let newImage = editImage, selectedPhoto != nil {
                            await profile.uploadProfileImage(newImage)
                        } else {
                            await profile.saveProfileToSupabase()
                        }
                        dismiss()   // dismiss AFTER the save/upload completes
                    }
                }) {
                    ZStack {
                        Text("Save Changes")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .opacity(isSaving ? 0 : 1)
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(editName.isEmpty ? Color.gray : Color.black)
                    .cornerRadius(12)
                }
                .disabled(editName.isEmpty || isSaving)
                .padding(.horizontal)
            }
        }
        .background(Color(.systemGray6).ignoresSafeArea())
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            editName       = profile.name
            editBio        = profile.bio
            editStreet     = profile.street
            editCity       = profile.city
            editPostalCode = profile.postalCode
            editCountry    = profile.country
            editImage      = profile.profileImage
        }
    }
}
