//
//  SyncStatusIndicator.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Pending sync count badge
struct PendingSyncBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))

                Text("\(count) pending")
                    .font(.caption)
            }
            .foregroundColor(SonderColors.ochre)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(SonderColors.ochre.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

#Preview("Pending Sync Badge") {
    VStack(spacing: 20) {
        PendingSyncBadge(count: 3)
        PendingSyncBadge(count: 0)
    }
    .padding()
}
