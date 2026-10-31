//
//  NotificationDelegate.swift
//  ExpenseTracker
//

import Observation
import UserNotifications

/// Lets reminders show as a banner even while the app is open.
///
/// Without a delegate, iOS silently drops a notification that arrives while the app is in the foreground,
/// which made EMI and premium reminders look like they never fired.
/// Where a tapped notification wants the app to go.
@MainActor @Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    /// The credit card account to open, from a card bill reminder.
    var cardUID: String?
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// A tap on a card bill reminder opens that card, where the friends' reminders are one tap away.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let uid = response.notification.request.content.userInfo["cardUID"] as? String else { return }
        await MainActor.run { NotificationRouter.shared.cardUID = uid }
    }
}
