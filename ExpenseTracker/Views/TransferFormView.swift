//
//  TransferFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for moving money between two of your accounts: a card bill payment, a savings top-up, a cash withdrawal.
/// A transfer is not spending and not income.
///
/// Pass `payingCard` to pay a credit card bill: the card is fixed as the destination, and the money comes
/// out of a bank or cash account.
struct TransferFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    /// The credit card being paid, when this is a bill payment.
    let payingCard: Account?

    @State private var amount: Decimal?
    @State private var fromUID = ""
    @State private var toUID = ""
    @State private var date = Date.now
    @State private var note: String

    /// - Parameters:
    ///   - payingCard: The credit card to pay. Leave `nil` for a general transfer.
    ///   - owed: What the card owes now, offered as the amount to pay.
    init(payingCard: Account? = nil, owed: Decimal? = nil) {
        self.payingCard = payingCard
        let suggested = (owed ?? 0) > 0 ? owed : nil
        _amount = State(initialValue: payingCard == nil ? nil : suggested)
        _note = State(initialValue: payingCard == nil ? "" : "Card bill payment")
    }

    private var accounts: [Account] { allAccounts.filter { !$0.isArchived } }

    /// Where the money can come from. Paying a card, it comes from a bank or cash account.
    private var fromChoices: [Account] {
        payingCard == nil ? accounts : accounts.filter { !$0.kind.isLiability }
    }

    private var from: Account? { accounts.first { $0.uid == fromUID } }
    private var to: Account? { accounts.first { $0.uid == toUID } }

    private var isValid: Bool {
        guard let amount, amount > 0, let from, let to else { return false }
        return from.uid != to.uid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(payingCard == nil ? "Amount" : "Amount Paid", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    TextField("Note (optional)", text: $note)
                }

                Section {
                    if let payingCard {
                        if fromChoices.isEmpty {
                            Text("Add a bank account or cash first, so there is somewhere to pay from.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Paid From", selection: $fromUID) {
                                ForEach(fromChoices) { account in
                                    Text(account.displayName).tag(account.uid)
                                }
                            }
                        }
                        LabeledContent("Card", value: payingCard.displayName)
                    } else {
                        Picker("From", selection: $fromUID) {
                            ForEach(accounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                        Picker("To", selection: $toUID) {
                            ForEach(accounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    if payingCard != nil {
                        Text("Paying the bill lowers what you owe on the card and lowers the account you pay from. It isn't counted as spending, because the purchases were already recorded when you made them.")
                    } else if let to, to.kind.isLiability {
                        Text("Paying a credit card lowers the amount you owe on it.")
                    } else if from != nil, from?.uid == to?.uid {
                        Text("Choose two different accounts.")
                            .foregroundStyle(.red)
                    }
                }

                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle(payingCard == nil ? "Add Transfer" : "Pay Card Bill")
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
            .onAppear {
                if let payingCard {
                    toUID = payingCard.uid
                    if fromUID.isEmpty { fromUID = fromChoices.first?.uid ?? "" }
                } else {
                    // Start with two different accounts chosen.
                    if fromUID.isEmpty { fromUID = accounts.first?.uid ?? "" }
                    if toUID.isEmpty { toUID = accounts.dropFirst().first?.uid ?? accounts.first?.uid ?? "" }
                }
            }
        }
    }

    private func save() {
        guard let amount, let from, let to, isValid else { return }
        let transfer = Transfer(
            amount: amount,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(transfer)
        transfer.fromAccount = from
        transfer.toAccount = to
        dismiss()
    }
}

#Preview {
    TransferFormView()
        .modelContainer(for: [Account.self, Transfer.self], inMemory: true)
}
