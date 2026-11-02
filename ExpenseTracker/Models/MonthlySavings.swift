//
//  MonthlySavings.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// What was left over at the end of one month and how much of it was added to the savings account.
///
/// One record exists per month. It is a snapshot taken when the month ended, so the same month is
/// never added twice. If entries for that month change later, `SavingsSweep.refresh` applies the difference.
@Model
final class MonthlySavings {
    /// First day of the month this record is for.
    var month: Date = Date.now
    /// Income minus spending, pending EMIs and premiums, and loans for the month. Negative when overspent.
    var leftoverPaise: Int64 = 0
    /// The part of the leftover added to the savings balance. Never negative.
    var appliedPaise: Int64 = 0
    /// The savings account it was added to, matching the bank name in Net Worth.
    var bankName: String = ""
    var createdAt: Date = Date.now
    /// The transfer that moved the leftover between accounts, when accounts are set up.
    var transfer: Transfer?

    init(month: Date, leftover: Decimal, applied: Decimal, bankName: String) {
        self.month = month
        self.leftoverPaise = Money.paise(from: leftover)
        self.appliedPaise = Money.paise(from: applied)
        self.bankName = bankName
    }

    var leftover: Decimal {
        get { Money.amount(fromPaise: leftoverPaise) }
        set { leftoverPaise = Money.paise(from: newValue) }
    }

    var applied: Decimal {
        get { Money.amount(fromPaise: appliedPaise) }
        set { appliedPaise = Money.paise(from: newValue) }
    }
}

/// Moves each finished month's leftover into a savings account in Net Worth.
enum SavingsSweep {
    static let enabledKey = "savingsSweepEnabled"
    static let bankKey = "savingsSweepBank"
    static let startKey = "savingsSweepStart"
    /// The account the leftover is moved out of, and the savings account it goes into.
    /// Used once accounts exist; the values are `Account.uid`.
    static let fromAccountKey = "savingsSweepFromAccount"
    static let toAccountKey = "savingsSweepToAccount"

    /// Safety net so a bad start date can't loop for decades.
    private static let maximumMonths = 120

    // MARK: Accounts

