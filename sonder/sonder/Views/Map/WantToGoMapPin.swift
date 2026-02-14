//
//  WantToGoMapPin.swift
//  sonder
//
//  Created by Michael Song on 2/11/26.
//

import SwiftUI

/// Bookmark-style pin for Want to Go places on the explore map
struct WantToGoMapPin: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(SonderColors.wantToGoPin.opacity(0.15))
                .frame(width: 36, height: 36)

            Image(systemName: "bookmark.fill")
                .font(.system(size: 18))
                .foregroundColor(SonderColors.wantToGoPin)
        }
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

#Preview {
    WantToGoMapPin()
}
