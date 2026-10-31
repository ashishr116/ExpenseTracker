//
//  PaymentSourceFields.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// The bank and card fields for choosing where a payment comes from, with your saved cards and banks one tap away.
///
/// For a card, your saved cards of that type appear as chips, and tapping one fills in the bank and last four digits
/// exactly as your account has them, so the payment lands in the right balance. For any type with a bank, your
/// banks and the popular ones appear as chips.
///
/// Put this inside a form section, below the picker for the payment type.
struct PaymentSourceFields: View {
    let accountType: AccountType
    @Binding var bankName: String
    @Binding var cardLastFour: String

    /// Cards you have saved, so a card payment uses the same bank and digits as the card's account.
    @Query(sort: \PaymentCard.createdAt, order: .reverse) private var storedCards: [PaymentCard]
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    private var trimmedBank: String { bankName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Banks of your open bank accounts, one entry per bank.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return accounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        if accountType.usesCard {
            let cards = storedCards.filter { $0.accountType == accountType }
            if !cards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(cards) { card in
                            Button(card.displayName, systemImage: card.accountType.systemImage) {
                                bankName = card.bankName
                                cardLastFour = card.cardLastFour
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        if accountType.usesBank {
            TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
                .textInputAutocapitalization(.words)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(bankChoices + PopularBank.names.filter { name in
                        !bankChoices.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
                    }, id: \.self) { bank in
                        let isSelected = trimmedBank.caseInsensitiveCompare(bank) == .orderedSame
                        Button {
                            bankName = bank
                        } label: {
                            Text(bank)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .foregroundStyle(isSelected ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        if accountType.usesCard {
            TextField("Card No. (last 4 digits)", text: $cardLastFour)
                .keyboardType(.numberPad)
                .onChange(of: cardLastFour) { _, newValue in
                    // Keep only digits and at most 4 of them.
                    let digits = String(newValue.filter(\.isNumber).prefix(4))
                    if digits != newValue { cardLastFour = digits }
                }
        }
    }
}
