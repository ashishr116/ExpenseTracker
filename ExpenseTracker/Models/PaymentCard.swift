//
//  PaymentCard.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// A saved credit or debit card with optional full card details (number, expiry, CVV).
///
/// The full details live in the Keychain (see `CardVault`), not in the database. These three database fields
/// are what earlier versions used, and are emptied once the details have been moved.
@Model
final class PaymentCard {
    var bankName: String
    var cardLastFour: String
    @Attribute(originalName: "cardNumber") private var legacyCardNumber: String = ""
    @Attribute(originalName: "expiryDate") private var legacyExpiryDate: String = ""
    @Attribute(originalName: "cvv") private var legacyCVV: String = ""
    /// Names this card's item in the Keychain. Empty until the card has details to keep.
    private var secretID: String = ""
    /// Changes whenever the details change, so screens showing them redraw.
    private var secretsRevision: Int = 0
    var cardholderName: String = ""
    var accountTypeRaw: String
    var nickname: String
    var createdAt: Date
    /// The credit card account this card belongs to, if it came from Accounts. Empty otherwise.
    var accountUID: String = ""
    /// For a credit card: the day of the month the bill is generated, 1 to 31. 0 means not set.
    var statementDay: Int = 0
    /// For a credit card: the day of the month the bill is due, 1 to 31. 0 means not set.
    var dueDay: Int = 0

    init(
        bankName: String,
        cardLastFour: String = "",
        cardNumber: String = "",
        expiryDate: String = "",
        cvv: String = "",
        cardholderName: String = "",
        accountType: AccountType = .creditCard,
        nickname: String = "",
        createdAt: Date = .now
    ) {
        self.bankName = bankName
        let cleanDigits = cardNumber.filter(\.isNumber)
        let lastFour = !cardLastFour.isEmpty ? cardLastFour : String(cleanDigits.suffix(4))
        self.cardLastFour = lastFour
        self.cardholderName = cardholderName
        self.accountTypeRaw = accountType.rawValue
        self.nickname = nickname
        self.createdAt = createdAt
        self.secrets = CardVault.Secrets(number: cleanDigits, expiry: expiryDate, cvv: cvv)
    }

    // MARK: Full details

    /// The number, expiry and CVV, read from the Keychain. Before a card has been moved there, they come
    /// from the old database fields.
    private var secrets: CardVault.Secrets {
        get {
            if !secretID.isEmpty, let saved = CardVault.load(secretID) { return saved }
            return CardVault.Secrets(number: legacyCardNumber, expiry: legacyExpiryDate, cvv: legacyCVV)
        }
        set {
            if secretID.isEmpty { secretID = UUID().uuidString }
            if CardVault.save(newValue, for: secretID) {
                legacyCardNumber = ""
                legacyExpiryDate = ""
                legacyCVV = ""
            } else {
                // The Keychain refused, so keep the details rather than lose them. They move on the next launch.
                legacyCardNumber = newValue.number
                legacyExpiryDate = newValue.expiry
                legacyCVV = newValue.cvv
            }
            secretsRevision += 1
        }
    }

    var cardNumber: String {
        get { secrets.number }
        set { secrets.number = newValue }
    }

    var expiryDate: String {
        get { secrets.expiry }
        set { secrets.expiry = newValue }
    }

    var cvv: String {
        get { secrets.cvv }
        set { secrets.cvv = newValue }
    }

    /// Moves details still held in the database into the Keychain, and clears them from the database.
    func moveSecretsToKeychain() {
        guard !legacyCardNumber.isEmpty || !legacyExpiryDate.isEmpty || !legacyCVV.isEmpty else { return }
        secrets = CardVault.Secrets(number: legacyCardNumber, expiry: legacyExpiryDate, cvv: legacyCVV)
    }

