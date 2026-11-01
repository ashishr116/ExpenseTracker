//
//  AccountFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for adding a bank account, cash wallet or credit card, or editing one when `account` is non-nil.
struct AccountFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: Account?

    @State private var kind: AccountKind
    @State private var name: String
    @State private var bankName: String
    @State private var cardLastFour: String
    @State private var openingBalance: Decimal?
    @State private var openingDate: Date
    /// For a credit card: whether the amount owed is on a bill already, not yet, or partly.
    @State private var openingSplit: OpeningSplit
    @State private var openingUnbilledPart: Decimal?
    @State private var isArchived: Bool
    /// For a credit card: the bill dates. They are kept on the card's saved card.
    @State private var statementDay = 0
    @State private var dueDay = 0
    @State private var hasLoadedBillDates = false
    @Query private var savedCards: [PaymentCard]

    /// How much of a card's opening amount is unbilled.
    private enum OpeningSplit: String, CaseIterable, Identifiable {
        case billed = "All Billed"
        case unbilled = "All Unbilled"
        case part = "Part Unbilled"

        var id: String { rawValue }
    }

    /// - Parameter kind: The type to start with when adding a new account.
    init(account: Account? = nil, kind: AccountKind = .bank) {
        self.account = account
        _kind = State(initialValue: account?.kind ?? kind)
        _name = State(initialValue: account?.name ?? "")
        _bankName = State(initialValue: account?.bankName ?? "")
        _cardLastFour = State(initialValue: account?.cardLastFour ?? "")
        _openingBalance = State(initialValue: account?.openingBalance)
        _openingDate = State(initialValue: account?.openingDate ?? .now)
        let owed = account?.openingBalance ?? 0
        let unbilled = account?.openingUnbilled ?? 0
        _openingSplit = State(initialValue: unbilled <= 0 ? .billed : (unbilled >= owed ? .unbilled : .part))
        _openingUnbilledPart = State(initialValue: unbilled > 0 && unbilled < owed ? unbilled : nil)
        _isArchived = State(initialValue: account?.isArchived ?? false)
    }

    private var trimmedBank: String { BankName.normalized(bankName) }

    /// The part of the amount owed that is not on a bill yet, from the choice made.
    private var openingUnbilledValue: Decimal {
        guard kind == .creditCard, let openingBalance, openingBalance > 0 else { return 0 }
        switch openingSplit {
        case .billed: return 0
        case .unbilled: return openingBalance
        case .part: return min(max(0, openingUnbilledPart ?? 0), openingBalance)
        }
    }

    private var isValid: Bool {
        guard openingBalance != nil else { return false }
        // A part that is unbilled can't be more than what is owed.
        if kind == .creditCard, openingSplit == .part, let part = openingUnbilledPart, let owed = openingBalance, part > owed {
            return false
        }
        // The bank name is how entries find this account, so banks and cards need one.
        return kind == .cash || !trimmedBank.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if account == nil {
                    Section {
                        Picker("Type", selection: $kind.animation()) {
                            ForEach(AccountKind.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.words)
                    if kind != .cash {
                        TextField("Bank Name (e.g. HDFC Bank)", text: $bankName)
                            .textInputAutocapitalization(.words)
                        bankChips
                    }
                    if kind == .creditCard {
                        TextField("Card No. (last 4 digits)", text: $cardLastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: cardLastFour) { _, newValue in
                                let digits = String(newValue.filter(\.isNumber).prefix(4))
                                if digits != newValue { cardLastFour = digits }
                            }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    if kind != .cash {
                        Text("Use the same bank name you pick when adding expenses and income. That is how entries find this account.")
                    }
                }

                Section {
                    TextField(kind.isLiability ? "Amount Owed Today" : "Balance Today", value: $openingBalance, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.semibold))
                    DatePicker("As Of", selection: $openingDate, displayedComponents: .date)
                    if kind == .creditCard {
                        Picker("This Amount Is", selection: $openingSplit.animation()) {
                            ForEach(OpeningSplit.allCases) { split in
                                Text(split.rawValue).tag(split)
                            }
                        }
                        if openingSplit == .part {
                            TextField("Unbilled Part", value: $openingUnbilledPart, format: .rupees)
                                .keyboardType(.decimalPad)
                            if let owed = openingBalance, let part = openingUnbilledPart, part <= owed {
                                LabeledContent("Billed Part", value: (owed - part).formatted(.rupees))
                            }
                        }
                    }
                } header: {
                    Text("Starting Point")
                } footer: {
                    Text(kind.isLiability
                         ? "Enter what you owe for your own spending. If friends have used the card, their share isn't part of this. It comes from the loans you record. Only entries on or after this date change the amount. Billed is on a statement already. Unbilled was spent since the last bill and goes on the next one. Set the bill day below so the card can show both."
                         : "Enter the real figure from your bank or statement. Only entries on or after this date change the balance, so older ones aren't counted twice.")
                }

                if kind == .creditCard {
                    BillDatesSection(statementDay: $statementDay, dueDay: $dueDay)
                }

                if account != nil {
                    Section {
                        Toggle("Closed Account", isOn: $isArchived)
                    } footer: {
                        Text("A closed account is hidden from the pickers. Its history and balance are kept.")
                    }
                }
            }
            .navigationTitle(account == nil ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Show the dates already saved on this card, once.
                guard !hasLoadedBillDates, let account,
                      let card = savedCards.first(where: { $0.accountUID == account.uid }) else { return }
                hasLoadedBillDates = true
                statementDay = card.statementDay
                dueDay = card.dueDay
            }
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

    private var bankChips: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popular Banks")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PopularBank.names, id: \.self) { bank in
                        let isSelected = trimmedBank.caseInsensitiveCompare(bank) == .orderedSame
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
        guard let openingBalance, isValid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bank = kind == .cash ? "" : trimmedBank
        let digits = kind == .creditCard ? cardLastFour : ""

        if let account {
            account.kind = kind
            account.name = trimmedName
            account.bankName = bank
            account.cardLastFour = digits
            account.openingBalance = openingBalance
            account.openingUnbilled = openingUnbilledValue
            account.openingDate = openingDate
            account.isArchived = isArchived
            CardSync.sync(in: modelContext, editing: account)
            saveBillDates(for: account)
        } else {
            let newAccount = Account(
                name: trimmedName,
                kind: kind,
                bankName: bank,
                cardLastFour: digits,
                openingBalance: openingBalance,
                openingDate: openingDate
            )
            newAccount.openingUnbilled = openingUnbilledValue
            modelContext.insert(newAccount)
            // A credit card also becomes a saved card, so it can be chosen when adding an expense.
            CardSync.sync(in: modelContext, editing: newAccount)
            saveBillDates(for: newAccount)
        }
        dismiss()
    }

    /// Stores the bill dates on the account's saved card, then refreshes the reminders that depend on them.
    private func saveBillDates(for account: Account) {
        if account.kind == .creditCard,
           let card = (try? modelContext.fetch(FetchDescriptor<PaymentCard>()))?.first(where: { $0.accountUID == account.uid }) {
            card.statementDay = statementDay
            card.dueDay = dueDay
        }
        let context = modelContext
        Task { await CardBillReminder.reschedule(in: context) }
    }
}

#Preview {
    AccountFormView()
        .modelContainer(for: Account.self, inMemory: true)
}
