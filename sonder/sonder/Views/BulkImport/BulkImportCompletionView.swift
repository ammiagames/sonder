//
//  BulkImportCompletionView.swift
//  sonder
//
//  Created by Michael Song on 2/25/26.
//

import SwiftUI

/// Success screen shown after bulk import completes.
struct BulkImportCompletionView: View {
    let logCount: Int
    let tripName: String?
    let onDone: () -> Void

    @State private var showCheckmark = false

    var body: some View {
        VStack(spacing: SonderSpacing.xl) {
            Spacer()

            // Animated checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SonderColors.sage)
                .scaleEffect(showCheckmark ? 1.0 : 0.5)
                .opacity(showCheckmark ? 1.0 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        showCheckmark = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }

            VStack(spacing: SonderSpacing.sm) {
                Text("Created \(logCount) \(logCount == 1 ? "Log" : "Logs")")
                    .font(SonderTypography.title)
                    .foregroundStyle(SonderColors.inkDark)

                if let tripName {
                    Text("Added to \(tripName)")
                        .font(SonderTypography.subheadline)
                        .foregroundStyle(SonderColors.inkMuted)
                }
            }

            Spacer()

            Button("Done") {
                onDone()
            }
            .buttonStyle(WarmButtonStyle())
            .padding(.bottom, SonderSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .background(SonderColors.cream)
    }
}
