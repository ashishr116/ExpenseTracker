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

    /// One payment you have made back, for the history in a payment message.
    struct PaidLine {
        let date: Date
        let amount: Decimal
    }

    /// Set when the message is about a payment you just made: that payment, every payment so far, and what is left.
    private(set) var latestPayment: BorrowingPayment.Snapshot?
    private(set) var paidLines: [PaidLine] = []
    private(set) var totalPaid: Decimal = 0
    private(set) var balance: Decimal = 0

    var id: String {
        friendName + phone + "\(amount)" + "\(date.timeIntervalSince1970)" + "\(latestPayment?.date.timeIntervalSince1970 ?? 0)" + "\(totalPaid)"
    }

    /// One debt in a friend-level summary message.
    struct SummaryItem {
        let date: Date
        let amount: Decimal
        let bankName: String
        let note: String
        let payments: [PaidLine]
        let balance: Decimal
    }

    private(set) var summaryItems: [SummaryItem] = []

    /// A message for a friend covering one or more debts: what you borrowed, every payment so far, and what is left.
    init(friendName: String, phone: String = "", borrowings: [Borrowing]) {
        let first = borrowings.sorted { $0.date < $1.date }.first
        self.init(
            friendName: friendName,
            phone: phone.isEmpty ? (borrowings.first { !$0.friendPhone.isEmpty }?.friendPhone ?? "") : phone,
            amount: borrowings.reduce(Decimal(0)) { $0 + $1.amount },
            date: first?.date ?? .now,
            bankName: first?.bankName ?? "",
            dueDate: borrowings.compactMap(\.dueDate).min(),
            note: ""
        )
        summaryItems = borrowings.sorted { $0.date < $1.date }.map { debt in
            SummaryItem(
                date: debt.date, amount: debt.amount, bankName: debt.bankName, note: debt.note,
                payments: debt.payments.sorted { $0.date < $1.date }.map { PaidLine(date: $0.date, amount: $0.amount) },
                balance: debt.outstandingAmount
            )
        }
        totalPaid = borrowings.reduce(Decimal(0)) { $0 + $1.paidAmount }
        balance = borrowings.outstandingTotal
    }

    /// A message telling the friend about a payment you made, with every payment so far.
    init(borrowing: Borrowing, paying payment: BorrowingPayment) {
        self.init(borrowing: borrowing)
        latestPayment = payment.snapshot
        paidLines = borrowing.payments.sorted { $0.date < $1.date }.map { PaidLine(date: $0.date, amount: $0.amount) }
        totalPaid = borrowing.paidAmount
        balance = borrowing.outstandingAmount
    }

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
        if let latestPayment { return paymentBody(latestPayment) }
        if !summaryItems.isEmpty { return summaryBody }
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

    /// The text for a friend's debts: each one, its payments, and the total left.
    private var summaryBody: String {
        let name = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = { (date: Date) in date.formatted(.dateTime.day().month(.abbreviated).year()) }
        var lines: [String] = []
        lines.append("Hi \(name.isEmpty ? "Friend" : name),")
        lines.append("Here is where we stand on the money I borrowed from you:")
        lines.append("")
        for item in summaryItems {
            var title = "• \(day(item.date)): \(item.amount.formatted(.rupees))"
            let bank = item.bankName.trimmingCharacters(in: .whitespacesAndNewlines)
            title += bank.isEmpty ? " (cash)" : " (into \(BankName.display(bank)))"
            if !item.note.isEmpty { title += " · \(item.note)" }
            lines.append(title)
            if item.payments.isEmpty {
                lines.append("   Not paid back yet")
            } else {
                for payment in item.payments {
                    lines.append("   Paid \(day(payment.date)): \(payment.amount.formatted(.rupees))")
                }
            }
            lines.append("   Left: \(item.balance.formatted(.rupees))")
        }
        lines.append("")
        lines.append("Total borrowed: \(amount.formatted(.rupees))")
        lines.append("Total paid: \(totalPaid.formatted(.rupees))")
        lines.append("Total left: \(balance.formatted(.rupees))")
        if balance > 0, let dueDate {
            lines.append("🗓️ I'll clear it by \(dueDate.formatted(.dateTime.day().month(.wide).year())).")
        }
        return lines.joined(separator: "\n")
    }

    /// The text for a payment: this payment, the borrowed amount, every payment so far, and what is left.
    private func paymentBody(_ latest: BorrowingPayment.Snapshot) -> String {
        let name = friendName.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = { (date: Date) in date.formatted(.dateTime.day().month(.abbreviated).year()) }
        var lines: [String] = []
        lines.append("Hi \(name.isEmpty ? "Friend" : name),")

        var paidLine = "I've paid you back \(latest.amount.formatted(.rupees)) on \(day(latest.date))"
        let bank = latest.bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        paidLine += bank.isEmpty ? " in cash." : " by bank transfer from \(BankName.display(bank))."
        lines.append(paidLine)
        lines.append("")
        lines.append("Borrowed: \(amount.formatted(.rupees)) on \(day(date))")
        lines.append("Paid so far:")
        for line in paidLines {
            lines.append("• \(day(line.date)): \(line.amount.formatted(.rupees))")
        }
        lines.append("Total paid: \(totalPaid.formatted(.rupees))")
        lines.append("")
        if balance > 0 {
            lines.append("Balance left: \(balance.formatted(.rupees))")
            if let dueDate {
                lines.append("🗓️ I'll clear the rest by \(dueDate.formatted(.dateTime.day().month(.wide).year())).")
            }
        } else {
            lines.append("That clears the full \(amount.formatted(.rupees)). Thank you so much!")
        }
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
