//
//  MonthlyRecap.swift
//  ExpenseTracker
//

import Foundation
import UserNotifications

/// A summary of one month: what came in, what went out, what was kept, and what stood out.
///
/// Rules match the rest of the app: spending counts when paid, so EMIs and premiums not yet paid are left out,
/// and money kept is income minus spending, minus cash lent to friends, plus cash loans repaid.
struct MonthlyRecap {
    struct CategoryTotal: Identifiable {
        let category: ExpenseCategory
        let total: Decimal
        var id: ExpenseCategory { category }
    }

    let month: Date
    /// The month has ended. Otherwise the figures are so far.
    let isFinished: Bool
    let income: Decimal
    let spent: Decimal
    let saved: Decimal
    /// Spending in the month before. `nil` when there was none, so there is nothing to compare with.
    let previousSpent: Decimal?
    let previousMonth: Date
    /// The three categories with the most spending, biggest first.
    let topCategories: [CategoryTotal]
    let biggestExpense: Expense?
    /// The category whose spending rose most since the month before, and by how much.
    let biggestRise: CategoryTotal?
    let fixedSpent: Decimal
    let variableSpent: Decimal
    /// Categories that went over their monthly limit.
    let overLimit: [ExpenseCategory]
    let goalsSetAside: Decimal
    let dailyAverage: Decimal
    let noSpendDays: Int
    /// Days counted for the daily average and no-spend days: the whole month, or up to today.
    let daysCounted: Int

    init(
        month: Date,
        expenses: [Expense],
        previousExpenses: [Expense],
        incomes: [Income],
        cashLoans: [Loan],
        cashRepayments: [LoanRepayment],
        budgets: [CategoryBudget],
        contributions: [GoalContribution],
        now: Date = .now
    ) {
        let calendar = Calendar.current
        let range = calendar.monthRange(containing: month)
        self.month = range.lowerBound
        self.isFinished = range.upperBound <= now
        self.previousMonth = calendar.date(byAdding: .month, value: -1, to: range.lowerBound) ?? range.lowerBound

        let paid = expenses.filter { !$0.isPlanned }
        let previousPaid = previousExpenses.filter { !$0.isPlanned }

        income = incomes.totalAmount
        spent = paid.totalAmount
        saved = income - spent - cashLoans.totalAmount + cashRepayments.totalAmount
        let before = previousPaid.totalAmount
        previousSpent = before > 0 ? before : nil

        let byCategory = Dictionary(grouping: paid, by: \.category).mapValues { $0.totalAmount }
        let ranked = byCategory
            .map { CategoryTotal(category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
        topCategories = Array(ranked.prefix(3))
        biggestExpense = paid.max { $0.amount < $1.amount }

        let previousByCategory = Dictionary(grouping: previousPaid, by: \.category).mapValues { $0.totalAmount }
        biggestRise = byCategory
            .map { CategoryTotal(category: $0.key, total: $0.value - (previousByCategory[$0.key] ?? 0)) }
            .filter { $0.total > 0 && before > 0 }
            .max { $0.total < $1.total }

        fixedSpent = paid.filter(\.isFixedSpending).totalAmount
        variableSpent = spent - fixedSpent

        overLimit = budgets
            .filter { budget in (byCategory[budget.category] ?? 0) > budget.limit }
            .map(\.category)
        goalsSetAside = contributions.totalAmount

        // Days to count: all of a finished month, up to today in the current one, none in a future month.
        let daysInMonth = calendar.range(of: .day, in: .month, for: range.lowerBound)?.count ?? 30
        let counted: Int
        if isFinished {
            counted = daysInMonth
        } else if range.lowerBound > now {
            counted = 0
        } else {
            counted = max(1, calendar.component(.day, from: now))
        }
        daysCounted = counted
        dailyAverage = counted > 0 ? spent / Decimal(counted) : 0
        let daysWithSpending = Set(paid.map { calendar.component(.day, from: $0.date) }.filter { $0 <= counted })
        noSpendDays = max(0, counted - daysWithSpending.count)
    }

    var hasData: Bool { income > 0 || spent > 0 }

    var savingsRate: Double? {
        guard income > 0 else { return nil }
        return NSDecimalNumber(decimal: saved / income).doubleValue
    }

    /// Change in spending since the month before, as a fraction. `nil` with nothing to compare.
    var spendingChange: Double? {
        guard let previousSpent, previousSpent > 0 else { return nil }
        return NSDecimalNumber(decimal: (spent - previousSpent) / previousSpent).doubleValue
    }

    private var monthName: String { month.formatted(.dateTime.month(.wide)) }
    private var previousMonthName: String { previousMonth.formatted(.dateTime.month(.wide)) }

    /// One or two plain sentences about the month.
    var headline: String {
        guard hasData else { return "Nothing was recorded for \(monthName)." }

        var sentences: [String] = []
        var first = isFinished
            ? "You spent \(spent.formatted(.rupees)) in \(monthName)"
            : "You have spent \(spent.formatted(.rupees)) so far in \(monthName)"
        if let change = spendingChange {
            let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
            if abs(change) < 0.01 {
                first += ", about the same as \(previousMonthName)"
            } else {
                first += change < 0
                    ? ", \(percent) less than \(previousMonthName)"
                    : ", \(percent) more than \(previousMonthName)"
            }
        }
        sentences.append(first + ".")

        if let top = topCategories.first {
            sentences.append("\(top.category.rawValue) was your biggest category.")
        }
        if income > 0 {
            if saved > 0 {
                let rate = (savingsRate ?? 0).formatted(.percent.precision(.fractionLength(0)))
                sentences.append(isFinished
                    ? "You kept \(saved.formatted(.rupees)), \(rate) of your income."
                    : "You are keeping \(saved.formatted(.rupees)) so far, \(rate) of your income.")
            } else if saved < 0 {
                sentences.append("You spent more than you earned.")
            }
        }
        return sentences.joined(separator: " ")
    }

    /// Text for sharing the recap.
    var shareText: String {
        var lines = ["\(month.formatted(.dateTime.month(.wide).year())) recap", "", headline, ""]
        lines.append("Income: \(income.formatted(.rupees))")
        lines.append("Spent: \(spent.formatted(.rupees))")
        lines.append("Kept: \(saved.formatted(.rupees))")
        if !topCategories.isEmpty {
            lines.append("")
            lines.append("Top categories:")
            for item in topCategories {
                lines.append("• \(item.category.rawValue): \(item.total.formatted(.rupees))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A notification on the 1st of every month, saying last month's recap is ready.
enum RecapReminder {
    private static let identifier = "monthly-recap"

    /// Schedules the repeating notification once, if reminders are allowed. Safe to call on every launch.
    static func scheduleIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        // Already waiting to go off.
        let pending = await center.pendingNotificationRequests()
        if pending.contains(where: { $0.identifier == identifier }) { return }

        let content = UNMutableNotificationContent()
        content.title = "Your monthly recap is ready"
        content.body = "See how last month went: what you spent, what you kept and where it went."
        content.sound = .default

        var components = DateComponents()
        components.day = 1
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
