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
    @State private var isArchived: Bool

    /// - Parameter kind: The type to start with when adding a new account.
    init(account: Account? = nil, kind: AccountKind = .bank) {
        self.account = account
        _kind = State(initialValue: account?.kind ?? kind)
        _name = State(initialValue: account?.name ?? "")
        _bankName = State(initialValue: account?.bankName ?? "")
        _cardLastFour = State(initialValue: account?.cardLastFour ?? "")
        _openingBalance = State(initialValue: account?.openingBalance)
        _openingDate = State(initialValue: account?.openingDate ?? .now)
        _isArchived = State(initialValue: account?.isArchived ?? false)
    }

    private var trimmedBank: String { bankName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isValid: Bool {
        guard openingBalance != nil else { return false }
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
                } header: {
                    Text("Starting Point")
                } footer: {
                    Text(kind.isLiability
                         ? "Enter what you owe for your own spending. If friends have used the card, their share isn't part of this. It comes from the loans you record. Only entries on or after this date change the amount."
                         : "Enter the real figure from your bank or statement. Only entries on or after this date change the balance, so older ones aren't counted twice.")
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
            account.openingDate = openingDate
            account.isArchived = isArchived
            CardSync.sync(in: modelContext, editing: account)
        } else {
            let newAccount = Account(
                name: trimmedName,
                kind: kind,
                bankName: bank,
                cardLastFour: digits,
                openingBalance: openingBalance,
                openingDate: openingDate
            )
            modelContext.insert(newAccount)
            // A credit card also becomes a saved card, so it can be chosen when adding an expense.
            CardSync.sync(in: modelContext, editing: newAccount)
        }
        dismiss()
    }
}

#Preview {
    AccountFormView()
        .modelContainer(for: Account.self, inMemory: true)
}
