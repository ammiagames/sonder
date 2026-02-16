//
//  NewTripSheetView.swift
//  sonder
//
//  Reusable half-sheet for creating a new trip with an optional cover photo.
//  Manages its own image picker sheet internally so the parent doesn't need
//  to present a second sheet (which SwiftUI doesn't support).
//

import SwiftUI

struct NewTripSheetView: View {
    @Binding var tripName: String
    @Binding var coverImage: UIImage?
    let onCancel: () -> Void
    let onCreate: () -> Void

    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SonderSpacing.md) {
                TextField("Trip name", text: $tripName)
                    .font(SonderTypography.body)
                    .padding(SonderSpacing.sm)
                    .background(SonderColors.warmGray)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

                // Cover photo picker
                VStack(alignment: .leading, spacing: SonderSpacing.xs) {
                    Text("Cover photo (optional)")
                        .font(SonderTypography.caption)
                        .foregroundColor(SonderColors.inkMuted)

                    if let image = coverImage {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))

                            Button {
                                coverImage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(SonderSpacing.xs)
                        }
                    } else {
                        Button {
                            showImagePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                Text("Add Cover Photo")
                                    .font(SonderTypography.body)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .background(SonderColors.warmGray)
                            .foregroundColor(SonderColors.inkMuted)
                            .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusMd))
                        }
                    }
                }

                Spacer()
            }
            .padding(SonderSpacing.md)
            .background(SonderColors.cream)
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                    }
                    .fontWeight(.semibold)
                    .disabled(tripName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .presentationDetents([.medium])
            .sheet(isPresented: $showImagePicker) {
                EditableImagePicker { image in
                    coverImage = image
                    showImagePicker = false
                } onCancel: {
                    showImagePicker = false
                }
                .ignoresSafeArea()
            }
        }
    }
}
