//
//  LogDetailView.swift
//  sonder
//
//  Created by Michael Song on 2/5/26.
//

import SwiftUI
import SwiftData

/// Editable detail view for a single log
struct LogDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(PhotoService.self) private var photoService
    @Environment(AuthenticationService.self) private var authService

    let log: Log
    let place: Place
    /// Called before the log is deleted so the parent can clear navigation state
    var onDelete: (() -> Void)?

    // Editable state
    @State private var rating: Rating
    @State private var note: String
    @State private var tags: [String]
    @State private var selectedTripID: String?
    @State private var selectedImage: UIImage?
    @State private var currentPhotoURL: String?

    // UI state
    @State private var showDeleteAlert = false
    @State private var showRemovePhotoAlert = false
    @State private var showImagePicker = false
    @State private var isSaving = false
    @State private var hasChanges = false
    @State private var showSavedToast = false
    @FocusState private var isNoteFocused: Bool

    @Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
    @Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]

    @State private var showNewTripAlert = false
    @State private var newTripName = ""
    @State private var showAllTrips = false

    private let maxNoteLength = 280

    /// Trips the user can add logs to (owned + collaborating),
    /// sorted by most recently used (latest log added), then by creation date.
    private var availableTrips: [Trip] {
        guard let userID = authService.currentUser?.id else { return [] }
        let accessible = allTrips.filter { trip in
            trip.createdBy == userID || trip.collaboratorIDs.contains(userID)
        }
        let latestLogByTrip: [String: Date] = allLogs.reduce(into: [:]) { map, log in
            guard let tripID = log.tripID else { return }
            if map[tripID] == nil || log.createdAt > map[tripID]! {
                map[tripID] = log.createdAt
            }
        }
        return accessible.sorted { a, b in
            let aDate = latestLogByTrip[a.id] ?? a.createdAt
            let bDate = latestLogByTrip[b.id] ?? b.createdAt
            return aDate > bDate
        }
    }

    /// Chips to display: first 3 available trips, plus the currently selected trip if not already shown.
    private var visibleTrips: [Trip] {
        var result = Array(availableTrips.prefix(3))
        if let tripID = selectedTripID,
           !result.contains(where: { $0.id == tripID }),
           let trip = availableTrips.first(where: { $0.id == tripID }) {
            result.insert(trip, at: 0)
        }
        return result
    }

    private var selectedTripBinding: Binding<Trip?> {
        Binding(
            get: { allTrips.first(where: { $0.id == selectedTripID }) },
            set: { selectedTripID = $0?.id }
        )
    }

    init(log: Log, place: Place, onDelete: (() -> Void)? = nil) {
        self.log = log
        self.place = place
        self.onDelete = onDelete
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
        .toolbar(showImagePicker ? .hidden : .automatic, for: .tabBar)
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
        .sheet(isPresented: $showImagePicker) {
            EditableImagePicker { image in
                selectedImage = image
                currentPhotoURL = nil
                hasChanges = true
                showImagePicker = false
            } onCancel: {
                showImagePicker = false
            }
            .ignoresSafeArea()
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
                hasChanges = true
            }
        } message: {
            Text("Remove this photo from your log?")
        }
        .sheet(isPresented: $showAllTrips) {
            AllTripsPickerSheet(
                trips: availableTrips,
                selectedTrip: selectedTripBinding,
                isPresented: $showAllTrips
            )
        }
        .alert("New Trip", isPresented: $showNewTripAlert) {
            TextField("Trip name", text: $newTripName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                createNewTrip()
            }
            .disabled(newTripName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Enter a name for your trip")
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
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 250)) {
                        photoPlaceholder
                    }
                } else {
                    photoPlaceholder
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
                Button {
                    showImagePicker = true
                } label: {
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
                .foregroundColor(SonderColors.inkDark)
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
        VStack(alignment: .leading, spacing: SonderSpacing.sm) {
            Text("Trip")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkDark)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SonderSpacing.xs) {
                    ForEach(visibleTrips, id: \.id) { trip in
                        tripChip(trip)
                    }

                    if availableTrips.count > 3 {
                        Button {
                            showAllTrips = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("More")
                                    .font(SonderTypography.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, SonderSpacing.sm)
                            .padding(.vertical, SonderSpacing.xs)
                            .background(SonderColors.warmGray)
                            .foregroundColor(SonderColors.inkMuted)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(SonderColors.inkLight.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        newTripName = ""
                        showNewTripAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("New Trip")
                                .font(SonderTypography.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, SonderSpacing.sm)
                        .padding(.vertical, SonderSpacing.xs)
                        .background(SonderColors.warmGray)
                        .foregroundColor(SonderColors.inkDark)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(SonderColors.inkLight.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let tripID = selectedTripID,
               let trip = allTrips.first(where: { $0.id == tripID }) {
                HStack(spacing: SonderSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(SonderColors.terracotta)
                    Text("Saving to \(trip.name)")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTripID)
    }

    private func tripChip(_ trip: Trip) -> some View {
        let isSelected = selectedTripID == trip.id

        return HStack(spacing: 4) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 10))
            Text(trip.name)
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(isSelected ? SonderColors.terracotta : SonderColors.warmGray)
        .foregroundColor(isSelected ? .white : SonderColors.inkDark)
        .clipShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTripID = isSelected ? nil : trip.id
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func createNewTrip() {
        guard let userId = authService.currentUser?.id else { return }
        let trimmedName = newTripName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let trip = Trip(
            name: trimmedName,
            createdBy: userId
        )

        modelContext.insert(trip)
        try? modelContext.save()

        selectedTripID = trip.id
    }

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
        // Capture ID + engine before the view is removed from the hierarchy —
        // @Environment wrappers may stop resolving after dismissal, and
        // the @Model reference can become stale after navigation pop.
        let logID = log.id
        let engine = syncEngine

        // Let the parent clear its navigation state first so it won't
        // re-evaluate with an invalidated model object after deletion.
        onDelete?()
        dismiss()

        Task { @MainActor in
            // Wait for the navigation pop animation to finish before
            // removing the model — prevents SwiftData EXC_BREAKPOINT.
            try? await Task.sleep(for: .milliseconds(350))
            // Deletes from local SwiftData AND Supabase (fetches fresh by ID)
            await engine.deleteLog(id: logID)
        }
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
