//
//  Income.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

// MARK: - Income Source

enum IncomeSource: String, CaseIterable, Identifiable, Codable {
    case salary = "Salary"
    case bonus = "Bonus"
    case freelance = "Freelance"
    case interest = "Interest"
    case rental = "Rental"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .salary: "briefcase"
        case .bonus: "gift"
        case .freelance: "laptopcomputer"
        case .interest: "percent"
        case .rental: "house"
        case .other: "plus.circle"
        }
    }
}

// MARK: - Income Model

/// Money received (e.g. monthly salary), persisted on-device with SwiftData.
@Model
final class Income {
    @Attribute(originalName: "amount") private var legacyAmount: Double = 0
    var amountPaise: Int64 = 0
    var sourceRaw: String
    var note: String
    /// The bank account the money was credited to (optional).
    var bankName: String
    var date: Date

    init(
        amount: Decimal,
        source: IncomeSource,
        note: String = "",
        bankName: String = "",
        date: Date = .now
    ) {
        self.amountPaise = Money.paise(from: amount)
        self.sourceRaw = source.rawValue
        self.note = note
        self.bankName = bankName
        self.date = date
    }

    var source: IncomeSource {
        get { IncomeSource(rawValue: sourceRaw) ?? .other }
        set { sourceRaw = newValue.rawValue }
    }

    var amount: Decimal {
        get { amountPaise == 0 && legacyAmount != 0 ? Money.amount(fromLegacy: legacyAmount) : Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    func migrateLegacyMoney() {
        guard amountPaise == 0, legacyAmount != 0 else { return }
        amountPaise = Money.paise(from: Money.amount(fromLegacy: legacyAmount))
    }

    /// Title to display, falling back to the source name when no note was entered.
    var displayTitle: String {
        note.isEmpty ? source.rawValue : note
    }
}

extension Sequence where Element == Income {
    var totalAmount: Decimal { reduce(0) { $0 + $1.amount } }
}
