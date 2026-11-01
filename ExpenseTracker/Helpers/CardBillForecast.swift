//
//  CardBillForecast.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// A credit card bill that will leave your account in some month, for the cash forecast.
struct ForecastCardBill: Identifiable {
    let id: String
    let cardName: String
    let dueDate: Date
    /// Your own part of the bill. Friends' shares are left out: you pay the bank first, but expect that back.
    let amount: Decimal
    /// True when the bill isn't generated yet, so this is only what has been spent so far.
    let isSoFar: Bool
}

/// Works out which credit card bills fall due in a month, so Budget and Monthly can show what will leave your cash.
///
/// A card needs its bill day to be forecast. The bill already generated is due on its due date. What has been
/// spent since is billed on the next bill day, and is due after that. Anything bought later isn't known yet.
enum CardBillForecast {
    /// The card bills due in the month containing `month`, your own part only.
    ///
    /// A bill whose due date has already passed but is still unpaid counts in the current month.
    @MainActor
    static func dues(in month: Date, context: ModelContext, now: Date = .now) -> [ForecastCardBill] {
        let calendar = Calendar.current
        let range = calendar.monthRange(containing: month)
        let currentRange = calendar.monthRange(containing: now)
        let today = calendar.startOfDay(for: now)

        let accounts = ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { $0.kind == .creditCard && !$0.isArchived }
        guard !accounts.isEmpty else { return [] }
        let cards = (try? context.fetch(FetchDescriptor<PaymentCard>())) ?? []
        let ledger = AccountLedger(
            accounts: (try? context.fetch(FetchDescriptor<Account>())) ?? [],
            expenses: (try? context.fetch(FetchDescriptor<Expense>())) ?? [],
            incomes: (try? context.fetch(FetchDescriptor<Income>())) ?? [],
            loans: (try? context.fetch(FetchDescriptor<Loan>())) ?? [],
            repayments: (try? context.fetch(FetchDescriptor<LoanRepayment>())) ?? [],
            transfers: (try? context.fetch(FetchDescriptor<Transfer>())) ?? [],
            borrowings: (try? context.fetch(FetchDescriptor<Borrowing>())) ?? [],
            borrowingPayments: (try? context.fetch(FetchDescriptor<BorrowingPayment>())) ?? [],
            now: now
        )

        var result: [ForecastCardBill] = []
        for account in accounts {
            guard let card = cards.first(where: { $0.accountUID == account.uid }), card.hasBillingCycle,
                  // Only your own part: no friends' purchases, and what you owe excludes what they owe.
                  let statement = CardBill.statement(
                    for: card, lines: ledger.lines(for: account), lentLines: [], owed: ledger.balance(of: account),
                    openingUnbilled: account.openingUnbilled, openingDate: account.openingDate, now: now
                  ) else { continue }

            // The bill already generated. Unpaid and overdue means it is still to be paid this month.
            if statement.billed > 0, let due = statement.dueDate {
                let counted = due < today ? today : due
                if counted >= range.lowerBound, counted < range.upperBound,
                   // An overdue bill only belongs to the current month.
                   due >= today || range == currentRange {
                    result.append(ForecastCardBill(
                        id: "\(account.uid)-billed", cardName: account.displayName, dueDate: counted,
                        amount: statement.billed, isSoFar: false
                    ))
                }
            }

            // What has been spent since, billed on the next bill day.
            if statement.unbilled > 0, let nextBill = statement.nextBillDate,
               let due = card.dueDate(forStatementOn: nextBill),
               due >= range.lowerBound, due < range.upperBound {
                result.append(ForecastCardBill(
                    id: "\(account.uid)-next", cardName: account.displayName, dueDate: due,
                    amount: statement.unbilled, isSoFar: true
                ))
            }
        }
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    /// Cards that have a bill day, as "BANK|1234", so their EMIs and premiums can be told apart from the rest.
    @MainActor
    static func cardKeysWithBillDay(context: ModelContext) -> Set<String> {
        let cards = (try? context.fetch(FetchDescriptor<PaymentCard>())) ?? []
        return Set(cards.filter { $0.hasBillingCycle && !$0.accountUID.isEmpty }.map { key(bank: $0.bankName, lastFour: $0.cardLastFour) })
    }

    static func key(bank: String, lastFour: String) -> String {
        BankName.normalized(bank) + "|" + String(lastFour.filter(\.isNumber).suffix(4))
    }

    /// EMIs and premiums still to be paid, leaving out those already on a credit card that has a bill day.
    /// An instalment that has reached the card is in that card's bill, so counting it here too would count it twice.
    static func pendingAmount(of expenses: [Expense], cardKeys: Set<String>, now: Date = .now) -> Decimal {
        expenses.reduce(Decimal(0)) { total, expense in
            guard expense.isPlanned else { return total }
            let isOnCardBill = expense.isBilledToCard && expense.date <= now
                && cardKeys.contains(key(bank: expense.bankName, lastFour: expense.cardLastFour))
            return isOnCardBill ? total : total + expense.amount
        }
    }
}
