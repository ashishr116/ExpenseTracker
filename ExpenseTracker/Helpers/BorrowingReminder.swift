//
//  BorrowingReminder.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import UserNotifications
import os

/// Reminders to you, before money you borrowed from a friend is due back: the day before, and on the day.
enum BorrowingReminder {
    private static let prefix = "borrowing-"
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ExpenseTracker", category: "BorrowingReminder")

    /// Replaces the scheduled reminders with ones for the debts as they are now.
    @MainActor
    static func reschedule(in context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let debts = ((try? context.fetch(FetchDescriptor<Borrowing>())) ?? [])
            .filter { !$0.isRepaid && $0.dueDate != nil }
            // Keep to the soonest few, so these never crowd out the other reminders.
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(8)
        let calendar = Calendar.current
        var count = 0
        defer { log.info("Scheduled \(count) borrowing reminders") }

        for debt in debts {
            guard let due = debt.dueDate else { continue }
            for offset in [1, 0] {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: due),
                      let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                      fire > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = offset == 0 ? "Pay \(debt.friendName) back today" : "Pay \(debt.friendName) back tomorrow"
                content.body = "You owe \(debt.friendName) \(debt.outstandingAmount.formatted(.rupees)), due \(due.formatted(.dateTime.day().month(.abbreviated)))."
                content.sound = .default

                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "\(prefix)\(abs(debt.persistentModelID.hashValue))-\(offset)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                count += 1
            }
        }
    }
}
