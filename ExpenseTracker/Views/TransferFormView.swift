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
    @Query private var loans: [Loan]

    /// The credit card being paid, when this is a bill payment.
    let payingCard: Account?

    @State private var amount: Decimal?
    @State private var fromUID = ""
    @State private var toUID = ""
    @State private var date = Date.now
    @State private var note: String
    /// Friends whose share of this bill you are paying yourself, with the amount for each.
    @State private var fronted: [String: Decimal] = [:]

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

    /// Friends who still owe something on the card being paid.
    private var shares: [CardBillShare] {
        guard let payingCard else { return [] }
        return CardBill.friendShares(bankName: payingCard.bankName, lastFour: payingCard.cardLastFour, loans: loans)
    }

    /// What you are paying for friends, on top of your own amount.
    private var frontedTotal: Decimal {
        shares.reduce(0) { $0 + (fronted[$1.id] ?? 0) }
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

                if !shares.isEmpty {
                    Section {
                        ForEach(shares) { share in
                            Toggle(isOn: Binding(
                                get: { fronted[share.id] != nil },
                                set: { fronted[share.id] = $0 ? share.amount : nil }
                            )) {
                                VStack(alignment: .leading) {
                                    Text("I paid for \(share.friendName)")
                                    Text("Owes \(share.amount, format: .rupees) on this card")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let value = fronted[share.id] {
                                TextField("Amount paid for \(share.friendName)", value: Binding(
                                    get: { value },
                                    set: { fronted[share.id] = $0 }
                                ), format: .rupees)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        if frontedTotal > 0, let amount {
                            LabeledContent("Total from \(from?.displayName ?? "account")", value: (amount + frontedTotal).formatted(.rupees))
                        }
                    } header: {
                        Text("Friends' Share")
                    } footer: {
                        Text("Switch on if a friend hasn't paid the bank and you covered their part. It is added on top of the amount above, taken from the same account, and becomes a cash loan to them dated today. It comes off their card loan.")
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
        coverFriends(from: from)
        dismiss()
    }
}

extension TransferFormView {
    /// For each friend whose share you paid: takes it off their card loans and lends it to them as cash from
    /// the account you paid from, so your balance drops once and they owe you the money.
    private func coverFriends(from account: Account) {
        for share in shares {
            guard var left = fronted[share.id], left > 0 else { continue }
            let lent = left
            for loan in share.loans.sorted(by: { $0.date < $1.date }) where left > 0 {
                let part = min(left, loan.outstandingAmount)
                guard part > 0 else { continue }
                loan.recordRepayment(part, on: date, note: "Card paid for loan", bankName: "", in: modelContext)
                left -= part
            }
            // Whatever was recorded against the card loans becomes the cash loan.
            let covered = lent - left
            guard covered > 0 else { continue }
            modelContext.insert(Loan(
                amount: covered,
                friendName: share.friendName,
                friendPhone: share.phone,
                note: "Card paid for loan",
                date: date,
                method: .cash,
                bankName: account.kind == .bank ? account.bankName : ""
            ))
        }
    }
}

#Preview {
    TransferFormView()
        .modelContainer(for: [Account.self, Transfer.self, Loan.self], inMemory: true)
}
