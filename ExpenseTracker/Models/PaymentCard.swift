//
//  PaymentCard.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// A saved credit or debit card with optional full card details (number, expiry, CVV).
@Model
final class PaymentCard {
    var bankName: String
    var cardLastFour: String
    var cardNumber: String = ""
    var expiryDate: String = ""
    var cvv: String = ""
    var cardholderName: String = ""
    var accountTypeRaw: String
    var nickname: String
    var createdAt: Date
    /// The credit card account this card belongs to, if it came from Accounts. Empty otherwise.
    var accountUID: String = ""

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
        self.cardNumber = cleanDigits
        self.expiryDate = expiryDate
        self.cvv = cvv
        self.cardholderName = cardholderName
        self.accountTypeRaw = accountType.rawValue
        self.nickname = nickname
        self.createdAt = createdAt
    }

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .creditCard }
        set { accountTypeRaw = newValue.rawValue }
    }

    var displayName: String {
        if !nickname.isEmpty { return nickname }
        let bank = bankName.isEmpty ? accountType.rawValue : bankName
        return cardLastFour.isEmpty ? bank : "\(bank) •••• \(cardLastFour)"
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
