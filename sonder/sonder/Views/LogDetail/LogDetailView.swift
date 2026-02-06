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
                VStack(alignment: .leading, spacing: 20) {
                    // Place info (not editable)
                    placeSection

                    Divider()

                    // Rating (tappable to change)
                    ratingSection

                    Divider()

                    // Note (tappable to edit)
                    noteSection

                    Divider()

                    // Tags (editable)
                    tagsSection

                    // Trip (tappable to change)
                    Divider()
                    tripSection

                    Divider()

                    // Meta info
                    metaSection

                    // Delete button
                    deleteSection
                }
                .padding()
            }
        }
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
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                } else if hasChanges {
                    // Save button (pill style)
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save")
                                    .fontWeight(.medium)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    }
                    .disabled(isSaving)
                }
            }
            .padding(.bottom, 20)
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

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                    Text("Tap camera to add photo")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
    }

    // MARK: - Place Section

    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin")
                    .foregroundColor(.secondary)
                Text(place.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Rating Section

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(Rating.allCases, id: \.self) { ratingOption in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            rating = ratingOption
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(ratingOption.emoji)
                                .font(.system(size: 32))

                            Text(ratingOption.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(rating == ratingOption ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        .foregroundColor(rating == ratingOption ? .accentColor : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(rating == ratingOption ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(.headline)

                Spacer()

                Text("\(note.count)/\(maxNoteLength)")
                    .font(.caption)
                    .foregroundColor(note.count > maxNoteLength ? .red : .secondary)
                    .opacity(isNoteFocused ? 1 : 0)
            }

            TextField("Add a note...", text: $note, axis: .vertical)
                .lineLimit(3...10)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            TagInputView(selectedTags: $tags)
        }
    }

    // MARK: - Trip Section

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip")
                .font(.headline)

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
                            .foregroundColor(.primary)
                    } else {
                        Label("No trip selected", systemImage: "airplane")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Meta Section

    private var metaSection: some View {
        HStack {
            Text("Logged")
                .foregroundColor(.secondary)
            Spacer()
            Text(log.createdAt.formatted(date: .long, time: .shortened))
        }
        .font(.subheadline)
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            HStack {
                Spacer()
                Label("Delete Log", systemImage: "trash")
                Spacer()
            }
            .padding()
            .background(Color(.systemRed).opacity(0.1))
            .foregroundColor(.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 20)
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
                Text("#\(tag)")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
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
