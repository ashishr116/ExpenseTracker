//
//  SalaryPlan.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Your monthly take-home salary: how much, on which day, and into which bank.
struct SalaryPlan: Equatable {
    var amount: Decimal
    /// Day of the month the salary is credited, 1 to 31. In shorter months it falls on the last day.
    var day: Int
    var bankName: String
}

/// Remembers the salary plan and adds the salary to your income each month, so you don't have to.
///
/// Each month is added once, and only if you haven't already entered a salary for that month yourself. It is
/// added ahead of time, dated on its salary day, so Budget and Monthly show the coming months' income. A month
/// you delete or change is never added again.
enum SalaryPlanStore {
    private static let enabledKey = "salaryEnabled"
    private static let amountKey = "salaryAmountPaise"
    private static let dayKey = "salaryDay"
    private static let bankKey = "salaryBank"
    private static let startKey = "salaryStart"
    private static let postedKey = "salaryPostedMonths"

    /// Safety net so a bad start date can't loop for decades.
    private static let maximumMonths = 120

    /// How many months after this one the salary is added ahead of time.
    private static let monthsAhead = 12

    /// The note on the entries added for you, which is how they are told apart from salary you entered yourself.
    private static let autoNote = "Monthly salary"

    /// The saved plan, or `nil` if there is none or it is switched off.
    static var current: SalaryPlan? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let paise = Int64(defaults.integer(forKey: amountKey))
        guard paise > 0 else { return nil }
        let day = defaults.integer(forKey: dayKey)
        return SalaryPlan(
            amount: Money.amount(fromPaise: paise),
            day: min(max(day, 1), 31),
            bankName: defaults.string(forKey: bankKey) ?? ""
        )
    }

    static func save(_ plan: SalaryPlan) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: enabledKey)
        defaults.set(Int(Money.paise(from: plan.amount)), forKey: amountKey)
        defaults.set(plan.day, forKey: dayKey)
        defaults.set(plan.bankName, forKey: bankKey)
        // Salary is added from the month it was set up, never for earlier months.
        if defaults.double(forKey: startKey) == 0 {
            let thisMonth = Calendar.current.monthRange(containing: .now).lowerBound
            defaults.set(thisMonth.timeIntervalSince1970, forKey: startKey)
        }
    }

    static func turnOff() {
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    // MARK: Adding salary

    /// Adds the salary for every month from the month it was set up, through the next twelve months.
    /// Future months are dated on their salary day, so they count in that month's totals but not in your account
    /// balances until the day arrives.
    @MainActor
    static func postDue(in context: ModelContext, now: Date = .now) {
        guard let plan = current else { return }
        let defaults = UserDefaults.standard
        let calendar = Calendar.current

        let startInterval = defaults.double(forKey: startKey)
        var month = calendar.monthRange(containing: Date(timeIntervalSince1970: startInterval > 0 ? startInterval : now.timeIntervalSince1970)).lowerBound
        let currentMonth = calendar.monthRange(containing: now).lowerBound
        let lastMonth = calendar.date(byAdding: .month, value: monthsAhead, to: currentMonth) ?? currentMonth
        var posted = Set(defaults.stringArray(forKey: postedKey) ?? [])

        var processed = 0
        while month <= lastMonth, processed < maximumMonths {
            let key = monthKey(month, calendar: calendar)
            if !posted.contains(key) {
                let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
                var components = calendar.dateComponents([.year, .month], from: month)
                components.day = min(plan.day, daysInMonth)
                components.hour = 12
                if let salaryDate = calendar.date(from: components) {
                    if !hasSalary(inMonthOf: month, in: context, calendar: calendar) {
                        context.insert(Income(
                            amount: plan.amount,
                            source: .salary,
                            note: autoNote,
                            bankName: plan.bankName,
                            date: salaryDate
                        ))
                    }
                    posted.insert(key)
                }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
            processed += 1
        }

        defaults.set(Array(posted), forKey: postedKey)
        try? context.save()
    }

    /// Removes the salary added ahead of time for months that haven't come yet, so a changed or stopped plan
    /// doesn't leave the old amount behind. Salary you entered yourself, or already received, stays.
    @MainActor
    static func removeUpcoming(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let salaryRaw = IncomeSource.salary.rawValue
        let note = autoNote
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate { $0.sourceRaw == salaryRaw && $0.note == note && $0.date > now }
        )
        let upcoming = (try? context.fetch(descriptor)) ?? []
        guard !upcoming.isEmpty else { return }

        // Forget those months, so the new plan adds them again.
        let defaults = UserDefaults.standard
        var posted = Set(defaults.stringArray(forKey: postedKey) ?? [])
        for income in upcoming {
            posted.remove(monthKey(calendar.monthRange(containing: income.date).lowerBound, calendar: calendar))
            context.delete(income)
        }
        defaults.set(Array(posted), forKey: postedKey)
        try? context.save()
    }

    private static func monthKey(_ month: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    /// Whether a salary entry already exists in that month, whether you entered it or it was added for you.
    private static func hasSalary(inMonthOf month: Date, in context: ModelContext, calendar: Calendar) -> Bool {
        let range = calendar.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound
        let salaryRaw = IncomeSource.salary.rawValue
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.sourceRaw == salaryRaw }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
