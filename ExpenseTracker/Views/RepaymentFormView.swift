//
//  RepaymentFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for recording a payment a friend has made towards a loan. It can be less than the full balance.
/// For credit card loans, also allows recording that you paid the card bill yourself, which moves the debt to a cash loan.
struct RepaymentFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let loan: Loan

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    enum RepayMode: String, CaseIterable, Identifiable {
        case friendPaid = "Friend Paid Directly"
        case iPaid = "I Paid Card (Move to Cash)"
        var id: String { rawValue }
    }

    @State private var repayMode: RepayMode
    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""
    /// The bank the money arrived in. Empty means cash.
    @State private var receivedIn: String
    /// The bank/cash account paid from when you cover the card bill.
    @State private var fromUID: String = ""

    init(loan: Loan, initialMode: RepayMode = .friendPaid) {
        self.loan = loan
        _repayMode = State(initialValue: initialMode)
        // Start with the full balance; change it for a part payment.
        _amount = State(initialValue: loan.outstandingAmount)
        // By default the money comes back to the account it was lent from.
        _receivedIn = State(initialValue: loan.method == .cash ? loan.bankName : "")
    }

    /// Banks of your open bank accounts, one entry per bank.
    private var bankChoices: [String] {
        var seen = Set<String>()
        return allAccounts
            .filter { $0.kind == .bank && !$0.isArchived && !$0.bankName.isEmpty }
            .map(\.bankName)
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var eligibleAccounts: [Account] {
        allAccounts.filter { !$0.isArchived && !$0.kind.isLiability }
    }

    private var fromAccount: Account? {
        eligibleAccounts.first { $0.uid == fromUID }
    }

    private var isValid: Bool {
        guard let amount else { return false }
        if amount <= 0 || amount > loan.outstandingAmount { return false }
        if loan.method == .card && repayMode == .iPaid && fromAccount == nil {
            return false
        }
        return true
    }

    /// What will still be owed after this payment.
    private var balanceAfter: Decimal {
        max(0, loan.outstandingAmount - (amount ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Friend", value: loan.friendName)
                    LabeledContent("Lent") {
                        Text(loan.amount, format: .rupees)
                    }
                    if loan.repaidAmount > 0 {
                        LabeledContent("Repaid So Far") {
                            Text(loan.repaidAmount, format: .rupees)
                                .foregroundStyle(.green)
                        }
                    }
                    LabeledContent("Still Owed") {
                        Text(loan.outstandingAmount, format: .rupees)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    if loan.method == .card, let cardDesc = loan.cardDescription {
                        LabeledContent("Card", value: cardDesc)
                    }
                }

                if loan.method == .card {
                    Section {
                        Picker("Repayment Option", selection: $repayMode) {
                            ForEach(RepayMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Repayment Option")
                    } footer: {
                        if repayMode == .iPaid {
                            Text("Use this when your friend hasn't paid the bank directly and you paid the card bill yourself. It clears this card loan and moves the amount to a Cash loan owed by \(loan.friendName) to you.")
                        } else {
                            Text("Use this when \(loan.friendName) paid the bank or credit card company directly.")
                        }
                    }
                }

                Section {
                    TextField(repayMode == .iPaid && loan.method == .card ? "Amount Paid for Friend" : "Amount Received", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))

                    DatePicker(repayMode == .iPaid && loan.method == .card ? "Paid On" : "Received On", selection: $date, displayedComponents: .date)

                    if loan.method == .card && repayMode == .iPaid {
                        if eligibleAccounts.isEmpty {
                            Text("Add a bank account or cash first so there is somewhere to pay from.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Paid From", selection: $fromUID) {
                                ForEach(eligibleAccounts) { account in
                                    Text(account.displayName).tag(account.uid)
                                }
                            }
                        }
                    } else if loan.method == .cash, !bankChoices.isEmpty {
                        Picker("Received In", selection: $receivedIn) {
                            Text("Cash").tag("")
                            ForEach(bankChoices, id: \.self) { bank in
                                Text(bank).tag(bank)
                            }
                        }
                    }

                    TextField("Note (optional)", text: $note)
                } header: {
                    Text(loan.method == .card && repayMode == .iPaid ? "Payment You Made" : "Payment")
                } footer: {
                    if let amount, amount > loan.outstandingAmount {
                        Text("That's more than the \(loan.outstandingAmount.formatted(.rupees)) still owed.")
                            .foregroundStyle(.red)
                    } else if isValid {
                        if loan.method == .card && repayMode == .iPaid {
                            Text("Takes \(amount?.formatted(.rupees) ?? "this") off their card loan, creates a Cash loan to \(loan.friendName) from \(fromAccount?.displayName ?? "account"), and lowers that account once. Pay the rest of the bill from the card's Pay Bill as usual: don't include their share in it.")
                        } else {
                            Text(balanceAfter == 0
                                 ? "This clears the loan."
                                 : "\(balanceAfter.formatted(.rupees)) will still be owed after this payment.")
                        }
                    }
                }

            }
            .navigationTitle(loan.method == .card && repayMode == .iPaid ? "I Paid Card Bill" : "Record Repayment")
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
                if fromUID.isEmpty {
                    fromUID = eligibleAccounts.first?.uid ?? ""
                }
            }
        }
    }

    private func save() {
        guard let amount, isValid else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if loan.method == .card && repayMode == .iPaid {
            let repaymentNote = trimmedNote.isEmpty ? "Card paid for loan" : trimmedNote
            loan.recordRepayment(amount, on: date, note: repaymentNote, bankName: "", in: modelContext)

            let fromAcc = fromAccount
            let newCashLoan = Loan(
                amount: amount,
                friendName: loan.friendName,
                friendPhone: loan.friendPhone,
                note: repaymentNote,
                date: date,
                method: .cash,
                bankName: fromAcc?.kind == .bank ? (fromAcc?.bankName ?? "") : ""
            )
            modelContext.insert(newCashLoan)
        } else {
            loan.recordRepayment(amount, on: date, note: trimmedNote, bankName: receivedIn, in: modelContext)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Loan.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let loan = Loan(amount: 5000, friendName: "Rahul")
    container.mainContext.insert(loan)
    return RepaymentFormView(loan: loan)
        .modelContainer(container)
}
