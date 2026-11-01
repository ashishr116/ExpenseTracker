//
//  CardSync.swift
//  ExpenseTracker
//

import Foundation
import SwiftData

/// The canonical spelling used when a bank name identifies an account or card.
/// Keeping this in one place prevents differently-cased entries from becoming separate cards.
enum BankName {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = normalized(lhs)
        return !lhs.isEmpty && lhs == normalized(rhs)
    }
}

/// Keeps Saved Cards in step with credit cards added under Accounts.
///
/// Expenses and loans pick a card from Saved Cards. Without this, a credit card added only under Accounts
/// would never show up there, and so couldn't be chosen when adding an expense.
enum CardSync {
    /// Makes sure credit card accounts and saved credit cards have a one-to-one link.
    ///
    /// A saved card for the same bank and card digits is linked to the account rather than duplicated.
    /// - Parameters:
    ///   - edited: An account the person just edited. Its bank, digits and name are copied to its saved card.
    ///   - editingCard: A saved card the person just edited. Its details are copied to its account.
    @MainActor
    static func sync(
        in context: ModelContext,
        editing edited: Account? = nil,
        editingCard: PaymentCard? = nil
    ) {
        var accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var cards = (try? context.fetch(FetchDescriptor<PaymentCard>())) ?? []

        // Upgrade data entered before bank names were standardized.
        accounts.forEach { account in
            account.bankName = BankName.normalized(account.bankName)
            account.cardLastFour = String(account.cardLastFour.filter(\.isNumber).suffix(4))
        }
        cards.forEach { card in
            card.bankName = BankName.normalized(card.bankName)
            card.cardLastFour = String(card.cardLastFour.filter(\.isNumber).suffix(4))
        }

        // A credit card saved while recording an expense or a friend's purchase also needs an Account,
        // otherwise its ledger entries have no balance to update.
        for card in cards where card.accountType == .creditCard {
            let linked = accounts.first { $0.uid == card.accountUID }
                ?? accounts.first { $0.kind == .creditCard && matches(card, $0) }
            if let account = linked {
                card.accountUID = account.uid
                if card === editingCard {
                    account.name = card.nickname
                    account.bankName = card.bankName
                    account.cardLastFour = card.cardLastFour
                }
            } else {
                let account = Account(
                    name: card.nickname,
                    kind: .creditCard,
                    bankName: card.bankName,
                    cardLastFour: card.cardLastFour
                )
                context.insert(account)
                accounts.append(account)
                card.accountUID = account.uid
            }
        }

        for account in accounts where account.kind == .creditCard && !account.isArchived {
            let linked = cards.first { $0.accountUID == account.uid }
                ?? cards.first { $0.accountType == .creditCard && $0.accountUID.isEmpty && matches($0, account) }

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

    /// A saved credit card is the same card only when its bank and last four digits both match.
    private static func matches(_ card: PaymentCard, _ account: Account) -> Bool {
        guard card.accountType == .creditCard else { return false }
        return BankName.matches(card.bankName, account.bankName)
            && card.cardLastFour == account.cardLastFour
    }
}
