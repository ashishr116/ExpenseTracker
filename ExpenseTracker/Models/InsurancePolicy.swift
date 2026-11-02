//
//  InsurancePolicy.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

// MARK: - Policy Type

enum InsuranceType: String, CaseIterable, Identifiable, Codable {
    case health = "Health Insurance"
    case term = "Term Plan"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .health: "cross.case"
        case .term: "umbrella"
        }
    }

    /// Default premium frequency for a new policy of this type.
    var defaultFrequency: PremiumFrequency {
        switch self {
        case .health: .annually
        case .term: .monthly
        }
    }

    var coverLabel: String {
        switch self {
        case .health: "Sum Insured"
        case .term: "Cover Amount"
        }
    }

    var validityLabel: String {
        switch self {
        case .health: "Valid Till"
        case .term: "Covered Till"
        }
    }
}

// MARK: - Premium Frequency

enum PremiumFrequency: String, CaseIterable, Identifiable, Codable {
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    case halfYearly = "Half-Yearly"
    case annually = "Annually"

    var id: String { rawValue }

    /// Months between payments.
    var months: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .halfYearly: 6
        case .annually: 12
        }
    }

    /// Payments per year.
    var paymentsPerYear: Int { 12 / months }

    /// e.g. "/ month", "/ year"
    var perLabel: String {
        switch self {
        case .monthly: "/ month"
        case .quarterly: "/ quarter"
        case .halfYearly: "/ 6 months"
        case .annually: "/ year"
        }
    }
}

// MARK: - Policy Model

/// A health insurance or term plan.
///
/// When `addsToExpenses` is on, the policy owns one real `Expense` per premium (`premiumExpenses`),
/// dated on each debit date from `firstPremiumDate` to `endDate`, so premiums show up in the
/// Daily, Monthly and Budget Plan views automatically.
@Model
final class InsurancePolicy {
    var typeRaw: String
    var insurerName: String
    var planName: String
    var policyNumber: String
    /// Sum insured (health) or cover amount (term).
    @Attribute(originalName: "coverAmount") private var legacyCoverAmount: Double = 0
    var coverAmountPaise: Int64 = 0
    /// Premium paid each period.
    @Attribute(originalName: "premiumAmount") private var legacyPremiumAmount: Double = 0
    var premiumAmountPaise: Int64 = 0
    var frequencyRaw: String
    /// Policy start date.
    var startDate: Date
    /// Expiry / renewal date (health) or end of cover (term).
    var endDate: Date
    /// Nominee (term) or members covered (health).
    var nomineeOrMembers: String
    var note: String

