//
//  BulkPhotoImportView.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import SwiftUI
import PhotosUI

/// Top-level coordinator for bulk photo import flow.
/// Presented as a fullScreenCover. Manages NavigationStack flow between steps.
struct BulkPhotoImportView: View {
    @Environment(AuthenticationService.self) private var authService
    @Environment(GooglePlacesService.self) private var googlePlacesService
    @Environment(PlacesCacheService.self) private var placesCacheService
    @Environment(PhotoService.self) private var photoService
    @Environment(PhotoSuggestionService.self) private var photoSuggestionService
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Pre-filled trip when launched from TripDetailView. nil for standalone import.
    let tripID: String?
    let tripName: String?

    @State private var importService: BulkPhotoImportService?
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var processingTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let service = importService {
                    switch service.state {
                    case .selecting:
                        selectingPlaceholder
                    case .extracting, .clustering, .resolving:
                        BulkImportProcessingView(state: service.state)
                    case .reviewing, .saving:
                        BulkImportReviewView(
                            importService: service,
                            tripID: tripID,
                            tripName: tripName
                        )
                    case .complete(let logCount):
                        BulkImportCompletionView(
                            logCount: logCount,
                            tripName: tripName,
                            onDone: { dismiss() }
                        )
                    case .failed(let message):
                        errorView(message: message)
                    }
                } else {
                    selectingPlaceholder
                }
            }
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        processingTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedItems,
            maxSelectionCount: 100,
            matching: .images,
            photoLibrary: .shared()
        )
        .task {
            // Ensure photo library access before presenting picker
            await photoSuggestionService.requestAuthorizationIfNeeded()

            let service = BulkPhotoImportService(
                googlePlacesService: googlePlacesService,
                placesCacheService: placesCacheService,
                photoService: photoService,
                photoSuggestionService: photoSuggestionService,
                syncEngine: syncEngine,
                modelContext: modelContext
            )
            importService = service
            showPhotoPicker = true
        }
        .onChange(of: selectedItems) { _, newItems in
            guard let service = importService, !newItems.isEmpty else {
                if selectedItems.isEmpty {
                    dismiss()
                }
                return
            }
            processingTask = Task {
                await service.processSelectedPhotos(newItems)
            }
        }
    }

    // MARK: - Subviews

    private var selectingPlaceholder: some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(SonderColors.inkLight)
            Text("Select photos to import")
                .font(SonderTypography.headline)
                .foregroundStyle(SonderColors.inkMuted)
            Button("Choose Photos") {
                showPhotoPicker = true
            }
            .buttonStyle(WarmButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SonderColors.cream)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: SonderSpacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(SonderColors.terracotta)
            Text(message)
                .font(SonderTypography.body)
                .foregroundStyle(SonderColors.inkDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SonderSpacing.xl)
            HStack(spacing: SonderSpacing.md) {
                Button("Try Again") {
                    selectedItems = []
                    showPhotoPicker = true
                }
                .buttonStyle(WarmButtonStyle())
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(WarmButtonStyle(isPrimary: false))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SonderColors.cream)
    }
}
