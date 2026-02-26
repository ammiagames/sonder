//
//  CreateEditTripView.swift
//  sonder
//
//  Created by Michael Song on 2/10/26.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.sonder.app", category: "CreateEditTripView")

enum TripFormMode {
    case create
    case edit(Trip)
}

/// Form for creating or editing a trip
struct CreateEditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(TripService.self) private var tripService
    @Environment(PhotoService.self) private var photoService
    @Environment(SyncEngine.self) private var syncEngine

    @Environment(\.modelContext) private var modelContext

    let mode: TripFormMode
    var onTripCreated: ((Trip) -> Void)?
    var onDelete: (() -> Void)?

    @State private var name = ""
    @State private var tripDescription = ""
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var coverPhotoURL: String?
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var showSavedToast = false
    @State private var showDateRangePicker = false
    @State private var showDeleteAlert = false
    @State private var showBulkImport = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingTrip: Trip? {
        if case .edit(let trip) = mode { return trip }
        return nil
    }

    private func refreshData() {
        // Reload trip data from SwiftData after bulk import dismiss
        if let trip = existingTrip {
            name = trip.name
            tripDescription = trip.tripDescription ?? ""
            startDate = trip.startDate
            endDate = trip.endDate
            coverPhotoURL = trip.coverPhotoURL
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Cover photo section
                Section {
                    coverPhotoSection
                }

                // Name section
                Section {
                    TextField("Trip Name", text: $name)
                } header: {
                    Text("Name")
                }

                // Description section
                Section {
                    TextField("What's this trip about?", text: $tripDescription, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Description (Optional)")
                }

                // Date section
                Section {
                    Button {
                        showDateRangePicker = true
                    } label: {
                        HStack(spacing: SonderSpacing.sm) {
                            Image(systemName: "calendar")
                                .foregroundStyle(SonderColors.inkLight)
                            Text("Dates")
                                .foregroundStyle(SonderColors.inkDark)
                            Spacer()
                            Text(tripDateSummary)
                                .font(SonderTypography.body)
                                .foregroundStyle(hasTripDates ? SonderColors.terracotta : SonderColors.inkLight)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if hasTripDates {
                        Button(role: .destructive) {
                            SonderHaptics.impact(.soft, intensity: 0.45)
                            startDate = nil
                            endDate = nil
                        } label: {
                            Label("Clear dates", systemImage: "xmark.circle")
                                .font(SonderTypography.caption)
                        }
                    }
                } header: {
                    Text("Dates (Optional)")
                } footer: {
                    Text("Choose start and end dates from a single calendar.")
                }

                // Import from Photos section (edit mode only)
                if isEditing {
                    Section {
                        Button {
                            showBulkImport = true
                        } label: {
                            HStack(spacing: SonderSpacing.sm) {
                                Image(systemName: "camera.fill")
                                    .foregroundStyle(SonderColors.terracotta)
                                Text("Import from Photos")
                                    .foregroundStyle(SonderColors.inkDark)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SonderColors.inkLight)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Delete section (edit mode only)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Trip")
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(SonderColors.cream)
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.colorScheme, .light)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveTrip()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SonderColors.sage)
                        Text("Saved")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                    }
                    .padding(.horizontal, SonderSpacing.md)
                    .padding(.vertical, SonderSpacing.sm)
                    .background(SonderColors.warmGray)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(SonderShadows.softOpacity), radius: SonderShadows.softRadius, y: SonderShadows.softY)
                    .padding(.bottom, SonderSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSavedToast)
            .alert("Delete Trip", isPresented: $showDeleteAlert) {
                Button("Delete Trip & Logs", role: .destructive) {
                    deleteTrip(keepLogs: false)
                }
                Button("Delete Trip, Keep Logs") {
                    deleteTrip(keepLogs: true)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you also want to delete all logs in this trip?")
            }
            .onAppear {
                loadExistingData()
            }
            .sheet(isPresented: $showImagePicker) {
                EditableImagePicker { image in
                    selectedImage = image
                    showImagePicker = false
                    Task { await uploadSelectedImage(image) }
                } onCancel: {
                    showImagePicker = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showDateRangePicker) {
                TripDateRangePickerSheet(
                    startDate: $startDate,
                    endDate: $endDate
                )
            }
            .fullScreenCover(isPresented: $showBulkImport) {
                if let trip = existingTrip {
                    BulkPhotoImportView(tripID: trip.id, tripName: trip.name)
                }
            }
            .onChange(of: showBulkImport) { _, isShowing in
                if !isShowing { refreshData() }
            }
        }
    }

    // MARK: - Cover Photo Section

    private var coverPhotoSection: some View {
        VStack(spacing: 12) {
            // Photo preview — show local image first, then remote URL
            Group {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let urlString = coverPhotoURL,
                          let url = URL(string: urlString) {
                    DownsampledAsyncImage(url: url, targetSize: CGSize(width: 400, height: 150)) {
                        coverPlaceholder
                    }
                    .id(urlString)
                } else {
                    coverPlaceholder
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isUploadingPhoto {
                    Color.black.opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ProgressView()
                        .tint(.white)
                }
            }

            // Photo buttons
            HStack {
                Button {
                    showImagePicker = true
                } label: {
                    Label(
                        coverPhotoURL == nil && selectedImage == nil ? "Add Cover Photo" : "Change Photo",
                        systemImage: "photo"
                    )
                }
                .disabled(isUploadingPhoto)

                if coverPhotoURL != nil || selectedImage != nil {
                    Button(role: .destructive) {
                        selectedImage = nil
                        coverPhotoURL = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .disabled(isUploadingPhoto)
                }
            }
            .font(.subheadline)
        }
    }

    private var coverPlaceholder: some View {
        TripCoverPlaceholderView(
            seedKey: coverPhotoURL ?? name,
            title: name.isEmpty ? "New Trip" : name,
            caption: "Add a cover photo"
        )
    }

    private var hasTripDates: Bool {
        startDate != nil || endDate != nil
    }

    private var tripDateSummary: String {
        if let start = startDate, let end = endDate {
            let normalizedStart = Calendar.current.startOfDay(for: start)
            let normalizedEnd = Calendar.current.startOfDay(for: end)
            if Calendar.current.isDate(normalizedStart, inSameDayAs: normalizedEnd) {
                return normalizedStart.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return "\(normalizedStart.formatted(.dateTime.month(.abbreviated).day())) - \(normalizedEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        if let start = startDate {
            return start.formatted(.dateTime.month(.abbreviated).day().year())
        }
        if let end = endDate {
            return "Until \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return "Add dates"
    }

    // MARK: - Actions

    private func loadExistingData() {
        if let trip = existingTrip {
            name = trip.name
            tripDescription = trip.tripDescription ?? ""
            startDate = trip.startDate
            endDate = trip.endDate
            coverPhotoURL = trip.coverPhotoURL
        }
    }

    private func uploadSelectedImage(_ image: UIImage) async {
        guard let userID = authService.currentUser?.id else { return }

        isUploadingPhoto = true
        defer { isUploadingPhoto = false }

        if let url = await photoService.uploadPhoto(image, for: userID) {
            coverPhotoURL = url
        }
    }

    private func saveTrip() {
        guard let userID = authService.currentUser?.id else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true

        Task {
            do {
                let trimmedDescription = tripDescription.trimmingCharacters(in: .whitespaces)

                let savedTrip: Trip

                if let trip = existingTrip {
                    // Update existing
                    trip.name = trimmedName
                    trip.tripDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
                    trip.startDate = startDate
                    trip.endDate = endDate
                    trip.coverPhotoURL = coverPhotoURL
                    try await tripService.updateTrip(trip)
                    savedTrip = trip
                } else {
                    // Create new
                    let newTrip = try await tripService.createTrip(
                        name: trimmedName,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        startDate: startDate,
                        endDate: endDate,
                        coverPhotoURL: coverPhotoURL,
                        createdBy: userID
                    )
                    onTripCreated?(newTrip)
                    savedTrip = newTrip
                }

                // Haptic feedback
                SonderHaptics.notification(.success)

                if isEditing {
                    isSaving = false
                    showSavedToast = true
                    try? await Task.sleep(for: .seconds(1.0))
                    guard !Task.isCancelled else { return }
                    dismiss()
                } else {
                    dismiss()
                }
            } catch {
                logger.error("Error saving trip: \(error.localizedDescription)")
            }

            isSaving = false
        }
    }

    private func deleteTrip(keepLogs: Bool) {
        guard let trip = existingTrip else { return }

        Task {
            do {
                if keepLogs {
                    try await tripService.deleteTrip(trip)
                } else {
                    try await tripService.deleteTripAndLogs(trip, syncEngine: syncEngine)
                }

                SonderHaptics.notification(.success)

                dismiss()
                onDelete?()
            } catch {
                logger.error("Error deleting trip: \(error.localizedDescription)")
            }
        }
    }
}

private struct TripDateRangePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var startDate: Date?
    @Binding var endDate: Date?

    @State private var draftStartDate: Date?
    @State private var draftEndDate: Date?
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    init(startDate: Binding<Date?>, endDate: Binding<Date?>) {
        self._startDate = startDate
        self._endDate = endDate

        let normalizedStart = startDate.wrappedValue.map { Calendar.current.startOfDay(for: $0) }
        let normalizedEnd = endDate.wrappedValue.map { Calendar.current.startOfDay(for: $0) }

        if normalizedStart == nil, let normalizedEnd {
            self._draftStartDate = State(initialValue: normalizedEnd)
            self._draftEndDate = State(initialValue: normalizedEnd)
        } else {
            self._draftStartDate = State(initialValue: normalizedStart)
            self._draftEndDate = State(initialValue: normalizedEnd)
        }

        let initialAnchor = normalizedStart ?? normalizedEnd ?? Calendar.current.startOfDay(for: Date())
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: initialAnchor)
        ) ?? initialAnchor
        self._displayedMonth = State(initialValue: monthStart)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        let head = Array(symbols[start...])
        let tail = Array(symbols[..<start])
        return head + tail
    }

    private var monthCells: [Date?] {
        guard
            let daysRange = calendar.range(of: .day, in: .month, for: displayedMonth),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else {
            return Array(repeating: nil, count: 42)
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingPadding = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalDays = daysRange.count

        return (0..<42).map { index in
            let dayOffset = index - leadingPadding
            guard dayOffset >= 0, dayOffset < totalDays else { return nil }
            return calendar.date(byAdding: .day, value: dayOffset, to: monthStart)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: SonderSpacing.md) {
                dateSummaryCard
                monthHeader
                weekdayHeader
                calendarGrid
                actionRow
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.top, SonderSpacing.sm)
            .padding(.bottom, SonderSpacing.md)
            .background(SonderColors.cream)
            .navigationTitle("Trip Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyAndDismiss() }
                }
            }
        }
    }

    private var dateSummaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selection")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkLight)
                .textCase(.uppercase)

            Text(selectionSummaryText)
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private var selectionSummaryText: String {
        if let start = draftStartDate, let end = draftEndDate {
            if calendar.isDate(start, inSameDayAs: end) {
                return start.formatted(.dateTime.month(.abbreviated).day().year())
            }
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        if let start = draftStartDate {
            return "Start: \(start.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return "Choose start and end dates"
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(SonderColors.warmGray)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(SonderColors.warmGray)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SonderColors.inkLight)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cellDate in
                if let date = cellDate {
                    dateCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 38)
                }
            }
        }
    }

    private func dateCell(for date: Date) -> some View {
        let normalized = calendar.startOfDay(for: date)
        let isStart = isSameDay(normalized, as: draftStartDate)
        let isEnd = isSameDay(normalized, as: draftEndDate)
        let isInRange = isDateInSelectedRange(normalized)

        return Button {
            selectDate(normalized)
        } label: {
            ZStack {
                if isInRange {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SonderColors.terracotta.opacity((isStart || isEnd) ? 0.28 : 0.14))
                }

                if isStart || isEnd {
                    Circle()
                        .fill(SonderColors.terracotta)
                        .padding(3)
                }

                Text("\(calendar.component(.day, from: normalized))")
                    .font(.system(size: 15, weight: (isStart || isEnd) ? .semibold : .regular, design: .rounded))
                    .foregroundStyle((isStart || isEnd) ? Color.white : SonderColors.inkDark)
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: SonderSpacing.sm) {
            Button("One day") {
                setOneDayRange()
            }
            .font(SonderTypography.caption)
            .foregroundStyle(SonderColors.terracotta)
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xs)
            .background(SonderColors.warmGray)
            .clipShape(Capsule())

            Spacer()

            Button("Clear") {
                clearDates()
            }
            .font(SonderTypography.caption)
            .foregroundStyle(.red.opacity(0.8))
            .padding(.horizontal, SonderSpacing.sm)
            .padding(.vertical, SonderSpacing.xs)
            .background(SonderColors.warmGray)
            .clipShape(Capsule())
        }
    }

    private func shiftMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = next
        SonderHaptics.impact(.soft, intensity: 0.35)
    }

    private func selectDate(_ date: Date) {
        if draftStartDate == nil || (draftStartDate != nil && draftEndDate != nil) {
            draftStartDate = date
            draftEndDate = nil
            SonderHaptics.impact(.light, intensity: 0.55)
            return
        }

        guard let start = draftStartDate else { return }
        if date < start {
            draftStartDate = date
            draftEndDate = start
        } else {
            draftEndDate = date
        }
        SonderHaptics.impact(.medium, intensity: 0.75)
    }

    private func setOneDayRange() {
        let day = calendar.startOfDay(for: draftStartDate ?? Date())
        draftStartDate = day
        draftEndDate = day
        SonderHaptics.impact(.medium, intensity: 0.65)
    }

    private func clearDates() {
        draftStartDate = nil
        draftEndDate = nil
        SonderHaptics.impact(.soft, intensity: 0.45)
    }

    private func applyAndDismiss() {
        if let start = draftStartDate, let end = draftEndDate, end < start {
            startDate = end
            endDate = start
        } else {
            startDate = draftStartDate
            endDate = draftEndDate
        }
        dismiss()
    }

    private func isDateInSelectedRange(_ date: Date) -> Bool {
        guard let start = draftStartDate, let end = draftEndDate else { return false }
        let lower = min(start, end)
        let upper = max(start, end)
        return date >= lower && date <= upper
    }

    private func isSameDay(_ lhs: Date, as rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }
}

#Preview {
    CreateEditTripView(mode: .create)
}