    /// Whether any account has been set up. If so, the leftover moves between accounts as a transfer.
    static func accountsExist(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) > 0
    }

    /// The chosen source and savings accounts, if both are set and still exist.
    static func configuredAccounts(in context: ModelContext) -> (from: Account, to: Account)? {
        let defaults = UserDefaults.standard
        let fromUID = defaults.string(forKey: fromAccountKey) ?? ""
        let toUID = defaults.string(forKey: toAccountKey) ?? ""
        guard !fromUID.isEmpty, !toUID.isEmpty, fromUID != toUID else { return nil }
        let all = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let from = all.first(where: { $0.uid == fromUID }),
              let to = all.first(where: { $0.uid == toUID }) else { return nil }
        return (from, to)
    }

    /// Records the move as a transfer dated on the last day of the month.
    private static func makeTransfer(
        amount: Decimal,
        month: Date,
        accounts: (from: Account, to: Account),
        in context: ModelContext
    ) -> Transfer {
        let calendar = Calendar.current
        let nextMonth = calendar.monthRange(containing: month).upperBound
        let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? month
        let date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: lastDay) ?? lastDay
        let transfer = Transfer(amount: amount, date: date, note: "Month-end savings")
        context.insert(transfer)
        transfer.fromAccount = accounts.from
        transfer.toAccount = accounts.to
        return transfer
    }

    // MARK: Savings account

    /// The savings holding for a bank, matched by the bank name entered in Net Worth.
    static func savingsHolding(for bank: String, in context: ModelContext, createIfMissing: Bool) -> Holding? {
        let savingsKind = HoldingKind.savings.rawValue
        let descriptor = FetchDescriptor<Holding>(predicate: #Predicate { $0.kindRaw == savingsKind })
        let holdings = (try? context.fetch(descriptor)) ?? []
        let trimmed = bank.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = holdings.first(where: { $0.platform.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        guard createIfMissing, !trimmed.isEmpty else { return nil }
        let holding = Holding(name: "\(trimmed) Savings", kind: .savings, platform: trimmed, currentValue: 0)
        context.insert(holding)
        return holding
    }

    // MARK: Leftover

    /// The cash really left from a month, the same figure as Cash Left in Monthly and Budget.
    ///
    /// Credit card purchases count when the card bill is paid, not when you buy, because that is when the money
    /// leaves your bank. So it is income, minus spending in cash, UPI and debit card, minus card bills paid,
    /// minus cash lent, plus cash loans repaid (and card shares friends paid you), plus money borrowed, minus
    /// payments back to friends, minus money put into investments (plus any taken out).
    static func leftover(for month: Date, in context: ModelContext) -> Decimal {
        let range = Calendar.current.monthRange(containing: month)
        let start = range.lowerBound
        let end = range.upperBound

        let incomes = (try? context.fetch(FetchDescriptor<Income>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let lent = (try? context.fetch(FetchDescriptor<Loan>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let repayments = (try? context.fetch(FetchDescriptor<LoanRepayment>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let borrowed = ((try? context.fetch(FetchDescriptor<Borrowing>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []).reduce(Decimal(0)) { $0 + $1.amount }
        let paidBack = ((try? context.fetch(FetchDescriptor<BorrowingPayment>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []).totalAmount
        let transfers = (try? context.fetch(FetchDescriptor<Transfer>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []

        return MonthCashView(
            income: incomes.totalAmount,
            expenses: expenses,
            cardPayments: transfers,
            cashLent: lent.filter { $0.method == .cash }.totalAmount,
            cashRepaid: repayments.filter { $0.isCashInflow || $0.isCardShareReceived }.totalAmount,
            borrowed: borrowed,
            paidBack: paidBack,
            now: end
        ).cashLeft
    }

    // MARK: Sweeping

    /// Adds the leftover of every finished month since the start month that hasn't been added yet.
    /// Safe to run on every launch. The current month is never touched until it ends.
    @MainActor
    static func run(in context: ModelContext, now: Date = .now) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return }
        let bank = (defaults.string(forKey: bankKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let startInterval = defaults.double(forKey: startKey)
        guard startInterval > 0 else { return }

        // With accounts, the leftover moves between two of them. Wait until both are chosen.
        let usesAccounts = accountsExist(in: context)
        let pair = configuredAccounts(in: context)
        if usesAccounts {
            guard pair != nil else { return }
        } else {
            guard !bank.isEmpty else { return }
        }

        let calendar = Calendar.current
        let currentMonth = calendar.monthRange(containing: now).lowerBound
        var month = calendar.monthRange(containing: Date(timeIntervalSince1970: startInterval)).lowerBound
        let existing = ((try? context.fetch(FetchDescriptor<MonthlySavings>())) ?? []).map(\.month)

        var processed = 0
        while month < currentMonth, processed < maximumMonths {
            let alreadyDone = existing.contains { calendar.isDate($0, equalTo: month, toGranularity: .month) }
            if !alreadyDone {
                sweep(month: month, into: bank, accounts: pair, in: context)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
            processed += 1
        }
        try? context.save()
    }

    private static func sweep(
        month: Date,
        into bank: String,
        accounts pair: (from: Account, to: Account)?,
        in context: ModelContext
    ) {
        let leftover = leftover(for: month, in: context)
        let record = MonthlySavings(month: month, leftover: leftover, applied: 0, bankName: pair?.to.storedName ?? bank)
        context.insert(record)
        guard leftover > 0 else { return }

        if let pair {
            // Real accounts: a transfer lowers the source and raises the savings account.
            record.transfer = makeTransfer(amount: leftover, month: month, accounts: pair, in: context)
            record.applied = leftover
        } else if let holding = savingsHolding(for: bank, in: context, createIfMissing: true) {
            holding.currentValue += leftover
            holding.updatedAt = .now
            record.applied = leftover
        }
    }

    /// Recalculates a finished month and applies only the difference to the savings balance.
    /// Use after adding or changing entries for a month that has already been swept.
    static func refresh(_ record: MonthlySavings, in context: ModelContext) {
        let leftover = leftover(for: record.month, in: context)
        let applied = max(0, leftover)

        if accountsExist(in: context) {
            if let transfer = record.transfer {
                if applied == 0 {
                    context.delete(transfer)
                    record.transfer = nil
                } else {
                    transfer.amount = applied
                }
            } else if applied > 0 {
                guard let pair = configuredAccounts(in: context) else { return }
                record.transfer = makeTransfer(amount: applied, month: record.month, accounts: pair, in: context)
            }
        } else {
            let difference = applied - record.applied
            if difference != 0,
               let holding = savingsHolding(for: record.bankName, in: context, createIfMissing: difference > 0) {
                holding.currentValue = max(0, holding.currentValue + difference)
                holding.updatedAt = .now
            }
        }
        record.leftover = leftover
        record.applied = applied
        try? context.save()
    }
}
