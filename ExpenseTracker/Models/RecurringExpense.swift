//
//  RecurringExpense.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Something you pay every month, such as rent, the maid or a subscription.
///
/// On the chosen day of each month the app adds an ordinary expense for it, so it shows in Daily, Monthly and
/// Budget like anything you entered yourself, and counts as spending that day. The expenses it adds can be edited
/// or deleted on their own without affecting this plan.
@Model
final class RecurringExpense {
    var title: String = ""
    var amountPaise: Int64 = 0
    var categoryRaw: String = ExpenseCategory.rent.rawValue
    var accountTypeRaw: String = AccountType.cash.rawValue
    var bankName: String = ""
    var cardLastFour: String = ""
    /// 1 to 28, so the day exists in every month.
    var dayOfMonth: Int = 1
    /// Payments before this day are not added. Set when pausing is undone, so paused months are not back-filled.
    var startDate: Date = Date.now
    var endDate: Date?
    var isActive: Bool = true
    /// The last month an expense was added for, so no month is added twice.
    var lastPostedMonth: Date?
    var createdAt: Date = Date.now

    init(
        title: String,
        amount: Decimal,
        category: ExpenseCategory,
        accountType: AccountType,
        bankName: String = "",
        cardLastFour: String = "",
        dayOfMonth: Int,
        startDate: Date = .now,
        endDate: Date? = nil
    ) {
        self.title = title
        self.amountPaise = Money.paise(from: amount)
        self.categoryRaw = category.rawValue
        self.accountTypeRaw = accountType.rawValue
        self.bankName = bankName
        self.cardLastFour = cardLastFour
        self.dayOfMonth = min(max(dayOfMonth, 1), 28)
        self.startDate = startDate
        self.endDate = endDate
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .cash }
        set { accountTypeRaw = newValue.rawValue }
    }

    /// e.g. "Credit Card · HDFC Bank · •••• 0214", or "Cash".
    var paymentDescription: String {
        var parts = [accountType.rawValue]
        if !bankName.isEmpty { parts.append(bankName) }
        if !cardLastFour.isEmpty { parts.append("•••• \(cardLastFour)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Dates

    /// 9am on the payment day of `month`.
    func dueDate(inMonth month: Date) -> Date? {
        RecurringExpense.dueDate(day: dayOfMonth, inMonth: month)
    }

    static func dueDate(day: Int, inMonth month: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(max(day, 1), 28)
        components.hour = 9
        return calendar.date(from: components)
    }

    /// The first payment day on or after `startDate`.
    static func firstDue(day: Int, startingFrom startDate: Date) -> Date? {
        let calendar = Calendar.current
        let startOfStart = calendar.startOfDay(for: startDate)
        var month = calendar.monthRange(containing: startDate).lowerBound
        for _ in 0..<2 {
            if let due = dueDate(day: day, inMonth: month), due >= startOfStart { return due }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            month = next
        }
        return nil
    }

    /// The next payment day after now, or `nil` when paused or finished.
    func nextDue(now: Date = .now) -> Date? {
        guard isActive else { return nil }
        let calendar = Calendar.current
        let startOfStart = calendar.startOfDay(for: startDate)
        var month = calendar.monthRange(containing: max(now, startDate)).lowerBound
        for _ in 0..<3 {
            if let due = dueDate(inMonth: month), due > now, due >= startOfStart {
                if let endDate, due > endDate { return nil }
                return due
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            month = next
        }
        return nil
    }

    /// The plan has an end date that has passed.
    func hasEnded(now: Date = .now) -> Bool {
        guard let endDate else { return false }
        return endDate < now
    }

    /// Whether this plan is a budget commitment in `month` that has not yet been posted as an expense.
    /// This lets budgets reserve rent and subscriptions before their payment day without recording spending early.
    func hasUnpostedCommitment(in month: Date) -> Bool {
        guard isActive,
              let due = dueDate(inMonth: month) else { return false }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        guard due >= start, endDate.map({ due <= $0 }) ?? true else { return false }
        guard let lastPostedMonth else { return true }
        return !calendar.isDate(lastPostedMonth, equalTo: month, toGranularity: .month)
    }
}

extension Sequence where Element == RecurringExpense {
    /// What the active plans add up to in a month.
    var monthlyTotal: Decimal { reduce(0) { $0 + ($1.isActive ? $1.amount : 0) } }
}

/// Adds the expense for each recurring plan whose payment day has come.
enum RecurringExpensePoster {
    /// Safety net so a start date far in the past can't add decades of expenses at once.
    private static let maximumMonths = 60

    /// Safe to run on every launch. Each month is added once, on or after its payment day.
    @MainActor
    static func run(in context: ModelContext, now: Date = .now) {
        let plans = (try? context.fetch(FetchDescriptor<RecurringExpense>())) ?? []
        let calendar = Calendar.current
        let currentMonth = calendar.monthRange(containing: now).lowerBound
        let startOfNow = now

        for plan in plans where plan.isActive {
            let startOfStart = calendar.startOfDay(for: plan.startDate)
            var month: Date
            if let last = plan.lastPostedMonth, let next = calendar.date(byAdding: .month, value: 1, to: last) {
                month = max(next, calendar.monthRange(containing: plan.startDate).lowerBound)
            } else {
                month = calendar.monthRange(containing: plan.startDate).lowerBound
            }

            var added = 0
            while month <= currentMonth, added < maximumMonths {
                if let due = plan.dueDate(inMonth: month) {
                    // Later days of this month haven't come yet.
                    if due > startOfNow { break }
                    let beforeEnd = plan.endDate.map { due <= $0 } ?? true
                    if due >= startOfStart, beforeEnd {
                        context.insert(Expense(
                            title: plan.title, amount: plan.amount, accountType: plan.accountType,
                            bankName: plan.bankName, cardLastFour: plan.cardLastFour,
                            category: plan.category, date: due
                        ))
                        plan.lastPostedMonth = month
                        added += 1
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        }
        try? context.save()
    }
}
