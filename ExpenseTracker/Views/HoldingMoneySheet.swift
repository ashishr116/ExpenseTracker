//
//  HoldingMoneySheet.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Puts money into an investment or takes it out. The investment's value and the chosen account move together,
/// so the money is never counted twice or lost from net worth.
struct HoldingMoneySheet: View {
    enum Mode: String, Identifiable {
        case add, withdraw
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    let holding: Holding
    let mode: Mode

    @State private var amount: Decimal?
    @State private var date = Date.now
    /// The bank or cash account. Empty means none: only the investment changes.
    @State private var accountUID = ""

    /// Cash and bank accounts money can come from or go to.
    private var accounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    private var account: Account? { accounts.first { $0.uid == accountUID } }

    private var isValid: Bool {
        guard let amount, amount > 0 else { return false }
        return mode == .add || amount <= holding.currentValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(holding.kind.valueLabel) {
                        Text(holding.currentValue, format: .rupees)
                    }
                    if holding.kind.tracksInvested, holding.investedAmount > 0 {
                        LabeledContent(holding.kind.investedLabel) {
                            Text(holding.investedAmount, format: .rupees)
                        }
                    }
                }

                Section {
                    TextField(mode == .add ? "Amount Put In" : "Amount Taken Out", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if !accounts.isEmpty {
                        Picker(mode == .add ? "Paid From" : "Received In", selection: $accountUID) {
                            Text("Not from an account").tag("")
                            ForEach(accounts) { account in
                                Text(account.displayName).tag(account.uid)
                            }
                        }
                    }
                } footer: {
                    if let amount, mode == .withdraw, amount > holding.currentValue {
                        Text("That's more than the \(holding.currentValue.formatted(.rupees)) it is worth.")
                            .foregroundStyle(.red)
                    } else if mode == .add {
                        Text(account == nil
                             ? "Only the investment goes up. Choose an account if the money came from one, or it is counted twice in your net worth."
                             : "\(account?.displayName ?? "The account") goes down and this investment goes up by the same amount.")
                    } else {
                        Text(account == nil
                             ? "Only the investment goes down. Choose the account the money went to, or it drops out of your net worth."
                             : "This investment goes down and \(account?.displayName ?? "the account") goes up by the same amount. What you put in goes down in proportion, so the gain shown stays right.")
                    }
                }
            }
            .navigationTitle(mode == .add ? "Add Money" : "Withdraw")
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
                // Start with the SIP's account, or the first bank.
                if accountUID.isEmpty {
                    accountUID = accounts.first { $0.uid == holding.sipAccountUID }?.uid
                        ?? accounts.first { $0.kind == .bank }?.uid ?? ""
                }
            }
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        switch mode {
        case .add: holding.addMoney(amount, from: account, on: date, in: modelContext)
        case .withdraw: holding.withdraw(amount, to: account, on: date, in: modelContext)
        }
        try? modelContext.save()
        dismiss()
    }
}
