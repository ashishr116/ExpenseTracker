//
//  EMI.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// A monthly instalment plan (e.g. an iPhone bought on a credit card EMI).
///
/// The EMI owns one real `Expense` per month (its `installments`), dated on the billing day
/// from `startMonth` through `endMonth`. Because they're ordinary expenses, they automatically
/// appear in the Daily, Monthly and Budget Plan views — including future months, for planning.
@Model
final class EMI {
    var name: String
    @Attribute(originalName: "monthlyAmount") private var legacyMonthlyAmount: Double = 0
    var monthlyAmountPaise: Int64 = 0
    var accountTypeRaw: String
    var bankName: String
    var cardLastFour: String
    /// Day of the month the EMI is billed (1–31; clamped to the month's length).
    var billingDay: Int
    /// Any date within the month of the first instalment.
    var startMonth: Date
    /// Any date within the month of the last instalment.
    var endMonth: Date

    /// Annual interest rate in percent. Optional; when set, net worth counts only the outstanding principal.
    var annualInterestRate: Double?
    /// Whether the outstanding amount counts as debt in net worth. Turn off when the same loan
    /// is also tracked as a debt under Investments, so it isn't counted twice.
    var includedInNetWorth: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \Expense.emi)
    var installments: [Expense] = []

    init(
        name: String,
        monthlyAmount: Decimal,
        accountType: AccountType = .creditCard,
        bankName: String,
        cardLastFour: String,
        billingDay: Int,
        startMonth: Date,
        endMonth: Date
    ) {
        self.name = name
        self.monthlyAmountPaise = Money.paise(from: monthlyAmount)
        self.accountTypeRaw = accountType.rawValue
        self.bankName = bankName
        self.cardLastFour = cardLastFour
        self.billingDay = billingDay
        self.startMonth = startMonth
        self.endMonth = endMonth
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .creditCard }
        set { accountTypeRaw = newValue.rawValue }
    }

    var monthlyAmount: Decimal {
        get {
            monthlyAmountPaise == 0 && legacyMonthlyAmount != 0
                ? Money.amount(fromLegacy: legacyMonthlyAmount)
                : Money.amount(fromPaise: monthlyAmountPaise)
        }
        set { monthlyAmountPaise = Money.paise(from: newValue) }
    }

    func migrateLegacyMoney() {
        guard monthlyAmountPaise == 0, legacyMonthlyAmount != 0 else { return }
        monthlyAmountPaise = Money.paise(from: Money.amount(fromLegacy: legacyMonthlyAmount))
    }

    /// The billing date of every instalment, first to last.
    var installmentDates: [Date] {
        EMI.installmentDates(billingDay: billingDay, startMonth: startMonth, endMonth: endMonth)
    }

    /// Instalments the user has recorded as paid. Paid status is never inferred from the calendar.
    var paidInstallments: [Expense] { installments.filter { $0.paidAt != nil } }

    /// Instalments not yet recorded as paid, soonest first.
    var pendingInstallments: [Expense] {
        installments.filter { $0.paidAt == nil }.sorted { $0.date < $1.date }
    }

    /// Pending instalments billed today. These trigger the due-date pop-up.
    func dueTodayInstallments(asOf now: Date = .now) -> [Expense] {
        pendingInstallments.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    /// Pending instalments whose billing date has passed. Shown as a badge in the EMI list.
    func overdueInstallments(asOf now: Date = .now) -> [Expense] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return pendingInstallments.filter { $0.date < startOfToday }
    }

    var paidCount: Int { paidInstallments.count }

    /// Real instalments once generated; the planned schedule before that.
    var totalCount: Int { installments.isEmpty ? installmentDates.count : installments.count }

    var remainingCount: Int { totalCount - paidCount }

    var remainingAmount: Decimal {
        installments.isEmpty
            ? Decimal(remainingCount) * monthlyAmount
            : pendingInstallments.reduce(0) { $0 + $1.amount }
    }

    /// What you still owe the lender today, excluding future interest.
    ///
    /// With an interest rate this is the present value of the unpaid instalments, which is the
    /// outstanding principal (plus interest accrued so far). Without a rate there is nothing to
    /// strip out, so it is the full remaining amount.
    var outstandingPrincipal: Decimal {
        guard let rate = annualInterestRate, rate > 0, !installments.isEmpty else { return remainingAmount }
        let monthlyRate = rate / 12 / 100
        let secondsPerMonth = 30.4375 * 86_400
        let now = Date.now
        var presentValue = 0.0
        for installment in pendingInstallments {
            let months = max(0, installment.date.timeIntervalSince(now) / secondsPerMonth)
            presentValue += (installment.amount as NSDecimalNumber).doubleValue / pow(1 + monthlyRate, months)
        }
        // Round to whole paise so floating-point noise doesn't leak into displayed totals.
        return Money.amount(fromPaise: Int64((presentValue * 100).rounded()))
    }

    /// Records an instalment as paid. Existing history is never rewritten by later edits.
    func markPaid(_ installment: Expense, on date: Date = .now) {
        installment.paidAt = date
    }

    /// True while there are instalments still to be billed.
    var isActive: Bool { remainingCount > 0 }

    /// e.g. "Credit Card · HDFC Bank · •••• 1234"
    var accountDescription: String {
        var parts = [accountType.rawValue]
        if !bankName.isEmpty { parts.append(bankName) }
        if !cardLastFour.isEmpty { parts.append("•••• \(cardLastFour)") }
        return parts.joined(separator: " · ")
    }

    /// Billing dates for each month from `startMonth` to `endMonth` inclusive.
    /// A billing day of 31 falls on the last day in shorter months (e.g. 30 Apr, 28 Feb).
    static func installmentDates(billingDay: Int, startMonth: Date, endMonth: Date) -> [Date] {
        let calendar = Calendar.current
        var month = calendar.monthRange(containing: startMonth).lowerBound
        let lastMonth = calendar.monthRange(containing: endMonth).lowerBound
        var dates: [Date] = []

        // Cap at 50 years of instalments as a safety net against bad input.
        while month <= lastMonth, dates.count < 600 {
            let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = min(max(billingDay, 1), daysInMonth)
            components.hour = 9
            if let date = calendar.date(from: components) {
                dates.append(date)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return dates
    }

    /// Rebuilds the *pending* instalments from the current schedule. Call after creating or editing the EMI.
    ///
    /// Instalments already recorded as paid are real financial history and are left untouched.
    /// A scheduled month that already has a paid instalment is not generated again.
    ///
    /// - Parameter markingFirstPaid: How many of the newly created instalments, earliest first, to record as
    ///   already paid on their billing date. Use it when adding an EMI that started in the past.
    func regenerateInstallments(in context: ModelContext, markingFirstPaid alreadyPaid: Int = 0) {
        let calendar = Calendar.current
        let paid = paidInstallments
        var created: [Expense] = []

        for expense in pendingInstallments {
            context.delete(expense)
        }
        installments.removeAll { $0.paidAt == nil }

        for date in installmentDates {
            if paid.contains(where: { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }) {
                continue
            }
            let expense = Expense(
                title: "\(name) EMI",
                amount: monthlyAmount,
                accountType: accountType,
                bankName: accountType.usesBank ? bankName : "",
                cardLastFour: accountType.usesCard ? cardLastFour : "",
                category: .loan,
                date: date
            )
            context.insert(expense)
            expense.emi = self
            created.append(expense)
        }

        // Instalments are created in date order, so the earliest ones are the first to be marked paid.
        for expense in created.prefix(max(0, alreadyPaid)) {
            expense.paidAt = expense.date
        }
    }
}

// MARK: - One-time migration

extension EMI {
    static let paidStateMigrationKey = "emiPaidStateMigrated"

    /// Before payments were recorded, an instalment counted as paid once its date passed.
    /// Carries that status over once so existing history stays paid after the upgrade.
    static func migratePaidStateIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: paidStateMigrationKey) else { return }
        let now = Date.now
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.paidAt == nil && $0.date <= now })
        if let expenses = try? context.fetch(descriptor) {
            for expense in expenses where expense.emi != nil {
                expense.paidAt = expense.date
            }
        }
        UserDefaults.standard.set(true, forKey: paidStateMigrationKey)
    }
}
