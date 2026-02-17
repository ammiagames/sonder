import SwiftUI
import SwiftData

struct CityLogsView: View {
    let title: String
    let logs: [Log]
    @Query private var places: [Place]
    @Query private var trips: [Trip]

    private var tripGroups: [(trip: Trip?, logs: [Log])] {
        Self.buildTripGroups(logs: logs, trips: trips)
    }

    /// Groups logs by their associated trip, with untripped/orphaned logs in a nil-trip section.
    /// Exposed as static for testability.
    static func buildTripGroups(logs: [Log], trips: [Trip]) -> [(trip: Trip?, logs: [Log])] {
        let grouped = Dictionary(grouping: logs) { $0.tripID }
        var sections: [(trip: Trip?, logs: [Log])] = []
        var orphanedLogs: [Log] = []

        for (tripID, groupLogs) in grouped {
            if let tripID, let trip = trips.first(where: { $0.id == tripID }) {
                sections.append((trip: trip, logs: groupLogs))
            } else if tripID != nil {
                // Logs with a tripID that no longer matches a local Trip
                orphanedLogs.append(contentsOf: groupLogs)
            }
        }

        // Sort by most recent log date
        sections.sort { a, b in
            let aDate = a.logs.map(\.createdAt).max() ?? .distantPast
            let bDate = b.logs.map(\.createdAt).max() ?? .distantPast
            return aDate > bDate
        }

        // Append untripped + orphaned logs at bottom
        let untripped = logs.filter { $0.tripID == nil } + orphanedLogs
        if !untripped.isEmpty {
            sections.append((trip: nil, logs: untripped.sorted { $0.createdAt > $1.createdAt }))
        }

        return sections
    }

    private var uniquePlaces: [Place] {
        let placeIDs = Set(logs.map(\.placeID))
        return places.filter { placeIDs.contains($0.id) }
    }

    private var lovedCount: Int {
        logs.filter { $0.rating == .mustSee }.count
    }

    private var dateRange: String {
        let dates = logs.map(\.createdAt).sorted()
        guard let first = dates.first, let last = dates.last else { return "" }
        let fmt = Date.FormatStyle().month(.abbreviated).year()
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
            return first.formatted(fmt)
        }
        return "\(first.formatted(fmt)) – \(last.formatted(fmt))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SonderSpacing.md) {
                // Stats header
                statsHeader

                // Trip sections
                ForEach(Array(tripGroups.enumerated()), id: \.offset) { _, group in
                    tripSection(trip: group.trip, logs: group.logs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SonderSpacing.md)
        }
        .background(SonderColors.cream)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: SonderSpacing.xs) {
            Text("\(uniquePlaces.count) places")
            Text("·").foregroundColor(SonderColors.inkLight)
            Text("\(lovedCount) must-see")
            Text("·").foregroundColor(SonderColors.inkLight)
            Text(dateRange)
        }
        .font(SonderTypography.caption)
        .foregroundColor(SonderColors.inkMuted)
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(SonderColors.warmGray)
        .clipShape(Capsule())
    }

    // MARK: - Trip Section

    private func tripSection(trip: Trip?, logs: [Log]) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            // Trip header
            tripHeader(trip: trip, logCount: logs.count)

            // Log cards
            ForEach(logs, id: \.id) { log in
                let place = places.first(where: { $0.id == log.placeID })
                logCard(log: log, place: place)
            }
        }
        .padding(SonderSpacing.sm)
        .background(SonderColors.warmGray)
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusLg))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    @ViewBuilder
    private func tripHeader(trip: Trip?, logCount: Int) -> some View {
        if let trip {
            NavigationLink {
                TripDetailView(trip: trip)
            } label: {
                HStack(spacing: SonderSpacing.sm) {
                    if let urlString = trip.coverPhotoURL, let url = URL(string: urlString) {
                        DownsampledAsyncImage(url: url, targetSize: CGSize(width: 40, height: 40)) {
                            Circle().fill(SonderColors.terracotta.opacity(0.3))
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.name)
                            .font(SonderTypography.headline)
                            .foregroundColor(SonderColors.inkDark)

                        HStack(spacing: SonderSpacing.xxs) {
                            if let start = trip.startDate {
                                Text(tripDateRange(start: start, end: trip.endDate))
                                    .font(SonderTypography.caption)
                                    .foregroundColor(SonderColors.inkMuted)
                            }
                            Text("· \(logCount) log\(logCount == 1 ? "" : "s")")
                                .font(SonderTypography.caption)
                                .foregroundColor(SonderColors.inkMuted)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SonderColors.inkLight)
                }
                .padding(.bottom, SonderSpacing.xs)
            }
            .buttonStyle(.plain)
        } else {
            Text("No Trip")
                .font(SonderTypography.headline)
                .foregroundColor(SonderColors.inkMuted)
                .padding(.bottom, SonderSpacing.xs)
        }
    }

    @ViewBuilder
    private func logCard(log: Log, place: Place?) -> some View {
        if let place {
            NavigationLink {
                LogDetailView(log: log, place: place)
            } label: {
                logCardContent(log: log, placeName: place.name)
            }
            .buttonStyle(.plain)
        } else {
            logCardContent(log: log, placeName: "Unknown Place")
        }
    }

    private func logCardContent(log: Log, placeName: String) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            // Photo thumbnail
            if let urlString = log.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .fill(SonderColors.warmGrayDark)
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            }

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(placeName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SonderColors.inkDark)
                        .lineLimit(1)

                    // Rating pill
                    Text(log.rating.emoji + " " + log.rating.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SonderColors.pinColor(for: log.rating))
                        .padding(.horizontal, SonderSpacing.xs)
                        .padding(.vertical, 2)
                        .background(SonderColors.pinColor(for: log.rating).opacity(0.15))
                        .clipShape(Capsule())

                    if let note = log.note, !note.isEmpty {
                        Text(note)
                            .font(SonderTypography.caption)
                            .foregroundColor(SonderColors.inkMuted)
                            .lineLimit(2)
                    }

                    Text(log.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(SonderColors.inkLight)
                }

                Spacer()
            }
            .padding(SonderSpacing.xs)
            .background(SonderColors.cream.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private func tripDateRange(start: Date, end: Date?) -> String {
        let fmt = Date.FormatStyle().month(.abbreviated).day()
        if let end {
            return "\(start.formatted(fmt)) – \(end.formatted(fmt))"
        }
        return start.formatted(fmt)
    }
}
