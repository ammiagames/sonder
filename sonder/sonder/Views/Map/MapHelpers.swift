//
//  MapHelpers.swift
//  sonder
//
//  Shared map utilities extracted from LogMapView.
//

import SwiftUI
import MapKit

// MARK: - Map Style Options

enum MapStyleOption: String, CaseIterable {
    case minimal
    case standard
    case hybrid
    case imagery

    var name: String {
        switch self {
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .imagery: return "Satellite"
        }
    }

    var icon: String {
        switch self {
        case .minimal: return "circle.grid.2x1"
        case .standard: return "map"
        case .hybrid: return "square.2.layers.3d"
        case .imagery: return "globe.americas"
        }
    }

    var style: MapStyle {
        switch self {
        case .minimal:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .standard:
            return .standard(elevation: .flat, pointsOfInterest: .including([.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .museum, .nationalPark, .park, .beach]))
        case .hybrid:
            return .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        case .imagery:
            return .imagery(elevation: .flat)
        }
    }
}

// MARK: - Directions Helpers

extension View {
    /// Presents a Sonder-styled directions menu with Apple Maps, Google Maps, and Copy Address.
    func directionsConfirmationDialog(
        isPresented: Binding<Bool>,
        coordinate: CLLocationCoordinate2D,
        name: String,
        address: String = ""
    ) -> some View {
        self.modifier(DirectionsMenuModifier(
            isPresented: isPresented,
            coordinate: coordinate,
            name: name,
            address: address
        ))
    }
}

// MARK: - Directions Menu Modifier

/// ViewModifier so it can hold @State for the copied toast independently of the menu.
private struct DirectionsMenuModifier: ViewModifier {
    @Binding var isPresented: Bool
    let coordinate: CLLocationCoordinate2D
    let name: String
    let address: String

    @State private var showCopiedToast = false
    @State private var toastDismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                DirectionsMenuOverlay(
                    isPresented: $isPresented,
                    coordinate: coordinate,
                    name: name,
                    address: address,
                    onCopied: {
                        showCopiedToast = true
                        toastDismissTask?.cancel()
                        toastDismissTask = Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            guard !Task.isCancelled else { return }
                            showCopiedToast = false
                        }
                    }
                )
            }
            // Toast: anchored to the absolute screen top via Color.clear.ignoresSafeArea(),
            // so it appears in the same position regardless of which view hosts the modifier
            // (full-screen views like LogViewScreen OR the partial-screen UnifiedBottomCard).
            .overlay {
                if showCopiedToast {
                    Color.clear
                        .ignoresSafeArea()
                        .overlay(alignment: .top) {
                            HStack(spacing: SonderSpacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Address copied")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, SonderSpacing.lg)
                            .padding(.vertical, SonderSpacing.sm)
                            .background(SonderColors.terracotta)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            // 110pt from screen top ≈ below status bar + navigation bar
                            .padding(.top, 110)
                        }
                        .allowsHitTesting(false)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: showCopiedToast)
    }
}

// MARK: - Directions Menu Overlay

private struct DirectionsMenuOverlay: View {
    @Binding var isPresented: Bool
    let coordinate: CLLocationCoordinate2D
    let name: String
    let address: String
    let onCopied: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)

                VStack(spacing: SonderSpacing.xs) {
                    // Options card
                    VStack(spacing: 0) {
                        menuRow(
                            icon: "map.fill",
                            iconColor: SonderColors.sage,
                            label: "Open in Apple Maps",
                            action: openAppleMaps
                        )
                        Divider().padding(.leading, 56)
                        menuRow(
                            icon: "location.fill",
                            iconColor: SonderColors.terracotta,
                            label: "Open in Google Maps",
                            action: openGoogleMaps
                        )
                        if !address.isEmpty {
                            Divider().padding(.leading, 56)
                            menuRow(
                                icon: "doc.on.clipboard.fill",
                                iconColor: SonderColors.inkMuted,
                                label: "Copy Address",
                                action: copyAddress
                            )
                        }
                    }
                    .background(SonderColors.cream)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusXl))
                    .shadow(color: .black.opacity(0.10), radius: 16, y: 4)

                    // Cancel card
                    Button(action: close) {
                        Text("Cancel")
                            .font(SonderTypography.headline)
                            .foregroundStyle(SonderColors.inkDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(SonderColors.cream)
                    .clipShape(RoundedRectangle(cornerRadius: SonderSpacing.radiusXl))
                    .shadow(color: .black.opacity(0.10), radius: 16, y: 4)
                }
                .padding(.horizontal, SonderSpacing.md)
                .padding(.bottom, 34)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = false
        }
    }

    @ViewBuilder
    private func menuRow(icon: String, iconColor: Color, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            close()
        } label: {
            HStack(spacing: SonderSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }

                Text(label)
                    .font(SonderTypography.body)
                    .foregroundStyle(SonderColors.inkDark)

                Spacer()
            }
            .padding(.horizontal, SonderSpacing.md)
            .padding(.vertical, SonderSpacing.sm + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openAppleMaps() {
        // Use name + address as the destination query so Apple Maps shows the
        // place name rather than raw coordinates in the directions card.
        let dest = address.isEmpty ? name : "\(name), \(address)"
        guard let encoded = dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "maps://?daddr=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }

    private func openGoogleMaps() {
        // Same approach: pass name + address so Google Maps labels the destination.
        let dest = address.isEmpty ? name : "\(name), \(address)"
        guard let encoded = dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let nativeURL = URL(string: "comgooglemaps://?daddr=\(encoded)&directionsmode=driving")
        guard let webURL = URL(string: "https://maps.google.com/maps?daddr=\(encoded)") else { return }
        let target = (nativeURL.flatMap { UIApplication.shared.canOpenURL($0) ? $0 : nil }) ?? webURL
        UIApplication.shared.open(target)
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        SonderHaptics.notification(.success)
        onCopied()
    }
}

// MARK: - MKCoordinateRegion Extension

extension MKCoordinateRegion {
    /// Creates a region that fits all given coordinates
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                latitudinalMeters: 10000,
                longitudinalMeters: 10000
            )
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.01,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.01
        )

        self = MKCoordinateRegion(center: center, span: span)
    }
}
