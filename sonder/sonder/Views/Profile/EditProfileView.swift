//
//  EditProfileView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import Supabase
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "EditProfileView")

/// Edit profile sheet for updating username, bio, and avatar
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine

    @State private var firstName: String = ""
    @State private var username: String = ""
    @State private var phoneNumber: String = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SonderSpacing.xl) {
                    // Avatar section
                    avatarSection

                    // First name section
                    firstNameSection

                    // Username section
                    usernameSection

                    // Phone number section
                    phoneNumberSection
                }
                .padding(SonderSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SonderColors.cream)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(SonderColors.inkMuted)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(SonderColors.terracotta)
                    .disabled(isSaving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .fullScreenCover(isPresented: $showImagePicker) {
                EditableImagePicker(
                    onImagePicked: { image in
                        selectedImage = image
                        showImagePicker = false
                    },
                    onCancel: {
                        showImagePicker = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: SonderSpacing.sm) {
            Button {
                showImagePicker = true
            } label: {
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let urlString = authService.currentUser?.avatarURL,
                              let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 100, height: 100)) {
                            avatarPlaceholder
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
            .buttonStyle(.plain)
            .disabled(isUploading)

            Text("Tap to change photo")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                SonderColors.placeholderGradient
            )
            .overlay {
                Text(username.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    // MARK: - First Name Section

    private var firstNameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("First Name")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("Your first name", text: $firstName)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            Text("Used in greetings around the app")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
        }
    }

    // MARK: - Username Section

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Username")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("Your username", text: $username)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: username) { _, newValue in
                    if newValue.count > 24 { username = String(newValue.prefix(24)) }
                }
        }
    }

    // MARK: - Phone Number Section

    private var phoneNumberSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Phone Number")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField("(555) 123-4567", text: $phoneNumber)
                .font(SonderTypography.body)
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .keyboardType(.phonePad)

            Text("Used to help friends find you. Never shared publicly.")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
        }
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        if let user = authService.currentUser {
            firstName = user.firstName ?? ""
            username = user.username
            phoneNumber = user.phoneNumber ?? ""
        }
    }

    private func saveProfile() {
        guard let user = authService.currentUser else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else { return }

        isSaving = true

        saveTask?.cancel()
        saveTask = Task {
            // Upload new photo if selected
            var newAvatarURL = user.avatarURL
            if let image = selectedImage {
                isUploading = true
                newAvatarURL = await photoService.uploadPhoto(image, for: user.id)
                guard !Task.isCancelled else { isUploading = false; isSaving = false; return }
                isUploading = false
            }

            // Update user locally
            let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
            user.firstName = trimmedFirstName.isEmpty ? nil : trimmedFirstName
            user.username = trimmedUsername
            user.avatarURL = newAvatarURL

            // Normalize and hash phone number
            let normalizedPhone = ContactsService.normalizePhoneNumber(phoneNumber)
            if !normalizedPhone.isEmpty {
                user.phoneNumber = normalizedPhone
                user.phoneNumberHash = ContactsService.sha256Hash(normalizedPhone)
            } else {
                user.phoneNumber = nil
                user.phoneNumberHash = nil
            }

            user.updatedAt = Date()

            do {
                // Save to local SwiftData
                try modelContext.save()

                guard !Task.isCancelled else { isSaving = false; return }

                // Sync user profile to Supabase
                await authService.syncUserProfile(user)

                // Haptic feedback
                SonderHaptics.notification(.success)

                await MainActor.run {
                    dismiss()
                }
            } catch {
                logger.error("Error saving profile: \(error.localizedDescription)")
            }

            isSaving = false
        }
    }

}

#Preview {
    EditProfileView()
}
