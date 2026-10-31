//
//  CategoryBudget.swift
//  ExpenseTracker
//

import Foundation
import SwiftData
import UserNotifications

/// A monthly spending limit for one category, for example ₹10,000 for Food & Dining.
///
/// The same limit applies to every month. What counts is what you have actually spent in the category that
/// month. EMIs and premiums that are not yet paid are not counted.
@Model
final class CategoryBudget {
    var categoryRaw: String = ExpenseCategory.food.rawValue
    var limitPaise: Int64 = 0
    var createdAt: Date = Date.now

    init(category: ExpenseCategory, limit: Decimal) {
        self.categoryRaw = category.rawValue
        self.limitPaise = Money.paise(from: limit)
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var limit: Decimal {
        get { Money.amount(fromPaise: limitPaise) }
        set { limitPaise = Money.paise(from: newValue) }
    }

    /// How close `spent` is to the limit.
    func level(spent: Decimal) -> Level {
        guard limit > 0 else { return .fine }
        let ratio = NSDecimalNumber(decimal: spent / limit).doubleValue
        if ratio > 1 { return .over }
        if ratio >= Level.nearThreshold { return .near }
        return .fine
    }

    enum Level {
        case fine
        /// 80% or more of the limit is used.
        case near
        /// More than the limit is spent.
        case over

        static let nearThreshold = 0.8
    }
}

/// Tells you when a category is close to its limit, and when it goes over. Each is sent once per month.
enum BudgetAlerts {
    private static let sentKey = "budgetAlertsSent"

    /// Looks at this month's spending against every limit. Safe to call after any change to expenses.
    @MainActor
    static func check(in context: ModelContext, now: Date = .now) async {
        let budgets = (try? context.fetch(FetchDescriptor<CategoryBudget>())) ?? []
        guard !budgets.isEmpty else { return }

        let calendar = Calendar.current
        let range = calendar.monthRange(containing: now)
        let start = range.lowerBound
        let end = range.upperBound
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let spentExpenses = expenses.filter { !$0.isPlanned }

        // Year and month in the phone's own time zone, e.g. "2026-10".
        let parts = calendar.dateComponents([.year, .month], from: start)
        let monthKey = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        var sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        // Forget earlier months so the list doesn't grow forever.
        sent = sent.filter { $0.hasPrefix(monthKey) }

        for budget in budgets {
            let spent = spentExpenses.filter { $0.category == budget.category }.totalAmount
            let level = budget.level(spent: spent)
            guard level != .fine else { continue }

            let nearKey = "\(monthKey)|\(budget.categoryRaw)|near"
            let overKey = "\(monthKey)|\(budget.categoryRaw)|over"
            switch level {
            case .near:
                guard !sent.contains(nearKey) else { continue }
                sent.insert(nearKey)
                await notify(
                    title: "\(budget.category.rawValue) is almost at its limit",
                    body: "You've spent \(spent.formatted(.rupees)) of your \(budget.limit.formatted(.rupees)) limit this month."
                )
            case .over:
                guard !sent.contains(overKey) else { continue }
                // Going straight past the limit also covers the earlier warning.
                sent.insert(nearKey)
                sent.insert(overKey)
                await notify(
                    title: "\(budget.category.rawValue) is over its limit",
                    body: "You've spent \(spent.formatted(.rupees)), which is \((spent - budget.limit).formatted(.rupees)) more than your \(budget.limit.formatted(.rupees)) limit."
                )
            case .fine:
                break
            }
        }
        UserDefaults.standard.set(Array(sent), forKey: sentKey)
    }

    /// Shows a notification now, if reminders are allowed.
    private static func notify(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "budget-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }
}
