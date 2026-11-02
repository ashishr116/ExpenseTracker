//
//  ExpenseFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a new expense, or editing an existing one when `expense` is non-nil.
struct ExpenseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PaymentCard.createdAt, order: .reverse) private var storedCards: [PaymentCard]
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    let expense: Expense?

    @State private var title: String
    @State private var amount: Decimal?
    @State private var accountType: AccountType
    @State private var bankName: String
    @State private var cardLastFour: String
    @State private var category: ExpenseCategory
    @State private var customCategory: String
    @State private var date: Date
    /// A credit card saved for the first time by this expense, while its bill day is being asked.
    @State private var cardAskingBillDay: PaymentCard?
    /// Money coming back: a refund or cashback. Saved as a negative amount.
    @State private var isRefund: Bool

    /// - Parameter defaultDate: Date used for new entries from a selected day or month.
    /// - Parameters:
    ///   - prefillTitle: Description to start a new expense with, for example the name of a goal just bought.
    ///   - prefillAmount: Amount to start a new expense with.
    ///   - isRefund: Start a new entry as a refund or cashback.
    init(
        expense: Expense? = nil, defaultDate: Date = .now, prefillTitle: String = "", prefillAmount: Decimal? = nil,
        isRefund: Bool = false
    ) {
        self.expense = expense
        _title = State(initialValue: expense?.title ?? prefillTitle)
        // A refund is stored as a negative amount, and entered as a positive one.
        _amount = State(initialValue: expense.map { abs($0.amount) } ?? prefillAmount)
        _isRefund = State(initialValue: expense?.isRefund ?? isRefund)
        _accountType = State(initialValue: expense?.accountType ?? .creditCard)
        _bankName = State(initialValue: expense?.bankName ?? "")
        _cardLastFour = State(initialValue: expense?.cardLastFour ?? "")
        _category = State(initialValue: expense?.category ?? .food)
        _customCategory = State(initialValue: expense?.customCategory ?? "")
        _date = State(initialValue: expense?.date ?? defaultDate)
    }

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0
    }

    /// Custom categories used before that match what is typed, for one-tap reuse.
    private var customSuggestions: [String] {
        let typed = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return allExpenses
            .filter { $0.category == .other }
            .map { $0.customCategory.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .filter { $0.caseInsensitiveCompare(typed) != .orderedSame && (typed.isEmpty || $0.localizedCaseInsensitiveContains(typed)) }
    }

    /// One candidate card available for quick selection.
    private struct CardChoice: Hashable, Identifiable {
        let accountType: AccountType
        let bankName: String
        let cardLastFour: String
        let nickname: String

        var id: String { "\(accountType.rawValue)|\(bankName)|\(cardLastFour)" }

        var title: String {
            if !nickname.isEmpty { return nickname }
            let bank = bankName.isEmpty ? accountType.rawValue : BankName.display(bankName)
            return cardLastFour.isEmpty ? bank : "\(bank) •••• \(cardLastFour)"
        }
    }

    /// Merged distinct cards from explicitly saved cards and past expense history.
    private var availableCards: [CardChoice] {
        var seen = Set<String>()
        var choices: [CardChoice] = []

        for card in storedCards {
            let choice = CardChoice(
                accountType: card.accountType,
                bankName: card.bankName,
                cardLastFour: card.cardLastFour,
                nickname: card.nickname
            )
            if seen.insert(choice.id).inserted {
                choices.append(choice)
            }
        }

        for exp in allExpenses where exp.accountType.usesCard {
            let choice = CardChoice(
                accountType: exp.accountType,
                bankName: exp.bankName,
                cardLastFour: exp.cardLastFour,
                nickname: ""
            )
            if seen.insert(choice.id).inserted {
                choices.append(choice)
            }
        }

        return choices
    }

    var body: some View {
        NavigationStack {
            Form {
                // Planned EMIs and premiums are always expenses.
                if expense?.emi == nil && expense?.insurancePolicy == nil {
                    Section {
                        Picker("Type", selection: $isRefund.animation()) {
                            Text("Expense").tag(false)
                            Text("Refund / Cashback").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    TextField(isRefund ? "Amount Back" : "Amount", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    TextField(isRefund ? "What for (e.g. Amazon return, cashback)" : "Description (optional)", text: $title)
                    Picker("Category", selection: $category.animation()) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    // Anything not in the list can be named here.
                    if category == .other {
                        TextField("Custom Category (optional)", text: $customCategory)
                            .textInputAutocapitalization(.words)
                        if !customSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(customSuggestions, id: \.self) { name in
                                        Button(name) { customCategory = name }
                                            .buttonStyle(.bordered)
                                            .buttonBorderShape(.capsule)
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text(isRefund ? "Refund / Cashback" : "Expense")
                } footer: {
                    if isRefund {
                        Text("Pick the category of what was refunded: it lowers that category's spending this month. Use Other for cashback. The money goes back where it was paid: a card owes less, or a bank or cash goes up.")
                    }
                }

                Section(isRefund ? "Credited To" : "Payment") {
                    Picker("Account Type", selection: $accountType.animation()) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.rawValue, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }

                    if accountType.usesCard {
                        let matching = availableCards.filter { $0.accountType == accountType }
                        if !matching.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Choose Saved Card")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(matching) { card in
                                            let isSelected = bankName.caseInsensitiveCompare(card.bankName) == .orderedSame
                                                && cardLastFour == card.cardLastFour
                                            Button {
                                                bankName = card.bankName
                                                cardLastFour = card.cardLastFour
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "creditcard")
                                                    Text(card.title)
                                                }
                                                .font(.subheadline)
                                                .fontWeight(isSelected ? .semibold : .regular)
                                                .foregroundStyle(isSelected ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }

                    if accountType.usesBank {
                        TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
                            .textInputAutocapitalization(.words)

                        popularBankChips
                    }

                    if accountType.usesCard {
                        TextField("Card No. (last 4 digits)", text: $cardLastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: cardLastFour) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(4))
                                if digits != newValue { cardLastFour = digits }
                            }
                    }
                }

                Section("When") {
                    DatePicker("Date & Time", selection: $date)
                }

                if let expense {
                    Section {
                        Button(isRefund ? "Delete Refund" : "Delete Expense", role: .destructive) {
                            modelContext.delete(expense)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isRefund
                             ? (expense == nil ? "New Refund" : "Edit Refund")
                             : (expense == nil ? "New Expense" : "Edit Expense"))
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
            // The expense is already saved. Once the bill day is answered or skipped, the form closes.
            .sheet(item: $cardAskingBillDay, onDismiss: { dismiss() }) { card in
                BillingCycleSheet(card: card)
            }
        }
    }

    private var popularBankChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popular Banks")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
    }

    private func save() {
        guard let amount, amount > 0 else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // A custom name only applies to the Other category.
        let trimmedCustom = category == .other ? customCategory.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let isBank = accountType.usesBank
        let isCard = accountType.usesCard
        let trimmedBank = isBank ? BankName.normalized(bankName) : ""
        let card = isCard ? cardLastFour : ""

        // Set when a credit card is saved for the first time, so its bill day can be asked for.
        var newCreditCard: PaymentCard?
        // Auto-save card to stored PaymentCard so user never has to re-enter it
        if isCard && (!trimmedBank.isEmpty || !card.isEmpty) {
            let alreadySaved = storedCards.contains {
                $0.accountType == accountType &&
                BankName.matches($0.bankName, trimmedBank) &&
                $0.cardLastFour == card
            }
            if !alreadySaved {
                let saved = PaymentCard(
                    bankName: trimmedBank,
                    cardLastFour: card,
                    accountType: accountType
                )
                modelContext.insert(saved)
                if accountType == .creditCard { newCreditCard = saved }
            }
        }
        // Credit cards saved from expenses need a matching Account before ledger entries are calculated.
        if accountType == .creditCard {
            CardSync.sync(in: modelContext)
        }

        // Money back is saved as a negative amount, so every total and balance takes it off.
        let signed = isRefund ? -amount : amount

        if let expense {
            expense.title = trimmedTitle
            expense.amount = signed
            expense.accountType = accountType
            expense.bankName = trimmedBank
            expense.cardLastFour = card
            expense.category = category
            expense.customCategory = trimmedCustom
            expense.date = date
        } else {
            let newExpense = Expense(
                title: trimmedTitle,
                amount: signed,
                accountType: accountType,
                bankName: trimmedBank,
                cardLastFour: card,
                category: category,
                date: date
            )
            newExpense.customCategory = trimmedCustom
            modelContext.insert(newExpense)
        }
        // Warn if this expense takes a category to or past its monthly limit.
        let context = modelContext
        Task { await BudgetAlerts.check(in: context) }
        if let newCreditCard {
            cardAskingBillDay = newCreditCard
        } else {
            dismiss()
        }
    }
}

#Preview {
    ExpenseFormView()
        .modelContainer(for: [Expense.self, PaymentCard.self], inMemory: true)
}
