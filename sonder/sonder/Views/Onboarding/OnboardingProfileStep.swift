//
//  OnboardingProfileStep.swift
//  sonder
//

import SwiftUI
import SwiftData
import Supabase

/// Step 2: Profile setup — username (required), photo/name/bio (optional)
struct OnboardingProfileStep: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthenticationService.self) private var authService
    @Environment(PhotoService.self) private var photoService

    @State private var username = ""
    @State private var firstName = ""
    @State private var bio = ""
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploading = false
    @State private var isSaving = false

    // Username validation
    @State private var usernameStatus: UsernameStatus = .empty
    @State private var usernameCheckTask: Task<Void, Never>?

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
                        .foregroundColor(SonderColors.inkDark)
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
                                    .foregroundColor(.white)
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
                Text(username.isEmpty ? "?" : username.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(SonderColors.terracotta)
            }
    }

    // MARK: - Username

    private var usernameSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Username")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
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
                            .foregroundColor(SonderColors.sage)
                    case .taken, .invalidChars, .tooShort:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(SonderColors.dustyRose)
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
                        .foregroundColor(SonderColors.dustyRose)
                case .invalidChars:
                    Text("Letters, numbers, and underscores only")
                        .foregroundColor(SonderColors.dustyRose)
                case .taken:
                    Text("Username is already taken")
                        .foregroundColor(SonderColors.dustyRose)
                case .available:
                    Text("Username is available")
                        .foregroundColor(SonderColors.sage)
                default:
                    Text("3-20 characters, letters, numbers, underscores")
                        .foregroundColor(SonderColors.inkLight)
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
                .foregroundColor(SonderColors.inkMuted)
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
                .foregroundColor(SonderColors.inkLight)
        }
    }

    // MARK: - Bio

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
            firstName = user.firstName ?? ""
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

        Task {
            // Upload photo if selected
            var newAvatarURL = user.avatarURL
            if let image = selectedImage {
                isUploading = true
                newAvatarURL = await photoService.uploadPhoto(image, for: user.id)
                isUploading = false
            }

            // Update user locally
            let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
            user.firstName = trimmedFirstName.isEmpty ? nil : trimmedFirstName
            user.username = trimmedUsername
            user.bio = bio.isEmpty ? nil : bio
            user.avatarURL = newAvatarURL
            user.updatedAt = Date()

            do {
                try modelContext.save()
                await syncUserToSupabase(user)

                let feedback = UINotificationFeedbackGenerator()
                feedback.notificationOccurred(.success)

                await MainActor.run { onContinue() }
            } catch {
                print("Error saving profile during onboarding: \(error)")
            }

            isSaving = false
        }
    }

    private func syncUserToSupabase(_ user: User) async {
        struct UserUpdate: Codable {
            let first_name: String?
            let username: String
            let bio: String?
            let avatar_url: String?
            let updated_at: Date
        }

        let update = UserUpdate(
            first_name: user.firstName,
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
        } catch {
            print("Error syncing user during onboarding: \(error)")
        }
    }
}
