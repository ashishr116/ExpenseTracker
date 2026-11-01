//
//  AccountLedger.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// One entry's effect on an account.
struct LedgerLine: Identifiable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    /// The change to the account's figure: positive raises it. For a bank or cash account that is the
    /// balance. For a credit card it is the amount owed.
    let effect: Decimal
    /// Set for transfers and adjustments, so they can be removed if entered by mistake.
    let transfer: Transfer?
}

/// Works out each account's balance from the entries, and finds entries that belong to no account.
///
/// Rules:
/// - Spending lowers a bank or cash account, and raises what a credit card owes.
/// - Income raises the bank account it was credited to.
/// - Cash and transfer loans lower the account they were paid from, and repayments raise the account
///   they were received in. Loans on your card or in your name never touch a balance.
/// - Transfers lower one account and raise another. Paying a card bill lowers what the card owes.
/// - EMIs and premiums count only once paid, on the day they were paid.
/// - Entries before an account's opening date, or dated in the future, are left out.
struct AccountLedger {
    let accounts: [Account]
    let now: Date

    private struct Entry {
        let accountUID: String?
        let line: LedgerLine
    }

    private let entries: [Entry]
    /// Friends' purchases on your credit cards and what they have paid back. These never change a balance:
    /// they are what friends owe the card, shown beside "mine" so the card matches the bank's statement.
    private let lentEntries: [Entry]

    init(
        accounts: [Account],
        expenses: [Expense],
        incomes: [Income],
        loans: [Loan],
        repayments: [LoanRepayment],
        transfers: [Transfer],
        borrowings: [Borrowing] = [],
        borrowingPayments: [BorrowingPayment] = [],
        now: Date = .now
    ) {
        // Active accounts first, so an entry prefers an open account over a closed one.
        let ordered = accounts.sorted { !$0.isArchived && $1.isArchived }
        self.accounts = accounts
        self.now = now

        func sameBank(_ a: String, _ b: String) -> Bool { BankName.matches(a, b) }

        /// The credit card with this bank and these last four digits.
        func creditCard(bank: String, lastFour: String) -> Account? {
            let cards = ordered.filter { $0.kind == .creditCard && sameBank($0.bankName, bank) }
            return cards.first { $0.cardLastFour == String(lastFour.filter(\.isNumber).suffix(4)) }
        }

        func account(for expense: Expense) -> Account? {
            switch expense.accountType {
            case .cash:
                return ordered.first { $0.kind == .cash }
            case .creditCard:
                return creditCard(bank: expense.bankName, lastFour: expense.cardLastFour)
            case .debitCard, .upi:
                return ordered.first { $0.kind == .bank && sameBank($0.bankName, expense.bankName) }
            }
        }

        /// Where a cash or transfer loan's money came from or went to. No bank means cash.
        func account(forLoanBank bank: String) -> Account? {
            let trimmed = bank.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return ordered.first { $0.kind == .cash } }
            return ordered.first { $0.kind == .bank && sameBank($0.bankName, trimmed) }
        }

        var built: [Entry] = []

