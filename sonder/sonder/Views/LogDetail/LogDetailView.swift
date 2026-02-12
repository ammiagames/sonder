//
//  LogDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Editable detail view for a single log
struct LogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(PhotoService.self) private var photoService
    @Environment(AuthenticationService.self) private var authService

    let log: Log
    let place: Place

    // Editable state
    @State private var rating: Rating
    @State private var note: String
    @State private var tags: [String]
    @State private var selectedTripID: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var currentPhotoURL: String?

    // UI state
    @State private var showDeleteAlert = false
    @State private var showRemovePhotoAlert = false
    @State private var isSaving = false
    @State private var hasChanges = false
    @State private var showSavedToast = false
    @FocusState private var isNoteFocused: Bool

    @Query private var trips: [Trip]

    private let maxNoteLength = 280

    init(log: Log, place: Place) {
        self.log = log
        self.place = place
        _rating = State(initialValue: log.rating)
        _note = State(initialValue: log.note ?? "")
        _tags = State(initialValue: log.tags)
        _selectedTripID = State(initialValue: log.tripID)
        _currentPhotoURL = State(initialValue: log.photoURL)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero photo (tappable to change)
                photoSection

                // Content
                VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                    // Place info (not editable)
                    placeSection

                    sectionDivider

                    // Rating (tappable to change)
                    ratingSection

                    sectionDivider

                    // Note (tappable to edit)
                    noteSection

                    sectionDivider

                    // Tags (editable)
                    tagsSection

                    // Trip (tappable to change)
                    sectionDivider
                    tripSection

                    sectionDivider

                    // Meta info
                    metaSection

                    // Delete button
                    deleteSection
                }
                .padding(SonderSpacing.lg)
            }
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isNoteFocused = false
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            Group {
                if showSavedToast {
                    // Saved confirmation toast
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(SonderColors.sage)
                        Text("Saved")
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)
                    }
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.warmGray)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
                } else if hasChanges {
                    // Save button (pill style)
                    Button {
                        save()
                    } label: {
                        HStack(spacing: SonderSpacing.xs) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save")
                                    .font(SonderTypography.headline)
                            }
                        }
                        .padding(.horizontal, SonderSpacing.lg)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(SonderColors.terracotta)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: SonderColors.terracotta.opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(isSaving)
                }
            }
            .padding(.bottom, SonderSpacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: hasChanges)
            .animation(.easeInOut(duration: 0.25), value: showSavedToast)
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    currentPhotoURL = nil
                    hasChanges = true
                }
            }
        }
        .onChange(of: rating) { _, _ in hasChanges = true }
        .onChange(of: note) { _, _ in hasChanges = true }
        .onChange(of: tags) { _, _ in hasChanges = true }
        .onChange(of: selectedTripID) { _, _ in hasChanges = true }
        .alert("Delete Log", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteLog()
            }
        } message: {
            Text("Are you sure you want to delete this log? This action cannot be undone.")
        }
        .alert("Remove Photo", isPresented: $showRemovePhotoAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                currentPhotoURL = nil
                selectedImage = nil
                selectedPhotoItem = nil
                hasChanges = true
            }
        } message: {
            Text("Remove this photo from your log?")
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        ZStack(alignment: .topTrailing) {
            // Photo display
            Group {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = currentPhotoURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            photoPlaceholder
                                .overlay { ProgressView() }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placePhoto
                        @unknown default:
                            photoPlaceholder
                        }
                    }
                } else {
                    placePhoto
                }
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .clipped()

            // Photo controls overlay
            HStack(spacing: 12) {
                // Remove photo button (if there's a user photo)
                if selectedImage != nil || currentPhotoURL != nil {
                    Button {
                        showRemovePhotoAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }

                // Change photo button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var placePhoto: some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 800) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    photoPlaceholder
                        .overlay { ProgressView() }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
        } else {
            photoPlaceholder
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(SonderColors.warmGray)
            .frame(height: 1)
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: SonderSpacing.xs) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                    Text("Tap camera to add photo")
                        .font(SonderTypography.caption)
                }
                .foregroundColor(SonderColors.terracotta.opacity(0.6))
            }
    }

    // MARK: - Place Section

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack(spacing: SonderSpacing.xs) {
                Image(systemName: "mappin")
                    .font(.system(size: 12))
                    .foregroundColor(SonderColors.inkMuted)
                Text(place.address)
                    .font(SonderTypography.caption)
                    .foregroundColor(SonderColors.inkMuted)
            }
        }
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Rating")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            HStack(spacing: SonderSpacing.sm) {
                ForEach(Rating.allCases, id: \.self) { ratingOption in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            rating = ratingOption
                        }
                    } label: {
                        VStack(spacing: SonderSpacing.xxs) {
                            Text(ratingOption.emoji)
                                .font(.system(size: 32))

                            Text(ratingOption.displayName)
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(rating == ratingOption ? SonderColors.terracotta.opacity(0.15) : SonderColors.warmGray)
                        .foregroundColor(rating == ratingOption ? SonderColors.terracotta : SonderColors.inkDark)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: SonderSpacing.radiusMd)
                                .stroke(rating == ratingOption ? SonderColors.terracotta : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            HStack {
                Text("Note")
                    .font(SonderTypography.headline)
                    .foregroundColor(SonderColors.inkDark)

                Spacer()

                Text("\(note.count)/\(maxNoteLength)")
                    .font(SonderTypography.caption)
                    .foregroundColor(note.count > maxNoteLength ? .red : SonderColors.inkLight)
                    .opacity(isNoteFocused ? 1 : 0)
            }

            TextField("Add a note...", text: $note, axis: .vertical)
                .font(SonderTypography.body)
                .lineLimit(3...10)
                .padding(SonderSpacing.sm)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                .focused($isNoteFocused)
                .onChange(of: note) { _, newValue in
                    if newValue.count > maxNoteLength {
                        note = String(newValue.prefix(maxNoteLength))
                    }
                }
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Tags")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            TagInputView(selectedTags: $tags)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text("Trip")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            Menu {
                Button("None") {
                    selectedTripID = nil
                }

                ForEach(trips, id: \.id) { trip in
                    Button(trip.name) {
                        selectedTripID = trip.id
                    }
                }
            } label: {
                HStack {
                    if let tripID = selectedTripID,
                       let trip = trips.first(where: { $0.id == tripID }) {
                        Label(trip.name, systemImage: "airplane")
                            .font(SonderTypography.body)
                            .foregroundColor(SonderColors.inkDark)
                    } else {
                        Label("No trip selected", systemImage: "airplane")
                            .font(SonderTypography.body)
                            .foregroundColor(SonderColors.inkMuted)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(SonderColors.inkLight)
                }
                .padding(SonderSpacing.md)
                .background(SonderColors.warmGray)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
            }
        }
    }

    // MARK: - Meta Section

    private var metaSection: some View {
        HStack {
            Text("Logged")
                .font(SonderTypography.caption)
                .foregroundColor(SonderColors.inkMuted)
            Spacer()
            Text(log.createdAt.formatted(date: .long, time: .shortened))
                .font(SonderTypography.body)
                .foregroundColor(SonderColors.inkDark)
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Label("Delete Log", systemImage: "trash")
                    .font(SonderTypography.body)
                Spacer()
            }
            .padding(SonderSpacing.md)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
        }
        .padding(.top, SonderSpacing.lg)
    }

    // MARK: - Actions

    private func save() {
        guard let userId = authService.currentUser?.id else { return }

        isSaving = true
        isNoteFocused = false // Dismiss keyboard

        Task {
            // Upload new photo if selected
            var photoURL = currentPhotoURL
            if let image = selectedImage {
                photoURL = await photoService.uploadPhoto(image, for: userId)
            }

            // Update log properties
            log.rating = rating
            log.photoURL = photoURL
            log.note = note.isEmpty ? nil : note
            log.tags = tags
            log.tripID = selectedTripID
            log.updatedAt = Date()
            log.syncStatus = .pending

            do {
                try modelContext.save()
                await syncEngine.syncNow()

                await MainActor.run {
                    isSaving = false
                    hasChanges = false

                    // Haptic feedback
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)

                    // Show toast
                    showSavedToast = true

                    // Auto-dismiss toast after 1.5 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showSavedToast = false
                    }
                }
            } catch {
                print("Failed to save log: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }

    private func deleteLog() {
        modelContext.delete(log)
        try? modelContext.save()

        Task {
            await syncEngine.syncNow()
        }

        dismiss()
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        FlowLayoutWrapper {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(SonderTypography.caption)
                    .padding(.horizontal, SonderSpacing.sm)
                    .padding(.vertical, SonderSpacing.xxs)
                    .background(SonderColors.terracotta.opacity(0.1))
                    .foregroundColor(SonderColors.terracotta)
                    .clipShape(Capsule())
            }
        }
    }
}

struct FlowLayoutWrapper: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(in: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                           y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    private func flowLayout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

#Preview {
    NavigationStack {
        LogDetailView(
            log: Log(
                userID: "user123",
                placeID: "place123",
                rating: .mustSee,
                note: "Amazing coffee! The pour-over was exceptional and the staff was super friendly.",
                tags: ["coffee", "cafe", "workspace"]
            ),
            place: Place(
                id: "place123",
                name: "Blue Bottle Coffee",
                address: "123 Main St, San Francisco, CA",
                latitude: 37.7749,
                longitude: -122.4194
            )
        )
    }
}
