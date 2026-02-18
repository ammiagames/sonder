//
//  AssignLogsToTripSheet.swift
//  sonder
//
//  Created by Michael Song on 2/16/26.
//

import SwiftUI

/// Multi-select sheet for assigning orphaned logs to a trip after creation.
struct AssignLogsToTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TripService.self) private var tripService

    let trip: Trip
    let orphanedLogs: [Log]
    let placesByID: [String: Place]

    @State private var selectedIDs: Set<String> = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                logList
                bottomBar
            }
            .background(SonderColors.cream)
            .navigationTitle("Add Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            Text(trip.name)
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkDark)

            Text("Select logs to add to this trip")
                .font(SonderTypography.caption)
                .foregroundStyle(SonderColors.inkMuted)

            HStack {
                Spacer()
                Button(selectedIDs.count == orphanedLogs.count ? "Deselect All" : "Select All") {
                    if selectedIDs.count == orphanedLogs.count {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(orphanedLogs.map(\.id))
                    }
                }
                .font(SonderTypography.caption)
                .fontWeight(.medium)
                .foregroundStyle(SonderColors.terracotta)
            }
        }
        .padding(.horizontal, SonderSpacing.md)
        .padding(.vertical, SonderSpacing.sm)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: SonderSpacing.xs) {
                ForEach(orphanedLogs, id: \.id) { log in
                    if let place = placesByID[log.placeID] {
                        selectableRow(log: log, place: place)
                    }
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.bottom, SonderSpacing.md)
        }
    }

    private func selectableRow(log: Log, place: Place) -> some View {
        let isSelected = selectedIDs.contains(log.id)

        return Button {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
            if isSelected {
                selectedIDs.remove(log.id)
            } else {
                selectedIDs.insert(log.id)
            }
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                // Reuse JournalLogRow visual pattern inline
                logRowContent(log: log, place: place)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? SonderColors.terracotta : SonderColors.inkLight)
            }
            .padding(SonderSpacing.sm)
            .background(isSelected ? SonderColors.terracotta.opacity(0.08) : SonderColors.warmGray)
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        }
        .buttonStyle(.plain)
    }

    private func logRowContent(log: Log, place: Place) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            // Photo thumbnail
            logPhoto(log: log, place: place)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                HStack {
                    Text(place.name)
                        .font(SonderTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)

                    Spacer()

                    Text(log.rating.emoji)
                        .font(.system(size: 16))
                }

                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)
                } else {
                    Text(place.address)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkDark)
                        .lineLimit(1)
                }

                Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkLight)
            }
        }
    }

    @ViewBuilder
    private func logPhoto(log: Log, place: Place) -> some View {
        if let urlString = log.photoURL, let url = URL(string: urlString) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) {
                placePhoto(place: place)
            }
        } else {
            placePhoto(place: place)
        }
    }

    @ViewBuilder
    private func placePhoto(place: Place) -> some View {
        if let photoRef = place.photoReference,
           let url = GooglePlacesService.photoURL(for: photoRef, maxWidth: 200) {
            DownsampledAsyncImage(url: url, targetSize: CGSize(width: 56, height: 56)) {
                photoPlaceholder
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        Rectangle()
            .fill(SonderColors.warmGrayDark)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(SonderColors.inkLight)
            }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if selectedIDs.isEmpty {
                    Button {
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SonderSpacing.sm)
                    }
                } else {
                    Button {
                        assignSelectedLogs()
                    } label: {
                        HStack(spacing: SonderSpacing.xs) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Add \(selectedIDs.count) Log\(selectedIDs.count == 1 ? "" : "s")")
                                .font(SonderTypography.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SonderSpacing.sm)
                        .background(SonderColors.terracotta)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                    }
                    .disabled(isSaving)
                }
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.vertical, SonderSpacing.sm)
        }
        .background(SonderColors.cream)
    }

    // MARK: - Actions

    private func assignSelectedLogs() {
        isSaving = true

        Task {
            for log in orphanedLogs where selectedIDs.contains(log.id) {
                try? await tripService.associateLog(log, with: trip)
            }

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            dismiss()
        }
    }
}
