//
//  CardBill.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import UserNotifications
import os

/// What one friend owes towards a credit card's bill.
struct CardBillShare: Identifiable {
    let friendName: String
    let phone: String
    /// The friend's open loans on this card.
    let loans: [Loan]
    /// What to ask for now: the EMI for an instalment loan, and what is still owed for any other loan.
    let amount: Decimal

    var id: String { friendName.lowercased() }
}

/// A card's latest bill and what has been spent since.
struct CardStatement {
    /// The day the latest bill was generated.
    let billDate: Date
    let dueDate: Date?
    /// What is still to pay on that bill, after any payments since.
    let billed: Decimal
    /// Spent on the card since the bill was generated. It goes on the next bill.
    let unbilled: Decimal
    let nextBillDate: Date?
}

/// One bill's span of days on a credit card.
struct CardCycle {
    /// The day the bill was generated.
    let billDate: Date
    /// First day of the span, the day after the previous bill.
    let start: Date
    /// The day after the bill day, where the next span begins.
    let end: Date
    let dueDate: Date?
}

enum CardBill {
    /// The bill `back` bills ago: 0 is the latest bill, 1 the one before it. `nil` without a bill day.
    static func cycle(for card: PaymentCard, back: Int, now: Date = .now) -> CardCycle? {
        guard card.hasBillingCycle else { return nil }
        let calendar = Calendar.current
        var bill = card.lastStatementDate(onOrBefore: now)
        for _ in 0..<back {
            guard let current = bill, let day = calendar.date(byAdding: .day, value: -1, to: current) else { return nil }
            bill = card.lastStatementDate(onOrBefore: day)
        }
        guard let billDate = bill,
              let end = calendar.date(byAdding: .day, value: 1, to: billDate),
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: billDate),
              let previous = card.lastStatementDate(onOrBefore: dayBefore),
              let start = calendar.date(byAdding: .day, value: 1, to: previous) else { return nil }
        return CardCycle(billDate: billDate, start: start, end: end, dueDate: card.dueDate(forStatementOn: billDate))
    }

    /// Splits what a card owes into the latest bill and the spending after it. `lines` and `lentLines` are the
    /// card's own movements and friends' purchases, and `owed` is the total on the card, friends included.
    static func statement(for card: PaymentCard, lines: [LedgerLine], lentLines: [LedgerLine], owed: Decimal, now: Date = .now) -> CardStatement? {
        let calendar = Calendar.current
        guard card.hasBillingCycle, let billDate = card.lastStatementDate(onOrBefore: now),
              let cutoff = calendar.date(byAdding: .day, value: 1, to: billDate) else { return nil }
        // Anything on the bill day itself is on that bill.
        let unbilled = (lines + lentLines)
            .filter { $0.date >= cutoff && $0.effect > 0 }
            .reduce(Decimal(0)) { $0 + $1.effect }
        return CardStatement(
            billDate: billDate,
            dueDate: card.dueDate(forStatementOn: billDate),
            billed: max(0, owed - unbilled),
            unbilled: unbilled,
            nextBillDate: card.nextStatementDate(from: cutoff)
        )
    }

    /// Friends who still owe something on this card, biggest amount first.
    ///
    /// A loan is on the card when the bank matches and, if the card has digits, those match too. This is how
    /// the account ledger finds a card's loans.
    static func friendShares(bankName: String, lastFour: String, loans: [Loan]) -> [CardBillShare] {
        func sameBank(_ a: String, _ b: String) -> Bool {
            let a = a.trimmingCharacters(in: .whitespaces)
            return !a.isEmpty && a.caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces)) == .orderedSame
        }

        let onCard = loans.filter { loan in
            loan.method == .card && !loan.isRepaid && loan.outstandingAmount > 0
                && sameBank(loan.bankName, bankName)
                && (lastFour.isEmpty || loan.cardLastFour == lastFour)
        }

        return Dictionary(grouping: onCard) { $0.friendName.trimmingCharacters(in: .whitespaces).lowercased() }
            .values
            .compactMap { group -> CardBillShare? in
                guard let first = group.first else { return nil }
                let amount = group.reduce(Decimal(0)) { $0 + ($1.isInstalmentLoan ? $1.emiDueAmount : $1.outstandingAmount) }
                // The most recently saved number for this friend.
                let phone = group.sorted { $0.date > $1.date }
                    .map { $0.friendPhone.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty } ?? ""
                return CardBillShare(friendName: first.friendName, phone: phone, loans: group, amount: amount)
            }
            .sorted { $0.amount > $1.amount }
    }
}

