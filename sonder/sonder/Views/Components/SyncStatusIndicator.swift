//
//  SyncStatusIndicator.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import SwiftUI

/// Indicator showing pending or failed sync status
struct SyncStatusIndicator: View {
    let status: SyncStatus
    let compact: Bool

    init(status: SyncStatus, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }

    var body: some View {
        switch status {
        case .synced:
            EmptyView()
        case .pending:
            pendingView
        case .failed:
            failedView
        }
    }

    private var pendingView: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: compact ? 10 : 12))

            if !compact {
                Text("Pending")
                    .font(.caption2)
            }
        }
        .foregroundColor(.orange)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var failedView: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 10 : 12))

            if !compact {
                Text("Failed")
                    .font(.caption2)
            }
        }
        .foregroundColor(.red)
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
    }
}

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
            .foregroundColor(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15))
            .clipShape(Capsule())
        }
    }
}

#Preview("Sync Indicators") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            SyncStatusIndicator(status: .pending)
            SyncStatusIndicator(status: .pending, compact: true)
        }

        HStack(spacing: 20) {
            SyncStatusIndicator(status: .failed)
            SyncStatusIndicator(status: .failed, compact: true)
        }

        SyncStatusIndicator(status: .synced)

        PendingSyncBadge(count: 3)
        PendingSyncBadge(count: 0)
    }
    .padding()
}