    // Added later — defaults let existing policies migrate automatically.
    /// The first date the premium is debited; later debits repeat on the same day. Falls back to `startDate`.
    var firstPremiumDate: Date?
    /// Whether premiums are added to your expenses on each debit date.
    var addsToExpenses: Bool = true
    /// The account premiums are debited from.
    var accountTypeRaw: String = AccountType.upi.rawValue
    var bankName: String = ""
    var cardLastFour: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Expense.insurancePolicy)
    var premiumExpenses: [Expense] = []

    init(
        type: InsuranceType,
        insurerName: String,
        planName: String = "",
        policyNumber: String = "",
        coverAmount: Decimal = 0,
        premiumAmount: Decimal,
        frequency: PremiumFrequency,
        startDate: Date,
        endDate: Date,
        nomineeOrMembers: String = "",
        note: String = "",
        firstPremiumDate: Date? = nil,
        addsToExpenses: Bool = true,
        accountType: AccountType = .upi,
        bankName: String = "",
        cardLastFour: String = ""
    ) {
        self.typeRaw = type.rawValue
        self.insurerName = insurerName
        self.planName = planName
        self.policyNumber = policyNumber
        self.coverAmountPaise = Money.paise(from: coverAmount)
        self.premiumAmountPaise = Money.paise(from: premiumAmount)
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.nomineeOrMembers = nomineeOrMembers
        self.note = note
        self.firstPremiumDate = firstPremiumDate
        self.addsToExpenses = addsToExpenses
        self.accountTypeRaw = accountType.rawValue
        self.bankName = bankName
        self.cardLastFour = cardLastFour
    }

    var type: InsuranceType {
        get { InsuranceType(rawValue: typeRaw) ?? .health }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: PremiumFrequency {
        get { PremiumFrequency(rawValue: frequencyRaw) ?? .annually }
        set { frequencyRaw = newValue.rawValue }
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .upi }
        set { accountTypeRaw = newValue.rawValue }
    }

    var coverAmount: Decimal {
        get {
            coverAmountPaise == 0 && legacyCoverAmount != 0
                ? Money.amount(fromLegacy: legacyCoverAmount)
                : Money.amount(fromPaise: coverAmountPaise)
        }
        set { coverAmountPaise = Money.paise(from: newValue) }
    }

    var premiumAmount: Decimal {
        get {
            premiumAmountPaise == 0 && legacyPremiumAmount != 0
                ? Money.amount(fromLegacy: legacyPremiumAmount)
                : Money.amount(fromPaise: premiumAmountPaise)
        }
        set { premiumAmountPaise = Money.paise(from: newValue) }
    }

    func migrateLegacyMoney() {
        if coverAmountPaise == 0, legacyCoverAmount != 0 {
            coverAmountPaise = Money.paise(from: Money.amount(fromLegacy: legacyCoverAmount))
        }
        if premiumAmountPaise == 0, legacyPremiumAmount != 0 {
            premiumAmountPaise = Money.paise(from: Money.amount(fromLegacy: legacyPremiumAmount))
        }
    }

    /// Premium converted to a yearly figure (e.g. ₹1,200/month → ₹14,400/year).
    var annualPremium: Decimal {
        premiumAmount * Decimal(frequency.paymentsPerYear)
    }

    var isExpired: Bool { endDate < Calendar.current.startOfDay(for: .now) }

    /// Days until the policy expires (negative once expired).
    var daysUntilExpiry: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: endDate)
        ).day ?? 0
    }

    /// Every debit date from the first premium until the policy ends.
    var premiumDates: [Date] {
        InsurancePolicy.premiumDates(
            first: firstPremiumDate ?? startDate,
            frequency: frequency,
            endDate: endDate
        )
    }

    /// Premiums the user has recorded as paid. Paid status is never inferred from the calendar.
    var paidPremiums: [Expense] { premiumExpenses.filter { $0.paidAt != nil } }

    /// Premiums not yet recorded as paid, soonest first.
    var pendingPremiums: [Expense] {
        premiumExpenses.filter { $0.paidAt == nil }.sorted { $0.date < $1.date }
    }

    /// Pending premiums debited today. These trigger the due-date pop-up.
    func dueTodayPremiums(asOf now: Date = .now) -> [Expense] {
        pendingPremiums.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    /// Pending premiums whose debit date has passed. Shown as a badge in the insurance list.
    func overduePremiums(asOf now: Date = .now) -> [Expense] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        return pendingPremiums.filter { $0.date < startOfToday }
    }

    /// Records a premium as paid. Existing history is never rewritten by later edits.
    func markPaid(_ premium: Expense, on date: Date = .now) {
        premium.paidAt = date
    }

    /// The next unpaid debit date (overdue ones included); `nil` once everything is paid or the policy has ended.
    /// Falls back to the schedule when premiums aren't being added to expenses.
    var nextPremiumDate: Date? {
        if addsToExpenses, !premiumExpenses.isEmpty {
            return pendingPremiums.first?.date
        }
        let today = Calendar.current.startOfDay(for: .now)
        return premiumDates.first { $0 >= today }
    }

    /// e.g. "Star Health · Family Health Optima"
    var title: String {
        planName.isEmpty ? insurerName : "\(insurerName) · \(planName)"
    }

    /// Debit dates stepping from `first` by the frequency, up to and including `endDate`.
    /// Each date is computed from `first` so a 31st falls on the last day of shorter months.
    static func premiumDates(first: Date, frequency: PremiumFrequency, endDate: Date) -> [Date] {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: endDate)
        var dates: [Date] = []
        var step = 0
        // Cap at 100 years of monthly payments as a safety net against bad input.
        while step < 1200,
              let date = calendar.date(byAdding: .month, value: frequency.months * step, to: first),
              calendar.startOfDay(for: date) <= lastDay {
            dates.append(date)
            step += 1
        }
        return dates
    }

    /// Rebuilds the *pending* premium expenses from the current schedule. Call after creating or editing the policy.
    ///
    /// Premiums already recorded as paid are real financial history and are left untouched.
    /// A scheduled date that already has a paid premium nearby is not generated again.
    ///
    /// - Parameter markingFirstPaid: How many of the newly created premiums, earliest first, to record as
    ///   already paid on their debit date. Use it when adding a policy that started in the past.
    func regeneratePremiumExpenses(in context: ModelContext, markingFirstPaid alreadyPaid: Int = 0) {
        let paid = paidPremiums
        let step = max(frequency.months, 1)
        var created: [Expense] = []

        for expense in premiumExpenses where expense.paidAt == nil {
            context.delete(expense)
        }
        premiumExpenses.removeAll { $0.paidAt == nil }

        guard addsToExpenses else { return }

        for date in premiumDates {
            // Skip a period that was already paid: a paid premium within half a billing period of this date.
            let halfPeriod = TimeInterval(step) * 15 * 86_400
            if paid.contains(where: { abs($0.date.timeIntervalSince(date)) < halfPeriod }) {
                continue
            }
            let expense = Expense(
                title: "\(insurerName) Premium",
                amount: premiumAmount,
                accountType: accountType,
                bankName: accountType.usesBank ? bankName : "",
                cardLastFour: accountType.usesCard ? cardLastFour : "",
                category: .insurance,
                date: date
            )
            context.insert(expense)
            expense.insurancePolicy = self
            created.append(expense)
        }

        // Premiums are created in date order, so the earliest ones are the first to be marked paid.
        for expense in created.prefix(max(0, alreadyPaid)) {
            expense.paidAt = expense.date
        }
    }

    /// Deletes the policy along with all of its premium expenses.
    /// Premiums that stay when the policy is deleted: those marked paid, and those already billed to a credit
    /// card, which the card owes whether marked paid or not. They are money that has really moved.
    func premiumsKeptOnDelete(now: Date = .now) -> [Expense] {
        premiumExpenses.filter { $0.paidAt != nil || ($0.isBilledToCard && $0.date <= now) }
    }

    /// Deletes the policy and its future premiums. Premiums already paid or billed stay as ordinary past
    /// expenses, so account balances and past months don't change.
    func delete(from context: ModelContext, now: Date = .now) {
        let kept = premiumsKeptOnDelete(now: now)
        for expense in premiumExpenses where !kept.contains(where: { $0 === expense }) {
            context.delete(expense)
        }
        for expense in kept {
            if expense.paidAt == nil { expense.paidAt = expense.date }
            expense.insurancePolicy = nil
        }
        premiumExpenses.removeAll()
        context.delete(self)
    }
}

// MARK: - One-time migration

extension InsurancePolicy {
    static let paidStateMigrationKey = "insurancePaidStateMigrated"

    /// Before payments were recorded, a premium counted as paid once its date passed.
    /// Carries that status over once so existing history stays paid after the upgrade.
    static func migratePaidStateIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: paidStateMigrationKey) else { return }
        let now = Date.now
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.paidAt == nil && $0.date <= now })
        if let expenses = try? context.fetch(descriptor) {
            for expense in expenses where expense.insurancePolicy != nil {
                expense.paidAt = expense.date
            }
        }
        UserDefaults.standard.set(true, forKey: paidStateMigrationKey)
    }
}
