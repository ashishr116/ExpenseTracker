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

/// A confirmation message informing a friend about borrowed money.
struct BorrowingMessage: Identifiable {
    let friendName: String
    let phone: String
    let amount: Decimal
    let date: Date
    let bankName: String
    let dueDate: Date?
    let note: String

    var id: String { friendName + phone + "\(amount)" + "\(date.timeIntervalSince1970)" }

    init(borrowing: Borrowing) {
        self.friendName = borrowing.friendName
        self.phone = borrowing.friendPhone
        self.amount = borrowing.amount
        self.date = borrowing.date
        self.bankName = borrowing.bankName
        self.dueDate = borrowing.dueDate
        self.note = borrowing.note
    }

    init(
        friendName: String,
        phone: String = "",
        amount: Decimal,
        date: Date = .now,
        bankName: String = "",
        dueDate: Date? = nil,
        note: String = ""
    ) {
        self.friendName = friendName
        self.phone = phone
        self.amount = amount
        self.date = date
        self.bankName = bankName
        self.dueDate = dueDate
        self.note = note
    }

    /// What form the borrow was: Cash or a transfer into a specific bank.
    var formDescription: String {
        let trimmed = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cash" : "Bank transfer into \(trimmed)"
    }

    /// Formatted message text informing the friend.
    var messageBody: String {
        let amountText = amount.formatted(.rupees)
        let dateText = date.formatted(.dateTime.day().month(.wide).year())
        var lines: [String] = []

        let name = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Hi \(name.isEmpty ? "Friend" : name),")
        lines.append("Confirming that I received \(amountText) from you on \(dateText) via \(formDescription).")
        lines.append("")

        if let dueDate {
            let dueText = dueDate.formatted(.dateTime.day().month(.wide).year())
            lines.append("🗓️ Promised return date: \(dueText)")
        } else {
            lines.append("🗓️ Promised to return soon.")
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            lines.append("📝 Note: \(trimmedNote)")
        }

        lines.append("")
        lines.append("Thanks a lot for the support!")
        return lines.joined(separator: "\n")
    }

    /// Link opening WhatsApp with the message pre-filled.
    var whatsAppURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        var digits = phone.filter(\.isNumber)
        if digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 10 { digits = "91" + digits }
        components.path = digits.isEmpty ? "/" : "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: messageBody)]
        return components.url
    }
}
