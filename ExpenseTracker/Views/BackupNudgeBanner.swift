//
//  BackupNudgeBanner.swift
//  ExpenseTracker
//

import SwiftUI

/// A note at the top of the Daily screen when it has been 30 days or more since the last backup.
struct BackupNudgeBanner: View {
    @AppStorage(BackupManager.lastBackupKey) private var lastBackup = 0.0
    @AppStorage(BackupNudge.firstSeenKey) private var firstSeen = 0.0
    @AppStorage(BackupNudge.snoozedUntilKey) private var snoozedUntil = 0.0

    /// Called when "Back Up Now" is tapped. The screen that holds the banner opens the backup sheet, because the
    /// banner itself disappears as soon as a backup is made, and a sheet attached to it would be pulled away with it.
    var onBackUp: () -> Void

    private var isDue: Bool {
        BackupNudge.isDue(lastBackup: lastBackup, firstSeen: firstSeen, snoozedUntil: snoozedUntil)
    }

    private var days: Int {
        BackupNudge.daysSince(lastBackup: lastBackup, firstSeen: firstSeen)
    }

    var body: some View {
        if isDue { banner }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Back up your data")
                        .font(.subheadline.weight(.semibold))
                    Text(lastBackup > 0
                         ? "Your last backup was \(days) days ago. If this phone is lost or broken, anything since is gone."
                         : "You haven't made a backup yet. If this phone is lost or broken, your records are gone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Back Up Now", action: onBackUp)
                            .buttonStyle(.borderedProminent)
                        Button("Later") { BackupNudge.snooze() }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom, 8)
    }
}

#Preview {
    BackupNudgeBanner(onBackUp: {})
}
