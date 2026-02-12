//
//  EditProfileView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import Supabase

/// Edit profile sheet for updating username, bio, and avatar
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine

    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var isSaving = false

    private let maxBioLength = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.xl) {
                    // Avatar section
                    avatarSection

                    // Username section
                    usernameSection

                    // Bio section
                    bioSection
                }
                .padding(SonderSpacing.lg)
            }
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(SonderColors.inkMuted)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(SonderColors.terracotta)
                    .disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    await loadImage(from: newValue)
                }
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: SonderSpacing.sm) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let urlString = authService.currentUser?.avatarURL,
                              let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                avatarPlaceholder
                            }
                        }
                    } else {
                        avatarPlaceholder
                    }

                    if isUploading {
                        Color.black.opacity(0.4)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(SonderColors.warmGray, lineWidth: 4)
                }
            }
            .disabled(isUploading)

            Text("Tap to change photo")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(username.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Username Section

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Username")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("Your username", text: $username)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    // MARK: - Bio Section

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Bio")
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(bio.count)/\(maxBioLength)")
                    .font(SonderTypography.caption)
                    .foregroundColor(bio.count > maxBioLength ? .red : SonderColors.inkLight)
            }

            TextField("Coffee snob. Always hunting for the best ramen.", text: $bio, axis: .vertical)
                .font(SonderTypography.body)
                .lineLimit(3...5)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .onChange(of: bio) { _, newValue in
                    if newValue.count > maxBioLength {
                        bio = String(newValue.prefix(maxBioLength))
                    }
                }

            Text("Tell others what you love to explore")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkLight)
        }
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        if let user = authService.currentUser {
            username = user.username
            bio = user.bio ?? ""
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = image
                }
            }
        } catch {
            print("Error loading image: \(error)")
        }
    }

    private func saveProfile() {
        guard let user = authService.currentUser else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }

        isSaving = true

        Task {
            // Upload new photo if selected
            var newAvatarURL = user.avatarURL
            if let image = selectedImage {
                isUploading = true
                newAvatarURL = await photoService.uploadPhoto(image, for: user.id)
                isUploading = false
            }

            // Update user locally
            user.username = trimmedUsername
            user.bio = bio.isEmpty ? nil : bio
            user.avatarURL = newAvatarURL
            user.updatedAt = Date()

            do {
                // Save to local SwiftData
                try modelContext.save()

                // Sync user profile to Supabase
                await syncUserToSupabase(user)

                // Haptic feedback
                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Error saving profile: \(error)")
            }

            isSaving = false
        }
    }

    private func syncUserToSupabase(_ user: User) async {
        struct UserUpdate: Codable {
            let username: String
            let bio: String?
            let avatar_url: String?
            let updated_at: Date
        }

        let update = UserUpdate(
            username: user.username,
            bio: user.bio,
            avatar_url: user.avatarURL,
            updated_at: user.updatedAt
        )

        do {
            try await SupabaseConfig.client
                .from("users")
                .update(update)
                .eq("id", value: user.id)
                .execute()
            print("User profile synced to Supabase")
        } catch {
            print("Error syncing user to Supabase: \(error)")
        }
    }
}

#Preview {
    EditProfileView()
}
