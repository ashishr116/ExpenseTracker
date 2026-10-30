//
//  Formatting.swift
//  ExpenseTracker
//

import Foundation

enum Money {
    private static let paisePerRupee = Decimal(100)

    static func amount(fromPaise paise: Int64) -> Decimal {
        Decimal(paise) / paisePerRupee
    }

    static func paise(from amount: Decimal) -> Int64 {
        let scaledAmount = amount * paisePerRupee
        let roundedAmount = NSDecimalNumber(decimal: scaledAmount)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: true,
                raiseOnUnderflow: true,
                raiseOnDivideByZero: true
            ))
        return roundedAmount.int64Value
    }

    static func amount(fromLegacy value: Double) -> Decimal {
        Decimal(string: String(value)) ?? 0
    }
}

extension FormatStyle where Self == Decimal.FormatStyle.Currency {
    /// Indian Rupee currency format, e.g. "₹30,000.00".
    static var rupees: Self { .currency(code: "INR") }
}

extension Date {
    /// "2026-10-30" in the device's own time zone, for file names.
    var fileNameStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}

extension Calendar {
    /// The half-open range covering the whole day that contains `date`.
    func dayRange(containing date: Date) -> Range<Date> {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 1, to: start) ?? start
        return start..<end
    }

    /// The half-open range covering the whole month that contains `date`.
    func monthRange(containing date: Date) -> Range<Date> {
        guard let interval = dateInterval(of: .month, for: date) else {
            return dayRange(containing: date)
        }
        return interval.start..<interval.end
    }
}

extension Sequence where Element == Expense {
    /// Everything, including EMIs and premiums not yet paid.
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }

    /// Money actually spent: excludes EMIs and premiums not yet recorded as paid.
    var spentAmount: Decimal { reduce(0) { $0 + ($1.isPlanned ? 0 : $1.amount) } }

    /// EMIs and premiums still to be paid.
    var plannedAmount: Decimal { reduce(0) { $0 + ($1.isPlanned ? $1.amount : 0) } }
}
