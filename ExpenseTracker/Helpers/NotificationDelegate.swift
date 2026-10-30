//
//  NotificationDelegate.swift
//  ExpenseTracker
//

import UserNotifications

/// Lets reminders show as a banner even while the app is open.
///
/// Without a delegate, iOS silently drops a notification that arrives while the app is in the foreground,
/// which made EMI and premium reminders look like they never fired.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
