//
//  BorrowingEventRow.swift
//  ExpenseTracker
//

import SwiftUI

/// One line for money borrowed from a friend, or a payment back to one, in the day and month lists.
struct BorrowingEventRow: View {
    let title: String
    let subtitle: String
    let amount: Decimal
    /// Money coming in (borrowed) rather than going out (paid back).
    let isIncoming: Bool

    init(borrowing: Borrowing) {
        title = "Borrowed from \(borrowing.friendName)"
        subtitle = borrowing.bankName.isEmpty ? "Cash" : BankName.display(borrowing.bankName)
        amount = borrowing.amount
        isIncoming = true
    }

    init(payment: BorrowingPayment) {
        title = "Repaid \(payment.borrowing?.friendName ?? "friend")"
        subtitle = payment.bankName.isEmpty ? "Cash" : BankName.display(payment.bankName)
        amount = payment.amount
        isIncoming = false
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.title3)
                .foregroundStyle(isIncoming ? Color.green : Color.orange)
                .frame(width: 36, height: 36)
                .background((isIncoming ? Color.green : Color.orange).opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(isIncoming ? "+" : "−")\(amount.formatted(.rupees))")
                .fontWeight(.semibold)
                .foregroundStyle(isIncoming ? Color.green : Color.orange)
        }
    }
}
