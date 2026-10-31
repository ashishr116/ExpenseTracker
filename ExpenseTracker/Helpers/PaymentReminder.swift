//
//  PaymentReminder.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import UserNotifications

/// Schedules local notifications for every pending EMI instalment and insurance premium:
///
/// - **Before the due date:** the day before (and a week before for half-yearly and yearly premiums),
///   so there is enough balance for an auto-debit. A bounced debit costs a fee and can hurt the credit score.
/// - **On the due date.**
/// - **After the due date:** 1, 3 and 7 days later while the item is still unpaid. Items that are already
///   overdue get reminders on the next three mornings.
///
/// Paying an item removes its reminders, because `sync` rebuilds the whole set.
enum PaymentReminder {
    private static let identifierPrefix = "due-"
    /// iOS keeps at most 64 pending local notifications per app.
    /// iOS keeps at most 64 notifications waiting. This leaves room for the monthly recap, card bill reminders
    /// and budget notices.
    private static let maximumScheduled = 40
    /// Reminders go out at 9am.
    private static let reminderHour = 9
    private static let overdueFollowUpDays = [1, 3, 7]

    private struct Reminder {
        let title: String
        let body: String
        let date: Date
        let id: String
    }

    private enum Kind {
        case emi(EMI)
        case premium(InsurancePolicy)
    }

    /// Replaces all scheduled payment reminders with ones for the current pending payments.
    /// Asks for notification permission the first time.
    @MainActor
    static func sync(emis: [EMI], policies: [InsurancePolicy], loans: [Loan] = []) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let pending = await center.pendingNotificationRequests()
        // "emi-" is the prefix used before insurance reminders existed.
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) || $0.hasPrefix("emi-") }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        let current = await center.notificationSettings()
        guard current.authorizationStatus == .authorized || current.authorizationStatus == .provisional else { return }

        var reminders: [Reminder] = []
        for emi in emis {
            for installment in emi.pendingInstallments {
                reminders += remindersFor(installment, kind: .emi(emi))
            }
        }
        for policy in policies {
            for premium in policy.pendingPremiums {
                reminders += remindersFor(premium, kind: .premium(policy))
            }
        }

        // Monthly reminders for friends' card EMIs repeat on their own, so each takes just one slot.
        let monthlyLoans = loans.filter(\.hasActiveMonthlyReminder)
        for loan in monthlyLoans {
            var components = DateComponents()
            components.day = min(max(loan.monthlyReminderDay, 1), 28)
            components.hour = reminderHour

            let content = UNMutableNotificationContent()
            let emiKind = loan.method == .personalLoan ? "personal loan EMI" : "card EMI"
            content.title = "\(loan.friendName)'s \(emiKind) is due"
            let amountPart = loan.monthlyInstalment.map { " (\($0.formatted(.rupees)))" } ?? ""
            content.body = "Ask \(loan.friendName) for this month's \(emiKind) payment\(amountPart). Open Loans to send a reminder."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let id = "\(identifierPrefix)loan-\(abs(loan.persistentModelID.hashValue))-monthly"
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        let slots = max(0, maximumScheduled - monthlyLoans.count)
        for reminder in reminders.sorted(by: { $0.date < $1.date }).prefix(slots) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - Building reminders

    /// 9am on the day `offset` days from `date` (negative is before).
    private static func morning(of date: Date, offsetDays offset: Int) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { return nil }
        return calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day)
    }

    private static func remindersFor(_ payment: Expense, kind: Kind) -> [Reminder] {
        let now = Date.now
        let due = payment.date
        let amount = payment.amount.formatted(.rupees)
        let name: String
        let noun: String
        let advanceDays: [Int]
        let overdueNote: String

        switch kind {
        case .emi(let emi):
            name = emi.name
            noun = "EMI"
            advanceDays = [1]
            overdueNote = "Late fees may apply and your credit score can be affected."
        case .premium(let policy):
            name = policy.title
            noun = "Premium"
            // Larger, less frequent premiums need funding earlier.
            advanceDays = policy.frequency.months >= 6 ? [7, 1] : [1]
            overdueNote = "Your cover may lapse once the insurer's grace period ends, usually 15 to 30 days."
        }

        let key = "\(identifierPrefix)\(abs(payment.persistentModelID.hashValue))"
        var result: [Reminder] = []

        func add(_ offset: Int, _ tag: String, title: String, body: String) {
            guard let date = morning(of: due, offsetDays: offset), date > now else { return }
            result.append(Reminder(title: title, body: body, date: date, id: "\(key)-\(tag)"))
        }

        // Before: keep enough balance for the debit.
        for lead in advanceDays {
            let when = lead == 1 ? "tomorrow" : "in \(lead) days"
            add(-lead, "before\(lead)",
                title: "\(noun) due \(when)",
                body: "\(name): \(amount) is due \(when). Keep enough balance so the debit doesn't bounce.")
        }

        // On the day.
        add(0, "due",
            title: "\(noun) due today",
            body: "\(name): \(amount) is due today. Open the app to record it once paid.")

        // After: repeat until it is marked paid.
        for days in overdueFollowUpDays {
            add(days, "late\(days)",
                title: "\(noun) overdue",
                body: "\(name): \(amount) was due \(days == 1 ? "yesterday" : "\(days) days ago"). \(overdueNote)")
        }

        // Already overdue beyond the follow-ups above: nudge on the next three mornings.
        let hasFutureFollowUp = result.contains { $0.id.contains("-late") }
        if due < Calendar.current.startOfDay(for: now), !hasFutureFollowUp {
            for day in 1...3 {
                guard let date = morning(of: now, offsetDays: day) else { continue }
                result.append(Reminder(
                    title: "\(noun) overdue",
                    body: "\(name): \(amount) is still unpaid. \(overdueNote)",
                    date: date,
                    id: "\(key)-overdue\(day)"
                ))
            }
        }
        return result
    }
}
