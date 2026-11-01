//
//  CardFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a new credit/debit card with full details (number, expiry, CVV) or editing an existing one.
struct CardFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var storedCards: [PaymentCard]

    let card: PaymentCard?

    @State private var bankName: String
    @State private var cardNumberInput: String
    @State private var expiryInput: String
    @State private var cvvInput: String
    @State private var cardholderName: String
    @State private var accountType: AccountType
    @State private var nickname: String
    @State private var isCVVVisible = false
    @State private var statementDay: Int
    @State private var dueDay: Int

    init(card: PaymentCard? = nil) {
        self.card = card
        _bankName = State(initialValue: card?.bankName ?? "")
        _cardNumberInput = State(initialValue: card?.formattedFullNumber ?? "")
        _expiryInput = State(initialValue: card?.expiryDate ?? "")
        _cvvInput = State(initialValue: card?.cvv ?? "")
        _cardholderName = State(initialValue: card?.cardholderName ?? "")
        _accountType = State(initialValue: card?.accountType ?? .creditCard)
        _nickname = State(initialValue: card?.nickname ?? "")
        _statementDay = State(initialValue: card?.statementDay ?? 0)
        _dueDay = State(initialValue: card?.dueDay ?? 0)
    }

    private var trimmedBank: String {
        BankName.normalized(bankName)
    }

    private var isValid: Bool {
        !trimmedBank.isEmpty || !cardNumberInput.filter(\.isNumber).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card Details") {
                    Picker("Card Type", selection: $accountType) {
                        ForEach(AccountType.allCases.filter(\.usesCard)) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }

                    TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
                        .textInputAutocapitalization(.words)

                    bankSuggestionChips

                    TextField("Card Number (16 digits)", text: $cardNumberInput)
                        .keyboardType(.numberPad)
                        .onChange(of: cardNumberInput) { _, newValue in
                            let formatted = formatCardNumberInput(newValue)
                            if formatted != newValue {
                                cardNumberInput = formatted
                            }
                        }

                    HStack(spacing: 16) {
                        TextField("Expiry (MM/YY)", text: $expiryInput)
                            .keyboardType(.numberPad)
                            .onChange(of: expiryInput) { _, newValue in
                                let formatted = formatExpiryInput(newValue)
                                if formatted != newValue {
                                    expiryInput = formatted
                                }
                            }

                        HStack {
                            if isCVVVisible {
                                TextField("CVV", text: $cvvInput)
                                    .keyboardType(.numberPad)
                            } else {
                                SecureField("CVV", text: $cvvInput)
                                    .keyboardType(.numberPad)
                            }

                            Button {
                                isCVVVisible.toggle()
                            } label: {
                                Image(systemName: isCVVVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .onChange(of: cvvInput) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(4))
                            if digits != newValue { cvvInput = digits }
                        }
                    }

                    TextField("Cardholder Name (optional)", text: $cardholderName)
                        .textInputAutocapitalization(.words)

                    TextField("Nickname (optional, e.g. Regalia Gold)", text: $nickname)
                        .textInputAutocapitalization(.words)
                }

                if accountType == .creditCard {
                    BillDatesSection(statementDay: $statementDay, dueDay: $dueDay)
                }

                if let card {
                    Section {
                        Button("Delete Card", role: .destructive) {
                            modelContext.delete(card)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(card == nil ? "Add Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var bankSuggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PopularBank.names, id: \.self) { bank in
                    let isSelected = bankName.caseInsensitiveCompare(bank) == .orderedSame
                    Button {
                        bankName = bank
                    } label: {
                        Text(BankName.display(bank))
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
            .padding(.vertical, 2)
        }
    }

    private func formatCardNumberInput(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(16))
        var formatted = ""
        for (index, char) in digits.enumerated() {
            if index > 0 && index % 4 == 0 {
                formatted.append(" ")
            }
            formatted.append(char)
        }
        return formatted
    }

    private func formatExpiryInput(_ input: String) -> String {
        let digits = String(input.filter(\.isNumber).prefix(4))
        if digits.count >= 3 {
            let month = digits.prefix(2)
            let year = digits.suffix(digits.count - 2)
            return "\(month)/\(year)"
        }
        return digits
    }

    private func save() {
        let cleanDigits = cardNumberInput.filter(\.isNumber)
        let lastFour = String(cleanDigits.suffix(4))
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCardholder = cardholderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpiry = expiryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCVV = String(cvvInput.filter(\.isNumber).prefix(4))

        func update(_ card: PaymentCard) {
            card.bankName = trimmedBank
            card.cardNumber = cleanDigits
            // A card saved from Accounts has digits but no full number. Leaving the number empty must not erase them.
            if !lastFour.isEmpty { card.cardLastFour = lastFour }
            card.expiryDate = trimmedExpiry
            card.cvv = cleanCVV
            card.cardholderName = trimmedCardholder
            card.accountType = accountType
            card.nickname = trimmedNickname
            card.statementDay = accountType == .creditCard ? statementDay : 0
            card.dueDay = accountType == .creditCard ? dueDay : 0
        }

        let savedCard: PaymentCard
        if let card {
            update(card)
            savedCard = card
        } else if let existing = storedCards.first(where: {
            $0.accountType == accountType
                && BankName.matches($0.bankName, trimmedBank)
                && $0.cardLastFour == lastFour
        }) {
            // A card first saved from an expense may have no full details; enrich that same record instead of
            // creating a second card with the same bank and last four digits.
            update(existing)
            savedCard = existing
        } else {
            let newCard = PaymentCard(
                bankName: trimmedBank,
                cardLastFour: lastFour,
                cardNumber: cleanDigits,
                expiryDate: trimmedExpiry,
                cvv: cleanCVV,
                cardholderName: trimmedCardholder,
                accountType: accountType,
                nickname: trimmedNickname
            )
            newCard.statementDay = accountType == .creditCard ? statementDay : 0
            newCard.dueDay = accountType == .creditCard ? dueDay : 0
            modelContext.insert(newCard)
            savedCard = newCard
        }
        CardSync.sync(in: modelContext, editingCard: savedCard)
        let context = modelContext
        Task { await CardBillReminder.reschedule(in: context) }
        dismiss()
    }
}

#Preview {
    CardFormView()
        .modelContainer(for: PaymentCard.self, inMemory: true)
}
