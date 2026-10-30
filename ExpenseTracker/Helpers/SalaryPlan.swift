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
/// Each month is added once, on or after the salary day, and only if you haven't already entered a salary
/// for that month yourself. A month you delete or change is never added again.
enum SalaryPlanStore {
    private static let enabledKey = "salaryEnabled"
    private static let amountKey = "salaryAmountPaise"
    private static let dayKey = "salaryDay"
    private static let bankKey = "salaryBank"
    private static let startKey = "salaryStart"
    private static let postedKey = "salaryPostedMonths"

    /// Safety net so a bad start date can't loop for decades.
    private static let maximumMonths = 120

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

    /// Adds the salary for every month, from the month it was set up to now, whose salary day has arrived.
    @MainActor
    static func postDue(in context: ModelContext, now: Date = .now) {
        guard let plan = current else { return }
        let defaults = UserDefaults.standard
        let calendar = Calendar.current

        let startInterval = defaults.double(forKey: startKey)
        var month = calendar.monthRange(containing: Date(timeIntervalSince1970: startInterval > 0 ? startInterval : now.timeIntervalSince1970)).lowerBound
        let currentMonth = calendar.monthRange(containing: now).lowerBound
        var posted = Set(defaults.stringArray(forKey: postedKey) ?? [])

        var processed = 0
        while month <= currentMonth, processed < maximumMonths {
            let key = monthKey(month, calendar: calendar)
            if !posted.contains(key) {
                let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
                var components = calendar.dateComponents([.year, .month], from: month)
                components.day = min(plan.day, daysInMonth)
                components.hour = 12
                if let salaryDate = calendar.date(from: components), salaryDate <= now {
                    if !hasSalary(inMonthOf: month, in: context, calendar: calendar) {
                        context.insert(Income(
                            amount: plan.amount,
                            source: .salary,
                            note: "Monthly salary",
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
