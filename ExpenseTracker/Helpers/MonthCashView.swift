//
//  MonthCashView.swift
//  ExpenseTracker
//

import Foundation

/// How a month looks in terms of cash that actually left your hands, as against spending on credit cards.
///
/// Spending is still recorded when you buy, so categories, limits and the recap stay right. This is an extra
/// view on top: a credit card purchase doesn't take money out of your bank until you pay the card bill, so it is
/// kept apart from cash. Paying the bill is what lowers cash.
///
/// - Cash left: income, minus spending in cash, UPI and on a debit card, minus card bills paid this month, minus
///   cash lent to friends, plus cash loans repaid.
/// - The bills paid this month may be for purchases made in earlier months. That is the real cash that left.
struct MonthCashView {
    /// One credit card's spending for the month.
    struct CardTotal: Identifiable {
        let id: String
        let name: String
        let total: Decimal
        let expenses: [Expense]
    }

    /// Spent on credit cards this month. Not yet taken from cash.
    let cardSpent: Decimal
    /// Spent in cash, by UPI or on a debit card this month.
    let cashSpent: Decimal
    /// Card bills paid from your accounts this month.
    let billsPaid: Decimal
    /// What you actually have left from this month's income.
    let cashLeft: Decimal
    /// Credit card spending, card by card, biggest first.
    let cards: [CardTotal]

    /// Whether credit cards played any part this month. When they didn't, the extra lines aren't shown.
    var hasCardActivity: Bool { cardSpent > 0 || billsPaid > 0 }

    /// - Parameters:
    ///   - expenses: The month's expenses. EMIs and premiums not yet paid are left out here, except those on a credit card whose billing date has come.
    ///   - cardPayments: The month's transfers. Only card bill payments are counted.
    init(
        income: Decimal,
        expenses: [Expense],
        cardPayments: [Transfer],
        cashLent: Decimal,
        cashRepaid: Decimal,
        borrowed: Decimal = 0,
        paidBack: Decimal = 0,
        now: Date = .now
    ) {
        let paid = expenses.filter { !$0.isPlanned }
        // An EMI or premium on a credit card is on the card from its billing date, marked paid or not,
        // as in the card's balance. It doesn't change cash, which only moves when the bill is paid.
        let onCards = expenses.filter {
            $0.accountType == .creditCard && (!$0.isPlanned || ($0.isBilledToCard && $0.date <= now))
        }

        cardSpent = onCards.totalAmount
        cashSpent = paid.filter { $0.accountType != .creditCard }.totalAmount
        billsPaid = cardPayments.filter(\.isCardBillPayment).reduce(Decimal(0)) { $0 + $1.amount }
        cashLeft = income - cashSpent - billsPaid - cashLent + cashRepaid + borrowed - paidBack

        cards = Dictionary(grouping: onCards) { "\($0.bankName)|\($0.cardLastFour)" }
            .map { key, items in
                let first = items[0]
                var parts: [String] = []
                if !first.bankName.isEmpty { parts.append(first.bankName) }
                if !first.cardLastFour.isEmpty { parts.append("•••• \(first.cardLastFour)") }
                return CardTotal(
                    id: key,
                    name: parts.isEmpty ? "Credit Card" : parts.joined(separator: " · "),
                    total: items.totalAmount,
                    expenses: items.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.total > $1.total }
    }
}
