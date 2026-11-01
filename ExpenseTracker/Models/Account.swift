//
//  Account.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// The kind of place money sits in.
enum AccountKind: String, CaseIterable, Identifiable, Codable {
    case bank = "Bank Account"
    case cash = "Cash"
    case creditCard = "Credit Card"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .bank: "building.columns"
        case .cash: "banknote"
        case .creditCard: "creditcard.fill"
        }
    }

    /// A credit card is money you owe. Its balance is the amount owed, and spending raises it.
    var isLiability: Bool { self == .creditCard }

    /// "Balance" for money you hold, "Owed" for a credit card.
    var balanceLabel: String { isLiability ? "Owed" : "Balance" }
}

/// A bank account, cash wallet or credit card with a running balance.
///
/// The balance is the opening balance plus every entry dated on or after the opening date:
/// income, spending, loans, and transfers. Entries find their account by bank name, card digits and
/// payment type, so existing entries keep working without being edited.
@Model
final class Account {
    /// Stable identifier, used to remember an account in settings.
    var uid: String = UUID().uuidString
    var name: String = ""
    var kindRaw: String = AccountKind.bank.rawValue
    /// Matches the bank name on expenses, income and loans (e.g. "HDFC Bank").
    var bankName: String = ""
    /// For a credit card: the last four digits, matching the card on expenses.
    var cardLastFour: String = ""
    /// What the account held on `openingDate`. For a credit card, what was owed.
    var openingBalancePaise: Int64 = 0
    /// For a credit card: the part of the opening amount owed that was spent since the last bill, so it is not
    /// on a bill yet. The rest of the opening amount is on a bill already. 0 means all of it is billed.
    var openingUnbilledPaise: Int64 = 0
    /// Entries before this day are ignored; the opening balance already includes them.
    var openingDate: Date = Date.now
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    init(
        name: String,
        kind: AccountKind,
        bankName: String = "",
        cardLastFour: String = "",
        openingBalance: Decimal = 0,
        openingDate: Date = .now
    ) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.bankName = BankName.normalized(bankName)
        self.cardLastFour = String(cardLastFour.filter(\.isNumber).suffix(4))
        self.openingBalancePaise = Money.paise(from: openingBalance)
        self.openingDate = openingDate
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .bank }
        set { kindRaw = newValue.rawValue }
    }

    var openingBalance: Decimal {
        get { Money.amount(fromPaise: openingBalancePaise) }
        set { openingBalancePaise = Money.paise(from: newValue) }
    }

    var openingUnbilled: Decimal {
        get { Money.amount(fromPaise: openingUnbilledPaise) }
        set { openingUnbilledPaise = Money.paise(from: newValue) }
    }

    var displayName: String { label(bank: BankName.display(bankName)) }

    /// The name with the bank as stored (capitals). For saving or matching, never for display.
    var storedName: String { label(bank: bankName) }

    private func label(bank: String) -> String {
        if !name.isEmpty { return name }
        switch kind {
        case .cash: return "Cash"
        case .bank: return bank.isEmpty ? "Bank Account" : bank
        case .creditCard: return bank.isEmpty ? "Credit Card" : "\(bank) Card"
        }
    }

    /// e.g. "HDFC Bank · •••• 1234"
    var detail: String {
        var parts: [String] = []
        if !bankName.isEmpty { parts.append(BankName.display(bankName)) }
        if !cardLastFour.isEmpty { parts.append("•••• \(cardLastFour)") }
        return parts.joined(separator: " · ")
    }
}

/// Money moved between two of your accounts, such as paying a card bill or topping up savings.
/// A transfer is not income or spending.
///
/// With only one side set it is an adjustment: money that appeared or disappeared outside the app,
/// used to bring a balance in line with the real one.
@Model
final class Transfer {
    var amountPaise: Int64 = 0
    var date: Date = Date.now
    var note: String = ""
    var fromAccount: Account?
    var toAccount: Account?

    init(amount: Decimal, date: Date = .now, note: String = "") {
        self.amountPaise = Money.paise(from: amount)
        self.date = date
        self.note = note
    }

    var amount: Decimal {
        get { Money.amount(fromPaise: amountPaise) }
        set { amountPaise = Money.paise(from: newValue) }
    }

    /// Only one side is an account of yours.
    var isAdjustment: Bool { fromAccount == nil || toAccount == nil }
}
