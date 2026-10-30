//
//  RepaymentFormView.swift
//  ExpenseTracker
//

import SwiftUI
import SwiftData

/// Sheet for recording a payment a friend has made towards a loan. It can be less than the full balance.
struct RepaymentFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let loan: Loan

    @Query(sort: \Account.createdAt) private var allAccounts: [Account]

    @State private var amount: Decimal?
    @State private var date = Date.now
    @State private var note = ""
    /// The bank the money arrived in. Empty means cash.
    @State private var receivedIn: String

    init(loan: Loan) {
        self.loan = loan
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

    private var isValid: Bool {
        guard let amount else { return false }
        return amount > 0 && amount <= loan.outstandingAmount
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
                }

                Section {
                    TextField("Amount Received", value: $amount, format: .rupees)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    DatePicker("Received On", selection: $date, displayedComponents: .date)
                    // Loans on your card or in your name are repaid to the card or lender, not to you.
                    if loan.method == .cash, !bankChoices.isEmpty {
                        Picker("Received In", selection: $receivedIn) {
                            Text("Cash").tag("")
                            ForEach(bankChoices, id: \.self) { bank in
                                Text(bank).tag(bank)
                            }
                        }
                    }
                    TextField("Note (optional)", text: $note)
                } header: {
                    Text("Payment")
                } footer: {
                    if let amount, amount > loan.outstandingAmount {
                        Text("That's more than the \(loan.outstandingAmount.formatted(.rupees)) still owed.")
                            .foregroundStyle(.red)
                    } else if isValid {
                        Text(balanceAfter == 0
                             ? "This clears the loan."
                             : "\(balanceAfter.formatted(.rupees)) will still be owed after this payment.")
                    }
                }
            }
            .navigationTitle("Record Repayment")
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

    private func save() {
        guard let amount, isValid else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        loan.recordRepayment(amount, on: date, note: trimmedNote, bankName: receivedIn, in: modelContext)
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
