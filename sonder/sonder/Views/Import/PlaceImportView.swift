//
//  PlaceImportView.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct PlaceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthenticationService.self) private var authService
    @Environment(PlaceImportService.self) private var importService
    @Environment(SavedListsService.self) private var savedListsService

    @State private var step: ImportStep = .sourceSelection
    @State private var showFilePicker = false
    @State private var parsedEntries: [ImportedPlaceEntry] = []
    @State private var selectedListID: String?
    @State private var newListName: String = ""
    @State private var listOption: ListOption = .noList

    enum ImportStep {
        case sourceSelection
        case instructions
        case listTarget
        case importing
        case summary
    }

    enum ListOption: Hashable {
        case noList
        case existing(String)
        case createNew
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .sourceSelection:
                    sourceSelectionView
                case .instructions:
                    instructionsView
                case .listTarget:
                    listTargetView
                case .importing:
                    progressView
                case .summary:
                    summaryView
                }
            }
            .background(SonderColors.cream)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .importing {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePicked(result)
        }
    }

    private var navigationTitle: String {
        switch step {
        case .sourceSelection: return "Import Places"
        case .instructions: return "Export from Google"
        case .listTarget: return "Save to List"
        case .importing: return "Importing"
        case .summary: return "Import Complete"
        }
    }

    // MARK: - Step 1: Source Selection

    private var sourceSelectionView: some View {
        List {
            Section {
                Button {
                    step = .instructions
                } label: {
                    HStack(spacing: SonderSpacing.md) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundStyle(SonderColors.terracotta)
                            .frame(width: 40, height: 40)
                            .background(SonderColors.terracotta.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                        VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                            Text("Import from Google Maps")
                                .font(SonderTypography.headline)
                                .foregroundStyle(SonderColors.inkDark)
                            Text("Import your saved places via Google Takeout")
                                .font(SonderTypography.caption)
                                .foregroundStyle(SonderColors.inkMuted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SonderColors.inkLight)
                    }
                    .padding(.vertical, SonderSpacing.xs)
                }

                // Apple Maps — Phase 2 placeholder
                HStack(spacing: SonderSpacing.md) {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(SonderColors.inkLight)
                        .frame(width: 40, height: 40)
                        .background(SonderColors.warmGray)
                        .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))

                    VStack(alignment: .leading, spacing: SonderSpacing.xxs) {
                        Text("Import from Apple Maps")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkLight)
                        Text("Coming soon")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkLight)
                    }

                    Spacer()
                }
                .padding(.vertical, SonderSpacing.xs)
            } header: {
                Text("Choose a source")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.terracotta)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .listRowBackground(SonderColors.warmGray)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Step 2: Google Takeout Instructions

    private var instructionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SonderSpacing.lg) {
                instructionStep(number: 1, text: "Go to **takeout.google.com** in your browser")
                instructionStep(number: 2, text: "Tap **Deselect all**, then select **\"Saved\"** or **\"Maps (your places)\"**")
                instructionStep(number: 3, text: "Tap **Next step** → **Create export** and download the .zip file")
                instructionStep(number: 4, text: "Unzip the download and find:")

                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    fileTypeRow(icon: "doc.text", name: "Saved Places.json", detail: "All starred/favorited places")
                    fileTypeRow(icon: "tablecells", name: "*.csv", detail: "Individual list files (e.g. Want to Go.csv)")
                }
                .padding(.leading, 44)

                if let error = importService.parseError {
                    HStack(spacing: SonderSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(SonderColors.dustyRose)
                        Text(error)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.dustyRose)
                    }
                    .padding(SonderSpacing.sm)
                    .background(SonderColors.dustyRose.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusSm))
                }

                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Select File", systemImage: "doc.badge.plus")
                            .font(SonderTypography.headline)
                        Spacer()
                    }
                    .padding(.vertical, SonderSpacing.sm)
                }
                .buttonStyle(WarmButtonStyle())
            }
            .padding(SonderSpacing.lg)
            .padding(.bottom, 80)
        }
    }

    private func instructionStep(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: SonderSpacing.sm) {
            Text("\(number)")
                .font(SonderTypography.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(SonderColors.terracotta)
                .clipShape(Circle())

            Text(text)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    private func fileTypeRow(icon: String, name: String, detail: String) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SonderColors.terracotta)
            VStack(alignment: .leading) {
                Text(name)
                    .font(SonderTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(SonderColors.inkDark)
                Text(detail)
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.inkMuted)
            }
        }
    }

    // MARK: - Step 3: List Target + Preview

    private var listTargetView: some View {
        List {
            Section {
                listOptionRow(
                    label: "All Saved Places",
                    subtitle: "No specific list",
                    option: .noList
                )

                ForEach(savedListsService.lists, id: \.id) { list in
                    listOptionRow(
                        label: "\(list.emoji) \(list.name)",
                        subtitle: nil,
                        option: .existing(list.id)
                    )
                }

                listOptionRow(
                    label: "Create new list",
                    subtitle: nil,
                    option: .createNew
                )

                if listOption == .createNew {
                    TextField("List name", text: $newListName)
                        .font(SonderTypography.body)
                        .padding(.leading, 36)
                }
            } header: {
                Text("Save to")
                    .font(SonderTypography.caption)
                    .foregroundStyle(SonderColors.terracotta)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .listRowBackground(SonderColors.warmGray)

            Section {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(SonderColors.terracotta)
                    Text("Found \(parsedEntries.count) places in file")
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkDark)
                }
            }
            .listRowBackground(SonderColors.warmGray)

            Section {
                Button {
                    startImport()
                } label: {
                    HStack {
                        Spacer()
                        Text("Import \(parsedEntries.count) Places")
                            .font(SonderTypography.headline)
                        Spacer()
                    }
                    .padding(.vertical, SonderSpacing.xs)
                }
                .buttonStyle(WarmButtonStyle())
                .disabled(listOption == .createNew && newListName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: SonderSpacing.md, leading: 0, bottom: 0, trailing: 0))
        }
        .scrollContentBackground(.hidden)
    }

    private func listOptionRow(label: String, subtitle: String?, option: ListOption) -> some View {
        Button {
            listOption = option
        } label: {
            HStack {
                Image(systemName: listOption == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(listOption == option ? SonderColors.terracotta : SonderColors.inkLight)

                VStack(alignment: .leading) {
                    Text(label)
                        .font(SonderTypography.body)
                        .foregroundStyle(SonderColors.inkDark)
                    if let subtitle {
                        Text(subtitle)
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Step 4: Progress

    private var progressView: some View {
        VStack(spacing: SonderSpacing.xl) {
            Spacer()

            if let job = importService.activeJob {
                VStack(spacing: SonderSpacing.md) {
                    Text("\(job.processedCount) of \(job.totalCount) places")
                        .font(SonderTypography.title)
                        .foregroundStyle(SonderColors.inkDark)

                    ProgressView(value: job.progress)
                        .tint(SonderColors.terracotta)
                        .padding(.horizontal, SonderSpacing.xl)
                }

                if let currentName = job.currentEntryName {
                    HStack(spacing: SonderSpacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Resolving \"\(currentName)\"...")
                            .font(SonderTypography.caption)
                            .foregroundStyle(SonderColors.inkMuted)
                    }
                }

                // Show recent results
                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    ForEach(recentResults(from: job), id: \.0) { entryID, entry, result in
                        resultRow(name: entry.name, result: result)
                    }
                }
                .padding(.horizontal, SonderSpacing.lg)
            }

            Spacer()
        }
        .padding(SonderSpacing.lg)
    }

    private func recentResults(from job: ImportJob) -> [(UUID, ImportedPlaceEntry, PlaceResolutionResult)] {
        let processed = job.entries.filter { job.results[$0.id] != nil }
        return processed.suffix(5).compactMap { entry in
            guard let result = job.results[entry.id] else { return nil }
            return (entry.id, entry, result)
        }
    }

    private func resultRow(name: String, result: PlaceResolutionResult) -> some View {
        HStack(spacing: SonderSpacing.xs) {
            switch result {
            case .resolved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SonderColors.sage)
            case .skipped:
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(SonderColors.inkLight)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SonderColors.dustyRose)
            }
            Text(name)
                .font(SonderTypography.subheadline)
                .foregroundStyle(SonderColors.inkDark)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: - Step 5: Summary

    private var summaryView: some View {
        VStack(spacing: SonderSpacing.xl) {
            Spacer()

            if let summary = importService.lastSummary {
                VStack(spacing: SonderSpacing.lg) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(SonderColors.sage)

                    VStack(spacing: SonderSpacing.sm) {
                        if summary.successCount > 0 {
                            summaryRow(
                                icon: "checkmark",
                                color: SonderColors.sage,
                                text: "\(summary.successCount) place\(summary.successCount == 1 ? "" : "s") imported"
                            )
                        }
                        if summary.skippedCount > 0 {
                            summaryRow(
                                icon: "arrow.uturn.backward",
                                color: SonderColors.inkLight,
                                text: "\(summary.skippedCount) already saved (skipped)"
                            )
                        }
                        if summary.failedCount > 0 {
                            summaryRow(
                                icon: "xmark",
                                color: SonderColors.dustyRose,
                                text: "\(summary.failedCount) couldn't be found"
                            )
                        }
                    }
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Done")
                        .font(SonderTypography.headline)
                    Spacer()
                }
                .padding(.vertical, SonderSpacing.sm)
            }
            .buttonStyle(WarmButtonStyle())
            .padding(.horizontal, SonderSpacing.lg)
            .padding(.bottom, SonderSpacing.xl)
        }
    }

    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: SonderSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
        }
    }

    // MARK: - Actions

    private func handleFilePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            parsedEntries = importService.parseFile(url: url)
            if !parsedEntries.isEmpty {
                step = .listTarget
            }
        case .failure(let error):
            importService.setParseError(error.localizedDescription)
        }
    }

    private func startImport() {
        guard let userID = authService.currentUser?.id else { return }

        step = .importing

        Task {
            // Create new list if needed
            var targetListID: String?
            switch listOption {
            case .noList:
                targetListID = nil
            case .existing(let id):
                targetListID = id
            case .createNew:
                let trimmed = newListName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let list = await savedListsService.createList(name: trimmed, userID: userID)
                    targetListID = list?.id
                }
            }

            await importService.importEntries(
                parsedEntries,
                userID: userID,
                targetListID: targetListID
            )

            step = .summary
        }
    }
}
