//
//  OnboardingProfileStep.swift
//  sonder
//

import SwiftUI
import SwiftData
import Supabase
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "OnboardingProfileStep")

/// Step 2: Profile setup — username (required), photo/name/bio (optional)
struct OnboardingProfileStep: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService

    @State private var username = ""
    @State private var firstName = ""
    @State private var bio = ""
    @State private var phoneNumber = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var isSaving = false

    // Username validation
    @State private var usernameStatus: UsernameStatus = .empty
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

    private let maxBioLength = 150

    enum UsernameStatus: Equatable {
        case empty
        case tooShort
        case invalidChars
        case checking
        case available
        case taken
    }

    private var isValid: Bool {
        usernameStatus == .available
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SonderSpacing.xl) {
                // Header
                VStack(spacing: SonderSpacing.xs) {
                    Text("Make it yours")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)
                }
                .padding(.top, SonderSpacing.lg)

                // Avatar
                avatarSection

                // Username (required)
                usernameSection

                // First name (optional)
                firstNameSection

                // Bio (optional)
                bioSection

                // Phone number (optional)
                phoneNumberSection

                // Save button
                Button(action: saveAndContinue) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(WarmButtonStyle(isPrimary: true))
                .disabled(!isValid || isSaving)
                .opacity(isValid && !isSaving ? 1 : 0.5)
                .padding(.top, SonderSpacing.md)
            }
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.bottom, SonderSpacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SonderColors.cream)
        .onAppear { loadCurrentValues() }
        .fullScreenCover(isPresented: $showImagePicker) {
            EditableImagePicker(
                onImagePicked: { image in
                    selectedImage = image
                    showImagePicker = false
                },
                onCancel: { showImagePicker = false }
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: SonderSpacing.sm) {
            Button { showImagePicker = true } label: {
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        avatarPlaceholder
                    }

                    if isUploading {
                        Color.black.opacity(0.4)
                        ProgressView().tint(.white)
                    }

                    // Camera badge
                    if !isUploading {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(SonderColors.terracotta)
                                    .clipShape(Circle())
                            }
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(SonderColors.warmGray, lineWidth: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(isUploading)

            Text("Add a photo")
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
                Text(username.isEmpty ? "?" : username.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(SonderColors.terracotta)
            }
    }

    // MARK: - Username

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Username")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                TextField("Choose a username", text: $username)
                    .font(SonderTypography.body)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: username) { _, newValue in
                        validateUsername(newValue)
                    }

                // Status indicator
                Group {
                    switch usernameStatus {
                    case .checking:
                        ProgressView()
                            .tint(SonderColors.terracotta)
                            .scaleEffect(0.8)
                    case .available:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SonderColors.sage)
                    case .taken, .invalidChars, .tooShort:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SonderColors.dustyRose)
                    case .empty:
                        EmptyView()
                    }
                }
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

            // Validation hint
            Group {
                switch usernameStatus {
                case .tooShort:
                    Text("Must be at least 3 characters")
                        .foregroundStyle(SonderColors.dustyRose)
                case .invalidChars:
                    Text("Letters, numbers, and underscores only")
                        .foregroundStyle(SonderColors.dustyRose)
                case .taken:
                    Text("Username is already taken")
                        .foregroundStyle(SonderColors.dustyRose)
                case .available:
                    Text("Username is available")
                        .foregroundStyle(SonderColors.sage)
                default:
                    Text("3-20 characters, letters, numbers, underscores")
                        .foregroundStyle(SonderColors.inkLight)
                }
            }
            .font(SonderTypography.caption)
        }
    }

    // MARK: - First Name

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

    // MARK: - Bio

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Bio")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(bio.count)/\(maxBioLength)")
                    .font(SonderTypography.caption)
                    .foregroundStyle(bio.count > maxBioLength ? .red : SonderColors.inkLight)
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
                .foregroundStyle(SonderColors.inkLight)
        }
    }

    // MARK: - Phone Number

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
            username = user.username
            firstName = user.firstName ?? ""
            phoneNumber = user.phoneNumber ?? ""
            // Trigger initial validation for the pre-filled username
            validateUsername(user.username)
        }
    }

    private func validateUsername(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Cancel any pending check
        usernameCheckTask?.cancel()

        guard !trimmed.isEmpty else {
            usernameStatus = .empty
            return
        }

        // Check length
        guard trimmed.count >= 3 && trimmed.count <= 20 else {
            usernameStatus = .tooShort
            return
        }

        // Check characters (alphanumeric + underscores)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            usernameStatus = .invalidChars
            return
        }

        // If it matches current user's username, it's available
        if trimmed.lowercased() == authService.currentUser?.username.lowercased() {
            usernameStatus = .available
            return
        }

        // Debounced uniqueness check
        usernameStatus = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await checkUsernameAvailability(trimmed)
        }
    }

    private func checkUsernameAvailability(_ name: String) async {
        do {
            let results: [User] = try await SupabaseConfig.client
                .from("users")
                .select("id")
                .ilike("username", pattern: name)
                .limit(1)
                .execute()
                .value

            if Task.isCancelled { return }

            if results.isEmpty {
                usernameStatus = .available
            } else if results.first?.id == authService.currentUser?.id {
                usernameStatus = .available
            } else {
                usernameStatus = .taken
            }
        } catch {
            // On network error, allow the user to continue
            if !Task.isCancelled {
                usernameStatus = .available
            }
        }
    }

    private func saveAndContinue() {
        guard let user = authService.currentUser, isValid else { return }
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)

        isSaving = true

        saveTask?.cancel()
        saveTask = Task {
            // Upload photo if selected
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
            user.bio = bio.isEmpty ? nil : bio
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
                try modelContext.save()
                guard !Task.isCancelled else { isSaving = false; return }
                await authService.syncUserProfile(user)

                SonderHaptics.notification(.success)

                await MainActor.run { onContinue() }
            } catch {
                logger.error("Error saving profile during onboarding: \(error.localizedDescription)")
            }

            isSaving = false
        }
    }

}