    /// The Keychain id of this card, used to tidy up items of deleted cards.
    var vaultID: String { secretID }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .creditCard }
        set { accountTypeRaw = newValue.rawValue }
    }

    var displayName: String {
        if !nickname.isEmpty { return nickname }
        let bank = bankName.isEmpty ? accountType.rawValue : bankName
        return cardLastFour.isEmpty ? bank : "\(bank) •••• \(cardLastFour)"
    }

    // MARK: Bill dates

    /// Days from the bill being generated to its due date when no due day is set.
    static let defaultDueGap = 18

    /// The bill day is set, so the statement can be worked out.
    var hasBillingCycle: Bool { accountType == .creditCard && statementDay > 0 }

    /// A due date can be worked out: from the due day, or from the bill day plus the default gap.
    var hasDueDate: Bool { accountType == .creditCard && (dueDay > 0 || statementDay > 0) }

    /// The next payment due date, today included.
    func nextDueDate(from now: Date = .now) -> Date? {
        if dueDay > 0 { return PaymentCard.nextDate(day: dueDay, from: now) }
        guard statementDay > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // The latest bill may still be unpaid, so start from it and move on until a due date is ahead.
        var statement = lastStatementDate(onOrBefore: now)
        for _ in 0..<3 {
            guard let current = statement else { return nil }
            if let due = dueDate(forStatementOn: current), due >= today { return due }
            statement = nextStatementDate(from: calendar.date(byAdding: .day, value: 1, to: current) ?? current)
        }
        return nil
    }

    /// The next day the bill is generated, today included.
    func nextStatementDate(from now: Date = .now) -> Date? {
        PaymentCard.nextDate(day: statementDay, from: now)
    }

    /// The latest day the bill was generated, today included.
    func lastStatementDate(onOrBefore now: Date = .now) -> Date? {
        guard statementDay > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var month = calendar.monthRange(containing: now).lowerBound
        for _ in 0..<3 {
            if let date = PaymentCard.date(day: statementDay, inMonth: month), date <= today { return date }
            guard let previous = calendar.date(byAdding: .month, value: -1, to: month) else { return nil }
            month = previous
        }
        return nil
    }

    /// When the bill generated on `statement` is due: the first due day after it, or the default gap later.
    func dueDate(forStatementOn statement: Date) -> Date? {
        let calendar = Calendar.current
        guard dueDay > 0 else { return calendar.date(byAdding: .day, value: PaymentCard.defaultDueGap, to: statement) }
        var month = calendar.monthRange(containing: statement).lowerBound
        for _ in 0..<3 {
            if let date = PaymentCard.date(day: dueDay, inMonth: month), date > statement { return date }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            month = next
        }
        return nil
    }

    /// The next date on or after today that falls on `day` of a month. A day the month doesn't have, such as the
    /// 31st in April, falls on the month's last day.
    static func nextDate(day: Int, from now: Date = .now) -> Date? {
        guard day > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var month = calendar.monthRange(containing: now).lowerBound
        for _ in 0..<3 {
            if let date = date(day: day, inMonth: month), date >= today { return date }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            month = next
        }
        return nil
    }

    /// `day` of the month containing `month`, or that month's last day if it is shorter.
    static func date(day: Int, inMonth month: Date) -> Date? {
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = min(max(day, 1), daysInMonth)
        return calendar.date(from: components)
    }

    /// Formatted full card number (e.g. "1234 5678 9012 3456")
    var formattedFullNumber: String {
        let digits = cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else {
            return cardLastFour.isEmpty ? "" : "•••• •••• •••• \(cardLastFour)"
        }
        var formatted = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted.append(" ")
            }
            formatted.append(char)
        }
        return formatted
    }

    /// Masked card number showing only last 4 digits (e.g. "•••• •••• •••• 1234")
    var maskedNumber: String {
        let lastFour = !cardLastFour.isEmpty ? cardLastFour : String(cardNumber.filter(\.isNumber).suffix(4))
        return lastFour.isEmpty ? "•••• •••• •••• ••••" : "•••• •••• •••• \(lastFour)"
    }
}
