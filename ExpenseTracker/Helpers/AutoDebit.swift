//
//  AutoDebit.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Records EMIs and premiums the bank takes on its own as paid on their date, so the bank balance drops when the
/// money really leaves, even if you never tick them.
///
/// Only plans paid by debit card or UPI with auto-debit on are touched. Each plan remembers how far it has been
/// checked, so a payment you mark as "didn't go through" is never marked paid again.
enum AutoDebit {
    @MainActor
    static func run(in context: ModelContext, now: Date = .now) {
        let emis = (try? context.fetch(FetchDescriptor<EMI>())) ?? []
        let policies = (try? context.fetch(FetchDescriptor<InsurancePolicy>())) ?? []
        var changed = false
        for emi in emis where emi.isAutoDebited {
            changed = mark(emi.installments, through: &emi.autoDebitThrough, now: now) || changed
        }
        for policy in policies where policy.isAutoDebited {
            changed = mark(policy.premiumExpenses, through: &policy.autoDebitThrough, now: now) || changed
        }
        if changed { try? context.save() }
    }

    /// The point to start from when auto-debit is first turned on: the start of today, so today's payment
    /// counts but earlier ones keep whatever you recorded.
    static func startingPoint(now: Date = .now) -> Date {
        Calendar.current.startOfDay(for: now).addingTimeInterval(-1)
    }

    /// Marks unpaid payments dated after `through` and up to now as paid on their date. Returns whether any changed.
    private static func mark(_ payments: [Expense], through: inout Date?, now: Date) -> Bool {
        // A plan seen for the first time starts from today, leaving its past as recorded.
        guard let start = through else {
            through = startingPoint(now: now)
            return mark(payments, through: &through, now: now)
        }
        var changed = false
        for payment in payments where payment.paidAt == nil && payment.date > start && payment.date <= now {
            payment.paidAt = payment.date
            changed = true
        }
        through = now
        return changed
    }

    /// The latest payment the bank took on its own, which can be undone if it didn't go through.
    static func lastAutoPaid(in payments: [Expense]) -> Expense? {
        payments
            .filter { $0.paidAt != nil && $0.paidAt == $0.date }
            .max { $0.date < $1.date }
    }
}