/// Notifications before a credit card's bill is due: your own reminder to pay it, and who to remind.
///
/// An iPhone app can't send a message by itself. The notification tells you who to remind, and tapping it
/// opens the card, where each friend has a button that opens a message or WhatsApp with the words already
/// written. The first one comes 5 days before the due date.
enum CardBillReminder {
    private static let prefix = "cardbill-"
    /// How many days before the due date to remind.
    private static let daysBefore = [5, 3, 1]
    /// How many due dates ahead to schedule. They are rebuilt every time the app opens.
    private static let dueDatesAhead = 2
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ExpenseTracker", category: "CardBillReminder")

    /// Replaces the scheduled bill reminders with ones for the cards as they are now.
    @MainActor
    static func reschedule(in context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            log.info("Card bill reminders skipped: notifications are not allowed")
            return
        }

        let cards = ((try? context.fetch(FetchDescriptor<PaymentCard>())) ?? []).filter(\.hasDueDate)
        guard !cards.isEmpty else { return }
        var count = 0
        defer { log.info("Scheduled \(count) card bill reminders for \(cards.count) card(s)") }
        let loans = (try? context.fetch(FetchDescriptor<Loan>())) ?? []
        let calendar = Calendar.current
        // What is billed on each card, to put the amount in your own reminder.
        let ledger = AccountLedger(
            accounts: (try? context.fetch(FetchDescriptor<Account>())) ?? [],
            expenses: (try? context.fetch(FetchDescriptor<Expense>())) ?? [],
            incomes: (try? context.fetch(FetchDescriptor<Income>())) ?? [],
            loans: loans,
            repayments: (try? context.fetch(FetchDescriptor<LoanRepayment>())) ?? [],
            transfers: (try? context.fetch(FetchDescriptor<Transfer>())) ?? [],
            borrowings: (try? context.fetch(FetchDescriptor<Borrowing>())) ?? [],
            borrowingPayments: (try? context.fetch(FetchDescriptor<BorrowingPayment>())) ?? [],
            now: now
        )
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []

        for card in cards {
            let account = accounts.first { $0.uid == card.accountUID }
            let statement = account.flatMap { account in
                CardBill.statement(
                    for: card,
                    lines: ledger.lines(for: account),
                    lentLines: ledger.lentLines(for: account),
                    owed: ledger.balance(of: account) + ledger.lentOutstanding(of: account),
                    now: now
                )
            }
            let shares = CardBill.friendShares(bankName: card.bankName, lastFour: card.cardLastFour, loans: loans)
            var due = card.nextDueDate(from: now)
            var scheduled = 0

            while let dueDate = due, scheduled < dueDatesAhead {
                // The amount is only known for the bill already generated. Nothing is sent for a bill that is paid.
                let billed = (scheduled == 0 && statement?.dueDate.map { calendar.isDate($0, inSameDayAs: dueDate) } == true)
                    ? statement?.billed : nil
                if billed == 0 && shares.isEmpty {
                    scheduled += 1
                    due = card.nextDueDate(from: calendar.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate)
                    continue
                }
                for offset in daysBefore {
                    guard let day = calendar.date(byAdding: .day, value: -offset, to: dueDate),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                          fire > now else { continue }

                    let content = UNMutableNotificationContent()
                    let name = card.displayName
                    let dueText = dueDate.formatted(.dateTime.day().month(.abbreviated))
                    content.title = "\(name) bill is due \(offset == 1 ? "tomorrow" : "in \(offset) days")"
                    let mine = (billed ?? 0) > 0
                        ? "Your bill of \((billed ?? 0).formatted(.rupees)) is due \(dueText)."
                        : "Pay your bill by \(dueText) to avoid late charges."
                    if shares.isEmpty {
                        content.body = mine
                    } else {
                        let list = shares.map { "\($0.friendName) (\($0.amount.formatted(.rupees)))" }.formatted(.list(type: .and))
                        content.body = "\(mine) Tap to remind \(list)."
                    }
                    content.sound = .default
                    if !card.accountUID.isEmpty { content.userInfo = ["cardUID": card.accountUID] }

                    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let key = dueDate.formatted(.iso8601.year().month().day())
                    let id = "\(prefix)\(abs(card.persistentModelID.hashValue))-\(key)-\(offset)"
                    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                    count += 1
                }
                scheduled += 1
                // The following month's due date.
                due = card.nextDueDate(from: calendar.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate)
            }
        }
    }
}
