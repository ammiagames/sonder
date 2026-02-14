//
//  SplashView.swift
//  sonder
//

import SwiftUI

/// Shown briefly while restoring the user session on launch.
/// Matches the auth screen branding so the transition feels seamless.
struct SplashView: View {
    var body: some View {
        VStack(spacing: SonderSpacing.sm) {
            Image(systemName: "map.fill")
                .font(.system(size: 80))
                .foregroundStyle(SonderColors.terracotta)

            Text("Sonder")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(SonderColors.inkDark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SonderColors.cream)
    }
}

#Preview {
    SplashView()
}
