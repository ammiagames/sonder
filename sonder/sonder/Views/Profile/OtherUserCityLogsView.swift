//
//  OtherUserCityLogsView.swift
//  sonder
//
//  Mirrors CityLogsView for viewing another user's logs in a city,
//  grouped by trip with a stats header.
//

import SwiftUI

struct OtherUserCityLogsView: View {
    let title: String
    let logs: [FeedItem]
    let trips: [Trip]

    private var tripGroups: [(trip: Trip?, logs: [FeedItem])] {
        let grouped = Dictionary(grouping: logs) { $0.log.tripID }
        var sections: [(trip: Trip?, logs: [FeedItem])] = []
        var orphanedLogs: [FeedItem] = []

        for (tripID, groupLogs) in grouped {
            if let tripID, let trip = trips.first(where: { $0.id == tripID }) {
                sections.append((trip: trip, logs: groupLogs))
            } else if tripID != nil {
                orphanedLogs.append(contentsOf: groupLogs)
            }
        }

        sections.sort { a, b in
            let aDate = a.logs.map(\.createdAt).max() ?? .distantPast
            let bDate = b.logs.map(\.createdAt).max() ?? .distantPast
            return aDate > bDate
        }

        let untripped = logs.filter { $0.log.tripID == nil } + orphanedLogs
        if !untripped.isEmpty {
            sections.append((trip: nil, logs: untripped.sorted { $0.createdAt > $1.createdAt }))
        }

        return sections
    }

    private var lovedCount: Int {
        logs.filter { $0.rating == .mustSee }.count
    }

    private var uniquePlaceCount: Int {
        Set(logs.map { $0.place.id }).count
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
                statsHeader

                ForEach(Array(tripGroups.enumerated()), id: \.offset) { _, group in
                    tripSection(trip: group.trip, logs: group.logs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SonderSpacing.md)
            .padding(.bottom, 80)
        }
        .background(SonderColors.cream)
        .scrollContentBackground(.hidden)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: SonderSpacing.xs) {
            Text("\(uniquePlaceCount) places")
            Text("·").foregroundStyle(SonderColors.inkLight)
            Text("\(lovedCount) must-see")
            Text("·").foregroundStyle(SonderColors.inkLight)
            Text(dateRange)
        }
        .font(SonderTypography.caption)
        .foregroundStyle(SonderColors.inkMuted)
        .padding(.horizontal, SonderSpacing.sm)
        .padding(.vertical, SonderSpacing.xs)
        .background(SonderColors.warmGray)
        .clipShape(Capsule())
    }

    // MARK: - Trip Section

    private func tripSection(trip: Trip?, logs: [FeedItem]) -> some View {
        VStack(alignment: .leading, spacing: SonderSpacing.xs) {
            tripHeader(trip: trip, logCount: logs.count)

            ForEach(logs) { item in
                NavigationLink {
                    FeedLogDetailView(feedItem: item)
                } label: {
                    logCard(item: item)
                }
                .buttonStyle(.plain)
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
                            .foregroundStyle(SonderColors.inkDark)

                        HStack(spacing: SonderSpacing.xxs) {
                            if let start = trip.startDate {
                                Text(tripDateRange(start: start, end: trip.endDate))
                                    .font(SonderTypography.caption)
                                    .foregroundStyle(SonderColors.inkMuted)
                            }
                            Text("· \(logCount) log\(logCount == 1 ? "" : "s")")
                                .font(SonderTypography.caption)
                                .foregroundStyle(SonderColors.inkMuted)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SonderColors.inkLight)
                }
                .padding(.bottom, SonderSpacing.xs)
            }
            .buttonStyle(.plain)
        } else {
            Text("No Trip")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkMuted)
                .padding(.bottom, SonderSpacing.xs)
        }
    }

    private func logCard(item: FeedItem) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            if let urlString = item.log.photoURL, let url = URL(string: urlString) {
                DownsampledAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) {
                    RoundedRectangle(cornerRadius: SonderSpacing.radiusSm)
                        .fill(SonderColors.warmGrayDark)
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
            }

            VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                Text(item.place.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SonderColors.inkDark)
                    .lineLimit(1)

                Text(item.rating.emoji + " " + item.rating.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SonderColors.pinColor(for: item.rating))
                    .padding(.horizontal, SonderSpacing.xs)
                    .padding(.vertical, 2)
                    .background(SonderColors.pinColor(for: item.rating).opacity(0.15))
                    .clipShape(Capsule())

                if let note = item.log.note, !note.isEmpty {
                    Text(note)
                        .font(SonderTypography.caption)
                        .foregroundStyle(SonderColors.inkMuted)
                        .lineLimit(2)
                }

                Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(SonderColors.inkLight)
            }

            Spacer()
        }
        .padding(SonderSpacing.xs)
        .background(SonderColors.cream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
    }

    private func tripDateRange(start: Date, end: Date?) -> String {
        ProfileShared.tripDateRange(start: start, end: end)
    }
}
