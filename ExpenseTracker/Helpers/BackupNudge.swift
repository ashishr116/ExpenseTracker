//
//  BackupNudge.swift
//  ExpenseTracker
//

import Foundation
import UserNotifications

/// Reminds you to back up when 30 days have passed without one.
///
/// Backups are not automatic, so a lost or broken phone loses everything since the last one. The nudge is a
/// banner on the Daily screen and a notification. The count starts from your last backup. If you have never made
/// one, it starts the first time the app opened with this feature, so nobody is nagged on day one.
enum BackupNudge {
    /// Days without a backup before the nudge appears.
    static let interval = 30
    /// Days "Later" hides the banner for.
    static let snoozeDays = 7

    static let firstSeenKey = "backupNudgeFirstSeen"
    static let snoozedUntilKey = "backupNudgeSnoozedUntil"
    private static let notificationID = "backup-nudge"

    /// Remembers when the app was first opened with this feature, if it hasn't been already.
    static func recordFirstSeen(now: Date = .now) {
        let defaults = UserDefaults.standard
        if defaults.double(forKey: firstSeenKey) == 0 {
            defaults.set(now.timeIntervalSince1970, forKey: firstSeenKey)
        }
    }

    /// The day the count runs from: the last backup, or the first launch if there has never been one.
    static func referenceDate(lastBackup: Double, firstSeen: Double, now: Date = .now) -> Date {
        if lastBackup > 0 { return Date(timeIntervalSince1970: lastBackup) }
        if firstSeen > 0 { return Date(timeIntervalSince1970: firstSeen) }
        return now
    }

    /// Whole days since the reference day.
    static func daysSince(lastBackup: Double, firstSeen: Double, now: Date = .now) -> Int {
        let calendar = Calendar.current
        let reference = referenceDate(lastBackup: lastBackup, firstSeen: firstSeen, now: now)
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// Whether the banner should show now.
    static func isDue(lastBackup: Double, firstSeen: Double, snoozedUntil: Double, now: Date = .now) -> Bool {
        daysSince(lastBackup: lastBackup, firstSeen: firstSeen, now: now) >= interval
            && now.timeIntervalSince1970 >= snoozedUntil
    }

    /// Hides the banner for a week.
    static func snooze(now: Date = .now) {
        let until = Calendar.current.date(byAdding: .day, value: snoozeDays, to: now) ?? now
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: snoozedUntilKey)
    }

    // MARK: Notification

    /// Schedules the reminder for when the 30 days are up, or weekly if they already are. Replaces any earlier one,
    /// so it is safe to call on every launch and again after a backup.
    static func scheduleReminder(now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let defaults = UserDefaults.standard
        let lastBackup = defaults.double(forKey: BackupManager.lastBackupKey)
        let firstSeen = defaults.double(forKey: firstSeenKey)
        let calendar = Calendar.current
        let reference = referenceDate(lastBackup: lastBackup, firstSeen: firstSeen, now: now)
        guard let dueDay = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: reference)),
              let dueMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDay) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to back up your data"
        content.body = lastBackup > 0
            ? "It has been \(interval) days since your last backup. Save one to iCloud Drive so a lost phone doesn't cost you your records."
            : "You haven't made a backup yet. Save one to iCloud Drive so a lost phone doesn't cost you your records."
        content.sound = .default

        let trigger: UNNotificationTrigger
        if dueMorning > now {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dueMorning)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            // Already overdue: remind once a week, on the same weekday, until a backup is made.
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return }
            var parts = calendar.dateComponents([.weekday], from: tomorrow)
            parts.hour = 9
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        }
        try? await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
