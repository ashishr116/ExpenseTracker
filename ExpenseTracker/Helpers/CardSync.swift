//
//  CardSync.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// Keeps Saved Cards in step with credit cards added under Accounts.
///
/// Expenses and loans pick a card from Saved Cards. Without this, a credit card added only under Accounts
/// would never show up there, and so couldn't be chosen when adding an expense.
enum CardSync {
    /// Makes sure every open credit card account has a saved card.
    ///
    /// A saved card for the same bank and card digits is linked to the account rather than duplicated.
    /// - Parameter edited: An account the person just edited. Its bank, digits and name are copied to its
    ///   saved card, so the two stay the same. Other cards are left as they are.
    @MainActor
    static func sync(in context: ModelContext, editing edited: Account? = nil) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var cards = (try? context.fetch(FetchDescriptor<PaymentCard>())) ?? []

        for account in accounts where account.kind == .creditCard && !account.isArchived {
            let linked = cards.first { $0.accountUID == account.uid }
                ?? cards.first { $0.accountUID.isEmpty && matches($0, account) }

            if let card = linked {
                card.accountUID = account.uid
                if account.uid == edited?.uid {
                    card.bankName = account.bankName
                    card.nickname = account.name
                    // Keep the digits in step, unless a full number is saved that says otherwise.
                    if card.cardNumber.isEmpty { card.cardLastFour = account.cardLastFour }
                }
            } else {
                let card = PaymentCard(
                    bankName: account.bankName,
                    cardLastFour: account.cardLastFour,
                    accountType: .creditCard,
                    nickname: account.name
                )
                card.accountUID = account.uid
                context.insert(card)
                cards.append(card)
            }
        }
        try? context.save()
    }

    /// A saved credit card with the same bank, and the same digits when the account has any.
    private static func matches(_ card: PaymentCard, _ account: Account) -> Bool {
        guard card.accountType == .creditCard else { return false }
        let sameBank = card.bankName.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(account.bankName.trimmingCharacters(in: .whitespaces)) == .orderedSame
        guard sameBank else { return false }
        return account.cardLastFour.isEmpty || card.cardLastFour == account.cardLastFour
    }
}