        // A card EMI or premium is on the card from its billing date, paid or not.
        for expense in expenses where !expense.isPlanned || expense.isBilledToCard {
            // Any other EMI or premium moves money on the day it was paid, not on its billing date.
            let isRecurring = expense.emi != nil || expense.insurancePolicy != nil
            let date = isRecurring && !expense.isBilledToCard ? (expense.paidAt ?? expense.date) : expense.date
            guard date <= now else { continue }
            let owner = account(for: expense)
            let amount = expense.amount
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "expense-\(expense.persistentModelID)",
                    date: date,
                    title: expense.displayTitle,
                    subtitle: expense.accountDescription,
                    effect: (owner?.kind.isLiability ?? false) ? amount : -amount,
                    transfer: nil
                )
            ))
        }

        for income in incomes where income.date <= now {
            let owner = ordered.first { $0.kind == .bank && sameBank($0.bankName, income.bankName) }
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "income-\(income.persistentModelID)",
                    date: income.date,
                    title: income.displayTitle,
                    subtitle: income.bankName.isEmpty ? "No bank chosen" : income.bankName,
                    effect: income.amount,
                    transfer: nil
                )
            ))
        }

        for loan in loans where loan.method == .cash && loan.date <= now {
            let owner = account(forLoanBank: loan.bankName)
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "loan-\(loan.persistentModelID)",
                    date: loan.date,
                    title: "Lent to \(loan.friendName)",
                    subtitle: loan.bankName.isEmpty ? "Cash" : loan.bankName,
                    effect: -loan.amount,
                    transfer: nil
                )
            ))
        }

        for repayment in repayments where repayment.isCashInflow && repayment.date <= now {
            let owner = account(forLoanBank: repayment.bankName)
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "repayment-\(repayment.persistentModelID)",
                    date: repayment.date,
                    title: "Repayment from \(repayment.loan?.friendName ?? "friend")",
                    subtitle: repayment.bankName.isEmpty ? "Cash" : repayment.bankName,
                    effect: repayment.amount,
                    transfer: nil
                )
            ))
        }

        // Money borrowed from a friend lands in an account, and paying it back takes it out again.
        for borrowing in borrowings where borrowing.date <= now {
            let owner = account(forLoanBank: borrowing.bankName)
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "borrowed-\(borrowing.persistentModelID)",
                    date: borrowing.date,
                    title: "Borrowed from \(borrowing.friendName)",
                    subtitle: borrowing.bankName.isEmpty ? "Cash" : borrowing.bankName,
                    effect: borrowing.amount,
                    transfer: nil
                )
            ))
        }

        for payment in borrowingPayments where payment.date <= now {
            let owner = account(forLoanBank: payment.bankName)
            built.append(Entry(
                accountUID: owner?.uid,
                line: LedgerLine(
                    id: "borrow-payment-\(payment.persistentModelID)",
                    date: payment.date,
                    title: "Repaid \(payment.borrowing?.friendName ?? "friend")",
                    subtitle: payment.bankName.isEmpty ? "Cash" : payment.bankName,
                    effect: -payment.amount,
                    transfer: nil
                )
            ))
        }

        for transfer in transfers where transfer.date <= now {
            let amount = transfer.amount
            let adjustment = transfer.isAdjustment
            if let from = transfer.fromAccount {
                built.append(Entry(
                    accountUID: from.uid,
                    line: LedgerLine(
                        id: "transfer-out-\(transfer.persistentModelID)",
                        date: transfer.date,
                        title: adjustment
                            ? (transfer.note.hasPrefix("Invested in ") ? "Invested" : "Adjustment")
                            : (transfer.toAccount?.kind.isLiability == true
                                ? "Paid \(transfer.toAccount?.displayName ?? "card") bill"
                                : "Transfer to \(transfer.toAccount?.displayName ?? "account")"),
                        subtitle: transfer.note,
                        effect: from.kind.isLiability ? amount : -amount,
                        transfer: transfer
                    )
                ))
            }
            if let to = transfer.toAccount {
                built.append(Entry(
                    accountUID: to.uid,
                    line: LedgerLine(
                        id: "transfer-in-\(transfer.persistentModelID)",
                        date: transfer.date,
                        title: adjustment
                            ? "Adjustment"
                            : (to.kind.isLiability
                                ? "Bill payment from \(transfer.fromAccount?.displayName ?? "account")"
                                : "Transfer from \(transfer.fromAccount?.displayName ?? "account")"),
                        subtitle: transfer.note,
                        effect: to.kind.isLiability ? -amount : amount,
                        transfer: transfer
                    )
                ))
            }
        }

        entries = built

        // Friends' card loans: what they spent on the card, less what they have paid back.
        var lent: [Entry] = []
        for loan in loans where loan.method == .card && loan.date <= now {
            guard let owner = creditCard(bank: loan.bankName, lastFour: loan.cardLastFour) else { continue }
            // A friend's EMI is billed one instalment a month, as on the card statement. Any other loan is billed whole.
            for charge in loan.cardCharges(upTo: now) {
                lent.append(Entry(
                    accountUID: owner.uid,
                    line: LedgerLine(
                        id: charge.id,
                        date: charge.date,
                        title: "Lent to \(loan.friendName)",
                        subtitle: charge.subtitle ?? (loan.note.isEmpty ? "Used your card" : loan.note),
                        effect: charge.amount,
                        transfer: nil
                    )
                ))
            }
        }
        for repayment in repayments where repayment.date <= now {
            guard let loan = repayment.loan, loan.method == .card,
                  let owner = creditCard(bank: loan.bankName, lastFour: loan.cardLastFour) else { continue }
            lent.append(Entry(
                accountUID: owner.uid,
                line: LedgerLine(
                    id: "card-repayment-\(repayment.persistentModelID)",
                    date: repayment.date,
                    title: "Repayment from \(loan.friendName)",
                    subtitle: repayment.note.isEmpty ? "Paid to the card" : repayment.note,
                    effect: -repayment.amount,
                    transfer: nil
                )
            ))
        }
        lentEntries = lent
    }

    // MARK: Results

    /// The entries that change this account, newest first. Only those on or after its opening day.
    func lines(for account: Account) -> [LedgerLine] {
        let start = Calendar.current.startOfDay(for: account.openingDate)
        return entries
            .filter { $0.accountUID == account.uid && $0.line.date >= start }
            .map(\.line)
            .sorted { $0.date > $1.date }
    }

    /// The opening balance plus every entry since. For a credit card this is the amount owed.
    func balance(of account: Account) -> Decimal {
        account.openingBalance + lines(for: account).reduce(0) { $0 + $1.effect }
    }

    /// Entries on or after the earliest opening day that match no account. These are why a balance
    /// can drift: fix the bank or card on the entry, or add the account.
    var unlinked: [LedgerLine] {
        guard let earliest = accounts.map(\.openingDate).min() else { return [] }
        let start = Calendar.current.startOfDay(for: earliest)
        return entries
            .filter { $0.accountUID == nil && $0.line.date >= start }
            .map(\.line)
            .sorted { $0.date > $1.date }
    }

    // MARK: Friends on a card

    /// Friends' purchases on this card and their repayments, newest first.
    func lentLines(for account: Account) -> [LedgerLine] {
        lentEntries
            .filter { $0.accountUID == account.uid }
            .map(\.line)
            .sorted { $0.date > $1.date }
    }

    /// What friends still owe the card. This is not your debt.
    func lentOutstanding(of account: Account) -> Decimal {
        lentEntries
            .filter { $0.accountUID == account.uid }
            .reduce(0) { $0 + $1.line.effect }
    }

    /// What friends still owe on all your credit cards.
    var lentTotal: Decimal {
        accounts.filter(\.kind.isLiability).reduce(0) { $0 + lentOutstanding(of: $1) }
    }

    /// Everything held in bank and cash accounts.
    var assetTotal: Decimal {
        accounts.filter { !$0.kind.isLiability }.reduce(0) { $0 + balance(of: $1) }
    }

    /// Everything owed on credit cards.
    var cardDuesTotal: Decimal {
        accounts.filter(\.kind.isLiability).reduce(0) { $0 + balance(of: $1) }
    }
}
