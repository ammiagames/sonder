//
//  FloatingActionButton.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Floating action button for creating new logs
struct FloatingActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(SonderColors.terracotta)
                        .shadow(color: SonderColors.terracotta.opacity(0.4), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.9))
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                Spacer()
                FloatingActionButton {
                    print("FAB tapped")
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
    }
}
