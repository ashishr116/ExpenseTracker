//
//  Borrowing.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Money you borrowed from a friend, the mirror of a `Loan`. It lands in one of your accounts, and you pay it
/// back in one or more parts, each a `BorrowingPayment`. It is a debt, not income.
@Model
final class Borrowing {
    var amountPaise: Int64 = 0
    var friendName: String = ""
    var friendPhone: String = ""
    var note: String = ""
    /// The day the money reached you.
    var date: Date = Date.now
    /// The bank account it landed in. Empty means cash.
    var bankName: String = ""
    /// When you promised to pay it back, if you did. A reminder comes before it.
    var dueDate: Date?
    /// The day the last payment cleared the debt; `nil` while any amount is still owed.
    var repaidDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \BorrowingPayment.borrowing)
    var payments: [BorrowingPayment] = []

    init(
        amount: Decimal,
        friendName: String,
        friendPhone: String = "",
        note: String = "",
        date: Date = .now,
        bankName: String = "",
        dueDate: Date? = nil
    ) {
        self.amountPaise = Money.paise(from: amount)
        self.friendName = friendName
        self.friendPhone = friendPhone
        self.note = note
        self.date = date
        self.bankName = bankName
        self.dueDate = dueDate
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    var isRepaid: Bool { repaidDate != nil }

    /// What you have paid back so far.
    var paidAmount: Decimal { payments.totalAmount }

    /// What you still owe.
    var outstandingAmount: Decimal { max(0, amount - paidAmount) }

    /// Past its due date and not yet paid back.
    var isOverdue: Bool {
        guard let dueDate, !isRepaid else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now)
    }

    /// Payments made, newest first.
    var sortedPayments: [BorrowingPayment] { payments.sorted { $0.date > $1.date } }

    /// Sets `repaidDate` from the payments: the date of the last one once nothing is owed, otherwise `nil`.
    func syncRepaidState() {
        if payments.isEmpty || outstandingAmount > 0 {
            repaidDate = nil
        } else {
            repaidDate = payments.map(\.date).max()
        }
    }

    /// Records a payment to the friend. The amount is capped at what is still owed.
    @discardableResult
    func recordPayment(
        _ paid: Decimal,
        on date: Date = .now,
        note: String = "",
        bankName paidFrom: String = "",
        in context: ModelContext
    ) -> BorrowingPayment? {
        let amount = min(paid, outstandingAmount)
        guard amount > 0 else { return nil }
        let payment = BorrowingPayment(amount: amount, date: date, note: note, bankName: paidFrom)
        context.insert(payment)
        payments.append(payment)
        syncRepaidState()
        return payment
    }

    /// Removes a payment entered by mistake. The debt becomes outstanding again.
    func removePayment(_ payment: BorrowingPayment, in context: ModelContext) {
        payments.removeAll { $0 === payment }
        context.delete(payment)
        syncRepaidState()
    }
}

/// One payment you made towards money borrowed from a friend.
@Model
final class BorrowingPayment {
    var amountPaise: Int64 = 0
    var date: Date = Date.now
    var note: String = ""
    /// The bank account it was paid from. Empty means cash.
    var bankName: String = ""
    var borrowing: Borrowing?

    init(amount: Decimal, date: Date = .now, note: String = "", bankName: String = "") {
        self.amountPaise = Money.paise(from: amount)
        self.date = date
        self.note = note
        self.bankName = bankName
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    /// The payment's details as plain values, so a message can be built without holding the model.
    struct Snapshot {
        let date: Date
        let amount: Decimal
        let bankName: String
    }

    var snapshot: Snapshot { Snapshot(date: date, amount: amount, bankName: bankName) }
}

extension Sequence where Element == BorrowingPayment {
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }
}

extension Sequence where Element == Borrowing {
    /// What you still owe friends after any payments.
    var outstandingTotal: Decimal { reduce(0) { $0 + $1.outstandingAmount } }
}
