//
//  Goal.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Something you are saving up for, such as a phone or a trip.
///
/// Money for a goal is set aside, not spent: it stays in your savings and nothing changes in your balances
/// or net worth. At the end of each month the app sets aside the monthly amount from what was left over.
/// You can also add money by hand. When you buy the thing, the goal is closed and the money is released.
@Model
final class Goal {
    var name: String = ""
    var targetPaise: Int64 = 0
    var monthlyPaise: Int64 = 0
    /// First month that counts. Its leftover is set aside when that month ends.
    var startMonth: Date = Date.now
    /// The finish date chosen when planning by date. `nil` when planning by monthly amount.
    var targetDate: Date?
    /// The last month whose leftover has been looked at, so no month is counted twice.
    var lastProcessedMonth: Date?
    /// When you bought it. `nil` while you are still saving.
    var completedAt: Date?
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal)
    var contributions: [GoalContribution] = []

    init(name: String, target: Decimal, monthly: Decimal, targetDate: Date? = nil, startMonth: Date = .now) {
        self.name = name
        self.targetPaise = Money.paise(from: target)
        self.monthlyPaise = Money.paise(from: monthly)
        self.targetDate = targetDate
        self.startMonth = Calendar.current.monthRange(containing: startMonth).lowerBound
    }

    var target: Decimal {
        get { Money.amount(fromPaise: targetPaise) }
        set { targetPaise = Money.paise(from: newValue) }
    }

    var monthly: Decimal {
        get { Money.amount(fromPaise: monthlyPaise) }
        set { monthlyPaise = Money.paise(from: newValue) }
    }

    // MARK: Progress

    /// Everything set aside so far, automatically and by hand.
    var saved: Decimal { contributions.reduce(0) { $0 + $1.amount } }

    var remaining: Decimal { max(0, target - saved) }

    /// 0 to 1.
    var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: saved / target).doubleValue))
    }

    var isCompleted: Bool { completedAt != nil }

    /// Enough has been set aside, but it hasn't been bought yet.
    var isFunded: Bool { !isCompleted && target > 0 && saved >= target }

    var sortedContributions: [GoalContribution] { contributions.sorted { $0.date > $1.date } }

    // MARK: Plan

    /// How many more monthly amounts are needed. `nil` when nothing is left or there is no monthly amount.
    var monthsToFinish: Int? {
        Goal.months(toSave: remaining, monthly: monthly)
    }

    /// The month the goal is expected to be fully set aside, at the planned monthly amount.
    func projectedFinish(from now: Date = .now) -> Date? {
        guard let months = monthsToFinish else { return nil }
        return Goal.finishMonth(afterMonths: months, from: now)
    }

    /// What should have been set aside by now if every finished month had gone to plan.
    func expectedSaved(now: Date = .now) -> Decimal {
        let calendar = Calendar.current
        let current = calendar.monthRange(containing: now).lowerBound
        let finished = max(0, calendar.dateComponents([.month], from: startMonth, to: current).month ?? 0)
        return min(target, monthly * Decimal(finished))
    }

    /// How far below plan the goal is. Zero when on track or ahead.
    func shortfall(now: Date = .now) -> Decimal {
        guard !isCompleted, !isFunded else { return 0 }
        return max(0, expectedSaved(now: now) - saved)
    }

    // MARK: Planning helpers, shared with the form

    /// Whole months of `monthly` needed to cover `amount`.
    static func months(toSave amount: Decimal, monthly: Decimal) -> Int? {
        guard amount > 0, monthly > 0 else { return nil }
        var months = amount / monthly
        var rounded = Decimal()
        NSDecimalRound(&rounded, &months, 0, .up)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The month in which the `months`th monthly amount is set aside. The first is set aside when this month ends.
    static func finishMonth(afterMonths months: Int, from now: Date = .now) -> Date? {
        let calendar = Calendar.current
        let current = calendar.monthRange(containing: now).lowerBound
        return calendar.date(byAdding: .month, value: max(0, months - 1), to: current)
    }

    /// How many month ends fall from this month up to and including the month of `date`. At least 1.
    static func monthEnds(until date: Date, from now: Date = .now) -> Int {
        let calendar = Calendar.current
        let start = calendar.monthRange(containing: now).lowerBound
        let end = calendar.monthRange(containing: date).lowerBound
        return max(1, (calendar.dateComponents([.month], from: start, to: end).month ?? 0) + 1)
    }

    /// The monthly amount, rounded up to a whole rupee, that covers `amount` in `months` months.
    static func monthly(toSave amount: Decimal, over months: Int) -> Decimal {
        guard amount > 0, months > 0 else { return 0 }
        var perMonth = amount / Decimal(months)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &perMonth, 0, .up)
        return rounded
    }
}

/// One amount set aside for a goal.
@Model
final class GoalContribution {
    var amountPaise: Int64 = 0
    var date: Date = Date.now
    var note: String = ""
    /// The month this came from when it was set aside automatically at month end. `nil` for amounts added by hand.
    var month: Date?
    var goal: Goal?

    init(amount: Decimal, date: Date = .now, note: String = "", month: Date? = nil) {
        self.amountPaise = Money.paise(from: amount)
        self.date = date
        self.note = note
        self.month = month
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    var isAutomatic: Bool { month != nil }
}

extension Sequence where Element == GoalContribution {
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }
}

/// Sets aside each goal's monthly amount from every finished month's leftover.
enum GoalAllocator {
    /// Safety net so a bad start date can't loop for decades.
    private static let maximumMonths = 120

    /// Looks at every finished month that no goal has seen yet. Safe to run on every launch.
    ///
    /// The leftover of a month is shared by all goals, oldest goal first. A goal takes its monthly amount, or
    /// less if the leftover runs out or the goal is already fully set aside. A month with nothing left over
    /// sets nothing aside, and the goal shows as behind plan.
    @MainActor
    static func run(in context: ModelContext, now: Date = .now) {
        let all = (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let goals = all.filter { !$0.isCompleted }
        guard !goals.isEmpty else { return }

        let calendar = Calendar.current
        let currentMonth = calendar.monthRange(containing: now).lowerBound

        /// The next month a goal still has to look at.
        func nextMonth(for goal: Goal) -> Date {
            guard let last = goal.lastProcessedMonth,
                  let next = calendar.date(byAdding: .month, value: 1, to: last) else { return goal.startMonth }
            return max(next, goal.startMonth)
        }

        guard var month = goals.map(nextMonth(for:)).min() else { return }
        var processed = 0

        while month < currentMonth, processed < maximumMonths {
            let due = goals.filter { nextMonth(for: $0) <= month }
            if !due.isEmpty {
                var pool = max(0, SavingsSweep.leftover(for: month, in: context))
                for goal in due {
                    let allotment = min(goal.monthly, goal.remaining, pool)
                    if allotment > 0 {
                        let contribution = GoalContribution(
                            amount: allotment, date: lastDay(of: month), note: "Month-end savings", month: month
                        )
                        context.insert(contribution)
                        goal.contributions.append(contribution)
                        pool -= allotment
                    }
                    goal.lastProcessedMonth = month
                }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
            processed += 1
        }
        try? context.save()
    }

    /// Noon on the last day of the month, so the amount shows under that month.
    private static func lastDay(of month: Date) -> Date {
        let calendar = Calendar.current
        let nextMonth = calendar.monthRange(containing: month).upperBound
        let last = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? month
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: last) ?? last
    }
}
